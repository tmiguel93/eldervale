class_name CharacterStateMachine
extends RefCounted
## Maquina de estados pura do personagem (sem nos). Avance com tick(delta).
## Estados temporizados (ATTACK, DODGE, HIT) percorrem WINDUP -> ACTIVE -> RECOVER (fases de
## duracao 0 sao puladas) e SEMPRE voltam a IDLE: nao ha softlock. Unica saida de DEAD: revive().
##
## Transicoes validas:
##  IDLE/MOVE   -> ATTACK (try_attack), DODGE (try_dodge), HIT (hit), DEAD (die)
##  ATTACK      -> DODGE so na fase RECOVER (cancelamento); HIT (interrompe); DEAD
##  DODGE       -> so IDLE ao fim (nao esquiva de novo, nao sofre HIT); DEAD
##  HIT         -> IDLE ao fim (sem novo stun enquanto atordoado); DEAD
##  DEAD        -> IDLE por revive()

signal state_changed(from: State, to: State)
signal phase_changed(state: State, phase: Phase)

enum State { IDLE, MOVE, ATTACK, DODGE, HIT, DEAD }
enum Phase { NONE, WINDUP, ACTIVE, RECOVER }

var state: State = State.IDLE
var phase: Phase = Phase.NONE

var _durations: Array[float] = [0.0, 0.0, 0.0] ## windup, active, recover
var _time_left: float = 0.0


func is_dead() -> bool:
	return state == State.DEAD


func can_start_action() -> bool:
	return state == State.IDLE or state == State.MOVE


func can_dodge() -> bool:
	return can_start_action() or (state == State.ATTACK and phase == Phase.RECOVER)


## Movimento livre bloqueado em ataque (windup/active), esquiva (tem deslocamento proprio), hit e morte.
func movement_locked() -> bool:
	match state:
		State.ATTACK:
			return phase == Phase.WINDUP or phase == Phase.ACTIVE
		State.DODGE, State.HIT, State.DEAD:
			return true
	return false


func is_strike_active() -> bool:
	return state == State.ATTACK and phase == Phase.ACTIVE


func set_moving(moving: bool) -> void:
	if state == State.IDLE and moving:
		_set_state(State.MOVE)
	elif state == State.MOVE and not moving:
		_set_state(State.IDLE)


func try_attack(windup: float, active: float, recover: float) -> bool:
	if not can_start_action() or windup + active + recover <= 0.0:
		return false
	_begin(State.ATTACK, windup, active, recover)
	return true


func try_dodge(windup: float, active: float, recover: float) -> bool:
	if not can_dodge() or windup + active + recover <= 0.0:
		return false
	_begin(State.DODGE, windup, active, recover)
	return true


## Atordoa por `stun` segundos. Falha se morto, em esquiva ou ja atordoado.
func hit(stun: float) -> bool:
	if state == State.DEAD or state == State.DODGE or state == State.HIT:
		return false
	_begin(State.HIT, 0.0, 0.0, stun)
	return true


func die() -> bool:
	if state == State.DEAD:
		return false
	phase = Phase.NONE
	_time_left = 0.0
	_set_state(State.DEAD)
	return true


func revive() -> bool:
	if state != State.DEAD:
		return false
	_set_state(State.IDLE)
	return true


func tick(delta: float) -> void:
	var remaining: float = delta
	while remaining > 0.0 and phase != Phase.NONE:
		if remaining < _time_left:
			_time_left -= remaining
			return
		remaining -= _time_left
		_enter_phase(_next_phase(phase))


func _begin(new_state: State, windup: float, active: float, recover: float) -> void:
	_durations = [maxf(windup, 0.0), maxf(active, 0.0), maxf(recover, 0.0)]
	phase = Phase.NONE
	_set_state(new_state)
	_enter_phase(Phase.WINDUP)


func _next_phase(p: Phase) -> Phase:
	match p:
		Phase.WINDUP:
			return Phase.ACTIVE
		Phase.ACTIVE:
			return Phase.RECOVER
	return Phase.NONE


## Entra em `p`, pulando fases de duracao 0; sem fases restantes, termina em IDLE.
func _enter_phase(p: Phase) -> void:
	var candidate: Phase = p
	while candidate != Phase.NONE:
		var duration: float = _durations[int(candidate) - 1]
		if duration > 0.0:
			phase = candidate
			_time_left = duration
			phase_changed.emit(state, phase)
			return
		candidate = _next_phase(candidate)
	phase = Phase.NONE
	_time_left = 0.0
	_set_state(State.IDLE)


func _set_state(new_state: State) -> void:
	if new_state == state:
		return
	var old: State = state
	state = new_state
	state_changed.emit(old, new_state)
