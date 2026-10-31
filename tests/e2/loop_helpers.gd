extends RefCounted
## Utilitarios dos testes de inimigo/loop (nao e um teste: nome sem prefixo test_).

const PLAYER_SCENE: String = "res://scenes/player/player.tscn"
const GRUNT_SCENE: String = "res://scenes/enemy/melee_grunt.tscn"
const CASTER_SCENE: String = "res://scenes/enemy/ranged_caster.tscn"


## Mundo com piso grande (camada 1, topo em y=0).
static func make_world(tree: SceneTree) -> Node3D:
	var world: Node3D = Node3D.new()
	var floor_body: StaticBody3D = StaticBody3D.new()
	var col: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3(300, 1, 300)
	col.shape = shape
	floor_body.add_child(col)
	floor_body.position = Vector3(0, -0.5, 0)
	world.add_child(floor_body)
	tree.root.add_child(world)
	return world


static func spawn_player(world: Node3D, pos: Vector3, physics: bool = false) -> Player:
	var p: Player = (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	p.position = pos
	world.add_child(p)
	p.use_external_input = true
	p.set_physics_process(physics)
	var combat: PlayerCombat = p.get_node("Combat") as PlayerCombat
	combat.read_input_actions = false
	combat.set_physics_process(false) # testes avancam com combat.step()
	return p


static func spawn_enemy(world: Node3D, scene_path: String, pos: Vector3, p_target: Node3D, seed_value: int = -1) -> Enemy:
	var e: Enemy = (load(scene_path) as PackedScene).instantiate() as Enemy
	e.position = pos
	e.target = p_target
	e.loot_seed = seed_value
	world.add_child(e)
	return e


## Primeira semente em [1, 200] cujo roll da tabela nao e vazio.
static func nonempty_seed(table: LootTable) -> int:
	for s: int in range(1, 200):
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = s
		if not table.roll(rng).is_empty():
			return s
	return -1


static func drops_to_dict(drops: Array[LootDrop]) -> Dictionary:
	var d: Dictionary = {}
	for x: LootDrop in drops:
		d[x.item_id] = int(d.get(x.item_id, 0)) + x.quantity
	return d


static func make_dummy_target(world: Node3D, pos: Vector3, hp: float = 500.0) -> HealthComponent:
	var troot: Node3D = Node3D.new()
	var thc: HealthComponent = HealthComponent.new()
	var tstats: StatBlock = StatBlock.new()
	tstats.max_health = hp
	tstats.defense = 0.0
	thc.stats = tstats
	troot.add_child(thc)
	var thb: Hurtbox = Hurtbox.new()
	thb.team = CombatLayers.Team.ENEMY
	thb.health = thc
	var tcol: CollisionShape3D = CollisionShape3D.new()
	var tshape: BoxShape3D = BoxShape3D.new()
	tshape.size = Vector3(0.8, 1.0, 0.8)
	tcol.shape = tshape
	thb.add_child(tcol)
	troot.add_child(thb)
	world.add_child(troot)
	troot.position = pos
	return thc
