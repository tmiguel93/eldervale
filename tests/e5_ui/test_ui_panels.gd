extends RefCounted
## E5.5 - paineis da UI do cliente com dados falsos (sem GPU): texto, estilo, inventario estimado, dialogo, quests,
## inventario, crafting, grupo, chefe, toasts, fade, mapa. Construcao sem erro, estados vazios, teclado.

const U = preload("res://tests/e5_ui/ui_helpers.gd")


func run(ctx: Object) -> void:
	var tree: SceneTree = ctx as SceneTree
	await tree.physics_frame
	_test_input_actions(ctx)
	_test_text(ctx)
	_test_client_inventory(ctx)
	_test_dialogue_panel(ctx)
	_test_quest_panel(ctx)
	_test_inventory_panel(ctx)
	_test_craft_panel(ctx)
	_test_party_and_boss(ctx)
	_test_toasts_and_fade(ctx)
	_test_interact_target(ctx)
	_test_map_view(ctx)
	await tree.process_frame


func _test_input_actions(ctx: Object) -> void:
	for a: String in ["interact", "quest_log_toggle", "inventory_toggle", "map_toggle"]:
		ctx.check(InputMap.has_action(a), "input '%s' existe" % a)
	# nenhuma tecla repetida entre as acoes novas e as de combate/movimento (E=skill_2 por isso interact e F)
	var seen: Dictionary = {}
	var clash: bool = false
	for a: StringName in InputMap.get_actions():
		if String(a).begins_with("ui_") or String(a).begins_with("inventory_slot_"):
			continue
		for ev: InputEvent in InputMap.action_get_events(a):
			if ev is InputEventKey:
				var code: int = (ev as InputEventKey).physical_keycode
				if seen.has(code) and String(seen[code]) != String(a):
					clash = true
				seen[code] = String(a)
	ctx.check(not clash, "teclas das acoes nao colidem entre si")
	ctx.check(String(seen.get(KEY_F, "")) == "interact" and String(seen.get(KEY_J, "")) == "quest_log_toggle" and String(seen.get(KEY_M, "")) == "map_toggle", "F/J/M mapeadas")


func _test_text(ctx: Object) -> void:
	ctx.check(UiText.item_name("potion_minor") == "Pocao Menor", "nome do item sem [PLACEHOLDER]: '%s'" % UiText.item_name("potion_minor"))
	ctx.check(UiText.item_name("item_inexistente") == "item inexistente", "item desconhecido cai no id legivel")
	ctx.check(UiText.item_name("../x") == ".. x".replace(" ", "/") or UiText.item_name("../x") == "../x", "id invalido nao vira caminho de arquivo")
	ctx.check(UiText.stack_text("scrap_material", 1) == UiText.item_name("scrap_material"), "stack qty 1 sem prefixo")
	ctx.check(UiText.stack_text("scrap_material", 3).begins_with("3x "), "stack qty 3 com prefixo")
	ctx.check(UiText.objective_line("Matar", 2, 5) == "[ ] Matar (2/5)", "objetivo parcial")
	ctx.check(UiText.objective_line("Matar", 9, 5) == "[x] Matar (5/5)", "objetivo concluido limitado")
	ctx.check(UiText.rewards_text(0, []) == "-", "recompensa vazia")
	ctx.check(UiText.rewards_text(60, [{"item_id": "potion_minor", "qty": 2}]).begins_with("60 XP, 2x"), "recompensa xp+item")
	for code: String in ["insufficient_ingredients", "inventory_full", "busy", "no_station", "too_far", "backend_error", "xyz"]:
		ctx.check(not UiText.craft_error(code).is_empty(), "erro de craft '%s' tem texto" % code)
	ctx.check(UiText.craft_error("insufficient_ingredients") != UiText.craft_error("inventory_full"), "erros de craft distintos")
	ctx.check(UiText.quest_error("too_far") != UiText.quest_error("wrong_npc"), "erros de quest distintos")
	ctx.check(UiText.quest_error("zzz").contains("zzz"), "codigo desconhecido aparece no texto")
	ctx.check(UiText.dialogue_error("too_far").length() > 5, "erro de dialogo")
	ctx.check(UiText.clamp_text("a".repeat(500), 20).length() == 20, "clamp_text limita")
	ctx.check(UiText.npc_name("npc_elder_orla") == "Ancia Orla", "nome do NPC sem placeholder: '%s'" % UiText.npc_name("npc_elder_orla"))
	ctx.check(UiText.zone_name("zone_hub") == WorldDef.shared().get_zone("zone_hub").display_name and UiText.zone_name("zona_x") == "zona_x", "nome da zona (e fallback para o id)")
	var t: Theme = UiStyle.theme()
	ctx.check(t == UiStyle.theme() and t.has_stylebox("normal", "Button"), "tema unico e completo")


