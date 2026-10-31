extends RefCounted
## E5.1: quests + dialogo NO SERVIDOR (ServerSession + QuestService), sem rede real. Cobre: fluxo
## completo por dialogo e por RPC, validacao/abuso, eventos de servidor (kill/coleta/area), recompensa
## unica, inventario cheio, persistencia/rehidratacao com backend FALSO e replay de recompensa.

const H = preload("res://tests/e3/server_helpers.gd")
const B = preload("res://tests/e4/backend_helpers.gd")
const Fake = preload("res://tests/e4/fake_backend.gd")


func run(ctx: Object) -> void:
	var tree: SceneTree = ctx as SceneTree
	await tree.physics_frame # a arvore precisa ter iniciado (nos adicionados em _initialize ainda nao estao "prontos")
	ServerLog.capturing = true
	ServerLog.reset_capture()
	_test_attach_and_sync(ctx, tree)
	_test_dialogue_flow_dev(ctx, tree)
	_test_dialogue_guards(ctx, tree)
	_test_direct_rpc(ctx, tree)
	_test_abuse(ctx, tree)
	_test_server_events(ctx, tree)
	_test_area_events(ctx, tree)
	_test_inventory_full(ctx, tree)
	_test_backend_persistence(ctx, tree)
	_test_reward_replay(ctx, tree)
	await _test_reward_retry_same_key(ctx, tree)
	_test_reconnect_no_double_reward(ctx, tree)
	_test_detach_cleanup(ctx, tree)
	ServerLog.capturing = false
	await tree.physics_frame


# ------------------------------------------------------------------ helpers

func _dev_rig(tree: SceneTree) -> H.Rig:
	var rig: H.Rig = H.make_rig(tree, false, 4, false)
	rig.session.quests.enforce_range = true
	return rig


func _join(rig: H.Rig, peer: int = 1) -> int:
	return H.join(rig, peer, "Tester%d" % peer)


func _lo(rig: Object, eid: int) -> PlayerLoadout:
	return PlayerLoadout.find_for(rig.world.get_player_node(eid))


func _goto_npc(rig: Object, eid: int, npc_id: String) -> void:
	var p: Vector3 = NpcDirectory.shared().get_npc(npc_id)["position"]
	rig.world.get_player_node(eid).global_position = p


func _goto(rig: Object, eid: int, pos: Vector3) -> void:
	rig.world.get_player_node(eid).global_position = pos


func _svc(rig: Object) -> QuestService:
	return rig.session.quests


func _open(rig: Object, eid: int, npc: String) -> Dictionary:
	return _svc(rig).cmd_dialogue(eid, 1, Protocol.DIALOGUE_OP_OPEN, npc, 0)


func _choose(rig: Object, eid: int, idx: int) -> Dictionary:
	return _svc(rig).cmd_dialogue(eid, 1, Protocol.DIALOGUE_OP_CHOOSE, "", idx)


func _set_completed(lo: PlayerLoadout, ids: Array) -> void:
	for id: Variant in ids:
		if not lo.quest_state.completed.has(String(id)):
			lo.quest_state.completed.append(String(id))


## Joga a cadeia ate `gw_welcome` concluida no jogador (sem passar pela rede).
func _complete_welcome_by_dialogue(rig: Object, eid: int) -> void:
	_goto_npc(rig, eid, "npc_elder_orla")
	_open(rig, eid, "npc_elder_orla")
	_choose(rig, eid, 0) # aceitar
	_goto_npc(rig, eid, "npc_hunter_brannoch")
	_open(rig, eid, "npc_hunter_brannoch") # talk
	_goto_npc(rig, eid, "npc_elder_orla")
	_open(rig, eid, "npc_elder_orla")
	_choose(rig, eid, 0) # entregar


# ------------------------------------------------------------------ testes

func _test_attach_and_sync(ctx: Object, tree: SceneTree) -> void:
	var rig: H.Rig = _dev_rig(tree)
	var eid: int = _join(rig)
	ctx.check(_svc(rig).has_player(eid), "jogador registrado no QuestService ao entrar")
	var syncs: Array[Dictionary] = rig.transport.quest_msgs(1, Protocol.QUEST_SYNC)
	ctx.check(syncs.size() == 1 and syncs[0]["quests"] == {"active": {}, "completed": []}, "QUEST_SYNC inicial com diario vazio")
	ctx.check(syncs[0]["statuses"]["gw_welcome"] == "available" and syncs[0]["statuses"]["gw_ruin_guardian"] == "unavailable", "sync traz o status de cada quest")
	rig.free_all()


