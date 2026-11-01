extends RefCounted
## E6.2 - dados de talentos: validacao do JSON (grafo acíclico, tiers, mestria unica, efeitos), referencias contra classes/skills/itens,
## curva de pontos e paridade com o catalogo gerado para o backend (shared/content_schemas/talents.json).

const T = preload("res://tests/e6_talents/talent_helpers.gd")
const CLASSES: Array[String] = ["warrior", "mage", "ranger"]


func run(ctx: Object) -> void:
	var tree: SceneTree = ctx as SceneTree
	await tree.physics_frame
	_test_catalog(ctx)
	_test_parse_errors(ctx)
	_test_points(ctx)
	_test_backend_parity(ctx)


func _raw(cid: String) -> Dictionary:
	return T.read_json("res://data/talents/%s.json" % cid) as Dictionary


func _test_catalog(ctx: Object) -> void:
	var cat: TalentCatalog = TalentCatalog.shared()
	ctx.check(cat.load_errors.is_empty(), "catalogo carrega sem erros: %s" % str(cat.load_errors))
	var reg: ContentRegistry = ContentRegistry.new()
	reg.load_all()
	var refs: Array[String] = cat.validate_refs(ClassCatalog.shared(), reg)
	ctx.check(refs.is_empty(), "referencias validas (classes, skills, itens do respec): %s" % str(refs))
	for cid: String in CLASSES:
		var t: TalentTree = cat.get_tree(cid)
		ctx.check(t != null, "%s: tem arvore" % cid)
		if t == null:
			continue
		ctx.check(t.nodes.size() >= 12 and t.nodes.size() <= 18, "%s: 12-18 nos (%d)" % [cid, t.nodes.size()])
		var tiers: Dictionary = {"small": 0, "notable": 0, "mastery": 0}
		var generic: int = 0
		for id: String in t.order:
			var n: Dictionary = t.nodes[id]
			tiers[String(n["tier"])] += 1
			if String(n["spec"]) == "":
				generic += 1
		ctx.check(int(tiers["mastery"]) == 1 and int(tiers["small"]) > 0 and int(tiers["notable"]) > 0, "%s: tiers small/notable e 1 mestria %s" % [cid, str(tiers)])
		ctx.check(generic >= 4 and t.nodes.size() - generic >= 5, "%s: nos genericos (%d) + de especializacao (%d)" % [cid, generic, t.nodes.size() - generic])
		ctx.check(t.specs.size() == 1, "%s: 1 especializacao inicial (%s)" % [cid, str(t.specs)])
		ctx.check(t.total_cost() > cat.points_for_level(50), "%s: arvore (%d pts) maior que os pontos do nivel 50 (%d) - escolhas importam" % [cid, t.total_cost(), cat.points_for_level(50)])
		var mastery: String = ""
		for id: String in t.order:
			if String((t.nodes[id] as Dictionary)["tier"]) == "mastery":
				mastery = id
		ctx.check(t.depth(mastery) >= 2 and int((t.nodes[mastery] as Dictionary)["min_points_spent"]) > 0, "%s: mestria e profunda e exige pontos gastos" % cid)
	ctx.check(cat.respec_require_safe_zone and not cat.respec_cost_items.is_empty(), "respec: custo em itens e exige zona segura (configuravel)")


func _test_parse_errors(ctx: Object) -> void:
	var good: Dictionary = _raw("warrior")
	ctx.check(TalentTree.parse(good)["tree"] != null, "base valida parseia")
	var cases: Array = [
		["ciclo", func(d: Dictionary) -> void: d["nodes"][0]["requires"] = [d["nodes"][3]["id"]], "ciclo"],
		["requisito inexistente", func(d: Dictionary) -> void: d["nodes"][1]["requires"] = ["fantasma"], "fantasma"],
		["auto-requisito", func(d: Dictionary) -> void: d["nodes"][1]["requires"] = [d["nodes"][1]["id"]], ""],
		["duas mestrias", func(d: Dictionary) -> void: d["nodes"][0]["tier"] = "mastery", ""],
		["sem mestria", func(d: Dictionary) -> void:
			for n: Dictionary in d["nodes"]:
				if n["tier"] == "mastery":
					n["tier"] = "notable", ""],
		["id duplicado", func(d: Dictionary) -> void: d["nodes"][1]["id"] = d["nodes"][0]["id"], ""],
		["max_rank absurdo", func(d: Dictionary) -> void: d["nodes"][0]["max_rank"] = 99, ""],
		["custo zero", func(d: Dictionary) -> void: d["nodes"][0]["cost"] = 0, ""],
		["tier invalido", func(d: Dictionary) -> void: d["nodes"][0]["tier"] = "epic", ""],
		["efeito desconhecido", func(d: Dictionary) -> void: d["nodes"][0]["effects"] = [{"type": "teleport"}], ""],
		["stat desconhecido", func(d: Dictionary) -> void: d["nodes"][0]["effects"] = [{"type": "stat", "stat": "luck", "amount": 1}], ""],
		["mod desconhecido", func(d: Dictionary) -> void: d["nodes"][0]["effects"] = [{"type": "skill_mod", "skill": "heavy_strike", "mod": "nuke"}], ""],
		["schema_version", func(d: Dictionary) -> void: d["schema_version"] = 7, ""],
		["no generico exige no de spec", func(d: Dictionary) -> void: d["nodes"][0]["requires"] = ["b_frenzy"], ""],
		["campo extra", func(d: Dictionary) -> void: d["nodes"][0]["hax"] = 1, ""],
	]
	for c: Array in cases:
		var d: Dictionary = good.duplicate(true)
		(c[1] as Callable).call(d)
		var r: Dictionary = TalentTree.parse(d)
		var errs: Array = r["errors"] as Array
		ctx.check(r["tree"] == null and not errs.is_empty(), "invalido recusado: %s" % c[0])
		if String(c[2]) != "":
			var found: bool = false
			for e: Variant in errs:
				found = found or String(e).contains(String(c[2]))
			ctx.check(found, "mensagem de '%s' cita '%s'" % [c[0], c[2]])
	ctx.check(TalentTree.parse(null)["tree"] == null and TalentTree.parse([])["tree"] == null, "raiz que nao e objeto e recusada")


