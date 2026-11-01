extends RefCounted
## E6.2 - modificadores de habilidade dos talentos aplicados no SERVIDOR em tempo de uso: projetil extra, area, custo/cooldown,
## conversao elemental, condicao, sinergia, duracao da esquiva; o SkillData compartilhado nunca muda; builds diferentes produzem
## resultados MEDIDAVELMENTE diferentes (criterio de aceite do roadmap).

const H = preload("res://tests/e2/loop_helpers.gd")
const C = preload("res://tests/e6_classes/class_helpers.gd")
const T = preload("res://tests/e6_talents/talent_helpers.gd")


func run(ctx: Object) -> void:
	var tree: SceneTree = ctx as SceneTree
	await tree.physics_frame
	_test_resolve_pure(ctx)
	await _test_extra_projectiles(ctx, tree)
	await _test_area(ctx, tree)
	await _test_cost_and_cooldown(ctx, tree)
	await _test_conversion(ctx, tree)
	await _test_condition_synergy_duration(ctx, tree)
	await _test_stats(ctx, tree)
	await _test_builds_differ(ctx, tree)
	await _test_reset_on_class_change(ctx, tree)


func _test_resolve_pure(ctx: Object) -> void:
	var sk: SkillData = ClassCatalog.load_skill(&"fireball")
	var before: Dictionary = T.snapshot(sk)
	var r0: SkillMods.Resolved = SkillMods.resolve(sk, [])
	ctx.check(r0.skill == sk and r0.applied == 0, "sem mods: resolve devolve o proprio SkillData")
	var mods: Array = [{"mod": "damage", "damage_pct": 0.5, "rank": 2}, {"mod": "cost", "cost_pct": -0.5, "cooldown_pct": -0.5, "rank": 2}]
	var r: SkillMods.Resolved = SkillMods.resolve(sk, mods)
	ctx.check(r.skill != sk and is_equal_approx(r.skill.damage_multiplier, sk.damage_multiplier * 2.0), "dano +50%% x rank 2 = x2 (copia efetiva)")
	ctx.check(r.skill.resource_cost >= sk.resource_cost * SkillMods.MIN_COST_FACTOR - 0.001 and r.skill.resource_cost < sk.resource_cost, "custo reduzido mas com piso de 25%")
	ctx.check(T.snapshot(sk) == before, "o SkillData compartilhado NAO foi mutado")
	var huge: SkillMods.Resolved = SkillMods.resolve(sk, [{"mod": "damage", "damage_pct": 5.0, "rank": 5}])
	ctx.check(is_equal_approx(huge.skill.damage_multiplier, sk.damage_multiplier * (1.0 + SkillMods.MAX_DAMAGE_BONUS)), "bonus de dano limitado ao teto")
	var many: SkillMods.Resolved = SkillMods.resolve(sk, [{"mod": "extra_projectiles", "count": 3, "spread_deg": 10.0, "damage_scale": 0.5, "rank": 5}])
	ctx.check(many.extra_projectiles == SkillMods.MAX_EXTRA_PROJECTILES, "projeteis extras limitados a %d" % SkillMods.MAX_EXTRA_PROJECTILES)
	var melee: SkillData = ClassCatalog.load_skill(&"heavy_strike")
	var rm: SkillMods.Resolved = SkillMods.resolve(melee, [{"mod": "extra_projectiles", "count": 1, "spread_deg": 10.0, "damage_scale": 0.5, "rank": 1}])
	ctx.check(rm.extra_projectiles == 0 and rm.applied == 0, "projetil extra e ignorado em habilidade corpo a corpo")
	ctx.check(SkillMods.fan_angle(0, 10.0) == 0.0 and SkillMods.fan_angle(1, 10.0) == 10.0 and SkillMods.fan_angle(2, 10.0) == -10.0 and SkillMods.fan_angle(3, 10.0) == 20.0, "leque: 0, +s, -s, +2s")
	var ctx_lo: Dictionary = {"hp_ratio": 0.3}
	var cond: Array = [{"mod": "condition", "when": "self_hp_below", "threshold": 0.5, "damage_pct": 0.25, "rank": 1}]
	ctx.check(SkillMods.resolve(sk, cond, ctx_lo).applied == 1 and SkillMods.resolve(sk, cond, {"hp_ratio": 0.9}).applied == 0, "condicao de vida: so abaixo do limite")
	var syn: Array = [{"mod": "synergy", "after_skill": "frost_nova", "window": 4.0, "damage_pct": 0.4, "rank": 1}]
	ctx.check(SkillMods.resolve(sk, syn, {"clock": 10.0, "last_use": {"frost_nova": 8.0}}).applied == 1, "sinergia dentro da janela")
	ctx.check(SkillMods.resolve(sk, syn, {"clock": 10.0, "last_use": {"frost_nova": 5.0}}).applied == 0 and SkillMods.resolve(sk, syn, {"clock": 10.0, "last_use": {}}).applied == 0, "sinergia fora da janela / sem uso previo")
	ctx.check(T.snapshot(sk) == before, "resolve repetido continua sem mutar o recurso")