func _test_dialogue_flow_dev(ctx: Object, tree: SceneTree) -> void:
	var rig: H.Rig = _dev_rig(tree)
	var eid: int = _join(rig)
	var lo: PlayerLoadout = _lo(rig, eid)
	var xp0: int = lo.progress.total_xp
	var potions0: int = lo.inventory.count(&"potion_minor")
	_goto_npc(rig, eid, "npc_elder_orla")
	ctx.check(bool(_open(rig, eid, "npc_elder_orla")["ok"]), "abrir dialogo perto da Orla")
	var v: Dictionary = rig.transport.dialogue_msgs(1, Protocol.DIALOGUE_VIEW).back()
	ctx.check(v["node_id"] == "welcome_offer" and v["npc_id"] == "npc_elder_orla" and (v["choices"] as Array).size() == 2 and not bool(v["terminal"]), "view da oferta (2 escolhas)")
	ctx.check(bool(_choose(rig, eid, 0)["ok"]), "escolher 'aceitar'")
	ctx.check(_svc(rig).tracker_of(eid).state.is_active("gw_welcome") and rig.transport.quest_msgs(1, Protocol.QUEST_ACCEPTED).size() == 1, "quest aceita pelo efeito do dialogo (QUEST_ACCEPTED enviado)")
	var last: Dictionary = rig.transport.dialogue_msgs(1, Protocol.DIALOGUE_VIEW).back()
	ctx.check(last["node_id"] == "welcome_accepted" and bool(last["terminal"]), "no terminal apos aceitar")
	ctx.check(not bool(_choose(rig, eid, 0)["ok"]), "dialogo terminal encerrou: nova escolha recusada")
	# entregar antes de falar com Brannoch: o dialogo nem oferece a entrega
	_open(rig, eid, "npc_elder_orla")
	ctx.check(rig.transport.dialogue_msgs(1, Protocol.DIALOGUE_VIEW).back()["node_id"] == "welcome_waiting", "Orla pede para falar com Brannoch")
	# talk com Brannoch (server-side) avanca o objetivo e deixa a quest pronta
	_goto_npc(rig, eid, "npc_hunter_brannoch")
	_open(rig, eid, "npc_hunter_brannoch")
	ctx.check(rig.transport.quest_msgs(1, Protocol.QUEST_PROGRESS).size() == 1 and rig.transport.quest_msgs(1, Protocol.QUEST_READY).size() == 1, "abrir dialogo com Brannoch: PROGRESS + READY")
	# entregar
	_goto_npc(rig, eid, "npc_elder_orla")
	_open(rig, eid, "npc_elder_orla")
	ctx.check(rig.transport.dialogue_msgs(1, Protocol.DIALOGUE_VIEW).back()["node_id"] == "welcome_done", "Orla oferece a entrega")
	_choose(rig, eid, 0)
	ctx.check(_svc(rig).tracker_of(eid).state.is_completed("gw_welcome"), "quest concluida")
	ctx.check(lo.progress.total_xp == xp0 + 60 and lo.inventory.count(&"potion_minor") == potions0 + 2, "recompensa aplicada no servidor (60 xp + 2 pocoes)")
	var done: Array[Dictionary] = rig.transport.quest_msgs(1, Protocol.QUEST_COMPLETED)
	ctx.check(done.size() == 1 and done[0]["xp"] == 60 and done[0]["items"][0]["item_id"] == "potion_minor", "QUEST_COMPLETED com a recompensa")
	ctx.check(rig.transport.quest_msgs(1, Protocol.QUEST_SYNC).size() == 2 and rig.transport.quest_msgs(1, Protocol.QUEST_SYNC).back()["statuses"]["gw_clear_clearing"] == "available", "sync apos concluir libera a proxima quest")
	# recompensa unica: repetir a entrega (RPC direto) e recusado e nada muda
	var again: Dictionary = _svc(rig).cmd_quest(eid, 9, Protocol.QUEST_OP_TURN_IN, "gw_welcome")
	ctx.check(not bool(again["ok"]) and again["code"] == "already_completed" and lo.progress.total_xp == xp0 + 60 and lo.inventory.count(&"potion_minor") == potions0 + 2, "segunda entrega recusada, sem dobrar recompensa")
	var err: Dictionary = rig.transport.quest_msgs(1, Protocol.QUEST_ERROR).back()
	ctx.check(err["req_id"] == 9 and err["code"] == "already_completed", "QUEST_ERROR com o req_id do pedido")
	# o dialogo da Orla agora oferece a proxima quest (gw_scrap_for_orla)
	_open(rig, eid, "npc_elder_orla")
	ctx.check(rig.transport.dialogue_msgs(1, Protocol.DIALOGUE_VIEW).back()["node_id"] == "scrap_offer", "Orla oferece a sucata depois de concluir gw_welcome")
	rig.free_all()