func _test_client_inventory(ctx: Object) -> void:
	var inv: ClientInventory = ClientInventory.new()
	var changes: Array[int] = [0]
	inv.changed.connect(func() -> void: changes[0] += 1)
	ctx.check(inv.entries().is_empty() and not inv.complete, "inventario inicia vazio e incompleto")
	inv.on_pickup({"id": 1, "item_id": "scrap_material", "qty": 5})
	inv.on_pickup({"id": 2, "item_id": "scrap_material", "qty": 1})
	ctx.check(inv.count("scrap_material") == 6, "pickups somam")
	inv.on_pickup({"item_id": "BAD ID", "qty": 5})
	inv.on_pickup({"item_id": "potion_minor", "qty": -2})
	ctx.check(inv.entries().size() == 1, "pickup invalido ignorado")
	inv.on_craft_ok({"req_id": 1, "recipe_id": "rcp_potion_minor", "results": [{"item_id": "potion_minor", "qty": 1}]})
	ctx.check(inv.count("scrap_material") == 3 and inv.count("potion_minor") == 1, "craft subtrai ingredientes e soma resultado")
	inv.on_craft_ok({"req_id": 2, "recipe_id": "rcp_amulet_vigor", "results": [{"item_id": "amulet_vigor", "qty": 1}]})
	ctx.check(inv.count("scrap_material") == 0 and inv.count("potion_minor") == 0, "estimativa nunca fica negativa")
	inv.on_quest_reward([{"item_id": "potion_minor", "qty": 2}, "lixo"])
	ctx.check(inv.count("potion_minor") == 2, "recompensa de quest soma")
	ctx.check(changes[0] > 3, "sinal changed emitido")
	inv.apply_full([{"item_id": "sword_basic", "qty": 1}, {"item_id": "potion_minor", "qty": 4}, {"item_id": "x y", "qty": 1}], {"weapon": "sword_basic", "armor": "BAD"})
	ctx.check(inv.complete and inv.count("potion_minor") == 4 and inv.equipment.size() == 1, "apply_full marca completo e filtra invalidos")
	inv.reset()
	ctx.check(not inv.complete and inv.entries().is_empty(), "reset limpa")


func _dlg_view(choices: Array, terminal: bool = false) -> Dictionary:
	return {"npc_id": "npc_elder_orla", "dialogue_id": "dlg_elder_orla", "node_id": "n", "speaker": "npc_elder_orla", "text": "Ola, viajante.", "text_key": "k", "choices": choices, "terminal": terminal}


