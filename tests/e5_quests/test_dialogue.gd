extends RefCounted
## E5.1: condicoes, parse/validacao e execucao de dialogos (logica pura).


func run(ctx: Object) -> void:
	_test_conditions(ctx)
	_test_parse_negative(ctx)
	_test_runner_flow(ctx)
	_test_runner_guards(ctx)
	_test_real_dialogue_driven_by_tracker(ctx)


func _ctx_with(states: Dictionary, level: int = 1) -> Dictionary:
	return {"level": level, "quests": states}


func _test_conditions(ctx: Object) -> void:
	var c: Dictionary = _ctx_with({"qa": "active", "qb": "completed"}, 5)
	ctx.check(DialogueCondition.check({"quest": "qa", "state": "active"}, c), "quest em estado")
	ctx.check(not DialogueCondition.check({"quest": "qa", "state": "ready"}, c), "quest fora do estado")
	ctx.check(DialogueCondition.check({"quest": "qa", "state": ["ready", "active"]}, c), "lista de estados")
	ctx.check(DialogueCondition.check({"quest": "desconhecida", "state": "unavailable"}, c), "quest ausente do contexto = unavailable")
	ctx.check(DialogueCondition.check({"min_level": 5}, c) and not DialogueCondition.check({"min_level": 6}, c), "min_level")
	ctx.check(DialogueCondition.check({"all": [{"quest": "qa", "state": "active"}, {"quest": "qb", "state": "completed"}]}, c), "all")
	ctx.check(not DialogueCondition.check({"all": [{"quest": "qa", "state": "active"}, {"quest": "qb", "state": "active"}]}, c), "all falha se um falha")
	ctx.check(DialogueCondition.check({"any": [{"quest": "qa", "state": "ready"}, {"quest": "qb", "state": "completed"}]}, c), "any")
	ctx.check(not DialogueCondition.check({"any": [{"quest": "qa", "state": "ready"}]}, c), "any falha se todos falham")
	ctx.check(DialogueCondition.check({"not": {"quest": "qa", "state": "ready"}}, c), "not")
	ctx.check(DialogueCondition.check(null, c) and DialogueCondition.check({}, c), "condicao ausente/vazia = verdadeira")
	ctx.check(not DialogueCondition.check("lixo", c) and not DialogueCondition.check({"desconhecida": 1}, c), "condicao invalida em runtime = falsa (fail closed)")
	var deep: Variant = {"quest": "qa", "state": "active"}
	for i: int in 8:
		deep = {"not": deep}
	ctx.check(not DialogueCondition.check(deep, c), "aninhamento alem de MAX_DEPTH = falso")
	ctx.check(not DialogueCondition.validate(deep).is_empty(), "validate recusa aninhamento excessivo")
	ctx.check(DialogueCondition.validate({"quest": "qa", "state": "active"}).is_empty(), "validate aceita condicao boa")
	ctx.check(not DialogueCondition.validate({"quest": "qa", "state": "voando"}).is_empty(), "validate recusa estado desconhecido")
	ctx.check(not DialogueCondition.validate({"quest": "qa", "state": "active"}, ["outra"]).is_empty(), "validate recusa quest desconhecida (catalogo)")
	ctx.check(not DialogueCondition.validate({"all": []}).is_empty() and not DialogueCondition.validate({"min_level": 0}).is_empty() and not DialogueCondition.validate(5).is_empty(), "validate recusa all vazio, min_level 0, nao-objeto")
	ctx.check(not DialogueCondition.validate({"quest": "qa", "state": "active", "extra": 1}).is_empty(), "validate recusa chave extra")


func _base() -> Dictionary:
	return {
		"schema_version": 1, "id": "dlg_t", "npc_id": "npc_t",
		"entries": [{"if": {"quest": "qa", "state": "active"}, "node": "n2"}, {"node": "n1"}],
		"nodes": {
			"n1": {"speaker": "npc_t", "text": "Oi", "text_key": "k1", "choices": [
				{"text": "Ir", "text_key": "k1a", "next": "n2", "effects": [{"type": "accept_quest", "quest_id": "qa"}]},
				{"text": "Secreta", "text_key": "k1b", "if": {"min_level": 10}, "next": null},
				{"text": "Sair", "text_key": "k1c", "next": null}]},
			"n2": {"speaker": "npc_t", "text": "Fim", "text_key": "k2", "on_enter": [{"type": "turn_in_quest", "quest_id": "qa"}]},
		},
	}


