extends RefCounted
## E5.1: conteudo de quests/dialogos/NPCs/areas (data/**) e o parse/validacao do schema.

func run(ctx: Object) -> void:
	_test_real_content(ctx)
	_test_quest_parse_negative(ctx)
	_test_npc_and_area_parse(ctx)
	_test_ref_validation_negative(ctx)


func _valid_quest() -> Dictionary:
	return {
		"schema_version": 1, "id": "t_quest", "type": "hunt", "region": "greenwood",
		"title": "T", "title_key": "k.t", "description": "D", "description_key": "k.d",
		"giver_npc": "npc_elder_orla", "turn_in_npc": "npc_elder_orla",
		"prerequisites": {"quests": [], "min_level": 1},
		"objectives": [{"id": "o1", "type": "kill", "target": "melee_grunt", "required": 2, "text": "x", "text_key": "k.o"}],
		"rewards": {"xp": 10, "items": [{"item_id": "potion_minor", "qty": 1}]},
	}


func _test_real_content(ctx: Object) -> void:
	var cat: QuestCatalog = QuestCatalog.load_dir()
	ctx.check(cat.load_errors.is_empty(), "catalogo de quests carrega sem erros: %s" % str(cat.load_errors))
	ctx.check(cat.ids().size() >= 5, "pelo menos 5 quests em Greenwood (%d)" % cat.ids().size())
	var reg: ContentRegistry = ContentRegistry.new()
	reg.load_all()
	var npcs: NpcDirectory = NpcDirectory.load_dir()
	var areas: AreaSet = AreaSet.load_dir()
	ctx.check(npcs.load_errors.is_empty() and npcs.ids().size() >= 3, "NPCs carregam sem erros (%s)" % str(npcs.load_errors))
	ctx.check(areas.load_errors.is_empty() and areas.ids().size() >= 2, "areas carregam sem erros (%s)" % str(areas.load_errors))
	var refs: Array[String] = cat.validate_refs(reg, npcs, areas, QuestCatalog.load_pending_refs())
	ctx.check(refs.is_empty(), "referencias de quests consistentes (itens/inimigos/NPCs/areas/prerequisitos): %s" % str(refs))
	# cobertura de tipos de objetivo (cada tipo exigido pelo escopo aparece em alguma quest)
	var seen: Dictionary = {}
	for id: String in cat.ids():
		for o: QuestDef.Objective in cat.get_quest(id).objectives:
			seen[o.type] = true
		ctx.check(cat.get_quest(id).title_key != "" and cat.get_quest(id).description_key != "", "quest %s tem chaves de traducao" % id)
	for t: String in QuestDef.OBJECTIVE_TYPES:
		ctx.check(seen.has(t), "objetivo do tipo '%s' coberto pelas quests de Greenwood" % t)
	# dialogos
	var dlg: DialogueCatalog = DialogueCatalog.load_dir(DialogueCatalog.DIALOGUES_DIR, cat.ids())
	ctx.check(dlg.load_errors.is_empty(), "dialogos carregam sem erros: %s" % str(dlg.load_errors))
	for npc_id: String in npcs.ids():
		var d: DialogueDef = dlg.for_npc(npc_id)
		ctx.check(d != null and d.id == npcs.dialogue_id_of(npc_id), "NPC %s tem o dialogo declarado" % npc_id)
	# cada quest e oferecida (accept) e entregue (turn_in) por um dialogo do NPC certo
	for id: String in cat.ids():
		var q: QuestDef = cat.get_quest(id)
		ctx.check(_dialogue_has_effect(dlg.for_npc(q.giver_npc), "accept_quest", id), "quest %s: aceitavel no dialogo de %s" % [id, q.giver_npc])
		ctx.check(_dialogue_has_effect(dlg.for_npc(q.turn_in_npc), "turn_in_quest", id), "quest %s: entregavel no dialogo de %s" % [id, q.turn_in_npc])
	# id do arquivo = id da quest; ids de recompensa respeitam a chave de idempotencia (<=128)
	for id: String in cat.ids():
		ctx.check(QuestTracker.reward_key(id, "11111111-1111-4111-8111-111111111111").length() <= 128, "chave de recompensa de %s cabe em 128 chars" % id)
	# E5.3: pendencia ruin_guardian resolvida (gw_ruin_guardian mata blight_treant); nada mais pendente
	ctx.check((QuestCatalog.load_pending_refs()["enemies"] as Array).is_empty() and (QuestCatalog.load_pending_refs()["items"] as Array).is_empty(), "sem ids pendentes em _pending_refs.json")


