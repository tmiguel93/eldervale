extends RefCounted
## E5.5 - ClientUi integrada a uma ClientSession falsa (sem rede/GPU): teclas, dialogo, quests, crafting, toasts por
## eventos/sinais, fade de zona, morte/respawn, grupo, minimapa, bloqueio de acoes, religacao de sessao e seguranca
## do modo bot.

const U = preload("res://tests/e5_ui/ui_helpers.gd")


func run(ctx: Object) -> void:
	var tree: SceneTree = ctx as SceneTree
	await tree.physics_frame
	_test_build_and_inputs(ctx, tree)
	_test_dialogue_flow(ctx, tree)
	_test_quest_flow(ctx, tree)
	_test_craft_flow(ctx, tree)
	_test_event_feedback(ctx, tree)
	_test_hud_frame(ctx, tree)
	_test_rebind_and_states(ctx, tree)
	_test_bot_safety(ctx)
	await _test_draw_pass(ctx, tree)


func _arrive(ss: ClientSession, pos: Vector3, zone: String = "zone_hub") -> void:
	U.world_event(ss, Protocol.EVENT_ZONE, {"id": ss.player_id, "zone": zone, "phase": Protocol.ZONE_PHASE_ARRIVED, "pos": pos})
	U.snapshot(ss, [U.player(ss.player_id, pos)])


func _test_build_and_inputs(ctx: Object, tree: SceneTree) -> void:
	var made: Dictionary = U.make_session()
	var ss: ClientSession = made["session"]
	var ui: ClientUi = U.make_ui(tree, ss)
	ctx.check(ui.dialogue != null and ui.quests != null and ui.inventory_panel != null and ui.craft != null and ui.map_panel != null and ui.minimap != null, "UI constroi todos os paineis")
	ctx.check(not ui.blocks_game_actions() and ui.open_panel_names().is_empty(), "nada aberto no inicio")
	ctx.check(ui.toasts.count() == 0 and not ui.party.visible and not ui.boss.visible, "HUD vazio no inicio")
	ctx.check(ui.handle_input(U.key(KEY_J)), "J consumido")
	ctx.check(ui.quests.is_open() and ui.blocks_game_actions(), "J abre o diario e bloqueia acoes")
	ctx.check(ui.handle_input(U.key(KEY_I)) and ui.inventory_panel.is_open() and not ui.quests.is_open(), "I abre inventario e fecha o diario (exclusivo)")
	ctx.check(ui.handle_input(U.key(KEY_M)) and ui.map_panel.is_open() and not ui.inventory_panel.is_open(), "M abre o mapa")
	ctx.check(ui.handle_input(U.key(KEY_M)) and ui.open_panel_names().is_empty() and not ui.blocks_game_actions(), "M de novo fecha")
	ui.handle_input(U.key(KEY_I))
	ctx.check(ui.handle_input(U.key(KEY_ESCAPE)) and not ui.inventory_panel.is_open(), "Esc fecha o painel aberto")
	ctx.check(not ui.handle_input(U.key(KEY_ESCAPE)), "Esc sem painel nao e consumido")
	ctx.check(not ui.handle_input(U.key(KEY_W)), "tecla de jogo (W) nao e consumida")
	ui.handle_input(U.key(KEY_J))
	ctx.check(ui.handle_input(U.key(KEY_DOWN)) or ui.quests.entries.is_empty(), "setas vao para o painel aberto")
	ui.handle_input(U.key(KEY_J))
	# fora de PLAYING nada funciona
	var idle: ClientSession = ClientSession.new()
	ui.bind(idle)
	ctx.check(not ui.handle_input(U.key(KEY_J)) and not ui.quests.is_open(), "sessao IDLE: teclas ignoradas")
	ui.bind(null)
	ctx.check(not ui.handle_input(U.key(KEY_J)), "sem sessao: teclas ignoradas")
	ui.on_event(Protocol.EVENT_PICKUP, {"id": 1, "item_id": "potion_minor", "qty": 1})
	ctx.check(ui.toasts.count() == 0, "sem sessao: eventos ignorados")
	U.free_ui(tree, ui)


