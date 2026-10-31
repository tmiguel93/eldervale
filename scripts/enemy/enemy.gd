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

signal defeated(enemy: Enemy, xp: int, drops: Array[LootDrop])

const STRIKE_TIME: float = 0.15
const GRAVITY: float = 24.0
const CORPSE_TIME: float = 0.7

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

var _strike_left: float = 0.0
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
	ai.origin = global_position
	ai.attack_released.connect(_on_attack_released)
	ai.return_timed_out.connect(_on_return_timed_out)
	ai.reset_completed.connect(_on_reset_completed)
	visual.apply(data)
	visual.bind(ai)
	_configure_hitbox()
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
	ai.tick(delta, global_position, tpos, alive)
	var speed: float = data.stats.move_speed
	velocity.x = ai.move_dir.x * speed
	velocity.z = ai.move_dir.z * speed
	if is_on_floor():
		velocity.y = minf(velocity.y, 0.0)
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()
	if ai.face_dir.length_squared() > 0.0001:
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
	var amount: float = data.stats.attack_power * data.attack_damage_multiplier
	if data.behavior == EnemyData.BEHAVIOR_RANGED:
		var proj: Projectile = Projectile.new()
		proj.direction = dir.normalized()
		proj.speed = data.projectile_speed
		proj.damage = amount
		proj.source = self
		var host: Node = get_parent()
		if host != null:
			host.add_child(proj)
			proj.global_position = global_position + Vector3(0.0, 1.0, 0.0) + dir * 0.6
	else:
		hitbox.rotation.y = atan2(-dir.x, -dir.z)
		hitbox.position = dir * data.attack_range * 0.6 + Vector3(0.0, 0.9, 0.0)
		hitbox.begin_strike(amount, self)
		_strike_left = STRIKE_TIME


## Teleporte de seguranca se o retorno a origem travou (anti-softlock).
func _on_return_timed_out() -> void:
	global_position = ai.origin
	velocity = Vector3.ZERO


func _on_reset_completed() -> void:
	health.reset() # leash: volta com vida cheia


func _on_died(source: Node) -> void:
	if defeat_count > 0:
		return
	defeat_count += 1
	ai.die()
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
