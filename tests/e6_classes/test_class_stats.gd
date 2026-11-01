extends RefCounted
## E6.1 - stats por classe e por nivel: base + crescimento, aplicados pelo PlayerLoadout; recurso por classe; builds distintos;
## CharacterCodec (class_id no personagem) sem alterar o formato do checkpoint.

const H = preload("res://tests/e2/loop_helpers.gd")
const C = preload("res://tests/e6_classes/class_helpers.gd")


func run(ctx: Object) -> void:
	var tree: SceneTree = ctx as SceneTree
	await tree.physics_frame
	_test_stats_at_level(ctx)
	_test_loadout_levels(ctx, tree)
	_test_resource_pool_per_class(ctx, tree)
	_test_codec(ctx, tree)
	_test_dev_default_class(ctx, tree)


func _test_stats_at_level(ctx: Object) -> void:
	for cid: String in C.CLASS_IDS:
		var def: ClassDef = ClassCatalog.shared().get_def(cid)
		ctx.check(StatUtil.equals(def.stats_at_level(1), def.base_stats), "%s: nivel 1 = base" % cid)
		var l10: StatBlock = def.stats_at_level(10)
		ctx.check(is_equal_approx(l10.max_health, def.base_stats.max_health + 9.0 * def.growth.max_health), "%s: vida nivel 10" % cid)
		ctx.check(is_equal_approx(l10.attack_power, def.base_stats.attack_power + 9.0 * def.growth.attack_power), "%s: ataque nivel 10" % cid)
		ctx.check(is_equal_approx(l10.max_resource, def.base_stats.max_resource + 9.0 * def.growth.max_resource), "%s: recurso nivel 10" % cid)
		ctx.check(StatUtil.equals(def.stats_at_level(0), def.base_stats) and StatUtil.equals(def.stats_at_level(-5), def.base_stats), "%s: nivel < 1 tratado como 1" % cid)
		ctx.check(l10.max_health > def.stats_at_level(2).max_health, "%s: cresce com o nivel" % cid)
	var w: ClassDef = ClassCatalog.shared().get_def("warrior")
	var m: ClassDef = ClassCatalog.shared().get_def("mage")
	var r: ClassDef = ClassCatalog.shared().get_def("ranger")
	ctx.check(w.stats_at_level(20).max_health > r.stats_at_level(20).max_health and r.stats_at_level(20).max_health > m.stats_at_level(20).max_health, "vida: guerreiro > patrulheiro > mago (nivel 20)")
	ctx.check(m.stats_at_level(20).max_resource > r.stats_at_level(20).max_resource and r.stats_at_level(20).max_resource > w.stats_at_level(20).max_resource, "recurso: mago > patrulheiro > guerreiro (nivel 20)")
	ctx.check(m.stats_at_level(20).attack_power > w.stats_at_level(20).attack_power, "mago tem mais poder de ataque que o guerreiro")
	ctx.check(StatUtil.equals(w.stats_at_level(1), _legacy_backend_base()), "guerreiro nivel 1 = stats base historicos do backend (saves existentes)")


func _legacy_backend_base() -> StatBlock:
	var b: StatBlock = StatBlock.new()
	b.max_health = 100.0
	b.max_resource = 50.0
	b.resource_regen = 5.0
	b.attack_power = 10.0
	b.defense = 0.0
	b.resistance = 0.0
	b.move_speed = 5.0
	return b


func _test_loadout_levels(ctx: Object, tree: SceneTree) -> void:
	var world: Node3D = H.make_world(tree)
	for cid: String in C.CLASS_IDS:
		var def: ClassDef = ClassCatalog.shared().get_def(cid)
		var p: Player = C.spawn(world, cid)
		var lo: PlayerLoadout = PlayerLoadout.find_for(p)
		lo.base_stats = def.base_stats.copy() # como o CharacterCodec faz com o personagem salvo
		lo.recalculate()
		ctx.check(lo.class_id() == cid and lo.class_def == def, "%s: loadout guarda a classe" % cid)
		ctx.check(StatUtil.equals(lo.final_stats, def.stats_at_level(1)), "%s: stats finais nivel 1 (sem equipamento)" % cid)
		lo.progress.level = 12
		lo.recalculate()
		ctx.check(StatUtil.equals(lo.final_stats, def.stats_at_level(12)), "%s: stats finais nivel 12 = base + crescimento da CLASSE" % cid)
		var gained: int = lo.grant_xp(CharacterProgress.total_xp_for_level(15) - lo.progress.total_xp)
		ctx.check(gained >= 1 and lo.progress.level == 15 and StatUtil.equals(lo.final_stats, def.stats_at_level(15)), "%s: subir de nivel reaplica o crescimento da classe" % cid)
		p.queue_free()
	# trocar a classe de um loadout nao reaproveita o crescimento anterior
	var p2: Player = C.spawn(world, "mage")
	var lo2: PlayerLoadout = PlayerLoadout.find_for(p2)
	lo2.base_stats = ClassCatalog.shared().get_def("warrior").base_stats.copy()
	lo2.progress.level = 10
	ctx.check(lo2.apply_class(ClassCatalog.shared().get_def("warrior")), "apply_class devolve true")
	ctx.check(StatUtil.equals(lo2.final_stats, ClassCatalog.shared().get_def("warrior").stats_at_level(10)), "reaplicar classe troca o crescimento")
	var before_class: String = lo2.class_id()
	ctx.check(not lo2.apply_class(null) and lo2.class_id() == before_class, "apply_class(null) recusado sem efeito")
	p2.queue_free()
	world.queue_free()
	await tree.physics_frame