func _test_parse_negative(ctx: Object) -> void:
	ctx.check(DialogueDef.parse(_base())["def"] != null, "dialogo de referencia parseia")
	var cases: Array = [
		["schema_version errado", func(d: Dictionary) -> void: d["schema_version"] = 3],
		["id invalido", func(d: Dictionary) -> void: d["id"] = "Dlg X"],
		["sem nos", func(d: Dictionary) -> void: d["nodes"] = {}],
		["entrada para no inexistente", func(d: Dictionary) -> void: d["entries"][1]["node"] = "nada"],
		["fallback com if", func(d: Dictionary) -> void: d["entries"][1]["if"] = {"min_level": 1}],
		["entrada sem if no meio", func(d: Dictionary) -> void: d["entries"].insert(0, {"node": "n1"})],
		["next inexistente", func(d: Dictionary) -> void: d["nodes"]["n1"]["choices"][0]["next"] = "nada"],
		["escolha sem next", func(d: Dictionary) -> void: d["nodes"]["n1"]["choices"][2].erase("next")],
		["texto vazio", func(d: Dictionary) -> void: d["nodes"]["n1"]["text"] = ""],
		["texto longo demais", func(d: Dictionary) -> void: d["nodes"]["n1"]["text"] = "x".repeat(600)],
		["efeito desconhecido", func(d: Dictionary) -> void: d["nodes"]["n1"]["choices"][0]["effects"] = [{"type": "dar_ouro", "quest_id": "qa"}]],
		["efeito com campo extra", func(d: Dictionary) -> void: d["nodes"]["n1"]["choices"][0]["effects"] = [{"type": "accept_quest", "quest_id": "qa", "x": 1}]],
		["mais de 6 escolhas", func(d: Dictionary) -> void: for i: int in 6: d["nodes"]["n1"]["choices"].append({"text": "x", "text_key": "k", "next": null})],
		["condicao invalida", func(d: Dictionary) -> void: d["nodes"]["n1"]["choices"][1]["if"] = {"quest": "qa", "state": "x"}],
		["id de no invalido", func(d: Dictionary) -> void: d["nodes"]["No Mau"] = d["nodes"]["n2"].duplicate(true)],
	]
	for c: Array in cases:
		var d: Dictionary = _base()
		(c[1] as Callable).call(d)
		var r: Dictionary = DialogueDef.parse(d)
		ctx.check(r["def"] == null and not (r["errors"] as Array).is_empty(), "dialogo invalido rejeitado: " + String(c[0]))
	var unknown: Dictionary = DialogueDef.parse(_base(), ["so_esta"])
	ctx.check(unknown["def"] == null, "efeitos/condicoes com quest fora do catalogo conhecido rejeitados")
	ctx.check(DialogueDef.parse(null)["def"] == null and DialogueDef.parse([])["def"] == null, "raiz nao-objeto rejeitada")


func _test_runner_flow(ctx: Object) -> void:
	var def: DialogueDef = DialogueDef.parse(_base())["def"]
	var r: DialogueRunner = DialogueRunner.new(def)
	ctx.check(r.start(_ctx_with({"qa": "available"})) and r.node_id == "n1", "entrada: fallback quando nada casa")
	ctx.check(r.take_enter_effects().is_empty() and r.take_enter_effects().is_empty(), "n1 sem on_enter")
	var v: Dictionary = r.view(_ctx_with({"qa": "available"}, 1))
	ctx.check(v["node_id"] == "n1" and v["text"] == "Oi" and v["speaker"] == "npc_t" and v["text_key"] == "k1" and not bool(v["terminal"]), "view: fala e metadados")
	ctx.check((v["choices"] as Array).size() == 2 and v["choices"][0]["index"] == 0 and v["choices"][1]["text"] == "Sair", "view: escolha oculta (nivel) nao aparece; indices compactos")
	var bad: Dictionary = r.choose(7, _ctx_with({}))
	ctx.check(not bool(bad["ok"]) and bad["code"] == "bad_choice" and not r.is_finished(), "indice fora da lista visivel recusado sem encerrar")
	var neg: Dictionary = r.choose(-1, _ctx_with({}))
	ctx.check(neg["code"] == "bad_choice", "indice negativo recusado")
	var ok: Dictionary = r.choose(0, _ctx_with({"qa": "available"}))
	ctx.check(bool(ok["ok"]) and ok["effects"] == [{"type": "accept_quest", "quest_id": "qa"}] and not bool(ok["ended"]) and r.node_id == "n2", "escolha devolve efeitos e avanca")
	ctx.check(r.take_enter_effects() == [{"type": "turn_in_quest", "quest_id": "qa"}], "on_enter do proximo no e entregue UMA vez")
	ctx.check(r.take_enter_effects().is_empty(), "on_enter nao se repete")
	var v2: Dictionary = r.view(_ctx_with({"qa": "active"}))
	ctx.check(bool(v2["terminal"]) and (v2["choices"] as Array).is_empty() and r.is_finished(), "no sem escolhas e terminal e encerra")
	ctx.check(r.choose(0, _ctx_with({}))["code"] == "finished", "choose apos o fim recusado")
	ctx.check(r.view(_ctx_with({})).is_empty(), "view apos o fim e vazia")
	# entrada por condicao
	var r2: DialogueRunner = DialogueRunner.new(def)
	r2.start(_ctx_with({"qa": "active"}))
	ctx.check(r2.node_id == "n2", "entrada condicional (qa ativa -> n2)")
	# escolher 'Sair' (next null) encerra
	var r3: DialogueRunner = DialogueRunner.new(def)
	r3.start(_ctx_with({}, 20))
	var v3: Dictionary = r3.view(_ctx_with({}, 20))
	ctx.check((v3["choices"] as Array).size() == 3, "com nivel 20 a escolha secreta aparece")
	var end: Dictionary = r3.choose(2, _ctx_with({}, 20))
	ctx.check(bool(end["ok"]) and bool(end["ended"]) and r3.is_finished(), "next null encerra o dialogo")
	var r4: DialogueRunner = DialogueRunner.new(def)
	r4.start(_ctx_with({}))
	r4.close()
	ctx.check(r4.is_finished() and r4.choose(0, _ctx_with({}))["code"] == "finished", "close encerra")