func _test_dialogue_guards(ctx: Object, tree: SceneTree) -> void:
	var rig: H.Rig = _dev_rig(tree)
	var eid: int = _join(rig)
	var d: Dictionary = _open(rig, eid, "npc_elder_orla")
	ctx.check(not bool(d["ok"]) and d["code"] == "too_far", "longe do NPC: too_far")
	ctx.check(rig.transport.dialogue_msgs(1, Protocol.DIALOGUE_ERROR).back()["code"] == "too_far", "DIALOGUE_ERROR enviado")
	ctx.check(_open(rig, eid, "npc_inexistente")["code"] == "unknown_npc", "npc desconhecido")
	ctx.check(_svc(rig).cmd_dialogue(eid, 1, Protocol.DIALOGUE_OP_CHOOSE, "", 0)["code"] == "no_dialogue", "escolher sem dialogo aberto")
	# talk NAO conta se estiver longe
	_svc(rig).cmd_quest(eid, 1, Protocol.QUEST_OP_ACCEPT, "gw_welcome")
	ctx.check(not _svc(rig).tracker_of(eid).state.is_active("gw_welcome"), "aceitar longe do doador falha (too_far)")
	_goto_npc(rig, eid, "npc_elder_orla")
	_svc(rig).cmd_quest(eid, 1, Protocol.QUEST_OP_ACCEPT, "gw_welcome")
	_open(rig, eid, "npc_hunter_brannoch") # longe de Brannoch
	ctx.check(_svc(rig).tracker_of(eid).state.progress_of("gw_welcome", "talk_brannoch") == 0, "falar com NPC distante nao avanca o objetivo")
	# abrir dialogo (oferta, nao terminal), depois se afastar: a escolha e recusada e o dialogo fecha
	_svc(rig).tracker_of(eid).abandon("gw_welcome")
	_open(rig, eid, "npc_elder_orla")
	_goto(rig, eid, Vector3(-80, 0, -80))
	var c: Dictionary = _choose(rig, eid, 0)
	ctx.check(not bool(c["ok"]) and c["code"] == "too_far", "escolha apos se afastar do NPC: recusada")
	ctx.check(not bool(_choose(rig, eid, 0)["ok"]), "dialogo fechado depois de se afastar")
	# indice invalido
	_goto_npc(rig, eid, "npc_elder_orla")
	_open(rig, eid, "npc_elder_orla")
	ctx.check(_choose(rig, eid, 9)["code"] == "bad_choice", "indice de escolha fora da lista")
	# fechar
	ctx.check(bool(_svc(rig).cmd_dialogue(eid, 1, Protocol.DIALOGUE_OP_CLOSE, "", 0)["ok"]), "fechar dialogo")
	ctx.check(rig.transport.dialogue_msgs(1, Protocol.DIALOGUE_END).size() >= 1, "DIALOGUE_END enviado")
	# efeito nao pode aceitar quest de OUTRO NPC (wrong_npc): forja um dialogo hostil
	var forged: Dictionary = {
		"schema_version": 1, "id": "dlg_forged", "npc_id": "npc_elder_orla",
		"entries": [{"node": "n"}],
		"nodes": {"n": {"speaker": "x", "text": "t", "text_key": "k", "choices": [
			{"text": "x", "text_key": "k", "next": null, "effects": [{"type": "accept_quest", "quest_id": "gw_clear_clearing"}]}]}}}
	var fdef: DialogueDef = DialogueDef.parse(forged)["def"]
	var cat: DialogueCatalog = DialogueCatalog.new()
	cat.add(fdef)
	_svc(rig).dialogues = cat
	_set_completed(_lo(rig, eid), ["gw_welcome"])
	_svc(rig).tracker_of(eid).state.active.erase("gw_welcome")
	_open(rig, eid, "npc_elder_orla")
	_choose(rig, eid, 0)
	ctx.check(not _svc(rig).tracker_of(eid).state.is_active("gw_clear_clearing"), "dialogo do NPC errado nao aceita quest de outro doador (wrong_npc)")
	ctx.check(rig.transport.quest_msgs(1, Protocol.QUEST_ERROR).back()["code"] == "wrong_npc", "QUEST_ERROR wrong_npc")
	rig.free_all()


func _test_direct_rpc(ctx: Object, tree: SceneTree) -> void:
	var rig: H.Rig = _dev_rig(tree)
	var eid: int = _join(rig)
	var s: ServerSession = rig.session
	_goto_npc(rig, eid, "npc_elder_orla")
	s.on_quest_cmd(1, 1, Protocol.QUEST_OP_ACCEPT, "gw_welcome")
	ctx.check(_svc(rig).tracker_of(eid).state.is_active("gw_welcome"), "on_quest_cmd aceitar (RPC) funciona perto do doador")
	s.test_now_msec += 1000
	s.on_quest_cmd(1, 2, Protocol.QUEST_OP_TURN_IN, "gw_welcome")
	ctx.check(rig.transport.quest_msgs(1, Protocol.QUEST_ERROR).back()["code"] == "not_ready", "entregar sem completar: not_ready")
	s.test_now_msec += 1000
	s.on_quest_cmd(1, 3, Protocol.QUEST_OP_ACCEPT, "gw_welcome")
	ctx.check(rig.transport.quest_msgs(1, Protocol.QUEST_ERROR).back()["code"] == "already_active", "aceitar de novo: already_active")
	s.test_now_msec += 1000
	s.on_quest_cmd(1, 4, Protocol.QUEST_OP_ABANDON, "gw_welcome")
	ctx.check(not _svc(rig).tracker_of(eid).state.is_active("gw_welcome") and rig.transport.quest_msgs(1, Protocol.QUEST_ABANDONED).size() == 1, "abandonar (RPC)")
	ctx.check(rig.transport.rejects.is_empty() and s.has_peer(1), "erros de regra nao punem o peer")
	s.test_now_msec += 1000
	s.on_quest_cmd(1, 5, Protocol.QUEST_OP_ACCEPT, "gw_ruin_guardian")
	ctx.check(rig.transport.quest_msgs(1, Protocol.QUEST_ERROR).back()["code"] == "too_far", "doador de outra quest longe: too_far (checa o doador, nao o NPC mais proximo)")
	# quest desconhecida (id valido mas inexistente)
	s.test_now_msec += 1000
	_goto_npc(rig, eid, "npc_elder_orla")
	s.on_quest_cmd(1, 6, Protocol.QUEST_OP_ACCEPT, "quest_que_nao_existe")
	ctx.check(rig.transport.quest_msgs(1, Protocol.QUEST_ERROR).back()["code"] == "unknown_quest", "quest desconhecida")
	# nenhum RPC concede progresso/recompensa: nao ha op para isso
	ctx.check(not bool(Protocol.validate_quest_cmd(1, 4, "gw_welcome")["ok"]) and not bool(Protocol.validate_quest_cmd(1, 99, "gw_welcome")["ok"]), "nao existe operacao de progresso/recompensa vinda do cliente")
	rig.free_all()


