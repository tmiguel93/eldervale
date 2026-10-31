extends RefCounted
## Fisica headless: player vs parede, rampa 25 graus e degrau pequeno.
## Mundo montado em codigo. Usa await physics_frame (pode ser sensivel ao timing da engine).

const PLAYER_SCENE: String = "res://scenes/player/player.tscn"


func run(ctx: Object) -> void:
	var tree: SceneTree = ctx as SceneTree
	await _wall_test(ctx, tree)
	await _ramp_test(ctx, tree)
	await _step_test(ctx, tree)


func _box(parent: Node, pos: Vector3, size: Vector3, rot_x_deg: float = 0.0) -> StaticBody3D:
	var body: StaticBody3D = StaticBody3D.new()
	var col: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	parent.add_child(body)
	body.position = pos
	body.rotation.x = deg_to_rad(rot_x_deg)
	return body


func _make_world(tree: SceneTree) -> Node3D:
	var world: Node3D = Node3D.new()
	tree.root.add_child(world)
	_box(world, Vector3(0, -0.5, 0), Vector3(60, 1, 60))  # chao, topo em y=0
	return world


func _spawn(world: Node3D, tree: SceneTree, pos: Vector3) -> Player:
	var player: Player = (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	player.position = pos  # world esta na origem
	world.add_child(player)
	player.use_external_input = true
	return player


func _frames(tree: SceneTree, n: int) -> void:
	for i: int in n:
		await tree.physics_frame


func _wall_test(ctx: Object, tree: SceneTree) -> void:
	var world: Node3D = _make_world(tree)
	_box(world, Vector3(0, 2, -5), Vector3(10, 4, 1))  # face frontal em z=-4.5
	var p: Player = _spawn(world, tree, Vector3(0, 0.05, 0))
	await _frames(tree, 20)
	ctx.check(p.is_on_floor(), "parede: player assenta no chao")
	p.external_input = Vector2(0, 1)  # frente, yaw 0 => -Z
	await _frames(tree, 300)  # ~5 s a 6 m/s tentaria 30 m
	ctx.check(p.global_position.z < -3.0, "parede: player andou ate perto da parede (z=%.2f)" % p.global_position.z)
	ctx.check(p.global_position.z > -4.5, "parede: nao atravessou (z=%.2f > -4.5)" % p.global_position.z)
	ctx.check(absf(p.global_position.y) < 0.1, "parede: permaneceu no chao (y=%.3f)" % p.global_position.y)
	world.queue_free()
	await _frames(tree, 2)


func _ramp_test(ctx: Object, tree: SceneTree) -> void:
	var world: Node3D = _make_world(tree)
	# Rampa 25 graus subindo para -Z: caixa inclinada em X (rot +25 => lado -Z sobe).
	_box(world, Vector3(0, 0.0, -9), Vector3(6, 0.4, 14), 25.0)
	var p: Player = _spawn(world, tree, Vector3(0, 0.05, 0))
	await _frames(tree, 20)
	p.external_input = Vector2(0, 1)
	await _frames(tree, 180)
	ctx.check(p.global_position.y > 0.8, "rampa 25 graus: player subiu (y=%.2f)" % p.global_position.y)
	ctx.check(p.global_position.z < -3.0, "rampa 25 graus: avancou (z=%.2f)" % p.global_position.z)
	world.queue_free()
	await _frames(tree, 2)


func _step_test(ctx: Object, tree: SceneTree) -> void:
	var world: Node3D = _make_world(tree)
	_box(world, Vector3(0, 0.1, -10), Vector3(10, 0.2, 10))  # degrau de 0.2 m, face em z=-5
	var p: Player = _spawn(world, tree, Vector3(0, 0.05, 0))
	await _frames(tree, 20)
	p.external_input = Vector2(0, 1)
	await _frames(tree, 150)
	ctx.check(p.global_position.z < -6.0, "degrau 0.2 m: subiu e avancou (z=%.2f)" % p.global_position.z)
	ctx.check(absf(p.global_position.y - 0.2) < 0.1, "degrau 0.2 m: apoiado no topo (y=%.3f)" % p.global_position.y)
	world.queue_free()
	await _frames(tree, 2)