func _dialogue_has_effect(d: DialogueDef, effect_type: String, quest_id: String) -> bool:
	if d == null:
		return false
	for nid: String in d.nodes:
		var node: Dictionary = d.nodes[nid]
		for e: Dictionary in node["on_enter"]:
			if e["type"] == effect_type and e["quest_id"] == quest_id:
				return true
		for c: Dictionary in node["choices"]:
			for e: Dictionary in c["effects"]:
				if e["type"] == effect_type and e["quest_id"] == quest_id:
					return true
	return false


func _test_quest_parse_negative(ctx: Object) -> void:
	ctx.check(QuestDef.parse(_valid_quest())["def"] != null, "quest valida de referencia parseia")
	var cases: Array = [
		["id invalido", func(d: Dictionary) -> void: d["id"] = "Bad-Id"],
		["schema_version errado", func(d: Dictionary) -> void: d["schema_version"] = 2],
		["type desconhecido", func(d: Dictionary) -> void: d["type"] = "pvp"],
		["sem objetivos", func(d: Dictionary) -> void: d["objectives"] = []],
		["objetivo required 0", func(d: Dictionary) -> void: d["objectives"][0]["required"] = 0],
		["objetivo required enorme", func(d: Dictionary) -> void: d["objectives"][0]["required"] = 100000],
		["objetivo tipo invalido", func(d: Dictionary) -> void: d["objectives"][0]["type"] = "craft"],
		["talk com required 2", func(d: Dictionary) -> void: d["objectives"][0]["type"] = "talk"],
		["objetivos duplicados", func(d: Dictionary) -> void: d["objectives"].append(d["objectives"][0].duplicate())],
		["recompensa vazia", func(d: Dictionary) -> void: d["rewards"] = {"xp": 0, "items": []}],
		["xp negativo", func(d: Dictionary) -> void: d["rewards"]["xp"] = -5],
		["xp enorme", func(d: Dictionary) -> void: d["rewards"]["xp"] = 10000000],
		["item de recompensa repetido", func(d: Dictionary) -> void: d["rewards"]["items"].append({"item_id": "potion_minor", "qty": 1})],
		["qty de recompensa 0", func(d: Dictionary) -> void: d["rewards"]["items"][0]["qty"] = 0],
		["min_level 0", func(d: Dictionary) -> void: d["prerequisites"]["min_level"] = 0],
		["prerequisito duplicado", func(d: Dictionary) -> void: d["prerequisites"]["quests"] = ["a_b", "a_b"]],
		["titulo vazio", func(d: Dictionary) -> void: d["title"] = "  "],
		["abandonable nao-bool", func(d: Dictionary) -> void: d["abandonable"] = "sim"],
	]
	for c: Array in cases:
		var d: Dictionary = _valid_quest()
		(c[1] as Callable).call(d)
		var r: Dictionary = QuestDef.parse(d)
		ctx.check(r["def"] == null and not (r["errors"] as Array).is_empty(), "quest invalida rejeitada: " + String(c[0]))
	ctx.check(QuestDef.parse("nao e dict")["def"] == null and QuestDef.parse(null)["def"] == null, "raiz nao-objeto rejeitada")
	var too_many: Dictionary = _valid_quest()
	for i: int in 7:
		too_many["objectives"].append({"id": "x%d" % i, "type": "kill", "target": "melee_grunt", "required": 1, "text": "x", "text_key": "k"})
	ctx.check(QuestDef.parse(too_many)["def"] == null, "mais de MAX_OBJECTIVES rejeitado")


