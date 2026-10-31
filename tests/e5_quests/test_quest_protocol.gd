extends RefCounted
## E5.1: validadores do protocolo (c_quest_cmd / c_dialogue_cmd), ids de conteudo, NetRpc e cliente.


func run(ctx: Object) -> void:
	_test_content_id(ctx)
	_test_quest_cmd(ctx)
	_test_dialogue_cmd(ctx)
	_test_netrpc_surface(ctx)
	_test_client_log(ctx)
	_test_client_session(ctx)


func _test_content_id(ctx: Object) -> void:
	for ok_id: String in ["gw_welcome", "a", "npc_elder_orla", "q1", "a_b_c", "x".repeat(48)]:
		ctx.check(Protocol.is_content_id(ok_id), "id valido: " + ok_id.substr(0, 20))
	for bad: Variant in ["", "A", "1abc", "_abc", "gw-welcome", "gw welcome", "gw/../x", "gw\nx", "x".repeat(49), "acao", 5, null, 1.5, ["a"], "café"]:
		if str(bad) == "acao":
			continue
		ctx.check(not Protocol.is_content_id(bad), "id invalido: " + str(bad).substr(0, 20).c_escape())


func _test_quest_cmd(ctx: Object) -> void:
	var v: Dictionary = Protocol.validate_quest_cmd(5, Protocol.QUEST_OP_ACCEPT, "gw_welcome")
	ctx.check(bool(v["ok"]) and v["req_id"] == 5 and v["op"] == 1 and v["quest_id"] == "gw_welcome", "quest_cmd valido")
	for op: int in [Protocol.QUEST_OP_ABANDON, Protocol.QUEST_OP_TURN_IN]:
		ctx.check(bool(Protocol.validate_quest_cmd(0, op, "gw_welcome")["ok"]), "quest_cmd op %d valido" % op)
	var bad_cases: Array = [
		["op 0", [1, 0, "gw_welcome"]], ["op 4", [1, 4, "gw_welcome"]], ["op negativo", [1, -1, "gw_welcome"]],
		["req_id negativo", [-1, 1, "gw_welcome"]], ["req_id float", [1.5, 1, "gw_welcome"]], ["req_id string", ["1", 1, "gw_welcome"]],
		["req_id enorme", [Protocol.MAX_REQ_ID + 1, 1, "gw_welcome"]], ["op string", [1, "1", "gw_welcome"]],
		["quest_id vazio", [1, 1, ""]], ["quest_id maiusculo", [1, 1, "GW"]], ["quest_id longo", [1, 1, "a".repeat(200)]],
		["quest_id numero", [1, 1, 7]], ["quest_id null", [1, 1, null]], ["quest_id traversal", [1, 1, "../etc"]],
	]
	for c: Array in bad_cases:
		var a: Array = c[1]
		var r: Dictionary = Protocol.validate_quest_cmd(a[0], a[1], a[2])
		ctx.check(not bool(r["ok"]) and int(r["code"]) == Protocol.REJECT_INVALID_PAYLOAD, "quest_cmd invalido: " + String(c[0]))


func _test_dialogue_cmd(ctx: Object) -> void:
	var o: Dictionary = Protocol.validate_dialogue_cmd(1, Protocol.DIALOGUE_OP_OPEN, "npc_elder_orla", 0)
	ctx.check(bool(o["ok"]) and o["npc_id"] == "npc_elder_orla", "dialogue open valido")
	var ch: Dictionary = Protocol.validate_dialogue_cmd(2, Protocol.DIALOGUE_OP_CHOOSE, "", 3)
	ctx.check(bool(ch["ok"]) and ch["choice"] == 3, "dialogue choose valido")
	ctx.check(bool(Protocol.validate_dialogue_cmd(3, Protocol.DIALOGUE_OP_CLOSE, "", 0)["ok"]), "dialogue close valido")
	var bad_cases: Array = [
		["open sem npc", [1, 1, "", 0]], ["open npc invalido", [1, 1, "NPC X", 0]], ["open com choice", [1, 1, "npc_a", 2]],
		["choose com npc", [1, 2, "npc_a", 0]], ["choose negativo", [1, 2, "", -1]], ["choose enorme", [1, 2, "", 16]],
		["close com choice", [1, 3, "", 1]], ["close com npc", [1, 3, "npc_a", 0]], ["op 0", [1, 0, "", 0]], ["op 4", [1, 4, "", 0]],
		["tipos", ["1", 1, "npc_a", 0]], ["npc int", [1, 1, 5, 0]], ["choice float", [1, 2, "", 1.0]],
	]
	for c: Array in bad_cases:
		var a: Array = c[1]
		var r: Dictionary = Protocol.validate_dialogue_cmd(a[0], a[1], a[2], a[3])
		ctx.check(not bool(r["ok"]), "dialogue_cmd invalido: " + String(c[0]))