func _test_dialogue_flow(ctx: Object, tree: SceneTree) -> void:
	var made: Dictionary = U.make_session()
	var ss: ClientSession = made["session"]
	var sent: Array = made["sent"]
	var ui: ClientUi = U.make_ui(tree, ss)
	_arrive(ss, U.HUB_FAR)
	ui.handle_input(U.key(KEY_F))
	ctx.check(sent.is_empty() and ui.toasts.texts().has("Nada para interagir aqui."), "F longe de tudo: so avisa, nada enviado")
	_arrive(ss, U.HUB_ORLA)
	ui.update_frame(0.016)
	ctx.check(ui.prompt.text == "[F] Falar com Ancia Orla", "prompt aparece perto do NPC")
	ui.handle_input(U.key(KEY_F))
	ctx.check(sent == [["dlg", Protocol.DIALOGUE_OP_OPEN, "npc_elder_orla", 0]], "F envia dialogue_open do NPC")
	ctx.check(not ui.dialogue.is_open(), "painel so abre quando o servidor responde")
	var view: Dictionary = {"npc_id": "npc_elder_orla", "dialogue_id": "dlg_elder_orla", "node_id": "welcome_offer", "speaker": "npc_elder_orla", "text": "Forasteiro...", "text_key": "k",
		"choices": [{"index": 0, "text": "Eu falarei com ele.", "text_key": "a"}, {"index": 1, "text": "Talvez depois.", "text_key": "b"}], "terminal": false}
	ui.handle_input(U.key(KEY_J))
	ss.on_dialogue(Protocol.DIALOGUE_VIEW, view)
	ctx.check(ui.dialogue.is_open() and ui.dialogue.choice_count() == 2 and not ui.quests.is_open(), "view do servidor abre o dialogo e fecha outros paineis")
	ui.update_frame(0.016)
	ctx.check(ui.prompt.text == "", "prompt some com painel aberto")
	ui.handle_input(U.key(KEY_DOWN))
	ui.handle_input(U.key(KEY_ENTER))
	ctx.check(sent.back() == ["dlg", Protocol.DIALOGUE_OP_CHOOSE, "", 1], "Baixo+Enter envia dialogue_choose(1)")
	ss.on_dialogue(Protocol.DIALOGUE_VIEW, {"npc_id": "npc_elder_orla", "dialogue_id": "d", "node_id": "n2", "speaker": "npc_elder_orla", "text": "Que as raizes guiem.", "text_key": "k", "choices": [], "terminal": true})
	ctx.check(ui.dialogue.terminal and ui.dialogue.is_open(), "no terminal mostra 'Fechar'")
	var n_sent: int = sent.size()
	ui.handle_input(U.key(KEY_F))
	ctx.check(not ui.dialogue.is_open() and sent.size() == n_sent, "F fecha o terminal sem enviar nada (servidor ja encerrou)")
	# Esc no meio da conversa avisa o servidor
	ss.on_dialogue(Protocol.DIALOGUE_VIEW, view)
	ui.handle_input(U.key(KEY_ESCAPE))
	ctx.check(not ui.dialogue.is_open() and sent.back() == ["dlg", Protocol.DIALOGUE_OP_CLOSE, "", 0], "Esc envia dialogue_close")
	# servidor encerra
	ss.on_dialogue(Protocol.DIALOGUE_VIEW, view)
	ss.on_dialogue(Protocol.DIALOGUE_END, {"npc_id": "npc_elder_orla"})
	ctx.check(not ui.dialogue.is_open(), "DIALOGUE_END fecha o painel")
	# erro
	ss.on_dialogue(Protocol.DIALOGUE_ERROR, {"req_id": 1, "op": 1, "code": "too_far"})
	ctx.check(ui.toasts.texts().has(UiText.dialogue_error("too_far")), "erro do servidor vira toast em portugues")
	ss.on_dialogue(Protocol.DIALOGUE_VIEW, view)
	ss.on_dialogue(Protocol.DIALOGUE_ERROR, {"req_id": 2, "op": 2, "code": "no_dialogue"})
	ctx.check(ui.dialogue.status_label.text == UiText.dialogue_error("no_dialogue"), "erro aparece na janela")
	# afastar-se fecha
	U.snapshot(ss, [U.player(ss.player_id, U.HUB_FAR)])
	ui.update_frame(0.016)
	ctx.check(not ui.dialogue.is_open() and sent.back()[1] == Protocol.DIALOGUE_OP_CLOSE, "afastar-se do NPC fecha o dialogo")
	# view malformada nao chega ao painel
	ss.on_dialogue(Protocol.DIALOGUE_VIEW, {"text": 5})
	ctx.check(not ui.dialogue.is_open(), "view malformada ignorada pela sessao")
	U.free_ui(tree, ui)