func _test_abuse(ctx: Object, tree: SceneTree) -> void:
	# comando antes do welcome
	var rig: H.Rig = _dev_rig(tree)
	rig.session.on_peer_connected(7)
	rig.session.on_quest_cmd(7, 1, Protocol.QUEST_OP_ACCEPT, "gw_welcome")
	ctx.check(rig.transport.reject_codes(7) == [Protocol.REJECT_NOT_AUTHENTICATED], "comando de quest antes do welcome -> reject(5)")
	rig.session.on_peer_connected(8)
	rig.session.on_dialogue_cmd(8, 1, Protocol.DIALOGUE_OP_OPEN, "npc_elder_orla", 0)
	ctx.check(rig.transport.reject_codes(8) == [Protocol.REJECT_NOT_AUTHENTICATED], "comando de dialogo antes do welcome -> reject(5)")
	rig.free_all()
	# payload invalido repetido -> contagem de abuso -> reject(4)
	var r2: H.Rig = _dev_rig(tree)
	r2.settings.max_invalid_inputs = 5
	r2.settings.quest_burst = 1000
	var eid: int = _join(r2)
	for i: int in 5:
		r2.session.on_quest_cmd(1, "x", 1, "gw_welcome")
	var st: ServerSession.PeerState = r2.session.get_peer_state(1)
	ctx.check(st != null and st.dropped_invalid == 5 and r2.transport.rejects.is_empty(), "5 payloads invalidos: descartados e contados, ainda conectado")
	r2.session.on_dialogue_cmd(1, 1, Protocol.DIALOGUE_OP_CHOOSE, "npc_a", 0) # invalido (npc so vale no open)
	ctx.check(r2.transport.reject_codes(1) == [Protocol.REJECT_RATE_LIMIT], "acima do limite de invalidos: reject(4)")
	ctx.check(not _svc(r2).has_player(eid) and r2.transport.disconnects.has(1), "peer rejeitado e desconectado; quests desligadas")
	r2.free_all()
	# rate limit proprio dos comandos de quest
	var r3: H.Rig = _dev_rig(tree)
	r3.settings.max_invalid_inputs = 1000
	var e3: int = _join(r3)
	_goto_npc(r3, e3, "npc_elder_orla")
	for i: int in 40:
		r3.session.on_quest_cmd(1, i, Protocol.QUEST_OP_ACCEPT, "gw_welcome")
	var st3: ServerSession.PeerState = r3.session.get_peer_state(1)
	ctx.check(st3.dropped_rate > 0 and st3.dropped_rate == 40 - r3.settings.quest_burst, "token bucket: %d comandos alem do burst descartados" % st3.dropped_rate)
	r3.free_all()