func _test_netrpc_surface(ctx: Object) -> void:
	var n: NetRpc = NetRpc.new()
	for sig: String in ["quest_cmd_received", "dialogue_cmd_received", "quest_update_received", "dialogue_received"]:
		ctx.check(n.has_signal(sig), "NetRpc tem sinal " + sig)
	for m: String in ["c_quest_cmd", "c_dialogue_cmd", "s_quest", "s_dialogue", "send_quest_cmd", "send_dialogue_cmd", "send_quest_update", "send_dialogue"]:
		ctx.check(n.has_method(m), "NetRpc tem metodo " + m)
	n.sim = NetSim.new()
	n.sim.configure(0, 0, 0.0, 1)
	n.send_quest_cmd(1, 1, "gw_welcome")
	n.send_dialogue_cmd(1, 1, "npc_elder_orla", 0)
	n.send_quest_update(2, 1, {})
	n.send_dialogue(2, 1, {})
	ctx.check(n.sim.pending() == 0, "envio sem conexao e ignorado (quest/dialogo)")
	n.free()
	ctx.check(Protocol.VERSION == 2, "VERSION continua 2 (extensao E5.1 e aditiva)")


func _test_client_log(ctx: Object) -> void:
	var log: ClientQuestLog = ClientQuestLog.new()
	var seen: Array[String] = []
	log.quest_accepted.connect(func(q: String) -> void: seen.append("acc:" + q))
	log.objective_progressed.connect(func(q: String, o: String, v: int, r: int) -> void: seen.append("prog:%s:%s:%d/%d" % [q, o, v, r]))
	log.quest_ready.connect(func(q: String) -> void: seen.append("ready:" + q))
	log.quest_completed.connect(func(q: String, xp: int, _items: Array) -> void: seen.append("done:%s:%d" % [q, xp]))
	log.quest_abandoned.connect(func(q: String) -> void: seen.append("ab:" + q))
	log.quest_error.connect(func(rid: int, op: int, q: String, code: String) -> void: seen.append("err:%d:%d:%s:%s" % [rid, op, q, code]))
	ctx.check(log.apply(Protocol.QUEST_SYNC, {"quests": {"active": {"gw_clear_clearing": {"objectives": {"kill_grunts": 5}}}, "completed": ["gw_welcome"]}, "statuses": {"gw_welcome": "completed", "gw_clear_clearing": "ready"}}), "sync aplicado")
	ctx.check(log.status_of("gw_welcome") == "completed" and log.status_of("gw_clear_clearing") == "ready" and log.ready.has("gw_clear_clearing"), "sync: concluida/pronta derivadas")
	log.apply(Protocol.QUEST_ACCEPTED, {"quest_id": "gw_scrap_for_orla"})
	log.apply(Protocol.QUEST_PROGRESS, {"quest_id": "gw_scrap_for_orla", "objective_id": "collect_scrap", "value": 3, "required": 6})
	log.apply(Protocol.QUEST_READY, {"quest_id": "gw_scrap_for_orla"})
	log.apply(Protocol.QUEST_COMPLETED, {"quest_id": "gw_scrap_for_orla", "xp": 120, "items": []})
	log.apply(Protocol.QUEST_ABANDONED, {"quest_id": "gw_clear_clearing"})
	log.apply(Protocol.QUEST_ERROR, {"req_id": 9, "op": 1, "quest_id": "gw_welcome", "code": "already_completed"})
	ctx.check(seen == ["acc:gw_scrap_for_orla", "prog:gw_scrap_for_orla:collect_scrap:3/6", "ready:gw_scrap_for_orla", "done:gw_scrap_for_orla:120", "ab:gw_clear_clearing", "err:9:1:gw_welcome:already_completed"], "sinais do log na ordem (%s)" % str(seen))
	ctx.check(log.status_of("gw_scrap_for_orla") == "completed" and not log.active.has("gw_clear_clearing"), "estado final do log")
	var before: int = log.updates_ignored
	ctx.check(not log.apply(Protocol.QUEST_ACCEPTED, {"quest_id": "Mau Id"}) and not log.apply(Protocol.QUEST_PROGRESS, {"quest_id": "gw_welcome"}) \
			and not log.apply(Protocol.QUEST_SYNC, {"quests": "lixo"}) and not log.apply(999, {}), "mensagens malformadas/desconhecidas ignoradas")
	ctx.check(log.updates_ignored == before + 4, "contador de ignoradas")


