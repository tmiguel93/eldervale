class_name Enemy
extends CharacterBody3D
## Inimigo base. Configurado por EnemyData (dados) + EnemyAI (maquina de estados pura).
## Pipeline de dano: Hurtbox(camada 3) -> HealthComponent -> DamageCalculator (existente).
## Ataque melee = Hitbox (camada 5, mascara player_hurt) ligado no instante do release da IA;
## ranged = Projectile. Morte: ocorre UMA vez (flag) -> para IA, desliga colisoes, rola o
## LootTable com RandomNumberGenerator (`loot_seed` >= 0 torna deterministico), cria pickups e
## concede XP ao Loadout do jogador que causou o golpe final. Autoridade local (E2).
## Hitbox deve ser filho de pai sem rotacao: so o Visual gira.
## Testes podem desligar physics_process e chamar step(delta).
## E5.2: ataques por dados (MELEE/AOE/PROJECTILE/CHARGE/SUMMON), fases de chefe (EnemyPhaseController),
## tabela de ameaca, escala de dificuldade (`set_difficulty`) e invocacao de adds (`summon_handler`).

signal defeated(enemy: Enemy, xp: int, drops: Array[LootDrop])
## E5.2: o chefe entrou na fase `phase_index` (>= 1).
signal phase_changed(enemy: Enemy, phase_index: int)

const STRIKE_TIME: float = 0.15
const GRAVITY: float = 24.0
const CORPSE_TIME: float = 0.7
const AOE_STRIKE_TIME: float = 0.2
const HITBOX_HEIGHT: float = 1.4
const SUMMON_RING_RADIUS: float = 2.5
## Fracao de ameaca perdida por segundo (o alvo pode mudar com o tempo).
const THREAT_DECAY_PER_SEC: float = 0.1

@export var data: EnemyData
## >= 0: semente do RNG de loot (testes/replay). -1: aleatorio.
@export var loot_seed: int = -1

var target: Node3D
var ai: EnemyAI
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var health: HealthComponent
var hurtbox: Hurtbox
var hitbox: Hitbox
var visual: EnemyVisual
var defeat_count: int = 0
var attack_count: int = 0
var last_drops: Array[LootDrop] = []
## Servidor dedicado (E3) desliga: drops sao so evento informativo, sem pickups no mundo.
var spawn_pickups: bool = true
## E5.2
var phase_ctrl: EnemyPhaseController
var threat: ThreatTable = ThreatTable.new()
var difficulty_damage_mult: float = 1.0
var difficulty_health_mult: float = 1.0
## Adds vivos invocados por este inimigo.
var summoned: Array[Enemy] = []
## Callable(summoner: Enemy, type_id: StringName, count: int) -> Array de Enemy criados. Vazio = padrao
## (instancia a cena como irmao). O servidor define o seu para registrar ids/eventos.
var summon_handler: Callable = Callable()
var dismissed: bool = false

var _strike_left: float = 0.0
var _phase_speed_mult: float = 1.0
var _phase_damage_mult: float = 1.0
var _invuln_left: float = 0.0
var _charge_left: float = 0.0
var _charge_dir: Vector3 = Vector3.ZERO
var _charge_speed: float = 0.0
var _summon_totals: Dictionary = {} ## attack id -> invocacoes feitas no encontro
var _encounter_gen: int = 0 ## muda a cada reset: invalida invocacoes adiadas
var _corpse_left: float = -1.0
var _warned_no_target: bool = false


func _ready() -> void:
	health = get_node_or_null("Health") as HealthComponent
	hurtbox = get_node_or_null("Hurtbox") as Hurtbox
	hitbox = get_node_or_null("Hitbox") as Hitbox
	visual = get_node_or_null("Visual") as EnemyVisual
	if data == null or health == null or hurtbox == null or hitbox == null or visual == null:
		push_error("Enemy: requer `data` e filhos Health/Hurtbox/Hitbox/Visual.")
		set_physics_process(false)
		return
	if loot_seed >= 0:
		rng.seed = loot_seed
	else:
		rng.randomize()
	health.stats = data.stats.copy() # copia: edicao em runtime nao altera o recurso
	health.reset()
	hurtbox.health = health
	hitbox.setup_team(CombatLayers.Team.ENEMY)
	ai = EnemyAI.from_data(data)
	ai.rng.seed = rng.randi()
	ai.origin = global_position
	ai.attack_released.connect(_on_attack_released)
	ai.return_timed_out.connect(_on_return_timed_out)
	ai.reset_completed.connect(_on_reset_completed)
	visual.apply(data)
	visual.bind(ai)
	_configure_hitbox()
	_scale_collision()
	if not data.phases.is_empty():
		phase_ctrl = EnemyPhaseController.new()
		phase_ctrl.setup(data.phases)
		_apply_phase(0)
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)


