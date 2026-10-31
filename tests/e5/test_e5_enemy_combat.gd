extends RefCounted
## E5.2: ataques por dados na fisica real (MELEE/AOE/PROJECTILE/CHARGE/SUMMON), fases do chefe,
## morte/loot/dismiss. DEPENDE DE TIMING (frames reais de fisica, com folga); o release do ataque e
## acionado direto (`_on_attack_released`) para isolar a geometria do golpe.

const H = preload("res://tests/e2/loop_helpers.gd")
const DT: float = 1.0 / 60.0


func _spawn(world: Node3D, id: StringName, pos: Vector3, target: Node3D, seed_value: int = 1) -> Enemy:
	var e: Enemy = H.spawn_enemy(world, EnemyCatalog.scene_path(id), pos, target, seed_value)
	e.set_physics_process(false)
	return e


## Forca o release de `attack_id` (como se o telegrafo tivesse acabado) mirando em `dir`.
func _release(e: Enemy, attack_id: StringName, dir: Vector3) -> void:
	var pool: Array[EnemyAttack] = e.ai.attacks.duplicate()
	pool.append_array(e.data.all_attacks())
	for a: EnemyAttack in pool:
		if a.id == attack_id:
			e.ai.current_attack = a
			break
	e.ai.face_dir = dir
	e._on_attack_released()


func _damage_probe(player: Player) -> Array[float]:
	var total: Array[float] = [0.0, 0.0]
	var hc: HealthComponent = player.get_node("Health") as HealthComponent
	hc.damaged.connect(func(_i: DamageInfo, f: float) -> void:
		total[0] += f
		total[1] += 1.0)
	return total


func _wait(tree: SceneTree, frames: int) -> void:
	for i: int in frames:
		await tree.physics_frame


## Avanca o inimigo (para encerrar golpes) sem deixar a IA iniciar outro ataque.
func _settle(tree: SceneTree, e: Enemy, frames: int) -> void:
	e.ai.cooldown_left = 99.0
	for i: int in frames:
		e.step(DT)
		await tree.physics_frame


func run(ctx: Object) -> void:
	var tree: SceneTree = ctx as SceneTree
	await tree.physics_frame
	await _test_aoe_and_melee(ctx, tree)
	await _test_projectiles(ctx, tree)
	await _test_charge(ctx, tree)
	await _test_summon(ctx, tree)
	await _test_boss_phases(ctx, tree)
	await _test_death_and_dismiss(ctx, tree)
	await _test_telegraph_visual(ctx, tree)
	await _test_all_types_engage(ctx, tree)


func _test_aoe_and_melee(ctx: Object, tree: SceneTree) -> void:
	var world: Node3D = H.make_world(tree)
	var near: Player = H.spawn_player(world, Vector3(0, 0.05, -2.5))
	var far: Player = H.spawn_player(world, Vector3(0, 0.05, -9.0))
	var behind: Player = H.spawn_player(world, Vector3(0, 0.05, 2.5))
	var dn: Array[float] = _damage_probe(near)
	var df: Array[float] = _damage_probe(far)
	var db: Array[float] = _damage_probe(behind)
	var brute: Enemy = _spawn(world, &"bark_brute", Vector3(0, 0.05, 0), near)
	await _wait(tree, 3)
	# slam: raio 2.6 a 1.4 m a frente (-Z): atinge o de -2.5, nao o de -9 nem o de tras
	_release(brute, &"slam", Vector3(0, 0, -1))
	await _settle(tree, brute, 14)
	var atk: float = brute.data.stats.attack_power * 1.1
	var expect: float = DamageCalculator.compute(atk, (near.get_node("Health") as HealthComponent).stats.defense, 0.0)
	ctx.check(dn[1] == 1.0 and absf(dn[0] - expect) < 0.01, "slam (AOE) acerta quem esta na area, 1 vez, dano=formula (%.1f)" % dn[0])
	ctx.check(df[1] == 0.0, "slam nao acerta quem esta fora do raio")
	ctx.check(db[1] == 0.0, "slam deslocado a frente nao acerta quem esta atras (2.5 m, raio 2.6 a 1.4 m a frente)")
	ctx.check(not brute.hitbox.active, "hitbox do AOE desliga sozinho")
	# swipe: caixa a frente (largura 2.2, alcance 2.6)
	_release(brute, &"swipe", Vector3(0, 0, 1))
	await _settle(tree, brute, 14)
	ctx.check(db[1] == 1.0, "swipe virado para tras atinge quem esta atras")
	ctx.check(dn[1] == 1.0, "swipe nao atinge quem esta do lado oposto")
	# dificuldade multiplica o dano
	brute.set_difficulty(1.0, 1.3)
	await _settle(tree, brute, 4)
	var before: float = dn[0]
	_release(brute, &"slam", Vector3(0, 0, -1))
	await _settle(tree, brute, 14)
	var scaled: float = DamageCalculator.compute(atk * 1.3, (near.get_node("Health") as HealthComponent).stats.defense, 0.0)
	ctx.check(absf((dn[0] - before) - scaled) < 0.01, "multiplicador de dano de dificuldade aplicado (%.1f)" % (dn[0] - before))
	world.queue_free()
	await tree.physics_frame