func _test_server_events(ctx: Object, tree: SceneTree) -> void:
	var rig: H.Rig = _dev_rig(tree)
	var a: int = _join(rig, 1)
	var b: int = _join(rig, 2)
	var la: PlayerLoadout = _lo(rig, a)
	_set_completed(la, ["gw_welcome"])
	_goto_npc(rig, a, "npc_hunter_brannoch")
	_svc(rig).cmd_quest(a, 1, Protocol.QUEST_OP_ACCEPT, "gw_clear_clearing")
	var t: QuestTracker = _svc(rig).tracker_of(a)
	ctx.check(t.state.is_active("gw_clear_clearing"), "preparo: gw_clear_clearing ativa")
	# kill do OUTRO jogador nao conta
	rig.world.player_killed_enemy.emit(b, 100, "melee_grunt")
	ctx.check(t.state.progress_of("gw_clear_clearing", "kill_grunts") == 0, "kill de outro jogador nao conta")
	for i: int in 5:
		rig.world.player_killed_enemy.emit(a, 100 + i, "melee_grunt")
	ctx.check(t.state.progress_of("gw_clear_clearing", "kill_grunts") == 5 and t.status_of("gw_clear_clearing", 1) == "ready", "5 kills do servidor: pronta")
	ctx.check(rig.transport.quest_msgs(1, Protocol.QUEST_PROGRESS).size() == 5 and rig.transport.quest_msgs(1, Protocol.QUEST_READY).size() == 1 and rig.transport.quest_msgs(2, Protocol.QUEST_PROGRESS).is_empty(), "mensagens so para o dono da quest")
	# kill REAL (cadeia mundo -> sessao)
	_svc(rig).tracker_of(a).abandon("gw_clear_clearing")
	_svc(rig).cmd_quest(a, 2, Protocol.QUEST_OP_ACCEPT, "gw_clear_clearing")
	var eid: int = rig.world.spawn_enemy(H.GRUNT_SCENE, Vector3(30, 0.05, 30))
	var enemy: Enemy = rig.world.get_enemy_node(eid)
	enemy.health.apply_damage(DamageInfo.make(99999.0, rig.world.get_player_node(a), Hitbox.new_hit_id()))
	ctx.check(t.state.progress_of("gw_clear_clearing", "kill_grunts") == 1, "kill REAL de melee_grunt avanca o objetivo do matador")
	# coleta: em modo dev (drops informativos) NAO conta; com persist_drops conta so o que entrou
	_svc(rig).tracker_of(a).abandon("gw_clear_clearing")
	_goto_npc(rig, a, "npc_elder_orla")
	_svc(rig).cmd_quest(a, 3, Protocol.QUEST_OP_ACCEPT, "gw_scrap_for_orla")
	rig.world.enemy_killed.emit(1, a, 0, [{"item_id": "scrap_material", "qty": 3}])
	ctx.check(t.state.progress_of("gw_scrap_for_orla", "collect_scrap") == 0, "modo dev: drops informativos nao contam como coleta")
	rig.settings.persist_drops = true
	rig.world.enemy_killed.emit(1, a, 0, [{"item_id": "scrap_material", "qty": 3}])
	ctx.check(t.state.progress_of("gw_scrap_for_orla", "collect_scrap") == 3, "persist_drops: itens que entraram contam")
	rig.world.enemy_killed.emit(1, b, 0, [{"item_id": "scrap_material", "qty": 3}])
	ctx.check(t.state.progress_of("gw_scrap_for_orla", "collect_scrap") == 3, "coleta de outro jogador nao conta")
	rig.world.enemy_killed.emit(1, a, 0, [{"item_id": "scrap_material", "qty": 99}, {"item_id": "potion_minor", "qty": 1}])
	ctx.check(t.status_of("gw_scrap_for_orla", 1) == "ready", "coleta completa a quest")
	# evento para jogador inexistente nao quebra
	rig.world.player_killed_enemy.emit(999, 1, "melee_grunt")
	_svc(rig).on_items_gained(999, [{"item_id": "x", "qty": 1}])
	ctx.check(true, "eventos para entidade inexistente sao ignorados")
	rig.free_all()


func _test_area_events(ctx: Object, tree: SceneTree) -> void:
	var rig: H.Rig = _dev_rig(tree)
	var eid: int = _join(rig)
	var lo: PlayerLoadout = _lo(rig, eid)
	_set_completed(lo, ["gw_welcome", "gw_clear_clearing"])
	lo.progress.level = 2
	_goto_npc(rig, eid, "npc_scholar_ilmar")
	_svc(rig).cmd_quest(eid, 1, Protocol.QUEST_OP_ACCEPT, "gw_ruins_expedition")
	var t: QuestTracker = _svc(rig).tracker_of(eid)
	ctx.check(t.state.is_active("gw_ruins_expedition"), "preparo: expedicao ativa (nivel 2)")
	var gate: Vector3 = AreaSet.shared().areas["area_ruins_gate"]["center"]
	var hall: Vector3 = AreaSet.shared().areas["area_ruins_hall"]["center"]
	_goto(rig, eid, gate)
	for i: int in 4:
		rig.session.step_tick()
	ctx.check(t.state.progress_of("gw_ruins_expedition", "reach_gate") == 0, "antes do intervalo de checagem nada acontece")
	rig.session.step_tick()
	ctx.check(t.state.progress_of("gw_ruins_expedition", "reach_gate") == 1, "entrar na area (posicao do servidor) avanca o objetivo")
	for i: int in 10:
		rig.session.step_tick()
	ctx.check(rig.transport.quest_msgs(1, Protocol.QUEST_PROGRESS).size() == 1, "permanecer na area nao repete o progresso")
	_goto(rig, eid, hall)
	for i: int in 5:
		rig.session.step_tick()
	ctx.check(t.status_of("gw_ruins_expedition", 2) == "ready", "segunda area: quest pronta")
	rig.free_all()