func _test_runner_guards(ctx: Object) -> void:
	var def: DialogueDef = DialogueDef.parse(_base())["def"]
	# a condicao da escolha e REAVALIADA no choose (estado mudou entre a view e a escolha)
	var r: DialogueRunner = DialogueRunner.new(def)
	r.start(_ctx_with({}, 20))
	r.view(_ctx_with({}, 20)) # cliente viu a escolha secreta (indice 1)
	var res: Dictionary = r.choose(1, _ctx_with({}, 1)) # mas o nivel caiu/contexto mudou
	ctx.check(not bool(res["ok"]) and res["code"] == "choice_unavailable", "escolha que deixou de valer e recusada no choose")
	# choose sem view previa nao consegue escolher (nada visivel)
	var r2: DialogueRunner = DialogueRunner.new(def)
	r2.start(_ctx_with({}))
	ctx.check(r2.choose(0, _ctx_with({}))["code"] == "bad_choice", "choose antes de qualquer view recusado")
	# retorna copias: alterar o resultado nao corrompe a definicao
	var r3: DialogueRunner = DialogueRunner.new(def)
	r3.start(_ctx_with({}))
	r3.view(_ctx_with({}))
	var eff: Array = r3.choose(0, _ctx_with({}))["effects"]
	eff.clear()
	var r4: DialogueRunner = DialogueRunner.new(def)
	r4.start(_ctx_with({}))
	r4.view(_ctx_with({}))
	ctx.check((r4.choose(0, _ctx_with({}))["effects"] as Array).size() == 1, "efeitos devolvidos sao copias (definicao intacta)")


func _test_real_dialogue_driven_by_tracker(ctx: Object) -> void:
	var cat: QuestCatalog = QuestCatalog.load_dir()
	var dlgs: DialogueCatalog = DialogueCatalog.load_dir(DialogueCatalog.DIALOGUES_DIR, cat.ids())
	var t: QuestTracker = QuestTracker.new(cat)
	var orla: DialogueDef = dlgs.for_npc("npc_elder_orla")
	var r: DialogueRunner = DialogueRunner.new(orla)
	r.start(t.dialogue_context(1))
	ctx.check(r.node_id == "welcome_offer", "Orla oferece gw_welcome a quem nao tem nada")
	var v: Dictionary = r.view(t.dialogue_context(1))
	ctx.check((v["choices"] as Array).size() == 2, "oferta tem aceitar/recusar")
	var ch: Dictionary = r.choose(0, t.dialogue_context(1))
	ctx.check(ch["effects"][0]["type"] == "accept_quest" and ch["effects"][0]["quest_id"] == "gw_welcome", "escolha 0 aceita gw_welcome")
	t.accept("gw_welcome", 1)
	var r2: DialogueRunner = DialogueRunner.new(orla)
	r2.start(t.dialogue_context(1))
	ctx.check(r2.node_id == "welcome_waiting", "com a quest ativa Orla diz para ir ate Brannoch")
	t.on_npc_talked("npc_hunter_brannoch")
	var r3: DialogueRunner = DialogueRunner.new(orla)
	r3.start(t.dialogue_context(1))
	r3.view(t.dialogue_context(1))
	ctx.check(r3.node_id == "welcome_done" and r3.choose(0, t.dialogue_context(1))["effects"][0]["type"] == "turn_in_quest", "pronta: Orla oferece a entrega")
	t.complete("gw_welcome")
	var r4: DialogueRunner = DialogueRunner.new(orla)
	r4.start(t.dialogue_context(1))
	ctx.check(r4.node_id == "scrap_offer", "concluida gw_welcome: Orla passa a oferecer a sucata")
	# idle quando nada se aplica (todas concluidas)
	var done: QuestTracker = QuestTracker.new(cat)
	done.state.completed.append_array(["gw_welcome", "gw_scrap_for_orla"])
	var r5: DialogueRunner = DialogueRunner.new(orla)
	r5.start(done.dialogue_context(1))
	ctx.check(r5.node_id == "idle", "sem pendencias: fala generica")