func _test_projectiles(ctx: Object, tree: SceneTree) -> void:
	var world: Node3D = H.make_world(tree)
	var player: Player = H.spawn_player(world, Vector3(0, 0.05, -8.0))
	var boss: Enemy = _spawn(world, &"blight_treant", Vector3(0, 0.05, 0), player)
	await _wait(tree, 2)
	# a fase 0 nao tem saraivada; vai para a 1 para usar seed_volley
	boss.health.apply_damage(DamageInfo.make(boss.health.max_health() * 0.4, null, Hitbox.new_hit_id()))
	await _wait(tree, 2)
	ctx.check(boss.phase_index() == 1, "(preparo) chefe a 60%% de vida esta na fase 1")
	var before: int = _count(world, Projectile)
	_release(boss, &"seed_volley", Vector3(0, 0, -1))
	var made: int = _count(world, Projectile) - before
	ctx.check(made == 5, "seed_volley fase 1: 5 projeteis (%d)" % made)
	var dirs: Array[Vector3] = []
	var src_ok: bool = true
	for c: Node in world.get_children():
		if c is Projectile:
			dirs.append((c as Projectile).direction)
			if (c as Projectile).source != boss:
				src_ok = false
	var spread: float = rad_to_deg(dirs[0].angle_to(dirs[dirs.size() - 1]))
	ctx.check(src_ok and absf(spread - 50.0) < 1.0, "abertura total ~50 graus (%.1f) e fonte = chefe" % spread)
	var px: Projectile = null
	for c: Node in world.get_children():
		if c is Projectile:
			px = c as Projectile
			break
	ctx.check(absf(px.damage - boss.data.stats.attack_power * 0.7 * boss._damage_scale()) < 0.01, "dano do projetil = poder x multiplicador do ataque")
	world.queue_free()
	await tree.physics_frame

	# arqueiro: 1 flecha rapida
	world = H.make_world(tree)
	player = H.spawn_player(world, Vector3(0, 0.05, -8.0))
	var archer: Enemy = _spawn(world, &"bow_scout", Vector3(0, 0.05, 0), player)
	await _wait(tree, 2)
	_release(archer, &"arrow", Vector3(0, 0, -1))
	var arrow: Projectile = null
	for c: Node in world.get_children():
		if c is Projectile:
			arrow = c as Projectile
	ctx.check(arrow != null and is_equal_approx(arrow.speed, 20.0) and _count(world, Projectile) == 1, "arqueiro: 1 flecha a 20 m/s")
	world.queue_free()
	await tree.physics_frame


func _count(world: Node, klass: Variant) -> int:
	var n: int = 0
	for c: Node in world.get_children():
		if is_instance_of(c, klass):
			n += 1
	return n