func _test_extra_projectiles(ctx: Object, tree: SceneTree) -> void:
	var sk: SkillData = ClassCatalog.load_skill(&"fireball")
	var world: Node3D = H.make_world(tree)
	var base: Player = T.build(world, "mage", "", {})
	var cb: PlayerCombat = C.combat_of(base)
	var got0: Array[SkillProjectile] = T.projectiles_of(cb)
	C.use_to_active(cb, sk)
	ctx.check(got0.size() == 1, "sem talento: 1 bola de fogo")
	var p: Player = T.build(world, "mage", "elementalist", {"e_twin_fireball": 1})
	var c: PlayerCombat = C.combat_of(p)
	var got: Array[SkillProjectile] = T.projectiles_of(c)
	var atk: float = c.health.stats.attack_power
	ctx.check(C.use_to_active(c, sk), "usa fireball com e_twin_fireball")
	ctx.check(got.size() == 2, "e_twin_fireball: 2 projeteis (1 extra)")
	if got.size() == 2:
		ctx.check(is_equal_approx(got[0].damage, atk * sk.damage_multiplier), "projetil central com dano cheio")
		ctx.check(is_equal_approx(got[1].damage, atk * sk.damage_multiplier * 0.6), "projetil extra com 60%% do dano")
		var ang: float = rad_to_deg(got[0].direction.angle_to(got[1].direction))
		ctx.check(absf(ang - 14.0) < 0.1, "extra desviado 14 graus (%.2f)" % ang)
		ctx.check(got[0].hit_id != got[1].hit_id, "cada projetil e um golpe independente (hit_id proprio)")
	var p2: Player = T.build(world, "mage", "elementalist", {"e_twin_fireball": 1, "e_archmage": 1})
	var c2: PlayerCombat = C.combat_of(p2)
	var got2: Array[SkillProjectile] = T.projectiles_of(c2)
	C.use_to_active(c2, sk)
	ctx.check(got2.size() == 3, "twin + archmage: 3 projeteis")
	ctx.check(T.snapshot(sk) == T.snapshot(ClassCatalog.load_skill(&"fireball")), "recurso fireball intacto")
	world.queue_free()
	await tree.physics_frame


