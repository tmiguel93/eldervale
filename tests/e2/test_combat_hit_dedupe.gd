extends RefCounted
## Hitbox/Hurtbox com fisica headless real: um unico dano por golpe (hit_id).
## Depende de await physics_frame; usa folgas de frames (pode ser sensivel ao timing da engine).


func _frames(tree: SceneTree, n: int) -> void:
	for i: int in n:
		await tree.physics_frame


func _make_target(world: Node3D, pos: Vector3) -> HealthComponent:
	var root: Node3D = Node3D.new()
	var hc: HealthComponent = HealthComponent.new()
	hc.name = "Health"
	var stats: StatBlock = StatBlock.new()
	stats.max_health = 1000.0
	stats.defense = 0.0
	hc.stats = stats
	root.add_child(hc)
	var hb: Hurtbox = Hurtbox.new()
	hb.team = CombatLayers.Team.ENEMY
	hb.health = hc
	var col: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3(1, 1, 1)
	col.shape = shape
	hb.add_child(col)
	root.add_child(hb)
	world.add_child(root)
	root.position = pos
	return hc


func run(ctx: Object) -> void:
	var tree: SceneTree = ctx as SceneTree
	var world: Node3D = Node3D.new()
	tree.root.add_child(world)
	var a: HealthComponent = _make_target(world, Vector3(0, 0, 0))
	var b: HealthComponent = _make_target(world, Vector3(0.3, 0, 0))
	var far: HealthComponent = _make_target(world, Vector3(20, 0, 0))

	var attacker: Node3D = Node3D.new()
	world.add_child(attacker)
	var hitbox: Hitbox = Hitbox.new()
	hitbox.setup_team(CombatLayers.Team.PLAYER)
	var hcol: CollisionShape3D = CollisionShape3D.new()
	var hshape: BoxShape3D = BoxShape3D.new()
	hshape.size = Vector3(4, 2, 4)
	hcol.shape = hshape
	hitbox.add_child(hcol)
	attacker.add_child(hitbox)
	await _frames(tree, 3)

	ctx.check(a.current_health == 1000.0, "hitbox inativo nao causa dano")
	var id1: int = hitbox.begin_strike(10.0, attacker)
	await _frames(tree, 12) # varios frames sobrepostos
	ctx.check(a.current_health == 990.0, "alvo A recebe 1 dano em varios frames (hp=%.1f)" % a.current_health)
	ctx.check(b.current_health == 990.0, "alvo B tambem recebe exatamente 1 dano (hp=%.1f)" % b.current_health)
	ctx.check(far.current_health == 1000.0, "alvo fora da area nao recebe dano")

	# sai e entra na area durante o MESMO golpe
	var a_root: Node3D = a.get_parent() as Node3D
	a_root.position = Vector3(20, 0, 5)
	await _frames(tree, 4)
	a_root.position = Vector3(0, 0, 0)
	await _frames(tree, 6)
	ctx.check(a.current_health == 990.0, "re-entrada no mesmo golpe nao repete dano (hp=%.1f)" % a.current_health)

	# entrega direta do mesmo (source, hit_id) tambem e ignorada pelo Hurtbox
	var hurt: Hurtbox = a_root.get_child(1) as Hurtbox
	var dup: DamageInfo = DamageInfo.make(10.0, attacker, id1)
	ctx.check(hurt.receive_hit(dup) == 0.0 and a.current_health == 990.0, "Hurtbox ignora (source, hit_id) repetido")

	# novo golpe = novo hit_id = novo dano
	hitbox.end_strike()
	await _frames(tree, 2)
	var id2: int = hitbox.begin_strike(10.0, attacker)
	ctx.check(id2 != id1, "hit_id novo por golpe")
	await _frames(tree, 8)
	ctx.check(a.current_health == 980.0, "segundo golpe causa novo dano (hp=%.1f)" % a.current_health)
	hitbox.end_strike()
	await _frames(tree, 5)
	ctx.check(a.current_health == 980.0, "sem dano depois do fim do golpe")

	world.queue_free()
	await _frames(tree, 2)