func _test_dialogue_panel(ctx: Object) -> void:
	var p: DialoguePanel = DialoguePanel.new()
	ctx.check(not p.is_open() and not p.visible, "dialogo inicia fechado")
	ctx.check(not p.handle_key(U.key(KEY_DOWN)), "fechado nao consome tecla")
	var picked: Array[int] = []
	p.choice_picked.connect(func(i: int) -> void: picked.append(i))
	var finished: Array[int] = [0]
	p.finished.connect(func() -> void: finished[0] += 1)
	p.show_view(_dlg_view([{"index": 0, "text": "Aceito."}, {"index": 1, "text": "Depois."}, {"index": 2, "text": "", "text_key": "dlg.k"}]))
	ctx.check(p.is_open() and p.choice_count() == 3, "mostra 3 escolhas")
	ctx.check(p.speaker_label.text == "Ancia Orla" and p.text_label.text == "Ola, viajante.", "fala e nome do NPC")
	ctx.check(p.choice_texts()[2] == "dlg.k", "escolha sem texto usa a chave")
	ctx.check(p.handle_key(U.key(KEY_DOWN)) and p.selected == 1, "Baixo seleciona a 2a")
	ctx.check(p.handle_key(U.key(KEY_DOWN)) and p.handle_key(U.key(KEY_DOWN)) and p.selected == 0, "navegacao com wrap")
	ctx.check(p.handle_key(U.key(KEY_UP)) and p.selected == 2, "Cima volta ao fim")
	ctx.check(p.handle_key(U.key(KEY_ENTER)) and picked == [2], "Enter escolhe o indice do servidor")
	ctx.check(p.handle_key(U.key(KEY_1)) and picked == [2, 0], "tecla 1 escolhe a 1a")
	ctx.check(p.handle_key(U.key(KEY_9)) and picked.size() == 2, "tecla fora do intervalo consome sem escolher")
	var enter_echo: InputEventKey = U.key(KEY_ENTER, true)
	p.handle_key(enter_echo)
	ctx.check(picked.size() == 2, "Enter com eco nao repete a escolha")
	(p.find_child("Choice1", true, false) as Button).pressed.emit()
	ctx.check(picked == [2, 0, 1], "clique do mouse escolhe")
	# indice do servidor pode ser diferente da posicao (escolhas ocultas)
	p.show_view(_dlg_view([{"index": 3, "text": "So esta"}]))
	p.handle_key(U.key(KEY_ENTER))
	ctx.check(picked.back() == 3, "usa o indice do servidor (3), nao a posicao")
	# terminal
	p.show_view(_dlg_view([], true))
	ctx.check(p.terminal and p.choice_count() == 0, "no terminal sem escolhas")
	ctx.check(not p.handle_key(U.key(KEY_DOWN)), "terminal ignora setas")
	ctx.check(p.handle_key(U.key(KEY_ENTER)) and finished[0] == 1, "Enter fecha o no terminal")
	p.show_view(_dlg_view([{"index": 0, "text": "x"}], true))
	ctx.check(p.terminal, "flag terminal do servidor vence")
	# malformados
	p.show_view({"npc_id": "npc_a", "speaker": "Fulano", "text": "", "text_key": "dlg.vazio", "choices": [5, {"index": "a"}, {"text": "sem indice"}, {"index": 1, "text": "ok"}]})
	ctx.check(p.choice_count() == 1 and p.text_label.text == "dlg.vazio" and p.speaker_label.text == "Fulano", "ignora escolhas malformadas e usa text_key")
	p.show_view(_dlg_view([{"index": 0, "text": "x".repeat(1000)}]))
	ctx.check(p.choice_texts()[0].length() <= 160, "texto de escolha limitado")
	var many: Array = []
	for i: int in 40:
		many.append({"index": i % 16, "text": "c%d" % i})
	p.show_view(_dlg_view(many))
	ctx.check(p.choice_count() == DialoguePanel.MAX_CHOICES, "no maximo %d escolhas" % DialoguePanel.MAX_CHOICES)
	p.set_status("Voce esta longe demais do NPC.", "bad")
	ctx.check(p.status_label.text.contains("longe"), "mostra texto de erro")
	p.close()
	ctx.check(not p.is_open() and not p.visible, "fecha")
	p.free()