func _test_quest_flow(ctx: Object, tree: SceneTree) -> void:
	var made: Dictionary = U.make_session()
	var ss: ClientSession = made["session"]
	var sent: Array = made["sent"]
	var ui: ClientUi = U.make_ui(tree, ss)
	_arrive(ss, U.HUB_ORLA)
	ss.on_quest_update(Protocol.QUEST_SYNC, {"quests": {"active": {}, "completed": []}, "statuses": {"gw_welcome": "available"}})
	ui.handle_input(U.key(KEY_J))
	ctx.check(ui.quests.entries.size() >= 1 and ui.quests.selected_id() == "gw_welcome" and ui.quests.selected_status() == "available", "sync do servidor popula o diario")
	ui.handle_input(U.key(KEY_ENTER))
	ctx.check(sent.back() == ["quest", Protocol.QUEST_OP_ACCEPT, "gw_welcome"], "Enter envia quest_accept")
	ss.on_quest_update(Protocol.QUEST_ACCEPTED, {"quest_id": "gw_welcome"})
	ctx.check(ui.toasts.texts().has("Quest aceita: " + UiText.quest_title("gw_welcome")), "toast de quest aceita")
	ctx.check(ui.quests.selected_status() == "active", "diario atualiza por sinal")
	ss.on_quest_update(Protocol.QUEST_PROGRESS, {"quest_id": "gw_welcome", "objective_id": "talk_brannoch", "value": 1, "required": 1})
	ctx.check(ui.toasts.texts().any(func(t: String) -> bool: return t.contains("(1/1)")), "toast de progresso")
	ss.on_quest_update(Protocol.QUEST_READY, {"quest_id": "gw_welcome"})
	ctx.check(ui.toasts.texts().any(func(t: String) -> bool: return t.begins_with("Quest pronta")) and ui.quests.selected_status() == "ready", "toast e estado 'pronta'")
	ui.quests.advance(1.0)
	ui.handle_input(U.key(KEY_ENTER))
	ctx.check(sent.back() == ["quest", Protocol.QUEST_OP_TURN_IN, "gw_welcome"], "Enter entrega a pronta")
	ss.on_quest_update(Protocol.QUEST_ERROR, {"req_id": 3, "op": 3, "quest_id": "gw_welcome", "code": "too_far"})
	ctx.check(ui.quests.status_label.text == UiText.quest_error("too_far") and ui.toasts.texts().any(func(t: String) -> bool: return t.contains(UiText.quest_error("too_far"))), "erro de entrega no painel e em toast")
	ss.on_quest_update(Protocol.QUEST_COMPLETED, {"quest_id": "gw_welcome", "xp": 60, "items": [{"item_id": "potion_minor", "qty": 2}]})
	ctx.check(ui.toasts.texts().any(func(t: String) -> bool: return t.begins_with("Quest concluida") and t.contains("60 XP")), "toast de conclusao com recompensa")
	ctx.check(ui.inventory.count("potion_minor") == 2, "recompensa entra na estimativa de inventario")
	ctx.check(ui.quests.entries.any(func(e: Dictionary) -> bool: return e["id"] == "gw_welcome" and e["status"] == "completed"), "concluida listada")
	ss.on_quest_update(Protocol.QUEST_ACCEPTED, {"quest_id": "gw_scrap_for_orla"})
	ui.quests.advance(1.0)
	for i: int in 3:
		if ui.quests.selected_id() != "gw_scrap_for_orla":
			ui.handle_input(U.key(KEY_DOWN))
	ui.handle_input(U.key(KEY_DELETE))
	ui.handle_input(U.key(KEY_DELETE))
	ctx.check(sent.back() == ["quest", Protocol.QUEST_OP_ABANDON, "gw_scrap_for_orla"], "abandono exige duas teclas")
	ss.on_quest_update(Protocol.QUEST_ABANDONED, {"quest_id": "gw_scrap_for_orla"})
	ctx.check(ui.toasts.texts().any(func(t: String) -> bool: return t.begins_with("Quest abandonada")), "toast de abandono")
	ss.send_quest_cmd = Callable()
	ui.quests.advance(1.0)
	ui.quests._select(0)
	ui.quests.refresh(null)
	U.free_ui(tree, ui)