func _configure_hitbox() -> void:
	var shape_node: CollisionShape3D = hitbox.get_node_or_null("Shape") as CollisionShape3D
	if shape_node == null:
		return
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(data.attack_range, 1.4, data.attack_range)
	shape_node.shape = box


func set_origin(p: Vector3) -> void:
	if ai != null:
		ai.origin = p


func _physics_process(delta: float) -> void:
	step(delta)


func step(delta: float) -> void:
	if ai == null or ai.is_dead():
		return
	var tpos: Vector3 = global_position
	var alive: bool = false
	var t: Node3D = _resolve_target()
	if t != null:
		tpos = t.global_position
		alive = not _target_dead(t)
	_update_blocked_attacks()
	threat.decay(THREAT_DECAY_PER_SEC, delta)
	ai.tick(delta, global_position, tpos, alive)
	if _invuln_left > 0.0:
		_invuln_left -= delta
		if _invuln_left <= 0.0:
			health.invulnerable = false
	var speed: float = data.stats.move_speed * _phase_speed_mult
	if _charge_left > 0.0:
		_charge_left -= delta
		velocity.x = _charge_dir.x * _charge_speed
		velocity.z = _charge_dir.z * _charge_speed
		if _charge_left <= 0.0:
			_end_charge()
	else:
		velocity.x = ai.move_dir.x * speed
		velocity.z = ai.move_dir.z * speed
	if is_on_floor():
		velocity.y = minf(velocity.y, 0.0)
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()
	if ai.face_dir.length_squared() > 0.0001 and _charge_left <= 0.0:
		visual.rotation.y = atan2(-ai.face_dir.x, -ai.face_dir.z)
	if _strike_left > 0.0:
		_strike_left -= delta
		if _strike_left <= 0.0:
			hitbox.end_strike()


func _process(delta: float) -> void:
	if _corpse_left >= 0.0:
		_corpse_left -= delta
		if _corpse_left <= 0.0:
			queue_free()


func _resolve_target() -> Node3D:
	if target != null and is_instance_valid(target):
		return target
	target = get_tree().get_first_node_in_group(&"player") as Node3D
	if target == null and not _warned_no_target:
		_warned_no_target = true
		push_warning("Enemy: sem alvo (grupo 'player'); permanece parado.")
	return target


static func _target_dead(t: Node3D) -> bool:
	var h: HealthComponent = t.get_node_or_null("Health") as HealthComponent
	return h != null and h.is_dead


func _on_attack_released() -> void:
	attack_count += 1
	var dir: Vector3 = ai.face_dir
	if dir.length_squared() < 0.0001:
		dir = Vector3(0.0, 0.0, -1.0)
	dir = dir.normalized()
	var atk: EnemyAttack = ai.current_attack
	if atk == null:
		_release_legacy(dir)
		return
	var amount: float = data.stats.attack_power * atk.damage_multiplier * _damage_scale()
	match atk.kind:
		EnemyAttack.Kind.MELEE:
			_strike_box(Vector3(atk.width, HITBOX_HEIGHT, atk.max_range), dir, atk.max_range * 0.55, amount, STRIKE_TIME)
		EnemyAttack.Kind.AOE:
			_strike_cylinder(atk.radius, dir * atk.aoe_offset, amount)
		EnemyAttack.Kind.PROJECTILE:
			_fire_projectiles(dir, atk.projectile_count, atk.spread_degrees, atk.projectile_speed, amount, atk.max_range)
		EnemyAttack.Kind.CHARGE:
			_begin_charge(atk, dir, amount)
		EnemyAttack.Kind.SUMMON:
			var made: int = _summon(atk.summon_id, atk.summon_count, atk.summon_max_alive, _summon_budget(atk))
			_summon_totals[atk.id] = int(_summon_totals.get(atk.id, 0)) + made


func _damage_scale() -> float:
	return _phase_damage_mult * difficulty_damage_mult


