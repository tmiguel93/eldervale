extends RefCounted
## E6.4: conteudo ampliado (12 quests, exploracao, NPCs) e parse/validacao dos novos tipos de objetivo e pontos de exploracao.

func run(ctx: Object) -> void:
	var tree: SceneTree = ctx as SceneTree
	await tree.physics_frame
	_test_quest_set(ctx)
	_test_exploration_data(ctx)
	_test_new_objective_types(ctx)
	_test_exploration_parse_negative(ctx)
	_test_state_discovered(ctx)
	_test_tracker_new_events(ctx)


func _ids(a: Array) -> Array[String]:
	var out: Array[String] = []
	for x: Variant in a:
		out.append(String(x))
	return out


func _test_quest_set(ctx: Object) -> void:
	var cat: QuestCatalog = QuestCatalog.load_dir()
	ctx.check(cat.load_errors.is_empty(), "catalogo carrega sem erros: %s" % str(cat.load_errors))
	ctx.check(cat.ids().size() >= 10 and cat.ids().size() <= 15, "10-15 quests em Greenwood (%d)" % cat.ids().size())
	var types: Dictionary = {}
	var objs: Dictionary = {}
	var rare_ref: bool = false
	var reg: ContentRegistry = ContentRegistry.new()
	reg.load_all()
	for id: String in cat.ids():
		var q: QuestDef = cat.get_quest(id)
		types[q.type] = true
		for o: QuestDef.Objective in q.objectives:
			objs[o.type] = true
		for it: Dictionary in q.reward_items:
			var item: ItemData = reg.items.get(StringName(it["item_id"])) as ItemData
			if item != null and item.rarity >= ItemData.Rarity.RARE:
				rare_ref = true
	ctx.check(rare_ref, "ao menos uma recompensa de quest e item raro/unico (referencia valida)")
	for t: String in QuestDef.OBJECTIVE_TYPES:
		ctx.check(objs.has(t), "tipo de objetivo '%s' usado por alguma quest" % t)
	ctx.check(types.size() >= 6, "variedade de tipos de quest (%d)" % types.size())
	ctx.check(cat.get_quest("gw_rootsong").reward_items.any(func(i: Dictionary) -> bool: return String(i["item_id"]) == "unique_featherknot"), "capstone paga o unico unique_featherknot")
	# cadeia: toda quest com pre-requisitos aponta para quests existentes e a raiz e gw_welcome
	var roots: int = 0
	for id: String in cat.ids():
		var q: QuestDef = cat.get_quest(id)
		if q.prereq_quests.is_empty():
			roots += 1
		for p: String in q.prereq_quests:
			ctx.check(cat.get_quest(p) != null, "%s: pre-requisito %s existe" % [id, p])
	ctx.check(roots == 1 and cat.get_quest("gw_welcome").prereq_quests.is_empty(), "uma unica raiz (gw_welcome)")
	var npcs: NpcDirectory = NpcDirectory.load_dir()
	var areas: AreaSet = AreaSet.load_dir()
	var refs: Array[String] = cat.validate_refs(reg, npcs, areas, QuestCatalog.load_pending_refs(), ExplorationCatalog.load_dir())
	ctx.check(refs.is_empty(), "referencias de quests (incl. craft/discover) consistentes: %s" % str(refs))
	var dlg: DialogueCatalog = DialogueCatalog.load_dir(DialogueCatalog.DIALOGUES_DIR, cat.ids())
	ctx.check(dlg.load_errors.is_empty(), "dialogos novos carregam: %s" % str(dlg.load_errors))
	for npc_id: String in ["npc_smith_dorran", "npc_mapper_pell", "npc_warden_lysa"]:
		ctx.check(npcs.has_npc(npc_id) and dlg.for_npc(npc_id) != null, "NPC novo %s com dialogo" % npc_id)
	var w: WorldDef = WorldDef.shared()
	ctx.check(w.validate(npcs, areas, areas.ids()).is_empty(), "mundo valido com os NPCs novos: %s" % str(w.validate(npcs, areas, areas.ids())))