func _test_craft_flow(ctx: Object, tree: SceneTree) -> void:
	var made: Dictionary = U.make_session()
	var ss: ClientSession = made["session"]
	var sent: Array = made["sent"]
	var ui: ClientUi = U.make_ui(tree, ss)
	_arrive(ss, U.HUB_STATION)
	ui.update_frame(0.016)
	ctx.check(ui.prompt.text.begins_with("[F] Usar"), "prompt da bancada")
	ui.handle_input(U.key(KEY_F))
	ctx.check(ui.craft.is_open() and ui.craft.recipes.size() == 5 and ui.craft.station_id == "station_greenwood_workbench", "F na bancada abre o crafting com as receitas")
	ui.handle_input(U.key(KEY_ENTER))
	ctx.check(sent.back() == ["craft", ui.craft.recipes[0].id] and ui.craft.pending, "Enter envia ClientSession.craft")
	ss.on_craft_update(Protocol.CRAFT_ERROR, {"req_id": 1, "recipe_id": ui.craft.recipes[0].id, "code": "insufficient_ingredients"})
	ctx.check(ui.craft.status_label.text == UiText.craft_error("insufficient_ingredients") and not ui.craft.pending, "craft_finished(erro) mostrado e destrava")
	ctx.check(ui.toasts.texts().has(UiText.craft_error("insufficient_ingredients")), "erro de craft em toast")
	ui.inventory.add("scrap_material", 4)
	var rid: String = "rcp_potion_minor"
	ss.on_craft_update(Protocol.CRAFT_OK, {"req_id": 2, "recipe_id": rid, "results": [{"item_id": "potion_minor", "qty": 1}]})
	ctx.check(ui.craft.status_label.text.begins_with("Fabricado") and ui.toasts.texts().any(func(t: String) -> bool: return t.begins_with("Fabricado")), "craft_finished(ok) mostrado")
	ctx.check(ui.inventory.count("scrap_material") == 1 and ui.inventory.count("potion_minor") == 1, "estimativa de inventario atualizada")
	ss.on_craft_update(Protocol.CRAFT_OK, {"req_id": "lixo"})
	ctx.check(ss.crafts_rejected == 1, "craft malformado descartado pela sessao")
	ui.handle_input(U.key(KEY_F))
	ctx.check(not ui.craft.is_open(), "F fecha o crafting")
	ui.handle_input(U.key(KEY_F))
	U.snapshot(ss, [U.player(ss.player_id, U.HUB_FAR)])
	ui.update_frame(0.016)
	ctx.check(not ui.craft.is_open(), "afastar-se da bancada fecha o crafting")
	ss.on_craft_update(Protocol.CRAFT_OK, {"req_id": 4, "recipe_id": rid, "results": [{"item_id": "potion_minor", "qty": 1}]})
	ctx.check(ui.inventory.count("potion_minor") == 2, "resultado de craft com painel fechado ainda conta")
	var none: ClientSession = U.make_session()["session"]
	none.send_craft_cmd = Callable()
	var ui2: ClientUi = U.make_ui(tree, none)
	_arrive(none, U.HUB_STATION)
	ui2.handle_input(U.key(KEY_F))
	ui2.handle_input(U.key(KEY_ENTER))
	ctx.check(ui2.craft.status_label.text.contains("conexao") and not ui2.craft.pending, "sem transporte: mensagem de falha")
	U.free_ui(tree, ui2)
	U.free_ui(tree, ui)