func _test_charge(ctx: Object, tree: SceneTree) -> void:
	var world: Node3D = H.make_world(tree)
	var player: Player = H.spawn_player(world, Vector3(0, 0.05, -4.0))
	var dp: Array[float] = _damage_probe(player)
	var lurker: Enemy = _spawn(world, &"burrow_lurker", Vector3(0, 0.05, 0), player)
	await _wait(tree, 3)
	lurker.ai.cooldown_left = 99.0 # a IA nao inicia outro ataque durante o teste
	_release(lurker, &"pounce", Vector3(0, 0, -1))
	var start_z: float = lurker.global_position.z
	for i: int in 40:
		lurker.step(DT)
		await tree.physics_frame
	var moved: float = start_z - lurker.global_position.z
	ctx.check(moved > 2.5 and moved < 7.5, "bote avanca ate o alvo/6 m (%.1f; o corpo do jogador bloqueia a 3.2 m)" % moved)
	ctx.check(dp[1] == 1.0, "o bote acerta o jogador no caminho uma unica vez (%d)" % int(dp[1]))
	ctx.check(lurker._charge_left <= 0.0 and not lurker.hitbox.active, "investida e hitbox terminam sozinhos")
	var vx: float = Vector2(lurker.velocity.x, lurker.velocity.z).length()
	ctx.check(vx < 0.5 or lurker.ai.move_dir.length() > 0.0, "apos a investida volta ao controle normal")
	world.queue_free()
	await tree.physics_frame


func _test_summon(ctx: Object, tree: SceneTree) -> void:
	var world: Node3D = H.make_world(tree)
	var player: Player = H.spawn_player(world, Vector3(0, 0.05, -8.0))
	var shaman: Enemy = _spawn(world, &"grove_shaman", Vector3(0, 0.05, 0), player)
	await _wait(tree, 2)
	_release(shaman, &"summon_sprouts", Vector3(0, 0, -1))
	ctx.check(_count(world, Enemy) == 3 and shaman.summoned.size() == 2, "invocacao cria 2 brotos (padrao: irmaos no mundo)")
	var all_sprouts: bool = true
	for e: Enemy in shaman.summoned:
		if e.data.id != &"root_sprout" or e.target != player:
			all_sprouts = false
	ctx.check(all_sprouts, "adds sao root_sprout e herdam o alvo")
	_release(shaman, &"summon_sprouts", Vector3(0, 0, -1))
	ctx.check(shaman.summoned.size() == 3, "limite de vivos (3): so +1 (%d)" % shaman.summoned.size())
	shaman._update_blocked_attacks()
	ctx.check(bool(shaman.ai.blocked.get(&"summon_sprouts", false)), "com 3 vivos a IA bloqueia nova invocacao")
	# mata um add: abre vaga; total do encontro limitado a 6
	shaman.summoned[0].health.apply_damage(DamageInfo.make(100000.0, player, Hitbox.new_hit_id()))
	shaman._update_blocked_attacks()
	ctx.check(not bool(shaman.ai.blocked.get(&"summon_sprouts", false)), "morte de um add libera nova invocacao")
	for i: int in 6:
		_release(shaman, &"summon_sprouts", Vector3(0, 0, -1))
		for e: Enemy in shaman.summoned:
			e.health.apply_damage(DamageInfo.make(100000.0, player, Hitbox.new_hit_id()))
	shaman._update_blocked_attacks()
	ctx.check(bool(shaman.ai.blocked.get(&"summon_sprouts", false)) and int(shaman._summon_totals.get(&"summon_sprouts", 0)) == 6, "teto de 6 invocacoes por encontro (anti-farm): %d" % int(shaman._summon_totals.get(&"summon_sprouts", 0)))
	world.queue_free()
	await tree.physics_frame