func _test_quest_panel(ctx: Object) -> void:
	var p: QuestPanel = QuestPanel.new()
	p.open()
	ctx.check(p.is_open() and p.entries.is_empty(), "painel constroi sem log")
	var log: ClientQuestLog = ClientQuestLog.new()
	p.refresh(log)
	ctx.check(p.entries.is_empty() and p.detail_title.text == "Sem quests" and not p.btn_primary.visible, "estado vazio sem erro")
	ctx.check(not p.handle_key(U.key(KEY_DOWN)), "lista vazia nao navega")
	var req: Array = []
	p.accept_requested.connect(func(q: String) -> void: req.append(["acc", q]))
	p.abandon_requested.connect(func(q: String) -> void: req.append(["aban", q]))
	p.turn_in_requested.connect(func(q: String) -> void: req.append(["turn", q]))
	U.quest_sync(log, {"gw_clear_clearing": {"objectives": {"kill_grunts": 2}}, "gw_scrap_for_orla": {"objectives": {}}}, ["gw_welcome"], {"gw_ruins_expedition": "available", "gw_ruin_guardian": "unavailable"})
	log.ready["gw_scrap_for_orla"] = true
	p.refresh(log)
	var groups: Array[String] = []
	for e: Dictionary in p.entries:
		groups.append(String(e["status"]))
	ctx.check(groups.size() >= 3 and groups.has("completed") and groups.has("active"), "agrupa estados: %s" % str(groups))
	var first_active: int = groups.find("active")
	var first_ready: int = groups.find("ready")
	var first_av: int = groups.find("available")
	var first_done: int = groups.find("completed")
	ctx.check(first_ready == 0 and first_ready < first_active and first_active < first_av and first_av < first_done, "ordem: prontas, ativas, disponiveis, concluidas")
	ctx.check(not groups.has("unavailable"), "indisponiveis ficam ocultas")
	# pronta: Enter entrega
	ctx.check(p.selected_id() == "gw_scrap_for_orla" and p.btn_primary.visible and p.btn_primary.text.begins_with("Entregar"), "pronta mostra Entregar")
	p.handle_key(U.key(KEY_ENTER))
	ctx.check(req == [["turn", "gw_scrap_for_orla"]], "Enter entrega")
	p.handle_key(U.key(KEY_ENTER))
	ctx.check(req.size() == 1, "cooldown evita pedido duplicado")
	p.advance(1.0)
	# ativa: detalhe com progresso, abandonar com confirmacao
	p.handle_key(U.key(KEY_DOWN))
	ctx.check(p.selected_id() == "gw_clear_clearing" and p.selected_status() == "active", "Baixo seleciona a ativa")
	ctx.check(p.detail_objectives.text.contains("(2/5)") and p.detail_objectives.text.contains("[ ]"), "progresso do objetivo: " + p.detail_objectives.text)
	ctx.check(p.detail_extra.text.contains("150 XP") and not p.btn_primary.visible and p.btn_abandon.visible, "recompensa e so Abandonar para ativa")
	p.handle_key(U.key(KEY_DELETE))
	ctx.check(req.size() == 1 and p.btn_abandon.text.contains("Confirmar"), "1o Del apenas pede confirmacao")
	p.advance(QuestPanel.CONFIRM_WINDOW + 0.1)
	ctx.check(not p.btn_abandon.text.contains("Confirmar"), "confirmacao expira")
	p.handle_key(U.key(KEY_DELETE))
	p.handle_key(U.key(KEY_DELETE))
	ctx.check(req.back() == ["aban", "gw_clear_clearing"], "2o Del abandona")
	# disponivel: aceitar
	p.handle_key(U.key(KEY_DOWN))
	ctx.check(p.selected_status() == "available" and p.btn_primary.text.begins_with("Aceitar") and not p.btn_abandon.visible, "disponivel mostra Aceitar")
	p.advance(1.0)
	p.btn_primary.pressed.emit()
	ctx.check(req.back() == ["acc", "gw_ruins_expedition"], "clique em Aceitar")
	# concluida: sem acao, objetivos marcados
	p.handle_key(U.key(KEY_DOWN))
	ctx.check(p.selected_status() == "completed" and not p.btn_primary.visible and not p.btn_abandon.visible and p.detail_objectives.text.contains("[x]"), "concluida sem botoes")
	# selecao preservada em refresh
	var sel: String = p.selected_id()
	log.apply(Protocol.QUEST_PROGRESS, {"quest_id": "gw_clear_clearing", "objective_id": "kill_grunts", "value": 3, "required": 5})
	p.refresh(log)
	ctx.check(p.selected_id() == sel, "refresh preserva a selecao")
	# fila cheia de ids desconhecidos nao quebra
	log.active["quest_que_nao_existe"] = {}
	p.refresh(log)
	ctx.check(p.entries.size() > 0, "quest desconhecida nao quebra a lista")
	p.set_status("Chegue mais perto do NPC.", "bad")
	ctx.check(p.status_label.text.contains("perto"), "erro exibido")
	p.free()