func _test_event_feedback(ctx: Object, tree: SceneTree) -> void:
	var made: Dictionary = U.make_session()
	var ss: ClientSession = made["session"]
	var ui: ClientUi = U.make_ui(tree, ss)
	_arrive(ss, Vector3.ZERO)
	ui.on_event(Protocol.EVENT_PICKUP, {"id": 3, "item_id": "scrap_material", "qty": 3})
	ctx.check(ui.toasts.texts().has("+ 3x " + UiText.item_name("scrap_material")), "toast de loot: " + str(ui.toasts.texts()))
	ctx.check(ui.inventory.count("scrap_material") == 3, "loot entra na estimativa")
	ui.toasts.clear_all()
	ui.on_event(Protocol.EVENT_ZONE, {"id": 99, "zone": "zone_wild", "phase": Protocol.ZONE_PHASE_LEAVING, "pos": Vector3.ZERO})
	ctx.check(ui.fade.alpha == 0.0, "zona de OUTRO jogador nao dispara fade")
	ui.on_event(Protocol.EVENT_ZONE, {"id": ss.player_id, "zone": "zone_wild", "phase": Protocol.ZONE_PHASE_LEAVING, "pos": Vector3.ZERO})
	ui.update_frame(0.1)
	ctx.check(ui.fade.alpha > 0.0, "zone(phase 0) inicia o fade")
	ui.update_frame(1.0)
	ctx.check(ui.fade.is_dark(), "fade completo")
	ui.on_event(Protocol.EVENT_ZONE, {"id": ss.player_id, "zone": "zone_wild", "phase": Protocol.ZONE_PHASE_ARRIVED, "pos": Vector3(150, 0, 0)})
	ui.update_frame(1.0)
	ctx.check(ui.fade.alpha == 0.0 and ui.toasts.texts().has("Zona: " + UiText.zone_name("zone_wild")), "zone(phase 1) clareia e avisa a zona")
	# morte/respawn
	ui.on_event(Protocol.EVENT_DEATH, {"id": 55})
	ctx.check(not ui.fade.dead, "morte de outra entidade nao afeta")
	ui.on_event(Protocol.EVENT_DEATH, {"id": ss.player_id})
	ctx.check(ui.fade.dead and ui.toasts.texts().has("Voce morreu."), "morte local: overlay e toast")
	ui.on_event(Protocol.EVENT_ZONE, {"id": ss.player_id, "zone": "zone_wild", "phase": Protocol.ZONE_PHASE_LEAVING, "pos": Vector3.ZERO})
	ui.update_frame(1.0)
	ui.on_event(Protocol.EVENT_RESPAWN, {"id": ss.player_id, "zone": "zone_hub", "pos": Vector3.ZERO})
	ui.update_frame(1.0)
	ctx.check(not ui.fade.dead and ui.fade.alpha == 0.0, "respawn tira o overlay e cancela fade preto")
	# reanimado sem o evento
	ui.on_event(Protocol.EVENT_DEATH, {"id": ss.player_id})
	U.snapshot(ss, [U.player(ss.player_id, Vector3.ZERO, 100.0, 100.0)])
	ui.update_frame(0.016)
	ctx.check(not ui.fade.dead, "hp > 0 no snapshot tira o overlay de morte")
	# nomes de jogadores
	ui.on_event(Protocol.EVENT_PLAYER_JOINED, {"id": 9, "name": "Ana"})
	ui.on_event(Protocol.EVENT_PLAYER_JOINED, {"id": "x", "name": "Bad"})
	ctx.check(ui.player_names == {9: "Ana"}, "nomes vindos de player_joined")
	ui.on_event(Protocol.EVENT_PLAYER_LEFT, {"id": 9})
	ctx.check(ui.player_names.is_empty(), "player_left remove")
	# eventos sem campos nao quebram
	ui.on_event(Protocol.EVENT_PICKUP, {})
	ui.on_event(Protocol.EVENT_ZONE, {})
	ui.on_event(Protocol.EVENT_DEATH, {})
	ui.on_event(999, {})
	ctx.check(true, "eventos vazios/desconhecidos nao quebram")
	U.free_ui(tree, ui)


