extends RefCounted
## E6.1 - cada habilidade das 3 classes: custo, cooldown, estados da maquina, alcance, dano, projeteis (velocidade, alcance,
## perfuracao, bloqueio do mundo), areas a distancia e esquivas/mobilidade. Fisica real so para sobreposicao; o tempo e manual.

const H = preload("res://tests/e2/loop_helpers.gd")
const C = preload("res://tests/e6_classes/class_helpers.gd")

var _projectiles: Array[SkillProjectile] = []


func run(ctx: Object) -> void:
	var tree: SceneTree = ctx as SceneTree
	await tree.physics_frame
	await _test_common_rules(ctx, tree)
	await _test_melee_and_areas(ctx, tree)
	await _test_projectiles(ctx, tree)
	await _test_world_block(ctx, tree)
	await _test_mobility(ctx, tree)


func _capture_reason(combat: PlayerCombat) -> Array[StringName]:
	var box: Array[StringName] = []
	combat.skill_failed.connect(func(_s: SkillData, reason: StringName) -> void: box.append(reason))
	return box


## Custo, cooldown, estado da maquina, recusa por cooldown/recurso/ocupado e retorno a IDLE - para os 12 slots.
func _test_common_rules(ctx: Object, tree: SceneTree) -> void:
	var world: Node3D = H.make_world(tree)
	for cid: String in C.CLASS_IDS:
		var p: Player = C.spawn(world, cid)
		var combat: PlayerCombat = C.combat_of(p)
		var reasons: Array[StringName] = _capture_reason(combat)
		combat.projectile_spawned.connect(func(pr: SkillProjectile) -> void: pr.set_physics_process(false); _projectiles.append(pr))
		for sid: String in C.SKILLS[cid]:
			C.reset(combat)
			reasons.clear()
			var skill: SkillData = ClassCatalog.load_skill(StringName(sid))
			var is_dodge: bool = skill.kind == SkillData.Kind.DODGE
			var pool0: float = combat.resource_pool.current
			ctx.check(combat.try_use(skill), "%s/%s: usa" % [cid, sid])
			ctx.check(is_equal_approx(pool0 - combat.resource_pool.current, skill.resource_cost), "%s/%s: consome custo %.0f" % [cid, sid, skill.resource_cost])
			ctx.check(is_equal_approx(combat.cooldowns.remaining(skill.id), skill.cooldown), "%s/%s: cooldown %.2fs iniciado" % [cid, sid, skill.cooldown])
			var want: CharacterStateMachine.State = CharacterStateMachine.State.DODGE if is_dodge else CharacterStateMachine.State.ATTACK
			ctx.check(combat.machine.state == want, "%s/%s: estado %s" % [cid, sid, "DODGE" if is_dodge else "ATTACK"])
			ctx.check(not combat.try_use(skill) and reasons.has(&"busy"), "%s/%s: ocupado recusa novo uso" % [cid, sid])
			combat.step(skill.total_duration() + 0.01)
			ctx.check(combat.machine.state == CharacterStateMachine.State.IDLE, "%s/%s: volta a IDLE em total_duration" % [cid, sid])
			reasons.clear()
			var pool1: float = combat.resource_pool.current
			if combat.cooldowns.remaining(skill.id) > 0.0:
				ctx.check(not combat.try_use(skill) and reasons.has(&"cooldown") and combat.resource_pool.current >= pool1, "%s/%s: cooldown recusa sem gastar" % [cid, sid])
			else:
				ctx.check(skill.cooldown <= skill.total_duration() + 0.011, "%s/%s: cooldown (%.2fs) expira junto com a propria acao" % [cid, sid, skill.cooldown])
			combat.step(skill.cooldown + 0.01)
			if skill.resource_cost > 0.0:
				combat.resource_pool.current = skill.resource_cost - 1.0
				reasons.clear()
				var cur: float = combat.resource_pool.current
				ctx.check(not combat.try_use(skill) and reasons.has(&"resource") and combat.resource_pool.current == cur and combat.cooldowns.is_ready(skill.id), "%s/%s: recurso insuficiente recusa sem efeitos" % [cid, sid])
				combat.resource_pool.current = skill.resource_cost
				ctx.check(combat.try_use(skill), "%s/%s: recurso exatamente suficiente usa" % [cid, sid])
			combat.step(skill.total_duration() + 0.01)
		p.queue_free()
	world.queue_free()
	await tree.physics_frame