func _test_inventory_panel(ctx: Object) -> void:
	var p: InventoryPanel = InventoryPanel.new()
	p.open()
	ctx.check(p.slot_buttons.size() == ClientInventory.SLOT_COUNT, "grade com %d slots" % ClientInventory.SLOT_COUNT)
	ctx.check(p.banner.visible and p.banner.text.contains("Estimativa"), "aviso de lacuna visivel quando incompleto")
	ctx.check(p.status_label.text.contains("Nenhum item"), "estado vazio")
	var inv: ClientInventory = ClientInventory.new()
	inv.add("scrap_material", 6)
	inv.add("potion_minor", 1)
	p.refresh(inv)
	ctx.check(p.slot_text(0) == UiText.item_name("potion_minor") and p.slot_text(1).contains("x6"), "slots com item/qty: '%s' | '%s'" % [p.slot_text(0), p.slot_text(1)])
	ctx.check(p.slot_text(2) == "" and p.slot_text(99) == "", "slots vazios")
	ctx.check(p.detail.text.contains("Slot 1"), "detalhe do cursor")
	p.handle_key(U.key(KEY_RIGHT))
	ctx.check(p.cursor == 1 and p.detail.text.contains("6x"), "seta direita move o cursor")
	p.handle_key(U.key(KEY_DOWN))
	ctx.check(p.cursor == 1 + InventoryPanel.COLUMNS, "seta baixo desce uma linha")
	for i: int in 10:
		p.handle_key(U.key(KEY_DOWN))
	ctx.check(p.cursor < ClientInventory.SLOT_COUNT, "cursor nao passa do fim")
	for i: int in 30:
		p.handle_key(U.key(KEY_LEFT))
	ctx.check(p.cursor == 0, "cursor nao passa do inicio")
	ctx.check(not p.handle_key(U.key(KEY_A)), "tecla alheia nao consumida")
	p.slot_buttons[3].mouse_entered.emit()
	ctx.check(p.cursor == 3, "mouse move o cursor")
	inv.apply_full([{"item_id": "sword_basic", "qty": 1}], {"weapon": "sword_basic"})
	p.refresh(inv)
	ctx.check(not p.banner.visible, "completo esconde o aviso")
	ctx.check((p.equip_labels["weapon"] as Label).text.contains(UiText.item_name("sword_basic")) and (p.equip_labels["armor"] as Label).text.ends_with("-"), "equipamento exibido")
	inv.apply_full([], {})
	p.refresh(inv)
	ctx.check(p.status_label.text.contains("vazia"), "mochila vazia (completa)")
	p.free()


func _test_craft_panel(ctx: Object) -> void:
	var cat: RecipeCatalog = RecipeCatalog.shared()
	var recs: Array[RecipeDef] = CraftPanel.recipes_for("station_greenwood_workbench", cat)
	ctx.check(recs.size() == 5 and CraftPanel.recipes_for("station_x", cat).is_empty(), "5 receitas da bancada, 0 de outra")
	var p: CraftPanel = CraftPanel.new()
	var asked: Array[String] = []
	p.craft_requested.connect(func(r: String) -> void: asked.append(r))
	p.open_station("station_x", "Nada", cat)
	ctx.check(p.recipes.is_empty() and p.btn_craft.disabled and p.detail_title.text == "Sem receitas", "estacao sem receitas: estado vazio")
	ctx.check(not p.handle_key(U.key(KEY_ENTER)) or asked.is_empty(), "Enter sem receita nao pede nada")
	p.open_station("station_greenwood_workbench", "Bancada de Greenwood", cat)
	ctx.check(p.title_label.text == "Bancada de Greenwood" and p.recipes.size() == 5 and not p.btn_craft.disabled, "abre com receitas")
	var first: RecipeDef = p.selected_recipe()
	ctx.check(p.detail_ing.text.contains("Ingredientes") and p.detail_ing.text.contains(UiText.item_name("scrap_material")), "ingredientes exibidos")
	ctx.check(p.detail_res.text.contains(UiText.item_name(String(first.results[0]["item_id"]))), "resultado exibido")
	p.handle_key(U.key(KEY_DOWN))
	ctx.check(p.selected_recipe() != first, "navega entre receitas")
	p.handle_key(U.key(KEY_UP))
	p.handle_key(U.key(KEY_ENTER))
	ctx.check(asked == [first.id] and p.pending and p.btn_craft.disabled, "Enter pede a receita e trava")
	p.handle_key(U.key(KEY_ENTER))
	ctx.check(asked.size() == 1, "nao repete enquanto pendente")
	p.show_result(false, {"req_id": 1, "recipe_id": first.id, "code": "insufficient_ingredients"})
	ctx.check(not p.pending and p.status_label.text == UiText.craft_error("insufficient_ingredients") and not p.btn_craft.disabled, "erro do servidor exibido e destrava")
	p.btn_craft.pressed.emit()
	ctx.check(asked.size() == 2, "clique pede de novo")
	p.show_result(true, {"req_id": 2, "recipe_id": first.id, "results": [{"item_id": "potion_minor", "qty": 1}]})
	ctx.check(p.status_label.text.begins_with("Fabricado:"), "sucesso exibido")
	p.btn_craft.pressed.emit()
	p.advance(CraftPanel.PENDING_TIMEOUT + 0.1)
	ctx.check(not p.pending and p.status_label.text.contains("Sem resposta"), "timeout destrava o botao")
	p.btn_craft.pressed.emit()
	p.show_send_failed()
	ctx.check(not p.pending and p.status_label.text.contains("conexao"), "falha de envio local")
	var inv: ClientInventory = ClientInventory.new()
	inv.apply_full([{"item_id": "scrap_material", "qty": 2}], {})
	p.set_inventory(inv)
	ctx.check(p.detail_ing.text.contains("tem 2"), "mostra 'tem N' so com inventario completo")
	p.free()


