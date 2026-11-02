extends RefCounted
## E5.2: dados de Greenwood (inimigos, chefes, loot, escalas) carregam e validam; a validacao
## detecta dados sinteticos quebrados. Totalmente deterministico (sem fisica).

const REGULAR: Array[StringName] = [
	&"melee_grunt", &"ranged_caster", &"forest_stalker", &"bow_scout",
	&"bark_brute", &"grove_shaman", &"burrow_lurker", &"root_sprout",
]


func _has_err(errors: Array[String], needle: String) -> bool:
	for e: String in errors:
		if e.contains(needle):
			return true
	return false


func _atk(kind: EnemyAttack.Kind = EnemyAttack.Kind.MELEE) -> EnemyAttack:
	var a: EnemyAttack = EnemyAttack.new()
	a.id = &"x"
	a.kind = kind
	return a


func run(ctx: Object) -> void:
	var reg: ContentRegistry = ContentRegistry.new()
	reg.load_all()
	var errs: Array[String] = reg.validate()
	for e: String in errs:
		print("    erro: ", e)
	ctx.check(errs.is_empty(), "conteudo real (itens+inimigos+loot+dificuldade): 0 erros")
	ctx.check(reg.enemies.size() == 10, "10 inimigos (8 comuns + mini-chefe + chefe): %d" % reg.enemies.size())
	ctx.check(reg.items.size() == 12, "itens: 7 base + 5 unicos de teste E6.3 (12)")
	ctx.check(reg.difficulties.has(&"greenwood_coop"), "escala de dificuldade carregada")

	# 6..8 tipos comuns de Greenwood, ids exatos do catalogo
	ctx.check(EnemyCatalog.GREENWOOD_REGULAR.size() >= 6 and EnemyCatalog.GREENWOOD_REGULAR.size() <= 8, "6-8 tipos comuns (%d)" % EnemyCatalog.GREENWOOD_REGULAR.size())
	var roles: Dictionary = {}
	for id: StringName in EnemyCatalog.all_ids():
		var d: EnemyData = reg.get_enemy(id)
		ctx.check(d != null, "inimigo '%s' registrado" % id)
		if d == null:
			continue
		ctx.check(ResourceLoader.exists(EnemyCatalog.scene_path(id)), "'%s': cena existe" % id)
		var packed: PackedScene = load(EnemyCatalog.scene_path(id)) as PackedScene
		var inst: Enemy = packed.instantiate() as Enemy
		ctx.check(inst != null and inst.data == d, "'%s': cena aponta para o proprio .tres" % id)
		if inst != null:
			inst.free()
		ctx.check(d.loot_table != null and d.loot_table.id == StringName("loot_" + String(id)), "'%s': loot_table loot_%s" % [id, id])
		ctx.check(d.xp_reward > 0 and d.stats.max_health > 0.0, "'%s': xp e vida positivos" % id)
		ctx.check(d.placeholder, "'%s': marcado placeholder" % id)
		roles[d.role] = true
		if d.is_boss():
			ctx.check(d.phases.size() >= 2 and d.attacks.is_empty(), "'%s': chefe com >= 2 fases" % id)
			ctx.check(EnemyPhaseController.validate_order(d.phases).is_empty(), "'%s': limiares decrescentes" % id)
		elif REGULAR.has(id) and id != &"melee_grunt" and id != &"ranged_caster":
			ctx.check(not d.attacks.is_empty(), "'%s': ataques por dados" % id)
		for a: EnemyAttack in d.all_attacks():
			ctx.check(a.windup >= 0.25, "'%s'/%s: telegrafo >= 0.25 s (%.2f)" % [id, a.id, a.windup])
	ctx.check(roles.size() >= 8, "papeis distintos (%d)" % roles.size())
	ctx.check(reg.get_enemy(&"thorn_alpha").tier == &"mini_boss" and reg.get_enemy(&"blight_treant").tier == &"boss", "tiers do mini-chefe e do chefe")
	ctx.check(reg.get_enemy(&"thorn_alpha").phases.size() == 2 and reg.get_enemy(&"blight_treant").phases.size() == 3, "fases: mini=2, chefe=3")
	ctx.check(reg.get_enemy(&"burrow_lurker").ambush and reg.get_enemy(&"grove_shaman").role == &"summoner", "emboscador e invocador")
	var summon_targets: Dictionary = {}
	for id: StringName in EnemyCatalog.all_ids():
		for a: EnemyAttack in reg.get_enemy(id).all_attacks():
			if a.kind == EnemyAttack.Kind.SUMMON:
				summon_targets[a.summon_id] = true
				ctx.check(reg.enemies.has(a.summon_id), "'%s'/%s: summon_id '%s' existe" % [id, a.id, a.summon_id])

	# catalogo: ids seguros
	ctx.check(EnemyCatalog.is_valid_id("bark_brute") and not EnemyCatalog.is_valid_id("../x") and not EnemyCatalog.is_valid_id("") and not EnemyCatalog.is_valid_id("A"), "EnemyCatalog.is_valid_id")
	ctx.check(EnemyCatalog.scene_path(&"../etc") == "" and EnemyCatalog.data_for(&"nao_existe") == null, "id invalido/inexistente => sem caminho/sem dados")
	ctx.check(EnemyCatalog.data_for(&"bark_brute") == reg.get_enemy(&"bark_brute") or EnemyCatalog.data_for(&"bark_brute").id == &"bark_brute", "EnemyCatalog.data_for")

	# --- dados quebrados sinteticos ---
	var bad: ContentRegistry = ContentRegistry.new()
	bad.register_item(_item())
	var a0: EnemyAttack = _atk()
	a0.windup = 0.0
	ctx.check(_has_err(a0.validate(), "windup deve ser > 0"), "ataque sem telegrafo rejeitado")
	var a1: EnemyAttack = _atk(EnemyAttack.Kind.PROJECTILE)
	a1.projectile_count = 99
	ctx.check(_has_err(a1.validate(), "projectile_count"), "projeteis demais rejeitado")
	var a2: EnemyAttack = _atk(EnemyAttack.Kind.SUMMON)
	ctx.check(_has_err(a2.validate(), "SUMMON exige"), "SUMMON sem id/contagem rejeitado")
	a2.summon_id = &"ghost"
	a2.summon_count = 1
	ctx.check(_has_err(a2.validate([&"melee_grunt"]), "inexistente"), "SUMMON com inimigo inexistente rejeitado")
	var a3: EnemyAttack = _atk(EnemyAttack.Kind.CHARGE)
	ctx.check(_has_err(a3.validate(), "CHARGE exige"), "CHARGE sem distancia/velocidade rejeitado")
	var a4: EnemyAttack = _atk()
	a4.min_range = 5.0
	a4.max_range = 2.0
	ctx.check(_has_err(a4.validate(), "faixa de alcance"), "faixa de alcance invertida rejeitada")

	var p0: EnemyPhase = EnemyPhase.new()
	p0.id = &"p0"
	p0.health_threshold = 1.0
	p0.attacks = [_atk()] as Array[EnemyAttack]
	var p1: EnemyPhase = EnemyPhase.new()
	p1.id = &"p1"
	p1.health_threshold = 1.0 # igual ao anterior: invalido
	p1.attacks = [_atk()] as Array[EnemyAttack]
	ctx.check(_has_err(EnemyPhaseController.validate_order([p0, p1] as Array[EnemyPhase]), "estritamente decrescentes"), "limiares repetidos rejeitados")
	p1.health_threshold = 0.5
	p1.transition_time = 99.0
	ctx.check(_has_err(p1.validate(), "transition_time"), "transicao longa demais rejeitada")
	p1.transition_time = 0.0
	p1.attacks = [] as Array[EnemyAttack]
	ctx.check(_has_err(p1.validate(), "sem ataques"), "fase sem ataques rejeitada")

	var boss: EnemyData = EnemyData.new()
	boss.id = &"boss_bad"
	boss.stats = StatUtil.zero()
	boss.stats.max_health = 100.0
	boss.tier = EnemyData.TIER_BOSS
	bad.register_enemy(boss)
	var weird: EnemyData = EnemyData.new()
	weird.id = &"weird"
	weird.stats = StatUtil.zero()
	weird.stats.max_health = 10.0
	weird.tier = &"deus"
	weird.windup = 0.0
	bad.register_enemy(weird)
	var berrs: Array[String] = bad.validate()
	ctx.check(_has_err(berrs, "exige fases"), "chefe sem fases rejeitado")
	ctx.check(_has_err(berrs, "tier invalido"), "tier desconhecido rejeitado")
	ctx.check(_has_err(berrs, "windup deve ser > 0"), "inimigo com windup 0 rejeitado")
	var selfsum: EnemyData = EnemyData.new()
	selfsum.id = &"selfsum"
	selfsum.stats = StatUtil.zero()
	selfsum.stats.max_health = 10.0
	var sa: EnemyAttack = _atk(EnemyAttack.Kind.SUMMON)
	sa.summon_id = &"selfsum"
	sa.summon_count = 1
	selfsum.attacks = [sa] as Array[EnemyAttack]
	var bad2: ContentRegistry = ContentRegistry.new()
	bad2.register_enemy(selfsum)
	ctx.check(_has_err(bad2.validate(), "invoca a si mesmo"), "auto-invocacao rejeitada")


func _item() -> ItemData:
	var it: ItemData = ItemData.new()
	it.id = &"i"
	it.display_name = "i"
	it.stat_modifiers = StatUtil.zero()
	return it