func _release_legacy(dir: Vector3) -> void:
	var amount: float = data.stats.attack_power * data.attack_damage_multiplier * _damage_scale()
	if data.behavior == EnemyData.BEHAVIOR_RANGED:
		_fire_projectiles(dir, 1, 0.0, data.projectile_speed, amount, 0.0)
	else:
		hitbox.rotation.y = atan2(-dir.x, -dir.z)
		hitbox.position = dir * data.attack_range * 0.6 + Vector3(0.0, 0.9, 0.0)
		hitbox.begin_strike(amount, self)
		_strike_left = STRIKE_TIME


func _fire_projectiles(dir: Vector3, count: int, spread_deg: float, speed: float, amount: float, max_range: float) -> void:
	var host: Node = get_parent()
	if host == null:
		return
	var n: int = maxi(count, 1)
	for i: int in n:
		var off: float = 0.0
		if n > 1:
			off = deg_to_rad(spread_deg) * (float(i) / float(n - 1) - 0.5)
		var proj: Projectile = Projectile.new()
		proj.direction = dir.rotated(Vector3.UP, off).normalized()
		proj.speed = speed
		proj.damage = amount
		proj.source = self
		if max_range > 0.0 and speed > 0.0:
			proj.lifetime = clampf(max_range * 1.5 / speed, 0.5, 6.0)
		host.add_child(proj)
		proj.global_position = global_position + Vector3(0.0, 1.0, 0.0) + dir * 0.6


func _strike_box(size: Vector3, dir: Vector3, forward: float, amount: float, duration: float) -> void:
	var box: BoxShape3D = BoxShape3D.new()
	box.size = size
	_set_hitbox_shape(box)
	hitbox.rotation.y = atan2(-dir.x, -dir.z)
	hitbox.position = dir * forward + Vector3(0.0, 0.9, 0.0)
	hitbox.begin_strike(amount, self)
	_strike_left = duration


func _strike_cylinder(radius: float, offset: Vector3, amount: float) -> void:
	var cyl: CylinderShape3D = CylinderShape3D.new()
	cyl.radius = radius
	cyl.height = HITBOX_HEIGHT
	_set_hitbox_shape(cyl)
	hitbox.rotation.y = 0.0
	hitbox.position = offset + Vector3(0.0, 0.9, 0.0)
	hitbox.begin_strike(amount, self)
	_strike_left = AOE_STRIKE_TIME


func _set_hitbox_shape(shape: Shape3D) -> void:
	var shape_node: CollisionShape3D = hitbox.get_node_or_null("Shape") as CollisionShape3D
	if shape_node != null:
		shape_node.shape = shape


func _begin_charge(atk: EnemyAttack, dir: Vector3, amount: float) -> void:
	_charge_dir = dir
	_charge_speed = atk.charge_speed
	_charge_left = atk.charge_distance / atk.charge_speed
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(atk.width, HITBOX_HEIGHT, 2.0)
	_set_hitbox_shape(box)
	hitbox.rotation.y = atan2(-dir.x, -dir.z)
	hitbox.position = dir * 1.0 + Vector3(0.0, 0.9, 0.0)
	hitbox.begin_strike(amount, self)
	_strike_left = _charge_left + 0.1
	visual.rotation.y = atan2(-dir.x, -dir.z)


func _end_charge() -> void:
	_charge_left = 0.0
	velocity.x = 0.0
	velocity.z = 0.0


## Teleporte de seguranca se o retorno a origem travou (anti-softlock).
func _on_return_timed_out() -> void:
	global_position = ai.origin
	velocity = Vector3.ZERO


func _on_reset_completed() -> void:
	health.reset() # leash: volta com vida cheia
	reset_encounter_state()


# ------------------------------------------------------------------ E5.2: fases, ameaca, adds

func phase_index() -> int:
	return phase_ctrl.index if phase_ctrl != null else 0


## Id do ataque em telegrafo (so enquanto a IA esta em ATTACK); "" caso contrario / modo legado.
func current_attack_id() -> String:
	if ai != null and ai.state == EnemyAI.State.ATTACK and ai.current_attack != null:
		return String(ai.current_attack.id)
	return ""