func _test_resource_pool_per_class(ctx: Object, tree: SceneTree) -> void:
	var world: Node3D = H.make_world(tree)
	for cid: String in C.CLASS_IDS:
		var def: ClassDef = ClassCatalog.shared().get_def(cid)
		var p: Player = C.spawn(world, cid)
		var lo: PlayerLoadout = PlayerLoadout.find_for(p)
		lo.base_stats = def.base_stats.copy()
		lo.recalculate()
		var combat: PlayerCombat = C.combat_of(p)
		ctx.check(is_equal_approx(combat.resource_pool.max_value(), def.base_stats.max_resource), "%s: pool de recurso = max_resource da classe" % cid)
		combat.resource_pool.current = 0.0
		combat.resource_pool.tick(1.0)
		ctx.check(is_equal_approx(combat.resource_pool.current, def.base_stats.resource_regen), "%s: regen por segundo da classe (%s)" % [cid, def.resource_kind])
		p.queue_free()
	world.queue_free()
	await tree.physics_frame


func _char(class_id: Variant, level: int = 4, with_class: bool = true) -> Dictionary:
	var def: ClassDef = ClassCatalog.shared().get_def(String(class_id)) if typeof(class_id) == TYPE_STRING else ClassCatalog.shared().default_def()
	var st: StatBlock = def.base_stats
	var ch: Dictionary = {
		"level": level, "xp": CharacterProgress.total_xp_for_level(level), "revision": 1, "inventory_capacity": 24,
		"stats": {"max_health": st.max_health, "max_resource": st.max_resource, "resource_regen": st.resource_regen, "attack_power": st.attack_power,
			"defense": st.defense, "resistance": st.resistance, "move_speed": st.move_speed},
		"inventory": [], "equipment": {}, "quests": {"active": {}, "completed": []},
	}
	if with_class:
		ch["class_id"] = class_id
	return ch


func _test_codec(ctx: Object, tree: SceneTree) -> void:
	var reg: ContentRegistry = ContentRegistry.new()
	reg.load_all()
	for cid: String in C.CLASS_IDS:
		ctx.check(CharacterCodec.validate(_char(cid), reg).is_empty(), "codec: class_id %s valido" % cid)
	ctx.check(CharacterCodec.validate(_char("warrior", 1, false), reg).is_empty(), "codec: class_id ausente (backend antigo) e aceito")
	for bad: Variant in ["necromancer", "Mage", "", 5, null, ["mage"], {"id": "mage"}, "../mage", "mage " + "x".repeat(60)]:
		var ch: Dictionary = _char("mage")
		ch["class_id"] = bad
		ctx.check(not CharacterCodec.validate(ch, reg).is_empty(), "codec: class_id invalido recusado (%s)" % str(bad).left(24))
	var world: Node3D = H.make_world(tree)
	for cid: String in C.CLASS_IDS:
		var def: ClassDef = ClassCatalog.shared().get_def(cid)
		var p: Player = H.spawn_player(world, Vector3.ZERO) # sem classe previa (legado)
		var lo: PlayerLoadout = PlayerLoadout.find_for(p)
		var ch2: Dictionary = _char(cid, 7)
		CharacterCodec.apply(lo, ch2)
		ctx.check(lo.class_id() == cid, "codec.apply: classe %s aplicada" % cid)
		ctx.check(StatUtil.equals(lo.final_stats, def.stats_at_level(7)), "codec.apply: %s nivel 7 = stats da classe" % cid)
		ctx.check(C.combat_of(p).basic_attack.id == StringName(C.SKILLS[cid][0]) and C.combat_of(p).dodge_skill.id == StringName(C.SKILLS[cid][3]), "codec.apply: slots de %s" % cid)
		var cap: Dictionary = CharacterCodec.capture(lo)
		ctx.check(not cap.has("class_id") and cap["level"] == 7, "codec.capture: checkpoint NAO leva class_id (o backend rejeita campo extra; a classe e imutavel)")
		ctx.check(cap.keys().size() == 7, "codec.capture: mesmas chaves do formato schema 1 (%s)" % str(cap.keys()))
		p.queue_free()
	# sem class_id no personagem: cai na classe padrao
	var p3: Player = C.spawn(world, "mage")
	var lo3: PlayerLoadout = PlayerLoadout.find_for(p3)
	CharacterCodec.apply(lo3, _char("warrior", 2, false))
	ctx.check(lo3.class_id() == "warrior", "codec.apply sem class_id => classe padrao")
	p3.queue_free()
	world.queue_free()
	await tree.physics_frame


func _test_dev_default_class(ctx: Object, tree: SceneTree) -> void:
	var rig: Variant = preload("res://tests/e3/server_helpers.gd").make_rig(tree)
	ctx.check(rig.settings.default_class_id == "warrior", "dev: classe padrao do servidor = warrior")
	var eid: int = rig.world.add_player(1, "Dev", false)
	var lo: PlayerLoadout = PlayerLoadout.find_for(rig.world.get_player_node(eid))
	ctx.check(lo.class_id() == "warrior" and lo.base_stats.max_health == 120.0, "dev: guerreiro mantem os stats da cena (E1-E5 intactos)")
	rig.settings.default_class_id = "mage"
	var eid2: int = rig.world.add_player(2, "DevMage", false)
	var lo2: PlayerLoadout = PlayerLoadout.find_for(rig.world.get_player_node(eid2))
	ctx.check(lo2.class_id() == "mage" and StatUtil.equals(lo2.final_stats, ClassCatalog.shared().get_def("mage").base_stats), "dev: --default-class mage aplica stats base do mago")
	rig.settings.default_class_id = "bogus"
	var eid3: int = rig.world.add_player(3, "DevBogus", false)
	ctx.check(PlayerLoadout.find_for(rig.world.get_player_node(eid3)).class_id() == "warrior", "dev: classe padrao invalida cai em warrior")
	rig.free_all()
	await tree.physics_frame