func _test_hud_frame(ctx: Object, tree: SceneTree) -> void:
	var made: Dictionary = U.make_session()
	var ss: ClientSession = made["session"]
	var ui: ClientUi = U.make_ui(tree, ss)
	_arrive(ss, Vector3(1, 0.05, 1))
	ui.local_name = "Tester"
	ui.on_event(Protocol.EVENT_PLAYER_JOINED, {"id": 9, "name": "Ana"})
	U.snapshot(ss, [U.player(7, Vector3(1, 0.05, 1), 60.0, 120.0), U.player(9, Vector3(3, 0.05, 1), 100.0, 100.0), U.enemy(40, "melee_grunt", Vector3(6, 0, 1)), U.enemy(41, "blight_treant", Vector3(8, 0, 1), 800.0, 1000.0, 2)])
	ui.update_frame(0.016, PI * 0.25)
	ctx.check(ui.vitals_box.visible and (ui.vitals_bar.get_node("Text") as Label).text == "Vida 60 / 120" and absf(ui.vitals_bar.value - 0.5) < 0.001, "barra de vida local")
	ctx.check(ui.party.visible and ui.party.row_count() == 2, "grupo mostra os 2 jogadores")
	ctx.check(ui.boss.visible and ui.boss.current_id == 41, "barra do chefe aparece com chefe no snapshot")
	ctx.check(ui.minimap_title.text == UiText.zone_name("zone_hub"), "minimapa mostra a zona")
	var types: Array[String] = []
	for it: Dictionary in ui.minimap.build_draw_list():
		types.append(String(it["type"]))
	ctx.check(types.has("local") and types.has("player") and types.has("enemy") and types.has("boss") and types.has("npc"), "minimapa tem local, jogador, inimigo, chefe e NPC: " + str(types))
	ui.handle_input(U.key(KEY_M))
	ui.update_frame(0.016)
	ctx.check(ui.map_panel.is_open() and ui.map_panel.view.build_draw_list().size() > 5 and ui.map_panel.zone_label.text == UiText.zone_name("zone_hub"), "mapa grande recebe os dados")
	U.snapshot(ss, [U.player(7, Vector3(1, 0.05, 1))])
	ui.update_frame(0.016)
	ctx.check(not ui.boss.visible and ui.party.row_count() == 1, "chefe e jogador somem do HUD quando saem do snapshot")
	U.snapshot(ss, [U.enemy(40, "melee_grunt", Vector3(6, 0, 1))])
	ui.update_frame(0.016)
	ctx.check(not ui.vitals_box.visible, "sem entidade local: sem barra de vida")
	U.free_ui(tree, ui)


