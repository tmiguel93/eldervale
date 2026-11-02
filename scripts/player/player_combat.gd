class_name PlayerCombat
extends Node
## Combate do jogador (filho do Player). Le as acoes de input `attack`, `skill_1`, `skill_2`,
## `dodge`, e coordena ResourcePool, CooldownTracker, CharacterStateMachine, Hitbox e HealthComponent.
## Roda ANTES do Player (process_physics_priority menor) para que trava de movimento e
## velocidade da esquiva valham no mesmo frame. A mira e o facing do jogador (mouse: futuro).
## Hitbox deve ser filho do Player (que nao rotaciona; o yaw vai em hitbox.rotation.y).
## Testes podem desligar o physics_process e chamar step(delta) manualmente.

signal skill_started(skill: SkillData)
signal skill_failed(skill: SkillData, reason: StringName) ## cooldown / resource / busy / dead / not_allowed
signal strike_started(skill: SkillData, hit_id: int)
## E6.1: um SkillProjectile foi disparado (para testes/efeitos); o projetil vive no mundo, nao sob o Player.
signal projectile_spawned(projectile: SkillProjectile)

## E6.1: slots de habilidade da classe (chaves de `apply_class`). A ordem e a do HUD.
const SLOTS: Array[StringName] = [&"attack", &"skill_1", &"skill_2", &"dodge"]

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
## E6.1: classe aplicada (`apply_class`). Com classe, SO as habilidades dela podem ser usadas (`try_use` recusa o resto com
## `not_allowed`). Vazio = jogador legado/offline sem restricao (cena do jogo local e testes E1-E5).
var class_id: StringName = &""
var allowed_skill_ids: Dictionary = {} ## StringName -> true
## E6.2: modificadores de habilidade dos talentos (skill_id -> Array[Dictionary]; SkillMods.collect). So o SERVIDOR os define
## (PlayerLoadout.apply_talents). Aplicados em TEMPO DE USO sobre uma copia do SkillData; o recurso compartilhado nunca e mutado.
var skill_mods: Dictionary = {}
var machine: CharacterStateMachine = CharacterStateMachine.new()
var resource_pool: ResourcePool = ResourcePool.new()
var cooldowns: CooldownTracker = CooldownTracker.new()

var health: HealthComponent
var hitbox: Hitbox
var _player: Player
var _current_skill: SkillData ## E6.2: habilidade EFETIVA do uso em curso (copia quando ha modificadores)
var _current_res: SkillMods.Resolved
var _clock: float = 0.0 ## E6.2: relogio de combate (soma dos `step`) para sinergias "apos usar X"
var _last_use: Dictionary = {} ## skill_id -> _clock do ultimo uso bem-sucedido
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
	_clock += delta
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


## E6.1: aplica a classe (so o SERVIDOR/jogo chama; nunca vem do cliente). Troca os 4 slots, restringe `try_use` as habilidades da
## classe e zera cooldowns/acao em curso. NAO mexe em stats (vem do personagem: CharacterCodec / PlayerLoadout.apply_class_growth).
func apply_class(def: ClassDef) -> bool:
	if def == null:
		return false
	var resolved: Dictionary = {}
	for slot: StringName in SLOTS:
		var skill: SkillData = ClassCatalog.load_skill(StringName(def.skills.get(String(slot), "")))
		if skill == null:
			return false
		resolved[slot] = skill
	basic_attack = resolved[&"attack"]
	skill_1 = resolved[&"skill_1"]
	skill_2 = resolved[&"skill_2"]
	dodge_skill = resolved[&"dodge"]
	allowed_skill_ids.clear()
	for slot: StringName in SLOTS:
		allowed_skill_ids[(resolved[slot] as SkillData).id] = true
	class_id = StringName(def.id)
	cooldowns.clear()
	skill_mods = {}
	_last_use.clear()
	return true


## Habilidade de um slot (`SLOTS`); null se o slot e desconhecido.
func skill_for_slot(slot: StringName) -> SkillData:
	match slot:
		&"attack": return basic_attack
		&"skill_1": return skill_1
		&"skill_2": return skill_2
		&"dodge": return dodge_skill
	return null


func is_skill_allowed(skill: SkillData) -> bool:
	return skill != null and (allowed_skill_ids.is_empty() or allowed_skill_ids.has(skill.id))


## E6.2: define os modificadores de habilidade (SkillMods.collect(...)["skills"]); so o servidor chama.
func set_skill_mods(mods: Dictionary) -> void:
	skill_mods = mods.duplicate(true)


## E6.3: mods da habilidade = os dela + os de item com skill "*" (curinga; nao vale para esquivas).
func mods_for(skill: SkillData) -> Array:
	var mods: Array = (skill_mods.get(skill.id, []) as Array).duplicate()
	if skill.kind != SkillData.Kind.DODGE and skill_mods.has("*"):
		mods.append_array(skill_mods["*"] as Array)
	return mods