func _test_boss_phases(ctx: Object, tree: SceneTree) -> void:
	var world: Node3D = H.make_world(tree)
	var player: Player = H.spawn_player(world, Vector3(0, 0.05, -20.0))
	var boss: Enemy = _spawn(world, &"blight_treant", Vector3(0, 0.05, 0), player)
	await _wait(tree, 2)
	var phases: Array[int] = []
	boss.phase_changed.connect(func(_e: Enemy, idx: int) -> void: phases.append(idx))
	var maxhp: float = boss.health.max_health()
	var ids0: Array = boss.ai.attacks.map(func(a: EnemyAttack) -> StringName: return a.id)
	ctx.check(boss.phase_index() == 0 and ids0 == [&"sweep", &"stomp"], "fase 0: varrida + pisao")
	boss.health.apply_damage(DamageInfo.make(maxhp * 0.2, null, Hitbox.new_hit_id()))
	ctx.check(boss.phase_index() == 0 and phases.is_empty(), "80%% de vida: ainda fase 0")
	boss.health.apply_damage(DamageInfo.make(maxhp * 0.15, null, Hitbox.new_hit_id()))
	ctx.check(boss.phase_index() == 1 and phases == [1], "cruzou 66%%: fase 1 (sinal phase_changed uma vez)")
	ctx.check(boss.health.invulnerable and boss.ai.lock_left > 0.9, "transicao: invulneravel e parado por ~1 s")
	var hp_during: float = boss.health.current_health
	var applied: float = boss.health.apply_damage(DamageInfo.make(500.0, null, Hitbox.new_hit_id()))
	ctx.check(applied == 0.0 and boss.health.current_health == hp_during, "dano durante a transicao e ignorado (sem pular fases)")
	var ids1: Array = boss.ai.attacks.map(func(a: EnemyAttack) -> StringName: return a.id)
	ctx.check(ids1.has(&"seed_volley") and ids1.has(&"call_sprouts"), "fase 1 ganha saraivada e invocacao")
	await _wait(tree, 3) # adds da transicao (call_deferred)
	ctx.check(boss.summoned.size() == 3 and _count(world, Enemy) == 4, "entrar na fase 1 invoca 3 brotos (%d)" % boss.summoned.size())
	for i: int in 70: # > 1 s de transicao
		boss.step(DT)
	ctx.check(not boss.health.invulnerable, "invulnerabilidade termina com a transicao")
	# golpe grande cruza 33% de uma vez: so entra na fase 2 (a 1 ja foi)
	boss.health.apply_damage(DamageInfo.make(maxhp * 0.4, null, Hitbox.new_hit_id()))
	ctx.check(boss.phase_index() == 2 and phases == [1, 2], "cruzou 33%%: fase 2 (%s)" % str(phases))
	ctx.check(is_equal_approx(boss._phase_damage_mult, 1.25) and is_equal_approx(boss._phase_speed_mult, 1.2) and is_equal_approx(boss.ai.cooldown_scale, 0.75), "fase 2: dano 1.25x, velocidade 1.2x, pausas 0.75x")
	var ids2: Array = boss.ai.attacks.map(func(a: EnemyAttack) -> StringName: return a.id)
	ctx.check(ids2.has(&"trample") and not ids2.has(&"call_sprouts"), "fase 2: pisoteio, sem invocar brotos")
	# reset do encontro (leash/wipe): volta a fase 0, vida cheia, adds somem
	boss.reset_encounter()
	await _wait(tree, 2)
	ctx.check(boss.phase_index() == 0 and boss.health.current_health == boss.health.max_health() and not boss.health.invulnerable, "reset_encounter: fase 0, vida cheia")
	ctx.check(boss.summoned.is_empty() and boss.ai.state == EnemyAI.State.IDLE, "reset_encounter: adds dispensados e IA em IDLE")
	await _wait(tree, 50) # corpos dos adds somem
	ctx.check(_count(world, Enemy) == 1, "adds dispensados saem do mundo")
	# um golpe letal no chefe nao dispara transicao de fase
	var phases2: Array[int] = []
	boss.phase_changed.connect(func(_e: Enemy, idx: int) -> void: phases2.append(idx))
	boss.health.apply_damage(DamageInfo.make(boss.health.max_health() * 5.0, player, Hitbox.new_hit_id()))
	ctx.check(boss.defeat_count == 1 and phases2.is_empty(), "golpe letal: morre sem trocar de fase")
	world.queue_free()
	await tree.physics_frame


