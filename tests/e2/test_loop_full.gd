extends RefCounted
## Loop completo em fisica headless: jogador mata inimigo -> loot cai -> pickup -> XP/level.
## Tambem: cooldown/custo ainda respeitados durante o loop e jogador morto nao age.
## DEPENDE DE TIMING (frames reais de fisica a 60 Hz; folgas generosas, limite de 900 frames).

const H = preload("res://tests/e2/loop_helpers.gd")


func run(ctx: Object) -> void:
	var tree: SceneTree = ctx as SceneTree
	var world: Node3D = H.make_world(tree)
	var player: Player = H.spawn_player(world, Vector3(0, 0.05, 0), true)
	var combat: PlayerCombat = player.get_node("Combat") as PlayerCombat
	combat.set_physics_process(true) # neste teste o combate avanca sozinho
	var health: HealthComponent = player.get_node("Health") as HealthComponent
	var loadout: PlayerLoadout = player.get_node("Loadout") as PlayerLoadout
	loadout.progress.add_xp(70) # 70 + 40 do grunt >= 100 => nivel 2
	await tree.physics_frame

	var grunt_data: EnemyData = load("res://data/enemies/melee_grunt.tres") as EnemyData
	var seed_value: int = H.nonempty_seed(grunt_data.loot_table)
	var ref: RandomNumberGenerator = RandomNumberGenerator.new()
	ref.seed = seed_value
	var expected: Dictionary = H.drops_to_dict(grunt_data.loot_table.roll(ref))

	# inimigo logo a frente (facing yaw 0 => -Z), dentro do alcance do golpe basico
	var enemy: Enemy = H.spawn_enemy(world, H.GRUNT_SCENE, Vector3(0, 0.05, -1.8), player, seed_value)
	var defeats: Array[int] = [0]
	enemy.defeated.connect(func(_e: Enemy, _x: int, _d: Array[LootDrop]) -> void: defeats[0] += 1)

	var basic: SkillData = combat.basic_attack
	var uses: int = 0
	var denied_cooldown: int = 0
	var frames: int = 0
	while defeats[0] == 0 and frames < 900:
		if combat.try_use(basic):
			uses += 1
		elif not combat.cooldowns.is_ready(basic.id):
			denied_cooldown += 1
		await tree.physics_frame # PlayerCombat avanca sozinho no physics_process
		frames += 1
		if health.is_dead:
			break
	ctx.check(defeats[0] == 1, "jogador derrubou o inimigo (%d frames, %d golpes)" % [frames, uses])
	ctx.check(uses >= 5, "golpes: 12 ATK vs 60 HP/1 DEF exige >= 6 acertos (usos=%d)" % uses)
	ctx.check(denied_cooldown > 0, "cooldown negou usos extras no loop (%d)" % denied_cooldown)
	ctx.check(enemy.defeat_count == 1, "morte unica")
	ctx.check(H.drops_to_dict(enemy.last_drops) == expected, "loot do loop = loot da semente")
	ctx.check(loadout.progress.level == 2 and loadout.progress.total_xp == 110, "XP 40 somado (70 -> 110) e nivel 2")
	ctx.check(health.stats.max_health == 130.0, "bonus de nivel aplicado no jogador em jogo")

	# loot no chao: leva o jogador ate cada pickup
	for i: int in 3:
		await tree.physics_frame
	var pickups: Array[Pickup] = []
	for c: Node in world.get_children():
		if c is Pickup:
			pickups.append(c as Pickup)
	var on_floor: Dictionary = {}
	for pk: Pickup in pickups:
		on_floor[pk.item_id] = int(on_floor.get(pk.item_id, 0)) + pk.quantity
	ctx.check(on_floor == expected, "pickups no chao = drops: %s" % str(on_floor))
	var starts: Dictionary = {}
	for id: StringName in expected:
		starts[id] = loadout.inventory.count(id)
	player.position = Vector3(0, 0.05, 0)
	var targets: Array[Vector3] = []
	for pk: Pickup in pickups:
		targets.append(pk.global_position)
	for tpos: Vector3 in targets:
		player.global_position = Vector3(tpos.x, 0.05, tpos.z)
		for i: int in 6:
			await tree.physics_frame
	var ok_inv: bool = true
	for id: StringName in expected:
		if loadout.inventory.count(id) != int(starts[id]) + int(expected[id]):
			ok_inv = false
	ctx.check(ok_inv, "inventario recebeu exatamente os drops")
	var left: int = 0
	for c: Node in world.get_children():
		if c is Pickup and not c.is_queued_for_deletion():
			left += 1
	ctx.check(left == 0, "pickups coletados somem do chao")

	# custo de recurso ainda respeitado no loop
	combat.cooldowns.clear()
	await tree.physics_frame
	combat.resource_pool.current = combat.skill_2.resource_cost - 1.0
	var before: float = combat.resource_pool.current
	ctx.check(not combat.try_use(combat.skill_2), "recurso insuficiente: skill negada apos o loop")
	ctx.check(combat.resource_pool.current >= before and combat.cooldowns.is_ready(combat.skill_2.id), "negada: nada gasto, sem cooldown")

	# jogador morto nao age
	health.apply_damage(DamageInfo.make(100000.0, null, Hitbox.new_hit_id()))
	await tree.physics_frame
	ctx.check(health.is_dead and combat.machine.is_dead(), "jogador morto (maquina em DEAD)")
	combat.resource_pool.current = combat.resource_pool.max_value()
	combat.cooldowns.clear()
	ctx.check(not combat.try_use(combat.basic_attack) and not combat.try_use(combat.skill_1) \
		and not combat.try_use(combat.skill_2) and not combat.try_use(combat.dodge_skill), "morto nao ataca nem esquiva")
	player.external_input = Vector2(1, 0)
	var x0: float = player.global_position.x
	for i: int in 10:
		await tree.physics_frame
	ctx.check(absf(player.global_position.x - x0) < 0.01 and player.movement_locked, "morto nao se move mesmo com input")
	world.queue_free()
	await tree.physics_frame