func _test_rebind_and_states(ctx: Object, tree: SceneTree) -> void:
	var a: Dictionary = U.make_session()
	var ssa: ClientSession = a["session"]
	var ui: ClientUi = U.make_ui(tree, ssa)
	ui.toast("antigo")
	ui.handle_input(U.key(KEY_J))
	ui.inventory.add("potion_minor", 2)
	var b: Dictionary = U.make_session(8)
	var ssb: ClientSession = b["session"]
	ui.bind(ssb)
	ctx.check(ui.session == ssb and ui.toasts.count() == 0 and not ui.quests.is_open() and ui.inventory.entries().is_empty(), "nova sessao zera toasts, paineis e inventario")
	ssa.on_quest_update(Protocol.QUEST_ACCEPTED, {"quest_id": "gw_welcome"})
	ctx.check(ui.toasts.count() == 0, "sessao antiga desligada (sem toast)")
	ssb.on_quest_update(Protocol.QUEST_ACCEPTED, {"quest_id": "gw_welcome"})
	ctx.check(ui.toasts.count() == 1, "sessao nova ligada")
	ssb.on_disconnected()
	ctx.check(not ui.handle_input(U.key(KEY_J)), "sessao desconectada: teclas ignoradas")
	ui.update_frame(0.016)
	ui.bind(ssb)
	ui.bind(ssb)
	ctx.check(ui.toasts.count() == 0, "rebind repetido e idempotente")
	U.free_ui(tree, ui)


## ClientUi so e criada em _build_presentation (caminho nao-bot): modo bot/headless de bots nunca a instancia.
func _test_bot_safety(ctx: Object) -> void:
	var src: String = FileAccess.get_file_as_string("res://scripts/client/client_main.gd")
	ctx.check(src.count("ClientUi.new()") == 1, "ClientUi.new() aparece uma vez em client_main")
	var i_ui: int = src.find("ClientUi.new()")
	var i_fn: int = src.rfind("func ", i_ui)
	ctx.check(src.substr(i_fn, 40).begins_with("func _build_presentation"), "criada somente em _build_presentation")
	var bot_idx: int = src.find("if not is_bot:\n\t\t_build_presentation()")
	ctx.check(bot_idx > 0, "_build_presentation so roda fora do modo bot (sem backend)")
	ctx.check(src.count("_build_presentation()") == 3, "chamadas de _build_presentation: definicao + 2 (login e conexao direta)")
	var run_bot: int = src.find("func _run_bot_flow")
	ctx.check(src.substr(run_bot, 900).find("_build_presentation") == -1, "fluxo de bot nao monta apresentacao")
	ctx.check(src.contains("_ui != null and _ui.blocks_game_actions()"), "acoes de combate bloqueadas com painel aberto")


func _test_draw_pass(ctx: Object, tree: SceneTree) -> void:
	var made: Dictionary = U.make_session()
	var ss: ClientSession = made["session"]
	var ui: ClientUi = U.make_ui(tree, ss)
	_arrive(ss, U.HUB_STATION)
	U.snapshot(ss, [U.player(7, U.HUB_STATION), U.enemy(40, "blight_treant", Vector3(8, 0, 1), 800.0, 1000.0)])
	ui.handle_input(U.key(KEY_M))
	ui.update_frame(0.016)
	await tree.process_frame
	await tree.process_frame
	ctx.check(ui.minimap.is_inside_tree() and ui.map_panel.view.is_inside_tree(), "passada de frames com mapa aberto (render dummy) sem erro")
	ui.handle_input(U.key(KEY_M))
	ui.handle_input(U.key(KEY_F))
	await tree.process_frame
	ctx.check(ui.craft.is_open(), "crafting aberto atraves de frames")
	U.free_ui(tree, ui)
	await tree.process_frame