## Aplica multiplicadores de dificuldade (por numero de jogadores). A vida mantem a PROPORCAO.
func set_difficulty(health_mult: float, damage_mult: float) -> void:
	if health == null or data == null:
		return
	difficulty_damage_mult = maxf(damage_mult, 0.0)
	difficulty_health_mult = maxf(health_mult, 0.01)
	var old_max: float = health.stats.max_health
	var fraction: float = health.current_health / old_max if old_max > 0.0 else 1.0
	health.stats.max_health = data.stats.max_health * difficulty_health_mult
	if not health.is_dead:
		health.current_health = clampf(fraction, 0.0, 1.0) * health.stats.max_health
		health.health_changed.emit(health.current_health, health.stats.max_health)


## Registra dano de um jogador na tabela de ameaca (id de entidade do servidor).
func add_threat(player_entity_id: int, amount: float) -> void:
	threat.add(player_entity_id, amount)


func _on_damaged(_info: DamageInfo, _final: float) -> void:
	if phase_ctrl == null or health.current_health <= 0.0:
		return
	var fraction: float = health.current_health / health.max_health()
	var entered: Array[int] = phase_ctrl.advance(fraction)
	for idx: int in entered:
		_apply_phase(idx)
		phase_changed.emit(self, idx)


func _apply_phase(idx: int) -> void:
	var ph: EnemyPhase = phase_ctrl.phases[idx]
	ai.attacks = ph.attacks.duplicate()
	ai.cooldown_scale = ph.cooldown_mult
	_phase_speed_mult = ph.speed_mult
	_phase_damage_mult = ph.damage_mult
	if idx == 0:
		return
	if ph.transition_time > 0.0:
		ai.begin_lock(ph.transition_time)
		_invuln_left = ph.transition_time
		health.invulnerable = true
		_end_charge()
		hitbox.end_strike()
	if ph.summon_count > 0:
		_summon_on_enter.call_deferred(ph.summon_id, ph.summon_count, _encounter_gen) # fora do flush de fisica (golpe/projetil)


## Marca como bloqueados os ataques de invocacao sem espaco (limite de vivos / total do encontro).
func _update_blocked_attacks() -> void:
	ai.blocked.clear()
	for atk: EnemyAttack in ai.attacks:
		if atk != null and atk.kind == EnemyAttack.Kind.SUMMON:
			if _summon_budget(atk) == 0 or _alive_summoned() >= (atk.summon_max_alive if atk.summon_max_alive > 0 else 1000000):
				ai.blocked[atk.id] = true


## Quantos adds ainda podem ser invocados por `atk` no encontro (-1 = sem limite de total).
func _summon_budget(atk: EnemyAttack) -> int:
	if atk.summon_max_total <= 0:
		return -1
	return maxi(0, atk.summon_max_total - int(_summon_totals.get(atk.id, 0)))


## Invocacao de entrada de fase (adiada). Ignorada se o encontro reiniciou ou o inimigo morreu no meio tempo.
func _summon_on_enter(type_id: StringName, count: int, gen: int) -> void:
	if gen != _encounter_gen or defeat_count > 0 or not is_inside_tree():
		return
	_summon(type_id, count, 0, -1)


func _alive_summoned() -> int:
	var alive: Array[Enemy] = []
	for e: Enemy in summoned:
		if is_instance_valid(e) and e.defeat_count == 0 and not e.dismissed:
			alive.append(e)
	summoned = alive
	return alive.size()


## Invoca ate `count` adds de `type_id`, respeitando `max_alive` (0 = livre) e `budget` (-1 = livre).
func _summon(type_id: StringName, count: int, max_alive: int, budget: int) -> int:
	var n: int = count
	if max_alive > 0:
		n = mini(n, max_alive - _alive_summoned())
	if budget >= 0:
		n = mini(n, budget)
	if n <= 0 or type_id == &"":
		return 0
	var made: Array = []
	if summon_handler.is_valid():
		made = summon_handler.call(self, type_id, n)
	else:
		made = _default_summon(type_id, n)
	var created: int = 0
	for e: Variant in made:
		if e is Enemy:
			summoned.append(e as Enemy)
			created += 1
	return created


func _default_summon(type_id: StringName, count: int) -> Array:
	var out: Array = []
	var host: Node = get_parent()
	var path: String = EnemyCatalog.scene_path(type_id)
	if host == null or path == "" or not ResourceLoader.exists(path):
		return out
	var scene: PackedScene = load(path) as PackedScene
	for i: int in count:
		var e: Enemy = scene.instantiate() as Enemy
		if e == null:
			continue
		e.target = target
		host.add_child(e)
		e.global_position = summon_position(global_position, i, count)
		e.set_origin(e.global_position)
		out.append(e)
	return out