func _test_death_and_dismiss(ctx: Object, tree: SceneTree) -> void:
	var world: Node3D = H.make_world(tree)
	var player: Player = H.spawn_player(world, Vector3(0, 0.05, -20.0))
	var loadout: PlayerLoadout = player.get_node("Loadout") as PlayerLoadout
	var alpha: Enemy = _spawn(world, &"thorn_alpha", Vector3(0, 0.05, 0), player, 5)
	await _wait(tree, 2)
	alpha.health.apply_damage(DamageInfo.make(alpha.health.max_health() * 0.55, player, Hitbox.new_hit_id()))
	ctx.check(alpha.phase_index() == 1, "mini-chefe entra na fase 2 a 45%% de vida")
	await _wait(tree, 3)
	ctx.check(alpha.summoned.size() == 2 and alpha.summoned[0].data.id == &"forest_stalker", "fase 2 do mini-chefe invoca 2 espreitadores")
	var adds: Array[Enemy] = alpha.summoned.duplicate()
	var xp_before: int = loadout.progress.total_xp
	var defeats: Array[int] = [0]
	alpha.defeated.connect(func(_e: Enemy, _x: int, _d: Array[LootDrop]) -> void: defeats[0] += 1)
	for i: int in 70:
		alpha.step(DT)
	alpha.health.apply_damage(DamageInfo.make(100000.0, player, Hitbox.new_hit_id()))
	await _wait(tree, 2)
	ctx.check(defeats[0] == 1 and alpha.defeat_count == 1, "mini-chefe morre uma vez")
	ctx.check(loadout.progress.total_xp == xp_before + 400, "XP do mini-chefe (400) concedido uma vez")
	var table_ids: Dictionary = {}
	for en: LootEntry in alpha.data.loot_table.entries:
		table_ids[en.item_id] = true
	var in_table: bool = not alpha.last_drops.is_empty()
	for dr: LootDrop in alpha.last_drops:
		if not table_ids.has(dr.item_id):
			in_table = false
	ctx.check(in_table and alpha.last_drops.size() >= 1, "drops do mini-chefe vem da propria tabela (%d pilhas)" % alpha.last_drops.size())
	var dismissed_all: bool = true
	for a: Enemy in adds:
		if is_instance_valid(a) and not a.dismissed:
			dismissed_all = false
	ctx.check(dismissed_all, "adds dispensados quando o mini-chefe morre")
	ctx.check(loadout.progress.total_xp == xp_before + 400, "adds dispensados nao dao XP")
	world.queue_free()
	await tree.physics_frame

	# loot do chefe: determinismo por semente, so itens existentes
	var reg: ContentRegistry = ContentRegistry.new()
	reg.load_all()
	var boss_data: EnemyData = reg.get_enemy(&"blight_treant")
	var r1: RandomNumberGenerator = RandomNumberGenerator.new()
	r1.seed = 99
	var r2: RandomNumberGenerator = RandomNumberGenerator.new()
	r2.seed = 99
	var d1: Dictionary = H.drops_to_dict(boss_data.loot_table.roll(r1))
	var d2: Dictionary = H.drops_to_dict(boss_data.loot_table.roll(r2))
	var known: bool = not d1.is_empty()
	for k: StringName in d1:
		if not reg.items.has(k):
			known = false
	ctx.check(d1 == d2 and known, "loot do chefe deterministico por semente e com itens existentes: %s" % str(d1))
	ctx.check(boss_data.loot_table.rolls >= 3 and boss_data.loot_table.nothing_weight == 0.0, "chefe sempre solta varios itens (rolls>=3, sem 'nada')")