func _test_inventory_full(ctx: Object, tree: SceneTree) -> void:
	var rig: H.Rig = _dev_rig(tree)
	var eid: int = _join(rig)
	var lo: PlayerLoadout = _lo(rig, eid)
	_goto_npc(rig, eid, "npc_elder_orla")
	_svc(rig).cmd_quest(eid, 1, Protocol.QUEST_OP_ACCEPT, "gw_welcome")
	_svc(rig).tracker_of(eid).on_npc_talked("npc_hunter_brannoch")
	# enche o inventario com itens nao empilhaveis
	while lo.inventory.free_slots() > 0:
		lo.inventory.add(&"sword_basic", 1)
	lo.inventory.remove(&"potion_minor", lo.inventory.count(&"potion_minor"))
	while lo.inventory.free_slots() > 0:
		lo.inventory.add(&"sword_basic", 1)
	var xp0: int = lo.progress.total_xp
	var snap: Array[Dictionary] = lo.inventory.contents()
	var r: Dictionary = _svc(rig).cmd_quest(eid, 4, Protocol.QUEST_OP_TURN_IN, "gw_welcome")
	ctx.check(not bool(r["ok"]) and r["code"] == "inventory_full", "entrega com inventario cheio: inventory_full")
	ctx.check(lo.progress.total_xp == xp0 and lo.inventory.contents() == snap, "nada aplicado (nem xp nem itens parciais)")
	ctx.check(_svc(rig).tracker_of(eid).status_of("gw_welcome", 1) == "ready", "a quest continua pronta para entregar depois")
	lo.inventory.remove(&"sword_basic", 3)
	ctx.check(bool(_svc(rig).cmd_quest(eid, 5, Protocol.QUEST_OP_TURN_IN, "gw_welcome")["ok"]), "com espaco, a entrega funciona")
	rig.free_all()


# ------------------------------------------------------------------ com backend falso

func _brig(tree: SceneTree, quests: Dictionary = {}) -> B.BRig:
	var rig: B.BRig = B.make(tree)
	rig.fake.add_character(B.CID1, 3, 700, [], {"weapon": "sword_basic", "armor": "armor_leather"}, 5, "Sir_Hero")
	if not quests.is_empty():
		rig.fake.chars[B.CID1]["quests"] = quests
	rig.fake.tickets[B.TICKET1] = B.CID1
	B.hello(rig, 1, B.TICKET1)
	return rig


func _eid(rig: B.BRig) -> int:
	return rig.session.get_peer_state(1).entity_id


func _test_backend_persistence(ctx: Object, tree: SceneTree) -> void:
	var saved: Dictionary = {"active": {"gw_clear_clearing": {"objectives": {"kill_grunts": 3.0}}}, "completed": ["gw_welcome"]}
	var rig: B.BRig = _brig(tree, saved)
	var eid: int = _eid(rig)
	var t: QuestTracker = rig.session.quests.tracker_of(eid)
	ctx.check(t != null and t.state.is_completed("gw_welcome") and t.state.progress_of("gw_clear_clearing", "kill_grunts") == 3, "rehidratacao: quests restauradas do backend (3/5, welcome concluida)")
	ctx.check(typeof(t.state.progress_of("gw_clear_clearing", "kill_grunts")) == TYPE_INT, "progresso rehidratado como int (JSON float)")
	var sy: Dictionary = rig.transport.quest_msgs(1, Protocol.QUEST_SYNC)[0]
	ctx.check(sy["quests"]["active"]["gw_clear_clearing"]["objectives"]["kill_grunts"] == 3, "cliente recebe o estado persistido no QUEST_SYNC inicial")
	rig.world.player_killed_enemy.emit(eid, 1, "melee_grunt")
	rig.world.player_killed_enemy.emit(eid, 2, "melee_grunt")
	rig.sync.tick(30.0) # autosave
	var cp: Dictionary = rig.fake.find_all("/checkpoint").back()["body"]["state"]
	ctx.check(cp["quests"]["active"]["gw_clear_clearing"]["objectives"]["kill_grunts"] == 5 and cp["quests"]["completed"] == ["gw_welcome"], "autosave inclui o progresso de quests (5/5)")
	ctx.check(rig.fake.chars[B.CID1]["quests"]["active"]["gw_clear_clearing"]["objectives"]["kill_grunts"] == 5, "backend guardou o progresso")
	# aceitar dispara checkpoint imediato (nao espera o autosave)
	var cps0: int = rig.fake.count("/checkpoint")
	var lo: PlayerLoadout = _lo(rig, eid)
	_goto_npc(rig, eid, "npc_elder_orla")
	rig.session.quests.cmd_quest(eid, 1, Protocol.QUEST_OP_ACCEPT, "gw_scrap_for_orla")
	ctx.check(rig.fake.count("/checkpoint") == cps0 + 1 and rig.fake.chars[B.CID1]["quests"]["active"].has("gw_scrap_for_orla"), "aceitar persiste na hora (checkpoint)")
	rig.session.quests.cmd_quest(eid, 2, Protocol.QUEST_OP_ABANDON, "gw_scrap_for_orla")
	ctx.check(not (rig.fake.chars[B.CID1]["quests"]["active"] as Dictionary).has("gw_scrap_for_orla"), "abandonar persiste na hora")
	# desconexao: checkpoint final leva as quests
	rig.session.on_peer_disconnected(1)
	var order: Array[String] = rig.fake.order()
	ctx.check(rig.fake.chars[B.CID1]["quests"]["completed"] == ["gw_welcome"] and lo != null, "estado final de quests no backend apos desconectar")
	rig.free_all()
	# personagem pre-E5.1 (sem campo quests) entra normalmente
	var rig2: B.BRig = B.make(tree)
	rig2.fake.add_character(B.CID1, 1, 0, [], {"weapon": "sword_basic"}, 0, "Velho")
	rig2.fake.chars[B.CID1].erase("quests")
	rig2.fake.tickets[B.TICKET1] = B.CID1
	B.hello(rig2, 1, B.TICKET1)
	ctx.check(rig2.session.get_peer_state(1).welcomed and rig2.session.quests.tracker_of(_eid(rig2)).state.active.is_empty(), "personagem sem campo quests entra com diario vazio")
	rig2.free_all()
	# quests desconhecidas no save sao descartadas (conteudo removido), sem derrubar o login
	var rig3: B.BRig = _brig(tree, {"active": {"quest_removida": {"objectives": {"x": 1}}}, "completed": ["tambem_removida", "gw_welcome"]})
	ctx.check(rig3.session.get_peer_state(1).welcomed and rig3.session.quests.tracker_of(_eid(rig3)).state.completed == ([ "gw_welcome" ] as Array[String]), "ids desconhecidos descartados no login")
	rig3.free_all()
	# forma invalida de quests => login recusado (estado corrompido nao e aceito)
	var rig4: B.BRig = B.make(tree)
	rig4.fake.add_character(B.CID1)
	rig4.fake.chars[B.CID1]["quests"] = {"active": "lixo", "completed": []}
	rig4.fake.tickets[B.TICKET1] = B.CID1
	B.hello(rig4, 1, B.TICKET1)
	ctx.check(rig4.transport.reject_codes(1) == [Protocol.REJECT_NOT_AUTHENTICATED] and rig4.world.player_count() == 0, "quests com forma invalida: reject(5), nenhum jogador")
	rig4.free_all()