func _test_area(ctx: Object, tree: SceneTree) -> void:
	var sk: SkillData = ClassCatalog.load_skill(&"whirlwind")
	var before: Dictionary = T.snapshot(sk)
	# alvo a 3.2 m: fora do raio base (2.6), dentro do raio com +30%% (3.38)
	for case: Array in [["sem talento", {}, false], ["w_wide_swing x2", {"w_wide_swing": 2}, true]]:
		var world: Node3D = H.make_world(tree)
		var p: Player = T.build(world, "warrior", "berserker", case[1] as Dictionary)
		var c: PlayerCombat = C.combat_of(p)
		var target: HealthComponent = C.dummy(world, Vector3(3.2, 0.9, 0.0))
		await tree.physics_frame
		var eff: SkillData = c.resolve_skill(sk).skill
		C.use_to_active(c, sk)
		for i: int in 6:
			await tree.physics_frame
		var dealt: float = target.stats.max_health - target.current_health
		ctx.check((dealt > 0.0) == bool(case[2]), "whirlwind a 3.2m %s: %s (dano %.1f, raio efetivo %.2f)" % [case[0], "acerta" if bool(case[2]) else "nao acerta", dealt, eff.hitbox_size.x])
		world.queue_free()
		await tree.physics_frame
	ctx.check(T.snapshot(sk) == before and ClassCatalog.load_skill(&"whirlwind").hitbox_size == before["size"], "whirlwind compartilhado intacto apos usos com area")
	var world2: Node3D = H.make_world(tree)
	var big: Player = T.build(world2, "warrior", "berserker", {"w_wide_swing": 2, "b_warlord": 1})
	var r: SkillMods.Resolved = C.combat_of(big).resolve_skill(sk)
	ctx.check(is_equal_approx(r.skill.hitbox_size.x, sk.hitbox_size.x * 1.6), "areas acumulam (+30%% +30%%) = x1.6")
	world2.queue_free()
	await tree.physics_frame


func _test_cost_and_cooldown(ctx: Object, tree: SceneTree) -> void:
	var sk: SkillData = ClassCatalog.load_skill(&"heavy_strike")
	var world: Node3D = H.make_world(tree)
	var plain: Player = T.build(world, "warrior", "", {})
	var cp: PlayerCombat = C.combat_of(plain)
	var pool0: float = cp.resource_pool.current
	cp.try_use(sk)
	var spent_plain: float = pool0 - cp.resource_pool.current
	var cd_plain: float = cp.cooldowns.remaining(sk.id)
	var p: Player = T.build(world, "warrior", "berserker", {"w_heavy_focus": 2, "b_warlord": 1})
	var c: PlayerCombat = C.combat_of(p)
	var pool1: float = c.resource_pool.current
	ctx.check(c.try_use(sk), "usa heavy_strike com custo reduzido")
	var spent: float = pool1 - c.resource_pool.current
	ctx.check(is_equal_approx(spent_plain, sk.resource_cost) and spent < spent_plain and is_equal_approx(spent, sk.resource_cost * 0.7), "custo -30%% (rank 2): %.1f -> %.1f" % [spent_plain, spent])
	ctx.check(c.cooldowns.remaining(sk.id) < cd_plain and is_equal_approx(c.cooldowns.remaining(sk.id), sk.cooldown * 0.8), "cooldown -20%% (warlord): %.2f -> %.2f" % [cd_plain, c.cooldowns.remaining(sk.id)])
	# recurso exatamente igual ao custo reduzido: usa; um pouco menos: recusa
	C.reset(c)
	c.resource_pool.current = sk.resource_cost * 0.7 - 0.01
	ctx.check(not c.try_use(sk), "recurso abaixo do custo EFETIVO recusa")
	c.resource_pool.current = sk.resource_cost * 0.7 + 0.01
	ctx.check(c.try_use(sk), "recurso acima do custo efetivo (mas abaixo do base) usa")
	world.queue_free()
	await tree.physics_frame


func _test_conversion(ctx: Object, tree: SceneTree) -> void:
	var world: Node3D = H.make_world(tree)
	var bolt: SkillData = ClassCatalog.load_skill(&"arcane_bolt")
	var m: Player = T.build(world, "mage", "elementalist", {"e_storm_bolt": 1})
	var cm: PlayerCombat = C.combat_of(m)
	var got: Array[SkillProjectile] = T.projectiles_of(cm)
	var atk: float = cm.health.stats.attack_power
	C.use_to_active(cm, bolt)
	ctx.check(got.size() == 1 and got[0].damage_type == &"lightning", "e_storm_bolt: arcane_bolt vira lightning")
	ctx.check(got.size() == 1 and is_equal_approx(got[0].damage, atk * bolt.damage_multiplier * 1.15), "conversao traz +15%% de dano")
	var plain: Player = T.build(world, "mage", "", {})
	var gp: Array[SkillProjectile] = T.projectiles_of(C.combat_of(plain))
	C.use_to_active(C.combat_of(plain), bolt)
	ctx.check(gp.size() == 1 and gp[0].damage_type == &"physical", "sem talento: dano fisico")
	var w: Player = T.build(world, "warrior", "berserker", {"b_searing": 1})
	var cw: PlayerCombat = C.combat_of(w)
	C.use_to_active(cw, ClassCatalog.load_skill(&"heavy_strike"))
	ctx.check(cw.hitbox.damage_type == &"fire", "b_searing: golpe corpo a corpo marcado como fire")
	var hs: SkillData = ClassCatalog.load_skill(&"heavy_strike")
	ctx.check(is_equal_approx(hs.damage_multiplier, ClassCatalog.load_skill(&"heavy_strike").damage_multiplier), "recurso heavy_strike intacto")
	world.queue_free()
	await tree.physics_frame