## Posicao do add `i` de `count` num anel em volta do invocador.
static func summon_position(center: Vector3, i: int, count: int) -> Vector3:
	var ang: float = TAU * float(i) / float(maxi(count, 1))
	return center + Vector3(cos(ang), 0.0, sin(ang)) * SUMMON_RING_RADIUS


## Remove os adds vivos sem drop/XP (invocador morreu ou encontro reiniciou).
func dismiss_summoned() -> void:
	for e: Enemy in summoned:
		if is_instance_valid(e) and e.defeat_count == 0:
			e.dismiss()
	summoned.clear()


## Sai de cena sem morte "valida": sem drop, sem XP, sem sinal `defeated`.
func dismiss() -> void:
	if dismissed or defeat_count > 0:
		return
	dismissed = true
	defeat_count = 1
	ai.die()
	_end_charge()
	hitbox.end_strike()
	hurtbox.set_deferred("monitorable", false)
	set_deferred("collision_layer", 0)
	velocity = Vector3.ZERO
	var fx: DeathEffect = get_node_or_null("DeathEffect") as DeathEffect
	if fx != null:
		fx.play()
	_corpse_left = CORPSE_TIME


## Estado do encontro volta ao inicio (fase 0, sem ameaca, sem adds, contadores zerados).
func reset_encounter_state() -> void:
	_encounter_gen += 1
	threat.clear()
	dismiss_summoned()
	_summon_totals.clear()
	_invuln_left = 0.0
	_end_charge()
	if phase_ctrl != null:
		phase_ctrl.reset()
		_apply_phase(0)


## Reinicio completo (ex.: todos os jogadores morreram): volta a origem com vida cheia.
func reset_encounter() -> void:
	if ai == null or ai.is_dead():
		return
	hitbox.end_strike()
	global_position = ai.origin
	velocity = Vector3.ZERO
	ai.reset_to_idle()
	health.reset()
	reset_encounter_state()


## Chefes maiores precisam de hurtbox/colisao maiores (copia das formas: as da cena sao compartilhadas).
func _scale_collision() -> void:
	var s: float = data.visual_scale
	if is_equal_approx(s, 1.0):
		return
	for path: String in ["CollisionShape3D", "Hurtbox/CollisionShape3D"]:
		var node: CollisionShape3D = get_node_or_null(path) as CollisionShape3D
		if node == null:
			continue
		var cap: CapsuleShape3D = node.shape as CapsuleShape3D
		if cap != null:
			var copy: CapsuleShape3D = cap.duplicate() as CapsuleShape3D
			copy.radius = cap.radius * s
			copy.height = maxf(cap.height * s, copy.radius * 2.0 + 0.01)
			node.shape = copy
			node.position.y *= s


func _on_died(source: Node) -> void:
	if defeat_count > 0:
		return
	defeat_count += 1
	ai.die()
	_end_charge()
	if data.dismiss_adds_on_death:
		dismiss_summoned()
	hitbox.end_strike()
	hurtbox.set_deferred("monitorable", false)
	set_deferred("collision_layer", 0)
	velocity = Vector3.ZERO
	var drops: Array[LootDrop] = []
	if data.loot_table != null:
		drops = data.loot_table.roll(rng)
	last_drops = drops
	if spawn_pickups:
		_spawn_pickups.call_deferred(drops)
	var xp: int = data.xp_reward
	var loadout: PlayerLoadout = PlayerLoadout.find_for(source)
	if loadout != null:
		loadout.grant_xp(xp)
	var fx: DeathEffect = get_node_or_null("DeathEffect") as DeathEffect
	if fx != null:
		fx.play()
	_corpse_left = CORPSE_TIME
	defeated.emit(self, xp, drops)


func _spawn_pickups(drops: Array[LootDrop]) -> void:
	var host: Node = get_parent()
	if host == null or not is_inside_tree():
		return
	var n: int = drops.size()
	for i: int in n:
		var p: Pickup = Pickup.create(drops[i].item_id, drops[i].quantity)
		if p == null:
			continue
		var ang: float = TAU * float(i) / float(maxi(n, 1))
		var off: Vector3 = Vector3(cos(ang), 0.0, sin(ang)) * (0.6 if n > 1 else 0.0)
		host.add_child(p)
		p.global_position = global_position + off + Vector3(0.0, 0.1, 0.0)