func _test_party_and_boss(ctx: Object) -> void:
	var ents: Array = [
		U.player(9, Vector3(1, 0, 1), 40.0, 100.0), U.player(7, Vector3.ZERO), U.player(3, Vector3(2, 0, 2), 0.0, 80.0),
		U.enemy(20, "melee_grunt", Vector3(5, 0, 5)),
	]
	var rows: Array[Dictionary] = PartyPanel.collect(ents, 7, {9: "Ana"}, "Eu")
	ctx.check(rows.size() == 3 and int(rows[0]["id"]) == 7 and String(rows[0]["name"]) == "Eu", "local primeiro; so jogadores")
	ctx.check(int(rows[1]["id"]) == 3 and int(rows[2]["id"]) == 9 and String(rows[2]["name"]) == "Ana", "ordem por id e nomes dos eventos")
	ctx.check(bool(rows[1]["dead"]) and String(rows[1]["name"]) == "Jogador 3", "morto marcado, nome padrao")
	var lots: Array = []
	for i: int in 20:
		lots.append(U.player(100 + i, Vector3.ZERO))
	ctx.check(PartyPanel.collect(lots, -1, {}).size() == PartyPanel.MAX_ROWS, "limita a %d linhas" % PartyPanel.MAX_ROWS)
	ctx.check(PartyPanel.collect([5, "x", {"kind": Protocol.KIND_PLAYER}], 1, {}).is_empty(), "lixo no vetor nao quebra")
	var pp: PartyPanel = PartyPanel.new()
	pp.refresh([], 7, {})
	ctx.check(not pp.visible and pp.row_count() == 0, "grupo vazio fica oculto")
	pp.refresh(ents, 7, {9: "Ana"})
	ctx.check(pp.visible and pp.row_count() == 3, "3 linhas")
	pp.refresh([U.player(7, Vector3.ZERO, 10.0, 100.0)], 7, {})
	ctx.check(pp.row_count() == 1, "remove quem saiu")
	pp.free()
	# chefe
	ctx.check(BossBar.pick_boss(ents).is_empty(), "sem chefe: nada")
	var bents: Array = ents + [U.enemy(30, "blight_treant", Vector3(40, 0, 0), 900.0, 1000.0, 1), U.enemy(31, "thorn_alpha", Vector3(3, 0, 0), 300.0, 400.0)]
	ctx.check(int(BossBar.pick_boss(bents, Vector3.ZERO)["id"]) == 31, "escolhe o chefe vivo mais proximo")
	bents[5]["hp"] = 0.0
	ctx.check(int(BossBar.pick_boss(bents, Vector3.ZERO)["id"]) == 30, "ignora chefe morto")
	var bb: BossBar = BossBar.new()
	bb.refresh(bents, Vector3.ZERO)
	ctx.check(bb.visible and bb.current_id == 30, "barra visivel com chefe")
	bb.refresh(ents, Vector3.ZERO)
	ctx.check(not bb.visible and bb.current_id == -1, "barra some sem chefe")
	bb.free()