func _test_telegraph_visual(ctx: Object, tree: SceneTree) -> void:
	var world: Node3D = H.make_world(tree)
	var player: Player = H.spawn_player(world, Vector3(0, 0.05, -2.0))
	var brute: Enemy = _spawn(world, &"bark_brute", Vector3(0, 0.05, 0), player)
	await _wait(tree, 2)
	ctx.check(not brute.visual.has_telegraph(), "sem telegrafo fora de ATTACK")
	var seen_tg: bool = false
	var seen_id: String = ""
	for i: int in 200:
		brute.step(DT)
		if brute.ai.state == EnemyAI.State.ATTACK:
			seen_id = brute.current_attack_id()
			if brute.visual.has_telegraph():
				seen_tg = true
				break
	ctx.check(seen_tg and seen_id != "", "durante o windup: indicador de chao visivel e atk='%s' replicavel" % seen_id)
	for i: int in 120:
		brute.step(DT)
		if brute.ai.state != EnemyAI.State.ATTACK:
			break
	await tree.process_frame
	ctx.check(brute.current_attack_id() == "" and not brute.visual.has_telegraph(), "apos o golpe: telegrafo some e atk vazio")
	# escala de colisao do chefe (visual_scale 2.2)
	var boss: Enemy = _spawn(world, &"blight_treant", Vector3(20, 0.05, 0), player)
	var shape: CapsuleShape3D = boss.get_node("Hurtbox/CollisionShape3D").shape as CapsuleShape3D
	var base_shape: CapsuleShape3D = brute.get_node("Hurtbox/CollisionShape3D").shape as CapsuleShape3D
	ctx.check(shape.radius > base_shape.radius * 1.5, "hurtbox do chefe e maior (%.2f vs %.2f)" % [shape.radius, base_shape.radius])
	ctx.check((load(EnemyCatalog.scene_path(&"melee_grunt")) as PackedScene).instantiate() != null, "cena base nao foi alterada (compartilhada)")
	world.queue_free()
	await tree.physics_frame


## Cada um dos 10 tipos, com IA e fisica reais, engaja o seu jogador (parado) e o fere em ate 8 s.
func _test_all_types_engage(ctx: Object, tree: SceneTree) -> void:
	var world: Node3D = H.make_world(tree)
	var ids: Array[StringName] = EnemyCatalog.all_ids()
	var probes: Dictionary = {}
	var enemies: Dictionary = {}
	var gap: Dictionary = {&"bow_scout": 8.0, &"ranged_caster": 7.0, &"grove_shaman": 7.0, &"burrow_lurker": 5.0,
		&"blight_treant": 6.0, &"thorn_alpha": 6.0}
	for i: int in ids.size():
		var id: StringName = ids[i]
		var origin: Vector3 = Vector3(float(i) * 70.0 - 300.0, 0.05, 0.0)
		var player: Player = H.spawn_player(world, origin + Vector3(0, 0, -float(gap.get(id, 4.0))))
		probes[id] = _damage_probe(player)
		var e: Enemy = H.spawn_enemy(world, EnemyCatalog.scene_path(id), origin, player, 3)
		enemies[id] = e
		ctx.check(e.visual.get_node_or_null("Body") != null and (e.visual.get_node("Body") as MeshInstance3D).mesh != null and e.visual.get_node_or_null("NameTag") != null, "'%s': visual placeholder montado" % id)
	for f: int in 480:
		await tree.physics_frame
	for id: StringName in ids:
		var e2: Enemy = enemies[id] as Enemy
		var dmg: Array[float] = probes[id] as Array[float]
		var engaged: bool = dmg[1] >= 1.0 or e2.attack_count >= 1
		ctx.check(engaged, "'%s' engaja e ataca de verdade (%d golpes, %d acertos)" % [id, e2.attack_count, int(dmg[1])])
	world.queue_free()
	await tree.physics_frame