func _ready_welcome(rig: B.BRig, eid: int) -> void:
	_goto_npc(rig, eid, "npc_elder_orla")
	rig.session.quests.cmd_quest(eid, 1, Protocol.QUEST_OP_ACCEPT, "gw_welcome")
	rig.session.quests.tracker_of(eid).on_npc_talked("npc_hunter_brannoch")


func _test_reward_replay(ctx: Object, tree: SceneTree) -> void:
	var rig: B.BRig = _brig(tree)
	var eid: int = _eid(rig)
	var lo: PlayerLoadout = _lo(rig, eid)
	_ready_welcome(rig, eid)
	var r: Dictionary = rig.session.quests.cmd_quest(eid, 2, Protocol.QUEST_OP_TURN_IN, "gw_welcome")
	ctx.check(bool(r["ok"]), "entrega com backend")
	var rw: Array[Dictionary] = rig.fake.find_all("/rewards")
	ctx.check(rw.size() == 1, "1 recompensa enviada ao backend")
	var body: Dictionary = rw[0]["body"]
	ctx.check(body["idempotency_key"] == "quest:gw_welcome:" + B.CID1 and body["quest_id"] == "gw_welcome", "chave estavel quest:<quest_id>:<character_id> e quest_id no corpo")
	ctx.check(int(body["xp"]) == 60 and body["items"].size() == 1 and body["items"][0]["item_id"] == "potion_minor" and int(body["items"][0]["qty"]) == 2, "xp/itens da recompensa = definicao da quest")
	ctx.check(rig.fake.chars[B.CID1]["quests"]["completed"].has("gw_welcome") and int(rig.fake.chars[B.CID1]["xp"]) == 760, "backend: quest concluida e xp somado uma vez")
	var xp_mem: int = lo.progress.total_xp
	# replay local (cliente malicioso reenviando) e recusado antes de qualquer envio
	var again: Dictionary = rig.session.quests.cmd_quest(eid, 3, Protocol.QUEST_OP_TURN_IN, "gw_welcome")
	ctx.check(not bool(again["ok"]) and rig.fake.count("/rewards") == 1 and lo.progress.total_xp == xp_mem, "replay de entrega: recusado localmente, sem novo pedido ao backend")
	# replay no nivel do backend (mesma chave de novo): replayed, sem dobrar
	var before: int = int(rig.fake.chars[B.CID1]["xp"])
	rig.sync.enqueue_reward(B.CID1, "quest:gw_welcome:" + B.CID1, 60, [{"item_id": "potion_minor", "qty": 2}], "gw_welcome")
	ctx.check(int(rig.fake.chars[B.CID1]["xp"]) == before, "backend: mesma chave => replay, xp nao dobra")
	rig.free_all()