func _test_toasts_and_fade(ctx: Object) -> void:
	var t: ToastStack = ToastStack.new()
	t.push("um")
	t.push("dois", "loot")
	t.push("")
	ctx.check(t.count() == 2, "2 toasts (vazio ignorado)")
	t.push("um")
	ctx.check(t.count() == 2, "mensagem repetida nao duplica")
	for i: int in 10:
		t.push("msg %d" % i)
	ctx.check(t.count() == ToastStack.MAX_VISIBLE, "no maximo %d visiveis" % ToastStack.MAX_VISIBLE)
	ctx.check(t.texts().back() == "msg 9", "mais novos ficam")
	t.push("x".repeat(500))
	ctx.check(t.texts().back().length() <= UiText.MAX_TOAST, "texto limitado")
	t.advance(ToastStack.DEFAULT_TTL - 0.1)
	ctx.check(t.count() > 0, "ainda visiveis antes do ttl")
	t.advance(0.2)
	ctx.check(t.count() == 0, "expiram sozinhos")
	t.push("a")
	t.clear_all()
	ctx.check(t.count() == 0 and t.get_child_count() == 0, "clear_all remove os nos")
	t.free()
	var f: ScreenFade = ScreenFade.new()
	ctx.check(f.alpha == 0.0 and not f.dead, "fade inicia transparente")
	f.fade_out()
	f.advance(0.1)
	ctx.check(f.alpha > 0.0 and f.alpha < 1.0, "escurece gradualmente")
	f.advance(1.0)
	ctx.check(f.is_dark(), "fica preto")
	f.fade_in()
	f.advance(0.1)
	ctx.check(f.alpha < 1.0, "clareia")
	f.advance(1.0)
	ctx.check(f.alpha == 0.0, "volta transparente")
	f.fade_out()
	f.advance(1.0)
	f.advance(ScreenFade.MAX_HOLD + 0.1)
	f.advance(1.0)
	ctx.check(f.alpha == 0.0, "trava de seguranca clareia sozinho")
	f.set_dead(true)
	ctx.check(f.dead, "estado de morte")
	f.reset()
	ctx.check(not f.dead and f.alpha == 0.0, "reset")
	f.free()


func _test_interact_target(ctx: Object) -> void:
	var zone: ZoneDef = WorldDef.shared().get_zone("zone_hub")
	var npcs: NpcDirectory = NpcDirectory.shared()
	var t: Dictionary = InteractTarget.find(U.HUB_ORLA, zone, npcs)
	ctx.check(String(t.get("kind", "")) == "npc" and String(t.get("id", "")) == "npc_elder_orla", "perto da Orla: alvo NPC")
	ctx.check(InteractTarget.prompt_text(t) == "[F] Falar com Ancia Orla", "prompt do NPC: " + InteractTarget.prompt_text(t))
	t = InteractTarget.find(U.HUB_STATION, zone, npcs)
	ctx.check(String(t.get("kind", "")) == "station" and InteractTarget.prompt_text(t).begins_with("[F] Usar"), "perto da bancada: estacao")
	ctx.check(InteractTarget.find(U.HUB_FAR, zone, npcs).is_empty() and InteractTarget.prompt_text({}) == "", "longe: nada")
	ctx.check(InteractTarget.find(Vector3(10, 30, -8), zone, npcs).is_empty(), "muito acima: fora de alcance (|dy|)")
	ctx.check(String(InteractTarget.find(U.HUB_ORLA, null, npcs).get("id", "")) == "npc_elder_orla", "sem zona (arena) considera todos os NPCs")
	ctx.check(InteractTarget.find(U.HUB_STATION, null, npcs).is_empty(), "sem zona nao ha estacoes")