func _test_exploration_data(ctx: Object) -> void:
	var ex: ExplorationCatalog = ExplorationCatalog.load_dir()
	ctx.check(ex.load_errors.is_empty(), "exploracao carrega sem erros: %s" % str(ex.load_errors))
	ctx.check(ex.ids().size() >= 6, "ao menos 6 atividades de exploracao (%d)" % ex.ids().size())
	var zones: Dictionary = {}
	var kinds: Dictionary = {}
	for id: String in ex.ids():
		var p: Dictionary = ex.get_point(id)
		zones[p["zone"]] = true
		kinds[p["kind"]] = true
		ctx.check(int(p["xp"]) > 0 or not (p["items"] as Array).is_empty(), "%s: tem recompensa" % id)
	ctx.check(zones.size() == 3, "pontos distribuidos nas 3 zonas (%s)" % str(zones.keys()))
	ctx.check(kinds.has("landmark") and kinds.has("chest") and kinds.has("secret"), "marcos, baus e segredos")
	var reg: ContentRegistry = ContentRegistry.new()
	reg.load_all()
	var errs: Array[String] = ex.validate_refs(reg, WorldDef.shared(), QuestCatalog.shared())
	ctx.check(errs.is_empty(), "exploracao: zonas/itens/quests consistentes: %s" % str(errs))
	# cilindro de descoberta
	var c: Vector3 = (ex.get_point("poi_wild_fallen_oak")["center"] as Vector3)
	ctx.check(ex.contains("poi_wild_fallen_oak", c) and not ex.contains("poi_wild_fallen_oak", c + Vector3(50, 0, 0)) and not ex.contains("poi_wild_fallen_oak", c + Vector3(0, 30, 0)), "contains: dentro / longe / acima")
	ctx.check(not ex.contains("poi_inexistente", c), "ponto desconhecido nunca contem")
	# backend: catalogo gerado bate com os dados
	var gen: Dictionary = JsonDir.read_json("res://shared/content_schemas/exploration.json")
	ctx.check(bool(gen["ok"]) and ((gen["data"] as Dictionary)["points"] as Array).size() == ex.ids().size(), "shared/content_schemas/exploration.json tem os mesmos pontos")
	for gp: Variant in (gen["data"] as Dictionary)["points"]:
		var mine: Dictionary = ex.get_point(String((gp as Dictionary)["id"]))
		ctx.check(not mine.is_empty() and int(((gp as Dictionary)["rewards"] as Dictionary)["xp"]) == int(mine["xp"]), "catalogo gerado: xp de %s confere" % String((gp as Dictionary)["id"]))


func _valid_quest() -> Dictionary:
	return {
		"schema_version": 1, "id": "t_quest", "type": "exploration", "region": "greenwood", "title": "T", "title_key": "k.t", "description": "D", "description_key": "k.d",
		"giver_npc": "npc_elder_orla", "turn_in_npc": "npc_elder_orla", "prerequisites": {"quests": [], "min_level": 1},
		"objectives": [{"id": "o1", "type": "discover", "target": "poi_wild_fallen_oak", "required": 1, "text": "x", "text_key": "k.o"}],
		"rewards": {"xp": 10, "items": []},
	}


func _test_new_objective_types(ctx: Object) -> void:
	ctx.check(QuestDef.parse(_valid_quest())["def"] != null, "objetivo discover valido")
	var d: Dictionary = _valid_quest()
	d["objectives"][0]["required"] = 2
	ctx.check(QuestDef.parse(d)["def"] == null, "discover exige required = 1")
	var c: Dictionary = _valid_quest()
	c["objectives"][0] = {"id": "o1", "type": "craft", "target": "potion_minor", "required": 3, "text": "x", "text_key": "k.o"}
	ctx.check(QuestDef.parse(c)["def"] != null, "craft aceita required > 1")
	var bad: Dictionary = _valid_quest()
	bad["objectives"][0]["type"] = "teleport"
	ctx.check(QuestDef.parse(bad)["def"] == null, "tipo desconhecido segue recusado")
	# refs: ponto inexistente / item de craft inexistente
	var reg: ContentRegistry = ContentRegistry.new()
	reg.load_all()
	var cat: QuestCatalog = QuestCatalog.new()
	var q: QuestDef = QuestDef.parse(_valid_quest())["def"]
	q.objectives[0].target = "poi_fantasma"
	cat.add(q)
	var errs: Array[String] = cat.validate_refs(reg, NpcDirectory.shared(), AreaSet.shared(), {}, ExplorationCatalog.shared())
	ctx.check(errs.any(func(e: String) -> bool: return e.contains("poi_fantasma")), "discover para ponto inexistente detectado")
	var cat2: QuestCatalog = QuestCatalog.new()
	var q2: QuestDef = QuestDef.parse(_valid_quest())["def"]
	q2.objectives[0].type = QuestDef.OBJ_CRAFT
	q2.objectives[0].target = "item_fantasma"
	cat2.add(q2)
	ctx.check(cat2.validate_refs(reg, NpcDirectory.shared(), AreaSet.shared(), {}, ExplorationCatalog.shared()).any(func(e: String) -> bool: return e.contains("item_fantasma")), "craft de item inexistente detectado")


