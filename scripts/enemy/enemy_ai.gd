class_name EnemyAI
extends RefCounted
## Maquina de estados PURA da IA de inimigo (sem nos, sem fisica). Entrada por tick():
## posicao propria, posicao do alvo, alvo vivo?. Saida: `move_dir` (plano XZ, unitario ou zero),
## `face_dir`, sinais de ataque. Quem move o corpo e o `Enemy`.
##
##  IDLE   -> CHASE   alvo vivo, dist <= aggro_range e alvo dentro do raio de leash da origem
##  CHASE  -> ATTACK  dist <= attack_range e cooldown pronto (telegrafa `windup` s, parado)
##  CHASE  -> RETURN  alvo morto, ou inimigo/alvo alem de `leash_range` da origem
##  ATTACK -> CHASE   ao fim do windup emite attack_released e inicia o cooldown
##  ATTACK -> RETURN  alvo morreu durante o windup (ataque cancelado, sem release)
##  RETURN -> IDLE    chegou na origem (ou estourou return_timeout -> return_timed_out + reset)
##  qualquer -> DEAD  die(); DEAD e terminal (tick nao faz nada)
## Em RETURN o alvo e ignorado (sem re-aggro ate chegar), evitando ping-pong no limite do leash.
## Nao ha softlock: todo estado tem saida por tempo (windup, return_timeout) ou por condicao.

enum State { IDLE, CHASE, ATTACK, RETURN, DEAD }

signal state_changed(from: State, to: State)
signal attack_telegraph_started
signal attack_released
signal return_timed_out
signal reset_completed

var aggro_range: float = 10.0
var attack_range: float = 1.8
var attack_cooldown: float = 1.5
var windup: float = 0.45
## Distancia maxima da origem que o inimigo OU o alvo podem ter antes do reset.
var leash_range: float = 20.0
## Fracao de attack_range em que para de avancar (histerese: ataca ate attack_range).
var stop_fraction: float = 0.9
## Ranged: se o alvo chega mais perto que attack_range * retreat_fraction, recua. 0 = nunca recua.
var retreat_fraction: float = 0.0
var arrive_radius: float = 0.6
var return_timeout: float = 10.0

var state: State = State.IDLE
var origin: Vector3 = Vector3.ZERO
var move_dir: Vector3 = Vector3.ZERO
var face_dir: Vector3 = Vector3.ZERO
var cooldown_left: float = 0.0

var _windup_left: float = 0.0
var _return_time: float = 0.0


static func from_data(d: EnemyData) -> EnemyAI:
	var ai: EnemyAI = EnemyAI.new()
	ai.aggro_range = d.aggro_range
	ai.attack_range = d.attack_range
	ai.attack_cooldown = d.attack_cooldown
	ai.leash_range = d.aggro_range * 2.0
	if d.behavior == EnemyData.BEHAVIOR_RANGED:
		ai.retreat_fraction = 0.5
	return ai


func is_dead() -> bool:
	return state == State.DEAD


func die() -> void:
	if state == State.DEAD:
		return
	move_dir = Vector3.ZERO
	_set_state(State.DEAD)


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


func tick(delta: float, pos: Vector3, target_pos: Vector3, target_alive: bool) -> void:
	move_dir = Vector3.ZERO
	if state == State.DEAD:
		return
	cooldown_left = maxf(0.0, cooldown_left - delta)
	var to_target: Vector3 = _flat(target_pos - pos)
	var dist: float = to_target.length()
	var target_from_origin: float = _flat(target_pos - origin).length()
	var self_from_origin: float = _flat(pos - origin).length()
	if dist > 0.0001:
		face_dir = to_target / dist

	if state == State.IDLE:
		if target_alive and dist <= aggro_range and target_from_origin <= leash_range:
			_set_state(State.CHASE)

	if state == State.CHASE:
		if not target_alive or self_from_origin > leash_range or target_from_origin > leash_range:
			_begin_return()
		elif dist <= attack_range and cooldown_left <= 0.0:
			_windup_left = windup
			_set_state(State.ATTACK)
			attack_telegraph_started.emit()
		elif retreat_fraction > 0.0 and dist < attack_range * retreat_fraction and dist > 0.0001:
			move_dir = -face_dir
		elif dist > attack_range * stop_fraction:
			move_dir = face_dir

	if state == State.ATTACK:
		if not target_alive:
			_begin_return()
		else:
			_windup_left -= delta
			if _windup_left <= 0.0:
				cooldown_left = attack_cooldown
				_set_state(State.CHASE)
				attack_released.emit()

	elif state == State.RETURN:
		_return_time += delta
		var to_origin: Vector3 = _flat(origin - pos)
		if to_origin.length() <= arrive_radius:
			_finish_return()
		elif _return_time >= return_timeout:
			return_timed_out.emit()
			_finish_return()
		else:
			move_dir = to_origin.normalized()
			face_dir = move_dir


func _begin_return() -> void:
	_return_time = 0.0
	_set_state(State.RETURN)


func _finish_return() -> void:
	_set_state(State.IDLE)
	reset_completed.emit()


func _set_state(new_state: State) -> void:
	if new_state == state:
		return
	var old: State = state
	state = new_state
	state_changed.emit(old, new_state)