func _test_reward_retry_same_key(ctx: Object, tree: SceneTree) -> void:
	var rig: B.BRig = _brig(tree)
	var eid: int = _eid(rig)
	_ready_welcome(rig, eid)
	rig.fake.force("/rewards", [Fake.NET_ERR, Fake.TIMEOUT_ERR])
	rig.session.quests.cmd_quest(eid, 2, Protocol.QUEST_OP_TURN_IN, "gw_welcome")
	var t0: int = Time.get_ticks_msec()
	while rig.fake.find_all("/rewards").size() < 3 and Time.get_ticks_msec() - t0 < 3000:
		await tree.process_frame
	for i: int in 5:
		await tree.process_frame
	var rw: Array[Dictionary] = rig.fake.find_all("/rewards")
	var keys: Dictionary = {}
	for x: Dictionary in rw:
		keys[x["body"]["idempotency_key"]] = true
	ctx.check(rw.size() == 3 and keys.size() == 1, "falha de rede: 3 tentativas com a MESMA chave")
	ctx.check(rw[0]["raw"] == rw[2]["raw"], "corpo identico em todas as tentativas")
	ctx.check(int(rig.fake.chars[B.CID1]["xp"]) == 760 and rig.fake.chars[B.CID1]["quests"]["completed"] == ["gw_welcome"], "aplicado no backend exatamente uma vez")
	rig.free_all()
	# falha permanente (backend recusa): estado em memoria mantido e logado, sem retry infinito
	var rig2: B.BRig = _brig(tree)
	var e2: int = _eid(rig2)
	_ready_welcome(rig2, e2)
	rig2.fake.force("/rewards", [Fake.err(409, "inventory_full")])
	rig2.session.quests.cmd_quest(e2, 2, Protocol.QUEST_OP_TURN_IN, "gw_welcome")
	ctx.check(rig2.fake.count("/rewards") == 1 and rig2.session.quests.tracker_of(e2).state.is_completed("gw_welcome"), "falha permanente: sem retry; memoria mantida")
	rig2.free_all()


func _test_reconnect_no_double_reward(ctx: Object, tree: SceneTree) -> void:
	var rig: B.BRig = _brig(tree)
	var eid: int = _eid(rig)
	_ready_welcome(rig, eid)
	rig.session.quests.cmd_quest(eid, 2, Protocol.QUEST_OP_TURN_IN, "gw_welcome")
	var xp_backend: int = int(rig.fake.chars[B.CID1]["xp"])
	rig.session.on_peer_disconnected(1)
	# reconecta: a quest concluida volta concluida e a entrega e recusada
	rig.fake.tickets[B.TICKET2] = B.CID1
	B.hello(rig, 2, B.TICKET2)
	var e2: int = rig.session.get_peer_state(2).entity_id
	var t: QuestTracker = rig.session.quests.tracker_of(e2)
	ctx.check(t != null and t.state.is_completed("gw_welcome"), "reconexao: quest continua concluida")
	_goto_npc(rig, e2, "npc_elder_orla")
	var r: Dictionary = rig.session.quests.cmd_quest(e2, 1, Protocol.QUEST_OP_TURN_IN, "gw_welcome")
	ctx.check(not bool(r["ok"]) and int(rig.fake.chars[B.CID1]["xp"]) == xp_backend, "reconexao: nao ha como receber a recompensa de novo")
	var acc: Dictionary = rig.session.quests.cmd_quest(e2, 2, Protocol.QUEST_OP_ACCEPT, "gw_welcome")
	ctx.check(not bool(acc["ok"]) and acc["code"] == "already_completed", "reconexao: nao reaceita quest concluida")
	rig.free_all()
	# crash entre a recompensa e o checkpoint: o backend ja marcou a quest (mesma transacao) => sem reentrega
	var rig2: B.BRig = _brig(tree, {"active": {"gw_welcome": {"objectives": {"talk_brannoch": 1}}}, "completed": []})
	var e3: int = _eid(rig2)
	_goto_npc(rig2, e3, "npc_elder_orla")
	ctx.check(rig2.session.quests.tracker_of(e3).status_of("gw_welcome", 3) == "ready", "save com quest pronta rehidrata como pronta")
	rig2.session.quests.cmd_quest(e3, 1, Protocol.QUEST_OP_TURN_IN, "gw_welcome")
	var xp_after: int = int(rig2.fake.chars[B.CID1]["xp"])
	# o mesmo pedido reenviado ao backend (como num retry apos perda de resposta) devolve replay
	rig2.sync.enqueue_reward(B.CID1, "quest:gw_welcome:" + B.CID1, 60, [{"item_id": "potion_minor", "qty": 2}], "gw_welcome")
	ctx.check(int(rig2.fake.chars[B.CID1]["xp"]) == xp_after and xp_after == 760, "retry apos resposta perdida: replay, xp aplicado uma vez")
	rig2.free_all()


func _test_detach_cleanup(ctx: Object, tree: SceneTree) -> void:
	var rig: H.Rig = _dev_rig(tree)
	var eid: int = _join(rig)
	var t: QuestTracker = _svc(rig).tracker_of(eid)
	ctx.check(t.quest_accepted.get_connections().size() == 1, "tracker conectado ao servico")
	rig.session.on_peer_disconnected(1)
	ctx.check(not _svc(rig).has_player(eid) and t.quest_accepted.get_connections().is_empty() and t.quest_completed.get_connections().is_empty(), "desconectar desliga o servico e solta os sinais (sem vazamento)")
	_svc(rig).on_enemy_killed(eid, "melee_grunt")
	ctx.check(_svc(rig).cmd_quest(eid, 1, Protocol.QUEST_OP_ACCEPT, "gw_welcome")["code"] == "no_player", "comandos de jogador desligado sao recusados")
	rig.free_all()
	# logs limpos: nada de segredo/ticket
	for line: String in ServerLog.captured:
		if line.contains(B.TICKET1) or line.contains(B.SECRET):
			ctx.check(false, "log vazou segredo/ticket")
			return
	ctx.check(true, "logs de quests sem segredos/tickets")
