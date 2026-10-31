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
## E5.2: com `attacks` nao vazio, o ataque e ESCOLHIDO (peso, alcance, recarga propria, sem repetir o
## anterior se houver alternativa) e o telegrafo usa o windup dele; `lock_left` > 0 (transicao de
## fase) deixa o inimigo parado, sem atacar nem perseguir. `attacks` vazio = comportamento legado.
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
## E5.2: lista de ataques (vazia = ataque unico legado). Preenchida pelo Enemy / pela fase atual.
var attacks: Array[EnemyAttack] = []
## Ataque em andamento (valido de ATTACK ate o proximo); null no modo legado.
var current_attack: EnemyAttack = null
## Multiplica as pausas entre ataques (fase: < 1 = mais agressivo).
var cooldown_scale: float = 1.0
## > 0: parado (transicao de fase). Ver begin_lock().
var lock_left: float = 0.0
## Ids de ataque que NAO podem ser escolhidos agora (ex.: invocacao com limite de vivos). id -> true.
var blocked: Dictionary = {}
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var last_attack_id: StringName = &""

var state: State = State.IDLE
var origin: Vector3 = Vector3.ZERO
var move_dir: Vector3 = Vector3.ZERO
var face_dir: Vector3 = Vector3.ZERO
var cooldown_left: float = 0.0

var _windup_left: float = 0.0
var _windup_total: float = 0.0
var _return_time: float = 0.0
var _attack_cd: Dictionary = {} ## attack id -> s restantes (recarga propria)


static func from_data(d: EnemyData) -> EnemyAI:
	var ai: EnemyAI = EnemyAI.new()
	ai.aggro_range = d.aggro_range
	ai.attack_range = d.attack_range
	ai.attack_cooldown = d.attack_cooldown
	ai.leash_range = d.leash_range if d.leash_range > 0.0 else d.aggro_range * 2.0
	ai.windup = d.windup
	ai.attacks = d.attacks.duplicate()
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


## Progresso do telegrafo (0..1) enquanto em ATTACK; 0 fora dele.
func windup_progress() -> float:
	if state != State.ATTACK or _windup_total <= 0.0:
		return 0.0
	return clampf(1.0 - _windup_left / _windup_total, 0.0, 1.0)


## Congela o inimigo por `time` s (transicao de fase). Um windup em andamento e cancelado sem release.
func begin_lock(time: float) -> void:
	lock_left = maxf(lock_left, time)
	if state == State.ATTACK:
		_set_state(State.CHASE)


## Volta a IDLE limpo (reset de encontro): sem ataque, recargas e travas zeradas. Nao mexe na origem.
func reset_to_idle() -> void:
	if state == State.DEAD:
		return
	lock_left = 0.0
	cooldown_left = 0.0
	_attack_cd.clear()
	current_attack = null
	last_attack_id = &""
	move_dir = Vector3.ZERO
	_set_state(State.IDLE)


## Escolhe um ataque para a distancia `dist` ou null. Deterministico dado o estado de `rng`.
func pick_attack(dist: float) -> EnemyAttack:
	var cands: Array[EnemyAttack] = []
	for a: EnemyAttack in attacks:
		if a == null or dist < a.min_range or dist > a.max_range:
			continue
		if float(_attack_cd.get(a.id, 0.0)) > 0.0 or bool(blocked.get(a.id, false)):
			continue
		cands.append(a)
	if cands.size() > 1:
		var varied: Array[EnemyAttack] = []
		for a: EnemyAttack in cands:
			if a.id != last_attack_id:
				varied.append(a)
		if not varied.is_empty():
			cands = varied
	if cands.is_empty():
		return null
	var total: float = 0.0
	for a: EnemyAttack in cands:
		total += maxf(a.weight, 0.0)
	if total <= 0.0:
		return cands[0]
	var roll: float = rng.randf() * total
	var acc: float = 0.0
	for a: EnemyAttack in cands:
		acc += maxf(a.weight, 0.0)
		if roll < acc:
			return a
	return cands[cands.size() - 1]


## Tenta iniciar um ataque (legado: dentro de attack_range; senao: escolhido da lista).
func _try_begin_attack(dist: float) -> bool:
	if attacks.is_empty():
		if dist > attack_range:
			return false
		current_attack = null
		_windup_total = windup
	else:
		var a: EnemyAttack = pick_attack(dist)
		if a == null:
			return false
		current_attack = a
		_windup_total = a.windup
	_windup_left = _windup_total
	return true


func _tick_attack_cooldowns(delta: float) -> void:
	for k: Variant in _attack_cd.keys():
		var left: float = float(_attack_cd[k]) - delta
		if left <= 0.0:
			_attack_cd.erase(k)
		else:
			_attack_cd[k] = left


func tick(delta: float, pos: Vector3, target_pos: Vector3, target_alive: bool) -> void:
	move_dir = Vector3.ZERO
	if state == State.DEAD:
		return
	cooldown_left = maxf(0.0, cooldown_left - delta)
	_tick_attack_cooldowns(delta)
	var to_target: Vector3 = _flat(target_pos - pos)
	var dist: float = to_target.length()
	var target_from_origin: float = _flat(target_pos - origin).length()
	var self_from_origin: float = _flat(pos - origin).length()
	if dist > 0.0001:
		face_dir = to_target / dist

	if state == State.IDLE:
		if target_alive and dist <= aggro_range and target_from_origin <= leash_range:
			_set_state(State.CHASE)

	if lock_left > 0.0 and state != State.RETURN:
		lock_left = maxf(0.0, lock_left - delta)
		return # transicao de fase: parado, sem atacar nem perseguir

	if state == State.CHASE:
		if not target_alive or self_from_origin > leash_range or target_from_origin > leash_range:
			_begin_return()
		elif cooldown_left <= 0.0 and _try_begin_attack(dist):
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
				if current_attack != null:
					cooldown_left = current_attack.cooldown * cooldown_scale
					_attack_cd[current_attack.id] = current_attack.own_cooldown
					last_attack_id = current_attack.id
				else:
					cooldown_left = attack_cooldown * cooldown_scale
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