## E6.2: valores efetivos da habilidade AGORA (custo, cooldown, dano, area...) com os modificadores dos talentos. Sem mods devolve o
## proprio SkillData. Util para HUD/testes; `try_use` usa exatamente isto.
func resolve_skill(skill: SkillData) -> SkillMods.Resolved:
	var mods: Array = mods_for(skill)
	if mods.is_empty():
		var plain: SkillMods.Resolved = SkillMods.Resolved.new()
		plain.skill = skill
		return plain
	var max_hp: float = health.max_health()
	var max_res: float = resource_pool.max_value()
	var ctx: Dictionary = {
		"hp_ratio": health.current_health / max_hp if max_hp > 0.0 else 1.0,
		"resource_ratio": resource_pool.current / max_res if max_res > 0.0 else 0.0,
		"clock": _clock, "last_use": _last_use,
	}
	return SkillMods.resolve(skill, mods, ctx)


## Tenta usar a habilidade. Ordem: classe -> estado -> cooldown -> custo; so gasta/inicia cooldown se TUDO ok.
## E6.2: custo/cooldown/dano/area vem da habilidade EFETIVA (talentos); o cooldown e identificado pelo id da habilidade base.
func try_use(skill: SkillData) -> bool:
	if skill == null:
		return false
	if not is_skill_allowed(skill):
		skill_failed.emit(skill, &"not_allowed")
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
	var res: SkillMods.Resolved = resolve_skill(skill)
	var eff: SkillData = res.skill
	if not resource_pool.can_afford(eff.resource_cost):
		skill_failed.emit(skill, &"resource")
		return false
	var started: bool
	if is_dodge:
		started = machine.try_dodge(eff.windup, eff.active, eff.recover)
	else:
		started = machine.try_attack(eff.windup, eff.active, eff.recover)
	if not started:
		skill_failed.emit(skill, &"busy")
		return false
	resource_pool.spend(eff.resource_cost)
	cooldowns.start(skill.id, eff.cooldown)
	_last_use[skill.id] = _clock
	_current_skill = eff
	_current_res = res
	if is_dodge:
		_begin_dodge(eff)
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
	var res: SkillMods.Resolved = _current_res
	if skill.is_projectile():
		_spawn_projectiles(skill, res)
		return
	var yaw: float = _player.facing_yaw_value
	hitbox.configure_shape(skill)
	hitbox.rotation.y = yaw
	hitbox.position = _player.get_facing_direction() * skill.hitbox_offset + Vector3(0.0, hitbox_height, 0.0)
	hitbox.damage_type = res.damage_type if res != null else &"physical"
	var amount: float = health.stats.attack_power * skill.damage_multiplier
	var hit_id: int = hitbox.begin_strike(amount, _player)
	strike_started.emit(skill, hit_id)


## Dispara o projetil da skill a frente do jogador (dano = ataque * multiplicador, calculado AGORA pelo servidor).
## E6.2: + `extra_projectiles` dos talentos em leque (o central tem dano cheio; os extras, `extra_damage_scale`); cada um e um golpe
## independente (hit_id proprio), entao varios podem acertar o mesmo alvo.
func _spawn_projectiles(skill: SkillData, res: SkillMods.Resolved) -> void:
	var parent: Node = _player.get_parent()
	if parent == null:
		parent = get_tree().root
	var amount: float = health.stats.attack_power * skill.damage_multiplier
	var origin: Vector3 = _player.global_position + _player.get_facing_direction() * skill.hitbox_offset + Vector3(0.0, hitbox_height, 0.0)
	var extra: int = res.extra_projectiles if res != null else 0
	var dtype: StringName = res.damage_type if res != null else &"physical"
	for k: int in extra + 1:
		var dir: Vector3 = _player.get_facing_direction()
		if k > 0:
			dir = dir.rotated(Vector3.UP, deg_to_rad(SkillMods.fan_angle(k, res.spread_deg)))
		var dmg: float = amount if k == 0 else amount * res.extra_damage_scale
		var proj: SkillProjectile = SkillProjectile.from_skill(skill, _player, Vector3.ZERO, dir, dmg)
		proj.damage_type = dtype
		parent.add_child(proj)
		proj.global_position = origin
		projectile_spawned.emit(proj)
		strike_started.emit(skill, proj.hit_id)


func _on_damaged(_info: DamageInfo, _final_amount: float) -> void:
	machine.hit(hit_stun)


func _on_died(_source: Node) -> void:
	machine.die()
	hitbox.end_strike()
	health.invulnerable = false
	_i_frames_left = 0.0