func _poi() -> Dictionary:
	return {"id": "poi_t", "kind": "chest", "zone": "zone_hub", "display_name": "T", "text": "x", "center": [0, 0, 0], "radius": 2.0, "min_level": 1,
		"requires_quests": [], "rewards": {"xp": 5, "items": [{"item_id": "potion_minor", "qty": 1}]}}


func _test_exploration_parse_negative(ctx: Object) -> void:
	var ex: ExplorationCatalog = ExplorationCatalog.new()
	ctx.check(ex.add_dict(_poi()) == "", "ponto valido")
	ctx.check(ex.add_dict(_poi()) != "", "id duplicado rejeitado")
	var cases: Array = [
		["kind invalido", func(d: Dictionary) -> void: d["kind"] = "tesouro"],
		["id invalido", func(d: Dictionary) -> void: d["id"] = "Bad-Id"],
		["raio 0", func(d: Dictionary) -> void: d["radius"] = 0.0],
		["raio enorme", func(d: Dictionary) -> void: d["radius"] = 500.0],
		["center curto", func(d: Dictionary) -> void: d["center"] = [1, 2]],
		["center nao finito", func(d: Dictionary) -> void: d["center"] = [1, INF, 2]],
		["min_level 0", func(d: Dictionary) -> void: d["min_level"] = 0],
		["recompensa vazia", func(d: Dictionary) -> void: d["rewards"] = {"xp": 0, "items": []}],
		["xp enorme", func(d: Dictionary) -> void: d["rewards"]["xp"] = 999999],
		["qty 0", func(d: Dictionary) -> void: d["rewards"]["items"][0]["qty"] = 0],
		["item repetido", func(d: Dictionary) -> void: d["rewards"]["items"].append({"item_id": "potion_minor", "qty": 1})],
		["texto vazio", func(d: Dictionary) -> void: d["text"] = " "],
		["requires nao e lista", func(d: Dictionary) -> void: d["requires_quests"] = "gw_welcome"],
		["zone invalida", func(d: Dictionary) -> void: d["zone"] = "Zona X"],
	]
	var n: int = 0
	for cs: Array in cases:
		var d: Dictionary = _poi()
		d["id"] = "poi_neg_%d" % n
		n += 1
		(cs[1] as Callable).call(d)
		if String(cs[0]) == "id invalido":
			d["id"] = "Bad-Id"
		ctx.check(ex.add_dict(d) != "", "ponto invalido rejeitado: " + String(cs[0]))
	ctx.check(ex.add_dict("lixo") != "" and ex.add_dict(null) != "", "raiz nao-objeto rejeitada")
	# refs quebradas
	var reg: ContentRegistry = ContentRegistry.new()
	reg.load_all()
	var e2: ExplorationCatalog = ExplorationCatalog.new()
	var p: Dictionary = _poi()
	p["rewards"]["items"][0]["item_id"] = "item_fantasma"
	p["requires_quests"] = ["quest_fantasma"]
	p["zone"] = "zone_fantasma"
	e2.add_dict(p)
	ctx.check(e2.validate_refs(reg, WorldDef.shared(), QuestCatalog.shared()).size() >= 3, "zona/item/quest inexistentes detectados")
	var e3: ExplorationCatalog = ExplorationCatalog.new()
	var far: Dictionary = _poi()
	far["center"] = [9000, 0, 9000]
	e3.add_dict(far)
	ctx.check(e3.validate_refs(reg, WorldDef.shared(), QuestCatalog.shared()).any(func(e: String) -> bool: return e.contains("fora da zona")), "ponto fora da zona detectado")


