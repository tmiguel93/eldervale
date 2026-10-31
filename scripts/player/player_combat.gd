class_name PlayerCombat
extends Node
## Combate do jogador (filho do Player). Le as acoes de input `attack`, `skill_1`, `skill_2`,
## `dodge`, e coordena ResourcePool, CooldownTracker, CharacterStateMachine, Hitbox e HealthComponent.
## Roda ANTES do Player (process_physics_priority menor) para que trava de movimento e
## velocidade da esquiva valham no mesmo frame. A mira e o facing do jogador (mouse: futuro).
## Hitbox deve ser filho do Player (que nao rotaciona; o yaw vai em hitbox.rotation.y).
## Testes podem desligar o physics_process e chamar step(delta) manualmente.

signal skill_started(skill: SkillData)
signal skill_failed(skill: SkillData, reason: StringName) ## cooldown / resource / busy / dead
signal strike_started(skill: SkillData, hit_id: int)

@export var base_stats: StatBlock
@export var health_path: NodePath = NodePath("../Health")
@export var hitbox_path: NodePath = NodePath("../Hitbox")
@export var basic_attack: SkillData
@export var skill_1: SkillData
@export var skill_2: SkillData
@export var dodge_skill: SkillData
@export var hit_stun: float = 0.25
@export var hitbox_height: float = 0.9

var read_input_actions: bool = true
var machine: CharacterStateMachine = CharacterStateMachine.new()
var resource_pool: ResourcePool = ResourcePool.new()
var cooldowns: CooldownTracker = CooldownTracker.new()

var health: HealthComponent
var hitbox: Hitbox
var _player: Player
var _current_skill: SkillData
var _i_frames_left: float = 0.0
var _dodge_velocity: Vector3 = Vector3.ZERO


func _ready() -> void:
	process_physics_priority = -10
	_player = get_parent() as Player
	health = get_node_or_null(health_path) as HealthComponent
	hitbox = get_node_or_null(hitbox_path) as Hitbox
	if _player == null or health == null or hitbox == null:
		push_error("PlayerCombat: requer pai Player, `health` e `hitbox`.")
		set_physics_process(false)
		return
	if base_stats != null:
		health.stats = base_stats.copy() # copia: edicoes em runtime nao alteram o recurso
		health.reset()
	resource_pool.setup(health.stats)
	hitbox.setup_team(CombatLayers.Team.PLAYER)
	machine.phase_changed.connect(_on_phase_changed)
	machine.state_changed.connect(_on_state_changed)
	health.died.connect(_on_died)
	health.damaged.connect(_on_damaged)


func _physics_process(delta: float) -> void:
	if read_input_actions:
		if Input.is_action_just_pressed(&"dodge"):
			try_use(dodge_skill)
		elif Input.is_action_just_pressed(&"attack"):
			try_use(basic_attack)
		elif Input.is_action_just_pressed(&"skill_1"):
			try_use(skill_1)
		elif Input.is_action_just_pressed(&"skill_2"):
			try_use(skill_2)
	step(delta)


## Avanca timers e sincroniza o Player. Chamado pelo physics_process (ou por testes).
func step(delta: float) -> void:
	if resource_pool.stats != health.stats:
		resource_pool.set_stats(health.stats)
	cooldowns.tick(delta)
	resource_pool.tick(delta)
	if _i_frames_left > 0.0:
		_i_frames_left -= delta
		if _i_frames_left <= 0.0:
			_i_frames_left = 0.0
			health.invulnerable = false
	machine.tick(delta)
	if machine.can_start_action():
		machine.set_moving(_player.get_move_direction().length_squared() > 0.0001)
	var strike_scale: float = _attack_move_scale()
	_player.movement_locked = machine.movement_locked() and strike_scale <= 0.0
	_player.move_speed_scale = strike_scale if (machine.movement_locked() and strike_scale > 0.0) else 1.0
	var dodging: bool = machine.state == CharacterStateMachine.State.DODGE \
		and machine.phase != CharacterStateMachine.Phase.RECOVER
	_player.use_forced_velocity = dodging
	_player.forced_velocity = _dodge_velocity if dodging else Vector3.ZERO


## Durante windup/active de um ATAQUE, devolve a fracao de velocidade permitida pela skill atual
## (0 = travado). Fora disso devolve 0 e o chamador usa o estado da maquina.
func _attack_move_scale() -> float:
	if machine.state == CharacterStateMachine.State.ATTACK and _current_skill != null:
		return _current_skill.attack_move_scale
	return 0.0


## Tenta usar a habilidade. Ordem: estado -> cooldown -> custo; so gasta/inicia cooldown se TUDO ok.
func try_use(skill: SkillData) -> bool:
	if skill == null:
		return false
	if machine.is_dead():
		skill_failed.emit(skill, &"dead")
		return false
	var is_dodge: bool = skill.kind == SkillData.Kind.DODGE
	if not (machine.can_dodge() if is_dodge else machine.can_start_action()):
		skill_failed.emit(skill, &"busy")
		return false
	if not cooldowns.is_ready(skill.id):
		skill_failed.emit(skill, &"cooldown")
		return false
	if not resource_pool.can_afford(skill.resource_cost):
		skill_failed.emit(skill, &"resource")
		return false
	var started: bool
	if is_dodge:
		started = machine.try_dodge(skill.windup, skill.active, skill.recover)
	else:
		started = machine.try_attack(skill.windup, skill.active, skill.recover)
	if not started:
		skill_failed.emit(skill, &"busy")
		return false
	resource_pool.spend(skill.resource_cost)
	cooldowns.start(skill.id, skill.cooldown)
	_current_skill = skill
	if is_dodge:
		_begin_dodge(skill)
	skill_started.emit(skill)
	return true


func _begin_dodge(skill: SkillData) -> void:
	var dir: Vector3 = _player.get_move_direction()
	if dir.length_squared() < 0.0001:
		dir = _player.get_facing_direction()
	dir = dir.normalized()
	_player.set_facing_yaw(PlayerMotion.facing_yaw(dir, _player.facing_yaw_value))
	var move_time: float = skill.windup + skill.active
	_dodge_velocity = dir * (skill.dodge_distance / move_time)
	_i_frames_left = skill.i_frames
	health.invulnerable = true


func _on_phase_changed(state: CharacterStateMachine.State, phase: CharacterStateMachine.Phase) -> void:
	if state != CharacterStateMachine.State.ATTACK or _current_skill == null:
		return
	if phase == CharacterStateMachine.Phase.ACTIVE:
		_begin_strike(_current_skill)
	elif phase == CharacterStateMachine.Phase.RECOVER:
		hitbox.end_strike()


func _on_state_changed(from: CharacterStateMachine.State, _to: CharacterStateMachine.State) -> void:
	if from == CharacterStateMachine.State.ATTACK:
		hitbox.end_strike()


func _begin_strike(skill: SkillData) -> void:
	var yaw: float = _player.facing_yaw_value
	hitbox.configure_shape(skill)
	hitbox.rotation.y = yaw
	hitbox.position = _player.get_facing_direction() * skill.hitbox_offset + Vector3(0.0, hitbox_height, 0.0)
	var amount: float = health.stats.attack_power * skill.damage_multiplier
	var hit_id: int = hitbox.begin_strike(amount, _player)
	strike_started.emit(skill, hit_id)


func _on_damaged(_info: DamageInfo, _final_amount: float) -> void:
	machine.hit(hit_stun)


func _on_died(_source: Node) -> void:
	machine.die()
	hitbox.end_strike()
	health.invulnerable = false
	_i_frames_left = 0.0
