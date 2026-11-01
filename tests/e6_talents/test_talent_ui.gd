extends RefCounted
## E6.2 - painel de talentos (Control em scripts/ui/client): ordem de exibicao, status por no, estado autoritativo, erros, sinais,
## double-press do reset e que NADA de UI e instanciado no servidor/bot (headless).


func run(ctx: Object) -> void:
	var tree: SceneTree = ctx as SceneTree
	await tree.physics_frame
	_test_statics(ctx)
	await _test_panel(ctx, tree)
	_test_not_in_server(ctx)


func _test_statics(ctx: Object) -> void:
	var cat: TalentCatalog = TalentCatalog.shared()
	var tr: TalentTree = cat.get_tree("warrior")
	var order: Array[String] = TalentPanel.display_order(tr)
	ctx.check(order.size() == tr.nodes.size(), "display_order cobre todos os nos")
	var seen: Dictionary = {}
	var ok_order: bool = true
	for id: String in order:
		for r: String in (tr.nodes[id]["requires"] as Array):
			if String(tr.nodes[r]["spec"]) == String(tr.nodes[id]["spec"]):
				ok_order = ok_order and seen.has(r)
		seen[id] = true
	ctx.check(ok_order, "no aparece depois de seus requisitos do mesmo grupo")
	ctx.check(String(tr.nodes[order[0]]["spec"]) == "", "genericos primeiro")
	var st: TalentState = TalentState.new()
	ctx.check(TalentPanel.node_status(tr, st, 5, cat, "w_vigor") == "available", "status: available")
	ctx.check(TalentPanel.node_status(tr, st, 5, cat, "w_iron_skin") == "prerequisite", "status: prerequisite")
	ctx.check(TalentPanel.node_status(tr, st, 1, cat, "w_vigor") == "no_points", "status: no_points")
	ctx.check(TalentPanel.node_status(tr, st, 5, cat, "b_frenzy") == "spec_not_chosen", "status: spec_not_chosen")
	st.ranks = {"w_vigor": 3}
	ctx.check(TalentPanel.node_status(tr, st, 5, cat, "w_vigor") == "maxed", "status: maxed")
	for s: String in ["available", "maxed", "prerequisite", "no_points", "spec_not_chosen", "wrong_spec", "level_too_low"]:
		ctx.check(TalentPanel.status_text(s) != s, "rotulo legivel para %s" % s)
	ctx.check(TalentPanel.node_line(tr.nodes["w_vigor"], 2, 0).contains("2/3"), "linha do no mostra ranks")
	ctx.check(UiText.talent_error("no_points") != "" and UiText.talent_error("not_safe_zone") != "" and UiText.talent_error("insufficient_items") != "", "mensagens de erro em pt-BR")


func _test_panel(ctx: Object, tree: SceneTree) -> void:
	var panel: TalentPanel = TalentPanel.new()
	tree.root.add_child(panel)
	await tree.process_frame
	panel.open()
	var allocs: Array[String] = []
	var specs: Array[String] = []
	var respecs: Array[int] = [0]
	panel.allocate_requested.connect(func(id: String) -> void: allocs.append(id))
	panel.spec_requested.connect(func(id: String) -> void: specs.append(id))
	panel.respec_requested.connect(func() -> void: respecs[0] += 1)
	panel.apply_state("warrior", {"spec": "", "ranks": {}, "respecs": 0, "level": 5, "points_total": 4, "points_spent": 0, "points_available": 4, "req_id": -1})
	ctx.check(panel.tree != null and panel.tree.class_id == "warrior" and panel.points_available == 4 and not panel.order.is_empty(), "apply_state monta a arvore da classe e guarda os pontos do servidor")
	ctx.check(panel.selected_id() == panel.order[0], "selecao inicial no primeiro no")
	panel._request_allocate()
	ctx.check(allocs == [panel.order[0]] and panel.pending, "alocar pede ao servidor (sinal) e fica pendente")
	panel._request_allocate()
	ctx.check(allocs.size() == 1, "pendente: nao reenvia")
	panel.show_error("Sem pontos")
	ctx.check(not panel.pending, "erro libera o painel")
	panel.apply_state("warrior", {"spec": "berserker", "ranks": {"w_vigor": 1}, "respecs": 0, "level": 5, "points_total": 4, "points_spent": 1, "points_available": 3, "req_id": 1})
	ctx.check(panel.state.spec_id == "berserker" and panel.state.rank_of("w_vigor") == 1 and panel.points_spent == 1, "estado do servidor refletido")
	# o painel nunca calcula pontos por conta propria: usa o que o servidor mandou
	panel.apply_state("warrior", {"spec": "", "ranks": {}, "respecs": 0, "level": 5, "points_total": 4, "points_spent": 0, "points_available": 9, "req_id": -1})
	ctx.check(panel.points_available == 9, "pontos exibidos = valor do servidor (cliente nao recalcula)")
	panel.apply_state("warrior", {"spec": "", "ranks": {"fantasma": 4, "w_vigor": 99}, "respecs": 0, "level": 5, "points_total": 4, "points_spent": 0, "points_available": 4, "req_id": -1})
	ctx.check(panel.state.rank_of("fantasma") == 0 and panel.state.rank_of("w_vigor") <= 3, "ranks invalidos vindos do fio sao saneados")
	# respec: duas pressoes
	panel._request_respec()
	ctx.check(respecs[0] == 0, "primeira pressao so pede confirmacao")
	panel._request_respec()
	ctx.check(respecs[0] == 1, "segunda pressao dentro da janela envia o reset")
	panel.reset()
	ctx.check(panel.class_id == "" and panel.tree == null or panel.class_id == "", "reset limpa a classe")
	panel.apply_state("inexistente", {"spec": "", "ranks": {}, "respecs": 0, "level": 1, "points_total": 0, "points_spent": 0, "points_available": 0, "req_id": -1})
	ctx.check(panel.tree == null, "classe sem arvore: painel vazio, sem erro")
	panel.queue_free()
	await tree.process_frame


func _test_not_in_server(ctx: Object) -> void:
	var f: FileAccess = FileAccess.open("res://scripts/server/server_session.gd", FileAccess.READ)
	var src: String = f.get_as_text()
	ctx.check(not src.contains("TalentPanel") and not src.contains("scripts/ui/client"), "servidor nao referencia o painel de talentos")
	var g: FileAccess = FileAccess.open("res://scripts/client/talent_bot.gd", FileAccess.READ)
	var bot: String = g.get_as_text()
	ctx.check(not bot.contains("TalentPanel") and not bot.contains("UiPanel"), "bot de talentos nao usa UI")