func _test_client_session(ctx: Object) -> void:
	var s: ClientSession = ClientSession.new()
	var sent: Array = []
	s.send_quest_cmd = func(r: int, op: int, q: String) -> void: sent.append(["q", r, op, q])
	s.send_dialogue_cmd = func(r: int, op: int, n: String, c: int) -> void: sent.append(["d", r, op, n, c])
	ctx.check(s.quest_accept("gw_welcome") == -1 and sent.is_empty(), "fora de PLAYING nada e enviado")
	s.begin(Protocol.VERSION, "t", "Ana", "")
	s.on_welcome(1, 30, 0)
	var r1: int = s.quest_accept("gw_welcome")
	var r2: int = s.quest_abandon("gw_welcome")
	var r3: int = s.quest_turn_in("gw_welcome")
	ctx.check(r1 > 0 and r2 == r1 + 1 and r3 == r2 + 1, "req_id crescente")
	s.dialogue_open("npc_elder_orla")
	s.dialogue_choose(1)
	s.dialogue_close()
	ctx.check(sent.size() == 6 and sent[0] == ["q", r1, 1, "gw_welcome"] and sent[1][2] == 2 and sent[2][2] == 3 and sent[3] == ["d", r3 + 1, 1, "npc_elder_orla", 0] and sent[4][2] == 2 and sent[4][4] == 1 and sent[5][2] == 3, "pedidos enviados com op/args corretos")
	ctx.check(s.quest_accept("ID RUIM") == -1 and s.dialogue_open("X") == -1 and s.dialogue_choose(99) == -1, "ids/indices locais invalidos nem saem do cliente")
	var views: Array = []
	s.dialogue_changed.connect(func(v: Dictionary) -> void: views.append(v))
	s.on_dialogue(Protocol.DIALOGUE_VIEW, {"text": "oi", "choices": [], "terminal": true})
	ctx.check(s.dialogue_view.get("text", "") == "oi" and views.size() == 1, "dialogo exibido")
	s.on_dialogue(Protocol.DIALOGUE_VIEW, {"text": 5})
	ctx.check(views.size() == 1, "view malformada ignorada")
	s.on_dialogue(Protocol.DIALOGUE_END, {"npc_id": "npc_elder_orla"})
	ctx.check(s.dialogue_view.is_empty() and views.size() == 2, "fim do dialogo limpa a view")
	s.on_quest_update(Protocol.QUEST_ACCEPTED, {"quest_id": "gw_welcome"})
	ctx.check(s.quest_log.active.has("gw_welcome"), "on_quest_update alimenta o diario")
	s.on_disconnected()
	s.on_quest_update(Protocol.QUEST_ABANDONED, {"quest_id": "gw_welcome"})
	ctx.check(s.quest_log.active.has("gw_welcome"), "fora de PLAYING as atualizacoes sao ignoradas")