## Dano exato (ataque * multiplicador, defesa 0) e geometria das habilidades corpo a corpo e de area.
func _test_melee_and_areas(ctx: Object, tree: SceneTree) -> void:
	# nome, classe, skill, posicao do alvo (relativa ao jogador, frente = -Z), deve acertar?
	var cases: Array = [
		["heavy_strike", "warrior", "heavy_strike", Vector3(0, 0.9, -1.4), true],
		["heavy_strike longe", "warrior", "heavy_strike", Vector3(0, 0.9, -4.0), false],
		["whirlwind lado", "warrior", "whirlwind", Vector3(2.0, 0.9, 0.0), true],
		["whirlwind fora", "warrior", "whirlwind", Vector3(4.0, 0.9, 0.0), false],
		["frost_nova perto", "mage", "frost_nova", Vector3(0, 0.9, 3.0), true],
		["frost_nova fora do raio", "mage", "frost_nova", Vector3(0, 0.9, 5.0), false],
		["arrow_rain no centro", "ranger", "arrow_rain", Vector3(0, 0.9, -6.0), true],
		["arrow_rain a 2m do centro", "ranger", "arrow_rain", Vector3(2.0, 0.9, -6.0), true],
		["arrow_rain colado no jogador", "ranger", "arrow_rain", Vector3(0, 0.9, -1.0), false],
		["arrow_rain alem da area", "ranger", "arrow_rain", Vector3(0, 0.9, -11.0), false],
	]
	for c: Array in cases:
		var world: Node3D = H.make_world(tree)
		var p: Player = C.spawn(world, String(c[1]))
		var combat: PlayerCombat = C.combat_of(p)
		var target: HealthComponent = C.dummy(world, c[3] as Vector3)
		await tree.physics_frame
		var skill: SkillData = ClassCatalog.load_skill(StringName(c[2]))
		var expected: float = combat.health.stats.attack_power * skill.damage_multiplier
		ctx.check(C.use_to_active(combat, skill), "%s: dispara" % c[0])
		for i: int in 6:
			await tree.physics_frame
		var dealt: float = target.stats.max_health - target.current_health
		if bool(c[4]):
			ctx.check(absf(dealt - expected) < 0.01, "%s: acerta com dano %.1f (esperado %.1f)" % [c[0], dealt, expected])
		else:
			ctx.check(dealt == 0.0, "%s: fora do alcance, sem dano" % c[0])
		combat.step(skill.total_duration())
		for i: int in 3:
			await tree.physics_frame
		ctx.check(absf((target.stats.max_health - target.current_health) - (expected if bool(c[4]) else 0.0)) < 0.01, "%s: um unico golpe (sem dano repetido)" % c[0])
		world.queue_free()
		await tree.physics_frame


func _spawn_proj_player(world: Node3D, class_id: String) -> Array:
	var p: Player = C.spawn(world, class_id)
	var combat: PlayerCombat = C.combat_of(p)
	var got: Array[SkillProjectile] = []
	combat.projectile_spawned.connect(func(pr: SkillProjectile) -> void:
		pr.set_physics_process(false) # o teste avanca o projetil manualmente (deterministico)
		got.append(pr))
	return [p, combat, got]


