extends RefCounted
## Morte do inimigo: uma vez so; um drop e um XP; loot deterministico por semente.
## Usa 1-2 await physics_frame apenas para os pickups (instanciados em call_deferred).

const H = preload("res://tests/e2/loop_helpers.gd")


func run(ctx: Object) -> void:
	var tree: SceneTree = ctx as SceneTree
	var world: Node3D = H.make_world(tree)
	var player: Player = H.spawn_player(world, Vector3(0, 0.05, 0))
	var loadout: PlayerLoadout = player.get_node("Loadout") as PlayerLoadout
	await tree.physics_frame

	var grunt_data: EnemyData = load("res://data/enemies/melee_grunt.tres") as EnemyData
	var seed_value: int = H.nonempty_seed(grunt_data.loot_table)
	ctx.check(seed_value > 0, "ha uma semente com drop nao vazio (%d)" % seed_value)

	# esperado direto da tabela, com a mesma semente
	var ref_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	ref_rng.seed = seed_value
	var expected: Dictionary = H.drops_to_dict(grunt_data.loot_table.roll(ref_rng))

	var enemy: Enemy = H.spawn_enemy(world, H.GRUNT_SCENE, Vector3(0, 0.05, -30), player, seed_value)
	enemy.set_physics_process(false)
	ctx.check(enemy.health.stats.max_health == grunt_data.stats.max_health, "vida vem do EnemyData")
	ctx.check(enemy.health.stats != grunt_data.stats, "stats do inimigo sao copia (recurso intacto)")
	ctx.check(enemy.hurtbox.collision_layer == CombatLayers.ENEMY_HURT, "Hurtbox na camada 3")
	ctx.check(enemy.hitbox.collision_layer == CombatLayers.ENEMY_HIT and enemy.hitbox.collision_mask == CombatLayers.PLAYER_HURT, "Hitbox na camada 5, mascara player_hurt")

	var deaths: Array[int] = [0]
	var xp_seen: Array[int] = [0]
	enemy.defeated.connect(func(_e: Enemy, xp: int, _d: Array[LootDrop]) -> void:
		deaths[0] += 1
		xp_seen[0] = xp)
	var lethal: DamageInfo = DamageInfo.make(100000.0, player, Hitbox.new_hit_id())
	enemy.health.apply_damage(lethal)
	enemy.health.apply_damage(DamageInfo.make(100000.0, player, Hitbox.new_hit_id()))
	ctx.check(deaths[0] == 1 and enemy.defeat_count == 1, "morre exatamente uma vez (segundo golpe ignorado)")
	ctx.check(enemy.ai.is_dead(), "IA parada (DEAD)")
	ctx.check(xp_seen[0] == grunt_data.xp_reward and loadout.progress.total_xp == grunt_data.xp_reward, "XP concedido uma vez (%d)" % loadout.progress.total_xp)
	ctx.check(H.drops_to_dict(enemy.last_drops) == expected, "loot deterministico por semente: %s" % str(expected))
	# chamar o handler de novo (simula sinal duplicado) nao duplica nada
	enemy._on_died(player)
	ctx.check(enemy.defeat_count == 1 and loadout.progress.total_xp == grunt_data.xp_reward, "handler repetido nao duplica XP/drop")

	await tree.physics_frame
	await tree.physics_frame
	var pickups: Array[Pickup] = []
	for c: Node in world.get_children():
		if c is Pickup:
			pickups.append(c as Pickup)
	var picked: Dictionary = {}
	for p: Pickup in pickups:
		picked[p.item_id] = int(picked.get(p.item_id, 0)) + p.quantity
	ctx.check(picked == expected, "pickups no chao = drops rolados (%d pilhas)" % pickups.size())

	# segundo inimigo, mesma semente => mesmos drops
	var e2: Enemy = H.spawn_enemy(world, H.GRUNT_SCENE, Vector3(5, 0.05, -30), player, seed_value)
	e2.set_physics_process(false)
	e2.health.apply_damage(DamageInfo.make(100000.0, null, Hitbox.new_hit_id()))
	ctx.check(H.drops_to_dict(e2.last_drops) == expected, "outro inimigo, mesma semente: mesmos drops")
	ctx.check(loadout.progress.total_xp == grunt_data.xp_reward, "morte sem fonte (source nulo) nao concede XP")

	# caster: malha diferente do grunt
	var caster: Enemy = H.spawn_enemy(world, H.CASTER_SCENE, Vector3(10, 0.05, -30), player)
	caster.set_physics_process(false)
	var gm: Mesh = (enemy.get_node("Visual/Body") as MeshInstance3D).mesh
	var cm: Mesh = (caster.get_node("Visual/Body") as MeshInstance3D).mesh
	ctx.check(gm is BoxMesh and cm is CylinderMesh, "placeholders distintos por tipo (caixa vs cone)")
	ctx.check(caster.data.behavior == EnemyData.BEHAVIOR_RANGED and caster.health.stats.max_health == 40.0, "caster configurado pelo EnemyData")

	world.queue_free()
	await tree.physics_frame