func _test_condition_synergy_duration(ctx: Object, tree: SceneTree) -> void:
	var world: Node3D = H.make_world(tree)
	var hs: SkillData = ClassCatalog.load_skill(&"heavy_strike")
	var p: Player = T.build(world, "warrior", "berserker", {"b_rage": 1, "b_reckless": 1})
	var c: PlayerCombat = C.combat_of(p)
	var base: float = hs.damage_multiplier
	ctx.check(is_equal_approx(c.resolve_skill(hs).skill.damage_multiplier, base), "vida cheia, sem esquiva previa: sem bonus")
	c.health.current_health = c.health.max_health() * 0.3
	ctx.check(is_equal_approx(c.resolve_skill(hs).skill.damage_multiplier, base * 1.25), "b_rage com vida baixa: +25%%")
	var dodge: SkillData = ClassCatalog.load_skill(&"dodge")
	c.health.current_health = c.health.max_health()
	C.reset(c)
	ctx.check(c.try_use(dodge), "esquiva")
	c.step(dodge.total_duration() + 0.01)
	ctx.check(is_equal_approx(c.resolve_skill(hs).skill.damage_multiplier, base * 1.35), "b_reckless: golpe logo apos esquiva +35%%")
	c.step(3.5)
	ctx.check(is_equal_approx(c.resolve_skill(hs).skill.damage_multiplier, base), "fora da janela de 3s: bonus some")
	# duracao da esquiva
	var q: Player = T.build(world, "warrior", "berserker", {"w_quick_roll": 2})
	var cq: PlayerCombat = C.combat_of(q)
	var eff: SkillData = cq.resolve_skill(dodge).skill
	ctx.check(is_equal_approx(eff.i_frames, minf(dodge.i_frames + 0.16, dodge.total_duration())) and eff.i_frames > dodge.i_frames, "w_quick_roll x2: +0.16s de i-frames (%.2f -> %.2f)" % [dodge.i_frames, eff.i_frames])
	ctx.check(dodge.i_frames == ClassCatalog.load_skill(&"dodge").i_frames, "dodge compartilhado intacto")
	# efeito de outra especializacao/no sem ranks nao vale
	var w2: Player = T.build(world, "warrior", "", {"b_carnage": 2})
	ctx.check(is_equal_approx(C.combat_of(w2).resolve_skill(hs).skill.damage_multiplier, base), "no de especializacao sem a especializacao escolhida e ignorado")
	world.queue_free()
	await tree.physics_frame


func _test_stats(ctx: Object, tree: SceneTree) -> void:
	var world: Node3D = H.make_world(tree)
	var plain: Player = T.build(world, "warrior", "", {})
	var tal: Player = T.build(world, "warrior", "berserker", {"w_vigor": 3, "w_might": 2})
	var s0: StatBlock = PlayerLoadout.find_for(plain).final_stats
	var s1: StatBlock = PlayerLoadout.find_for(tal).final_stats
	ctx.check(s1.max_health > s0.max_health and s1.attack_power > s0.attack_power, "nos de stats aumentam vida (%.0f -> %.0f) e ataque (%.1f -> %.1f)" % [s0.max_health, s1.max_health, s0.attack_power, s1.attack_power])
	var lo: PlayerLoadout = PlayerLoadout.find_for(tal)
	lo.talents = TalentState.new()
	lo.apply_talents()
	ctx.check(is_equal_approx(lo.final_stats.max_health, s0.max_health) and is_equal_approx(lo.final_stats.attack_power, s0.attack_power), "reset dos talentos devolve os stats base")
	world.queue_free()
	await tree.physics_frame