func _test_projectiles(ctx: Object, tree: SceneTree) -> void:
	var specs: Array = [["mage", "arcane_bolt"], ["mage", "fireball"], ["ranger", "quick_shot"], ["ranger", "piercing_arrow"]]
	for sp: Array in specs:
		var cid: String = sp[0]
		var sid: String = sp[1]
		var skill: SkillData = ClassCatalog.load_skill(StringName(sid))
		# --- parametros do projetil vem da skill; dano calculado pelo servidor ---
		var world: Node3D = H.make_world(tree)
		var pack: Array = _spawn_proj_player(world, cid)
		var combat: PlayerCombat = pack[1]
		var got: Array[SkillProjectile] = pack[2]
		ctx.check(C.use_to_active(combat, skill), "%s: dispara" % sid)
		ctx.check(got.size() == 1, "%s: exatamente 1 projetil" % sid)
		var pr: SkillProjectile = got[0]
		var amount: float = combat.health.stats.attack_power * skill.damage_multiplier
		ctx.check(is_equal_approx(pr.speed, skill.projectile_speed) and is_equal_approx(pr.max_range, skill.projectile_range) and pr.pierce == skill.projectile_pierce, "%s: velocidade/alcance/perfuracao da skill" % sid)
		ctx.check(is_equal_approx(pr.damage, amount) and is_equal_approx(pr.radius, skill.hitbox_size.x), "%s: dano %.1f e raio %.2f" % [sid, pr.damage, pr.radius])
		ctx.check(pr.direction.is_equal_approx(Vector3(0, 0, -1)), "%s: segue o facing (-Z)" % sid)
		ctx.check(pr.global_position.is_equal_approx(Vector3(0.0, 0.9, -skill.hitbox_offset)), "%s: nasce a frente do jogador" % sid)
		ctx.check(pr.get_parent() == world and pr.source == pack[0], "%s: vive no mundo, origem = jogador" % sid)
		# --- alcance: sem alvos percorre exatamente projectile_range e expira ---
		var expired: Array[int] = [0]
		pr.expired.connect(func() -> void: expired[0] += 1)
		var z0: float = pr.global_position.z
		C.run_projectile(pr, 0.05)
		ctx.check(pr.consumed and expired[0] == 1 and absf(pr.traveled - skill.projectile_range) < 0.001, "%s: expira apos %.1f m (percorreu %.2f)" % [sid, skill.projectile_range, pr.traveled])
		ctx.check(absf((z0 - pr.global_position.z) - skill.projectile_range) < 0.01, "%s: posicao final coerente" % sid)
		world.queue_free()
		await tree.physics_frame

		# --- acerta o primeiro alvo (dano exato) e some quando nao perfura ---
		var world2: Node3D = H.make_world(tree)
		var pack2: Array = _spawn_proj_player(world2, cid)
		var combat2: PlayerCombat = pack2[1]
		var near: HealthComponent = C.dummy(world2, Vector3(0, 0.9, -7.0))
		var far: HealthComponent = C.dummy(world2, Vector3(0, 0.9, -10.0))
		var beyond: HealthComponent = C.dummy(world2, Vector3(0, 0.9, -(skill.projectile_range + 6.0)))
		var side: HealthComponent = C.dummy(world2, Vector3(3.0, 0.9, -7.0))
		await tree.physics_frame
		C.use_to_active(combat2, skill)
		var pr2: SkillProjectile = (pack2[2] as Array[SkillProjectile])[0]
		var amount2: float = combat2.health.stats.attack_power * skill.damage_multiplier
		var hits: Array[int] = [0]
		pr2.hit_target.connect(func(_h: Hurtbox, _a: float) -> void: hits[0] += 1)
		C.run_projectile(pr2, 0.05)
		var d_near: float = near.stats.max_health - near.current_health
		var d_far: float = far.stats.max_health - far.current_health
		ctx.check(absf(d_near - amount2) < 0.01, "%s: acerta o primeiro alvo (%.1f)" % [sid, d_near])
		ctx.check(side.current_health == side.stats.max_health, "%s: alvo fora da trajetoria intacto" % sid)
		ctx.check(beyond.current_health == beyond.stats.max_health, "%s: alvo alem do alcance intacto" % sid)
		if skill.projectile_pierce == 0:
			ctx.check(hits[0] == 1 and far.current_health == far.stats.max_health, "%s: sem perfuracao: some no 1o alvo" % sid)
		else:
			ctx.check(hits[0] == 2 and absf(d_far - amount2) < 0.01, "%s: perfura e acerta o 2o alvo" % sid)
		ctx.check(pr2.consumed, "%s: projetil consumido" % sid)
		world2.queue_free()
		await tree.physics_frame

	# --- perfuracao: pierce 2 acerta 3 alvos em linha e para no 4o ---
	var world3: Node3D = H.make_world(tree)
	var pack3: Array = _spawn_proj_player(world3, "ranger")
	var combat3: PlayerCombat = pack3[1]
	var arrow: SkillData = ClassCatalog.load_skill(&"piercing_arrow")
	var line: Array[HealthComponent] = []
	for i: int in 4:
		line.append(C.dummy(world3, Vector3(0, 0.9, -5.0 - 3.0 * float(i))))
	await tree.physics_frame
	C.use_to_active(combat3, arrow)
	var pr3: SkillProjectile = (pack3[2] as Array[SkillProjectile])[0]
	C.run_projectile(pr3, 0.05)
	var amount3: float = combat3.health.stats.attack_power * arrow.damage_multiplier
	var dmg: Array[float] = []
	for h: HealthComponent in line:
		dmg.append(h.stats.max_health - h.current_health)
	ctx.check(absf(dmg[0] - amount3) < 0.01 and absf(dmg[1] - amount3) < 0.01 and absf(dmg[2] - amount3) < 0.01 and dmg[3] == 0.0, "piercing_arrow: acerta 3 alvos em linha e para no 4o %s" % str(dmg))
	ctx.check(pr3.hits == 3, "piercing_arrow: contou 3 acertos")
	world3.queue_free()
	await tree.physics_frame

	# --- cada alvo so recebe UM golpe do mesmo projetil, e dois projeteis sao golpes distintos ---
	var world4: Node3D = H.make_world(tree)
	var pack4: Array = _spawn_proj_player(world4, "mage")
	var combat4: PlayerCombat = pack4[1]
	var bolt: SkillData = ClassCatalog.load_skill(&"arcane_bolt")
	var tgt: HealthComponent = C.dummy(world4, Vector3(0, 0.9, -5.0))
	await tree.physics_frame
	C.use_to_active(combat4, bolt)
	combat4.step(bolt.total_duration() + bolt.cooldown)
	C.use_to_active(combat4, bolt)
	var ps: Array[SkillProjectile] = pack4[2]
	ctx.check(ps.size() == 2 and ps[0].hit_id != ps[1].hit_id, "dois disparos = dois hit_id distintos")
	C.run_projectile(ps[0], 0.05)
	C.run_projectile(ps[1], 0.05)
	var a4: float = combat4.health.stats.attack_power * bolt.damage_multiplier
	ctx.check(absf((tgt.stats.max_health - tgt.current_health) - 2.0 * a4) < 0.01, "dois disparos distintos causam 2 golpes")
	world4.queue_free()
	await tree.physics_frame

	# --- atacante removido: projetil nao causa dano nem erro ---
	var world5: Node3D = H.make_world(tree)
	var pack5: Array = _spawn_proj_player(world5, "mage")
	var tgt5: HealthComponent = C.dummy(world5, Vector3(0, 0.9, -4.0))
	await tree.physics_frame
	C.use_to_active(pack5[1], ClassCatalog.load_skill(&"fireball"))
	var pr5: SkillProjectile = (pack5[2] as Array[SkillProjectile])[0]
	(pack5[0] as Player).free()
	pr5.step(0.1)
	ctx.check(pr5.consumed and tgt5.current_health == tgt5.stats.max_health, "dono removido: projetil morre sem dano")
	world5.queue_free()
	await tree.physics_frame