func _test_points(ctx: Object) -> void:
	var cat: TalentCatalog = TalentCatalog.shared()
	ctx.check(cat.points_for_level(1) == 0 and cat.points_for_level(0) == 0 and cat.points_for_level(-3) == 0, "nivel 1 (ou invalido): 0 pontos")
	ctx.check(cat.points_for_level(2) == 1 and cat.points_for_level(10) == 9 and cat.points_for_level(50) == 49, "1 ponto por nivel a partir do 2 (10 -> 9, 50 -> 49)")
	ctx.check(cat.points_for_level(10000) == cat.max_points, "limite max_points")
	var prev: int = 0
	var mono: bool = true
	for l: int in range(1, 80):
		var v: int = cat.points_for_level(l)
		mono = mono and v >= prev
		prev = v
	ctx.check(mono, "curva monotonica")
	# curva configuravel por dado: arquivo temporario em user:// com 2 pontos por nivel a partir do 3
	var dir: String = "user://e6_talents_cfg"
	DirAccess.make_dir_recursive_absolute(dir)
	var f: FileAccess = FileAccess.open(dir + "/_progression.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"points": {"first_point_level": 3, "points_per_level": 2, "max_points": 10}, "respec": {"cost_items": [], "require_safe_zone": false}}))
	f.close()
	var custom: TalentCatalog = TalentCatalog.load_dir(dir)
	ctx.check(custom.points_for_level(2) == 0 and custom.points_for_level(3) == 2 and custom.points_for_level(5) == 6 and custom.points_for_level(99) == 10, "curva vinda do dado: 2/nivel desde o 3, teto 10")
	ctx.check(not custom.respec_require_safe_zone and custom.respec_cost_items.is_empty(), "respec configuravel (sem custo, sem zona segura)")


## Godot e backend leem o MESMO dado: o catalogo gerado precisa espelhar o que o Godot carregou.
func _test_backend_parity(ctx: Object) -> void:
	var gen: Variant = T.read_json("res://shared/content_schemas/talents.json")
	ctx.check(typeof(gen) == TYPE_DICTIONARY, "talents.json gerado existe")
	if typeof(gen) != TYPE_DICTIONARY:
		return
	var cat: TalentCatalog = TalentCatalog.shared()
	var g: Dictionary = gen
	ctx.check(int(g["points"]["first_point_level"]) == 2 and int(g["points"]["points_per_level"]) == 1 and int(g["points"]["max_points"]) == cat.max_points, "curva de pontos igual")
	ctx.check(int(g["respec"]["cost_items"][0]["qty"]) == int(cat.respec_cost_items[0]["qty"]) and String(g["respec"]["cost_items"][0]["item_id"]) == String(cat.respec_cost_items[0]["item_id"]), "custo do respec igual")
	ctx.check((g["trees"] as Array).size() == cat.ids().size(), "mesmo numero de arvores")
	for t: Dictionary in g["trees"]:
		var gt: TalentTree = cat.get_tree(String(t["class_id"]))
		ctx.check(gt != null and (t["nodes"] as Array).size() == gt.nodes.size(), "%s: mesmo numero de nos" % t["class_id"])
		if gt == null:
			continue
		var same: bool = true
		for n: Dictionary in t["nodes"]:
			var d: Dictionary = gt.get_node_def(String(n["id"]))
			same = same and not d.is_empty() and int(d["cost"]) == int(n["cost"]) and int(d["max_rank"]) == int(n["max_rank"]) \
				and String(d["spec"]) == String(n["spec"]) and int(d["min_points_spent"]) == int(n["min_points_spent"]) \
				and int(d["min_level"]) == int(n["min_level"]) and (d["requires"] as Array) == (n["requires"] as Array)
		ctx.check(same, "%s: custo/rank/spec/requisitos identicos ao catalogo do backend" % t["class_id"])
		ctx.check((t["specs"] as Array) == gt.specs, "%s: especializacoes iguais" % t["class_id"])