## Criterio de aceite: builds DIFERENTES => resultados medidos DIFERENTES, na mesma situacao.
func _test_builds_differ(ctx: Object, tree: SceneTree) -> void:
	# (a) mago: build "gemeos" x build "tempestade"; alvo fixo a 8 m
	var results: Dictionary = {}
	for b: Array in [["twin", {"e_twin_fireball": 1}], ["plain", {}], ["arc", {"e_arc_flow": 3}]]:
		var world: Node3D = H.make_world(tree)
		var p: Player = T.build(world, "mage", "elementalist", b[1] as Dictionary)
		var c: PlayerCombat = C.combat_of(p)
		var target: HealthComponent = C.dummy(world, Vector3(0.0, 0.9, -4.0))
		await tree.physics_frame
		var got: Array[SkillProjectile] = T.projectiles_of(c)
		var pool0: float = c.resource_pool.current
		C.use_to_active(c, ClassCatalog.load_skill(&"fireball"))
		for pr: SkillProjectile in got:
			for i: int in 20:
				pr.step(0.05)
		await tree.physics_frame
		results[b[0]] = {"dmg": target.stats.max_health - target.current_health, "cost": pool0 - c.resource_pool.current, "n": got.size()}
		world.queue_free()
		await tree.physics_frame
	ctx.check(float(results["twin"]["dmg"]) > float(results["plain"]["dmg"]) * 1.2, "build gemeos causa mais dano que o basico (%.1f vs %.1f)" % [results["twin"]["dmg"], results["plain"]["dmg"]])
	ctx.check(float(results["arc"]["cost"]) < float(results["plain"]["cost"]) and is_equal_approx(float(results["arc"]["dmg"]), float(results["plain"]["dmg"])), "build economia gasta menos recurso com o MESMO dano (%.1f vs %.1f)" % [results["arc"]["cost"], results["plain"]["cost"]])
	ctx.check(int(results["twin"]["n"]) == 2 and int(results["plain"]["n"]) == 1, "gemeos 2 projeteis x basico 1")
	# (b) guerreiro: dano de heavy_strike com e sem carnificina; cada build mede diferente
	var hs: SkillData = ClassCatalog.load_skill(&"heavy_strike")
	var dealt: Dictionary = {}
	for b: Array in [["basic", {}], ["carnage", {"b_carnage": 2}]]:
		var world: Node3D = H.make_world(tree)
		var p: Player = T.build(world, "warrior", "berserker", b[1] as Dictionary)
		var c: PlayerCombat = C.combat_of(p)
		var target: HealthComponent = C.dummy(world, Vector3(0, 0.9, -1.4))
		await tree.physics_frame
		C.use_to_active(c, hs)
		for i: int in 6:
			await tree.physics_frame
		dealt[b[0]] = target.stats.max_health - target.current_health
		world.queue_free()
		await tree.physics_frame
	ctx.check(float(dealt["carnage"]) > float(dealt["basic"]) and absf(float(dealt["carnage"]) / float(dealt["basic"]) - 1.2) < 0.01, "carnificina x2 = +20%% de dano medido (%.1f vs %.1f)" % [dealt["carnage"], dealt["basic"]])


func _test_reset_on_class_change(ctx: Object, tree: SceneTree) -> void:
	var world: Node3D = H.make_world(tree)
	var p: Player = T.build(world, "warrior", "berserker", {"w_vigor": 2, "b_carnage": 1})
	var lo: PlayerLoadout = PlayerLoadout.find_for(p)
	lo.apply_class(ClassCatalog.shared().get_def("mage"))
	ctx.check(lo.talents.is_empty() and C.combat_of(p).skill_mods.is_empty(), "trocar de classe zera talentos e modificadores")
	ctx.check(lo.talent_tree() != null and lo.talent_tree().class_id == "mage", "arvore passa a ser a da nova classe")
	world.queue_free()
	await tree.physics_frame