func _test_world_block(ctx: Object, tree: SceneTree) -> void:
	var world: Node3D = H.make_world(tree)
	var wall: StaticBody3D = StaticBody3D.new()
	var col: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(6, 4, 0.5)
	col.shape = box
	wall.add_child(col)
	world.add_child(wall)
	wall.position = Vector3(0, 2, -5.0)
	var pack: Array = _spawn_proj_player(world, "ranger")
	var behind: HealthComponent = C.dummy(world, Vector3(0, 0.9, -9.0))
	await tree.physics_frame
	var shot: SkillData = ClassCatalog.load_skill(&"quick_shot")
	C.use_to_active(pack[1], shot)
	var pr: SkillProjectile = (pack[2] as Array[SkillProjectile])[0]
	C.run_projectile(pr, 0.05)
	ctx.check(pr.consumed and pr.traveled < 5.0, "parede do mundo consome o projetil (%.2f m)" % pr.traveled)
	ctx.check(behind.current_health == behind.stats.max_health, "alvo atras da parede intacto")
	world.queue_free()
	await tree.physics_frame


func _test_mobility(ctx: Object, tree: SceneTree) -> void:
	var world: Node3D = H.make_world(tree)
	var distances: Dictionary = {}
	for cid: String in C.CLASS_IDS:
		var p: Player = C.spawn(world, cid)
		var combat: PlayerCombat = C.combat_of(p)
		var skill: SkillData = combat.dodge_skill
		ctx.check(skill.kind == SkillData.Kind.DODGE, "%s: slot de mobilidade e esquiva" % cid)
		ctx.check(combat.try_use(skill), "%s/%s: inicia" % [cid, skill.id])
		ctx.check(combat.health.invulnerable, "%s/%s: i-frames ao iniciar" % [cid, skill.id])
		combat.step(0.001)
		var moved: float = p.forced_velocity.length() * (skill.windup + skill.active)
		distances[cid] = moved
		ctx.check(p.use_forced_velocity and absf(moved - skill.dodge_distance) < 0.01, "%s/%s: desloca %.2f m (dado %.2f)" % [cid, skill.id, moved, skill.dodge_distance])
		var hp: float = combat.health.current_health
		var attacker: Node = Node.new()
		ctx.check(combat.health.apply_damage(DamageInfo.make(20.0, attacker, 700000 + cid.length())) == 0.0 and combat.health.current_health == hp, "%s/%s: dano bloqueado nos i-frames" % [cid, skill.id])
		combat.step(skill.i_frames + 0.01)
		ctx.check(not combat.health.invulnerable, "%s/%s: i-frames terminam em %.2fs" % [cid, skill.id, skill.i_frames])
		combat.step(skill.total_duration())
		ctx.check(not p.use_forced_velocity and combat.machine.state == CharacterStateMachine.State.IDLE, "%s/%s: deslocamento termina" % [cid, skill.id])
		attacker.free()
		p.queue_free()
	ctx.check(float(distances["mage"]) > float(distances["warrior"]) and float(distances["mage"]) > float(distances["ranger"]), "blink e o maior deslocamento (mobilidade do mago)")
	world.queue_free()
	await tree.physics_frame