func _test_state_discovered(ctx: Object) -> void:
	var s: QuestState = QuestState.new()
	ctx.check(s.to_dict() == {"active": {}, "completed": []}, "estado sem descobertas mantem o formato antigo")
	s.discovered.append("poi_wild_old_milestone")
	s.discovered.append("poi_hub_hollow_stump")
	var d: Dictionary = s.to_dict()
	ctx.check(d["discovered"] == ["poi_hub_hollow_stump", "poi_wild_old_milestone"], "discovered serializado ordenado")
	var r: QuestState = QuestState.new()
	ctx.check(r.restore(d, QuestCatalog.shared()).is_empty() and r.discovered.size() == 2, "restore devolve as descobertas")
	var w: Array[String] = r.restore({"active": {}, "completed": [], "discovered": ["poi_hub_hollow_stump", "poi_fantasma", "poi_hub_hollow_stump"]}, QuestCatalog.shared())
	ctx.check(r.discovered == ([ "poi_hub_hollow_stump" ] as Array[String]) and w.size() == 1, "restore leniente: desconhecido descartado, duplicata colapsada")
	ctx.check(QuestState.shape_error({"active": {}, "completed": [], "discovered": "x"}) != "", "forma: discovered nao-lista recusada")
	ctx.check(QuestState.shape_error({"active": {}, "completed": [], "discovered": ["Bad Id"]}) != "", "forma: id invalido recusado")
	ctx.check(QuestState.shape_error({"active": {}, "completed": []}) == "", "forma antiga continua valida")


func _test_tracker_new_events(ctx: Object) -> void:
	var t: QuestTracker = QuestTracker.new(QuestCatalog.shared())
	t.state.completed.append("gw_welcome")
	ctx.check(bool(t.accept("gw_wild_survey", 1)["ok"]), "aceitar gw_wild_survey")
	ctx.check(t.on_poi_discovered("poi_wild_fallen_oak") and t.state.progress_of("gw_wild_survey", "find_oak") == 1, "descoberta avanca o objetivo discover")
	ctx.check(not t.on_poi_discovered("poi_wild_fallen_oak") and t.state.progress_of("gw_wild_survey", "find_oak") == 1, "descobrir de novo nao repete")
	ctx.check(t.status_of("gw_wild_survey", 1) == "active", "ainda falta um marco")
	t.on_poi_discovered("poi_wild_old_milestone")
	ctx.check(t.status_of("gw_wild_survey", 1) == "ready", "dois marcos: pronta")
	# descoberta ANTES de aceitar conta ao aceitar (a descoberta e unica; senao a quest travaria)
	var t2: QuestTracker = QuestTracker.new(QuestCatalog.shared())
	t2.state.completed.append("gw_welcome")
	t2.on_poi_discovered("poi_wild_fallen_oak")
	t2.on_poi_discovered("poi_wild_old_milestone")
	var ready_seen: Array[String] = []
	t2.quest_ready.connect(func(q: String) -> void: ready_seen.append(q))
	t2.accept("gw_wild_survey", 1)
	ctx.check(t2.status_of("gw_wild_survey", 1) == "ready" and ready_seen == (["gw_wild_survey"] as Array[String]), "pontos ja descobertos contam ao aceitar (pronta na hora)")
	# craft soma quantidade, so com a quest ativa
	var t3: QuestTracker = QuestTracker.new(QuestCatalog.shared())
	t3.state.completed.append_array(["gw_welcome", "gw_scrap_for_orla"] as Array[String])
	ctx.check(t3.on_item_crafted("potion_minor", 1) == 0, "craft sem quest ativa nao conta")
	t3.accept("gw_bench_lessons", 1)
	t3.on_item_crafted("potion_minor", 1)
	t3.on_item_crafted("scrap_material", 5)
	ctx.check(t3.state.progress_of("gw_bench_lessons", "craft_potions") == 1, "craft de outro item nao conta; quantidade soma")
	t3.on_item_crafted("potion_minor", 9)
	ctx.check(t3.state.progress_of("gw_bench_lessons", "craft_potions") == 2 and t3.status_of("gw_bench_lessons", 1) == "ready", "craft limitado a required")