func _test_map_view(ctx: Object) -> void:
	var zone: ZoneDef = WorldDef.shared().get_zone("zone_hub")
	var mm: MapView = MapView.new(MapView.Mode.MINI, Vector2(168, 168))
	var ents: Array = [U.player(7, Vector3(0, 0, 0)), U.player(8, Vector3(5, 0, 0)), U.enemy(20, "melee_grunt", Vector3(4, 0, 4)), U.enemy(21, "melee_grunt", Vector3(500, 0, 0)),
		U.enemy(22, "blight_treant", Vector3(-3, 0, 3), 100.0, 100.0), U.enemy(23, "melee_grunt", Vector3(1, 0, 1), 0.0)]
	mm.set_state(zone, 7, Vector3.ZERO, ents, PI * 0.25)
	var dl: Array[Dictionary] = mm.build_draw_list()
	var types: Array[String] = []
	for it: Dictionary in dl:
		types.append(String(it["type"]))
	ctx.check(types.count("local") == 1 and types.back() == "local", "jogador local desenhado por ultimo, uma vez")
	ctx.check(types.has("zone") and types.count("player") == 1, "zona e outro jogador")
	ctx.check(types.count("enemy") == 1 and types.count("boss") == 1, "so inimigos vivos e proximos (1 comum, 1 chefe)")
	var local_pos: Vector2 = dl.back()["pos"]
	ctx.check(local_pos.is_equal_approx(Vector2(84, 84)), "local no centro do minimapa")
	# 'frente' da camera aponta para cima na tela
	var fwd: Vector3 = PlayerMotion.world_direction(Vector2(0, 1), PI * 0.25)
	var up: Vector2 = mm.project(fwd * 10.0)
	ctx.check(absf(up.x - 84.0) < 0.01 and up.y < 84.0, "frente da camera vai para cima")
	var rt: Vector3 = PlayerMotion.world_direction(Vector2(1, 0), PI * 0.25)
	ctx.check(mm.project(rt * 10.0).x > 84.0, "direita da camera vai para a direita")
	mm.set_state(zone, 7, Vector3(10, 0, -8), [], PI * 0.25)
	var near_npc: bool = false
	var portal_seen: bool = false
	for it: Dictionary in mm.build_draw_list():
		if String(it["type"]) == "npc" and String(it["label"]) == "Ancia Orla":
			near_npc = true
		if String(it["type"]) == "portal":
			portal_seen = true
	ctx.check(near_npc and portal_seen, "perto da Orla: NPC e portal (a ~19 m) dentro da janela de 36 m")
	mm.set_state(zone, 7, Vector3(-25, 0, 25), [], PI * 0.25)
	var far_types: Array[String] = []
	for it: Dictionary in mm.build_draw_list():
		far_types.append(String(it["type"]))
	ctx.check(not far_types.has("portal") and far_types.has("zone"), "portal fora da janela e omitido; zona sempre desenhada")
	mm.set_state(null, 7, null, [], NAN)
	ctx.check(mm.build_draw_list().is_empty(), "sem zona nem local: lista vazia")
	mm.free()
	var fm: MapView = MapView.new(MapView.Mode.FULL, Vector2(540, 500))
	fm.set_state(zone, 7, Vector3(-10, 0, 10), [], 0.0)
	var ft: Array[String] = []
	for it: Dictionary in fm.build_draw_list():
		ft.append(String(it["type"]))
	ctx.check(ft.count("portal") == 1 and ft.count("npc") == 3 and ft.count("station") == 1, "mapa grande: portal, 3 NPCs, bancada")
	var north: Vector2 = fm.project(zone.center + Vector3(0, 0, -10))
	var south: Vector2 = fm.project(zone.center + Vector3(0, 0, 10))
	ctx.check(north.y < south.y and fm.project(zone.center).is_equal_approx(Vector2(270, 250)), "mapa grande: norte (-Z) em cima, zona centralizada")
	var corners: Vector2 = fm.project(zone.center + Vector3(zone.size.x * 0.5, 0, zone.size.y * 0.5))
	ctx.check(corners.x <= 540.0 and corners.y <= 500.0, "zona cabe no mapa grande")
	fm.free()
	var mp: MapPanel = MapPanel.new()
	mp.set_zone_title("Vila")
	ctx.check(mp.view.mode == MapView.Mode.FULL and mp.zone_label.text == "Vila", "painel do mapa")
	mp.free()