func _test_npc_and_area_parse(ctx: Object) -> void:
	var n: NpcDirectory = NpcDirectory.new()
	var good: Dictionary = {"id": "npc_x", "display_name": "X", "dialogue_id": "dlg_x", "interact_radius": 2.0, "position": [1, 0, 1]}
	ctx.check(n.add_dict(good) == "", "NPC valido")
	ctx.check(n.add_dict(good) != "", "NPC duplicado rejeitado")
	var bad_radius: Dictionary = good.duplicate()
	bad_radius["id"] = "npc_y"
	bad_radius["interact_radius"] = 0.0
	ctx.check(n.add_dict(bad_radius) != "", "NPC com raio 0 rejeitado")
	bad_radius["interact_radius"] = 9999.0
	ctx.check(n.add_dict(bad_radius) != "", "NPC com raio enorme rejeitado")
	var bad_pos: Dictionary = good.duplicate()
	bad_pos["id"] = "npc_z"
	bad_pos["position"] = [1, 2]
	ctx.check(n.add_dict(bad_pos) != "", "NPC com posicao invalida rejeitado")
	ctx.check(n.in_range("npc_x", Vector3(1.5, 0.0, 1.0)) and not n.in_range("npc_x", Vector3(5.0, 0.0, 5.0)) and not n.in_range("nao_existe", Vector3.ZERO), "in_range: dentro/fora/desconhecido")
	ctx.check(not n.in_range("npc_x", Vector3(1.0, 50.0, 1.0)), "in_range respeita diferenca vertical")
	var a: AreaSet = AreaSet.new()
	ctx.check(a.add_dict({"id": "area_t", "center": [0, 0, 0], "radius": 3.0, "height": 2.0}) == "", "area valida")
	ctx.check(a.add_dict({"id": "area_t", "center": [0, 0, 0], "radius": 3.0}) != "", "area duplicada rejeitada")
	ctx.check(a.add_dict({"id": "area_u", "center": [0, 0, 0], "radius": -1.0}) != "", "area com raio negativo rejeitada")
	ctx.check(a.contains("area_t", Vector3(2.0, 1.0, 0.0)) and not a.contains("area_t", Vector3(4.0, 0.0, 0.0)) and not a.contains("area_t", Vector3(0.0, 3.0, 0.0)), "contains: raio e altura")
	var w: AreaWatcher = AreaWatcher.new(a)
	ctx.check(w.update(Vector3(10, 0, 0)).is_empty(), "watcher: fora nao dispara")
	ctx.check(w.update(Vector3(1, 0, 0)) == (["area_t"] as Array[String]), "watcher: entrada dispara")
	ctx.check(w.update(Vector3(1.5, 0, 0)).is_empty() and w.is_inside("area_t"), "watcher: permanecer dentro nao repete")
	w.update(Vector3(10, 0, 0))
	ctx.check(w.update(Vector3(0, 0, 1)) == (["area_t"] as Array[String]), "watcher: sair e reentrar dispara de novo")


func _test_ref_validation_negative(ctx: Object) -> void:
	var reg: ContentRegistry = ContentRegistry.new()
	reg.load_all()
	var npcs: NpcDirectory = NpcDirectory.load_dir()
	var areas: AreaSet = AreaSet.load_dir()
	var cat: QuestCatalog = QuestCatalog.new()
	var q: QuestDef = QuestDef.parse(_valid_quest())["def"]
	q.objectives[0].target = "inimigo_fantasma"
	q.giver_npc = "npc_fantasma"
	q.prereq_quests = ["quest_fantasma"] as Array[String]
	q.reward_items = [{"item_id": "item_fantasma", "qty": 1}]
	cat.add(q)
	var errs: Array[String] = cat.validate_refs(reg, npcs, areas, {"enemies": [], "items": []})
	ctx.check(errs.size() >= 4, "referencias quebradas detectadas (%d erros)" % errs.size())
	var pending_ok: Array[String] = cat.validate_refs(reg, npcs, areas, {"enemies": ["inimigo_fantasma"], "items": ["item_fantasma"]})
	ctx.check(pending_ok.size() == errs.size() - 2, "ids listados como pendentes sao aceitos")
	# ciclo de prerequisitos
	var c2: QuestCatalog = QuestCatalog.new()
	var a: QuestDef = QuestDef.parse(_valid_quest())["def"]
	a.id = "q_a"
	a.prereq_quests = ["q_b"] as Array[String]
	var b: QuestDef = QuestDef.parse(_valid_quest())["def"]
	b.id = "q_b"
	b.prereq_quests = ["q_a"] as Array[String]
	c2.add(a)
	c2.add(b)
	var cyc: Array[String] = c2.validate_refs(reg, npcs, areas, {})
	var found_cycle: bool = false
	for e: String in cyc:
		if e.contains("ciclo"):
			found_cycle = true
	ctx.check(found_cycle, "ciclo de prerequisitos detectado")
	var dup: QuestCatalog = QuestCatalog.new()
	dup.add(a)
	dup.add(a)
	ctx.check(not dup.load_errors.is_empty(), "id de quest duplicado detectado")
