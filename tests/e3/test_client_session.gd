extends RefCounted
## ClientSession (sem rede real): hello/welcome/reject, seq crescente, eventos, RTT, snapshots.


func _ent(id: int, kind: int, pos: Vector3) -> Dictionary:
	return {"id": id, "kind": kind, "pos": pos, "yaw": 0.0, "hp": 10.0, "max_hp": 10.0, "state": 0, "type": "x"}


func run(ctx: Object) -> void:
	var sent_hello: Array = []
	var sent_inputs: Array = []
	var sent_pings: Array = []
	var ss: ClientSession = ClientSession.new()
	ss.send_hello = func(v: int, b: String, n: String) -> void: sent_hello.append([v, b, n])
	ss.send_input = func(seq: int, m: Vector2, y: float, a: int, ct: int) -> void: sent_inputs.append([seq, m, y, a, ct])
	ss.send_ping = func(t: int) -> void: sent_pings.append(t)

	# fora de PLAYING nada e enviado / welcome sem hello e ignorado
	ctx.check(ss.send_move(Vector2(0, 1), 0.0, 0) == -1 and sent_inputs.is_empty(), "sess: sem welcome nao envia input")
	ss.on_welcome(7, 30, 1)
	ctx.check(ss.state == ClientSession.State.IDLE, "sess: welcome sem hello ignorado")

	ss.begin(Protocol.VERSION, "dev", "Tester")
	ctx.check(sent_hello.size() == 1 and sent_hello[0][0] == Protocol.VERSION and sent_hello[0][2] == "Tester", "sess: hello enviado com versao do Protocol")
	ss.on_snapshot(1, 0, [_ent(7, 1, Vector3.ZERO)], 0.0)
	ctx.check(ss.result.snapshots_received == 0, "sess: snapshot antes do welcome ignorado")
	ss.on_welcome(7, 30, 99)
	ctx.check(ss.state == ClientSession.State.PLAYING and ss.player_id == 7 and ss.result.welcome["tick_rate"] == 30, "sess: welcome -> PLAYING")
	ss.on_welcome(8, 60, 1)
	ctx.check(ss.player_id == 7, "sess: segundo welcome ignorado")

	# seq crescente
	var seqs: Array = []
	for i: int in 5:
		seqs.append(ss.send_move(Vector2(0, 1), 0.5, 1))
	var inc: bool = true
	for i: int in range(1, seqs.size()):
		inc = inc and int(seqs[i]) > int(seqs[i - 1])
	ctx.check(inc and seqs[0] == 1 and sent_inputs.size() == 5, "sess: seq crescente a partir de 1")
	ctx.check(int(sent_inputs[4][4]) > int(sent_inputs[0][4]), "sess: client_tick crescente")

	# snapshot: filtra entidade invalida e reconcilia com o jogador local
	var bad: Dictionary = {"id": 3, "kind": 9, "pos": Vector3.ZERO}
	ss.on_snapshot(5, 2, [_ent(7, 1, Vector3(0, 0, -0.4)), _ent(20, 2, Vector3(3, 0, 3)), bad, "lixo"], 100.0)
	ctx.check(ss.entity_count == 2 and ss.entities_rejected == 2, "sess: entidades invalidas descartadas")
	ctx.check(ss.prediction.initialized, "sess: predicao inicializada no primeiro snapshot")
	ss.on_snapshot(5, 2, [_ent(7, 1, Vector3.ZERO)], 110.0)
	ctx.check(ss.result.snapshots_received == 1, "sess: tick repetido descartado")
	ss.on_snapshot(6, 3, [_ent(7, 1, Vector3(0, 0, -0.6))], 200.0)
	ctx.check(ss.result.last_server_tick == 6 and absf(ss.result.max_snapshot_gap_ms - 100.0) < 0.01, "sess: gap maximo medido (100 ms)")
	ctx.check(ss.last_input_seq_ack == 3, "sess: last_input_seq registrado")

	# eventos: dedupe por id
	ss.on_event(1, Protocol.EVENT_DAMAGE, {"target_id": 20, "amount": 5.0})
	ss.on_event(1, Protocol.EVENT_DAMAGE, {"target_id": 20, "amount": 5.0})
	ss.on_event(0, Protocol.EVENT_DEATH, {})
	ss.on_event(2, Protocol.EVENT_DEATH, {"id": 20})
	var evs: Array[Dictionary] = ss.drain_events()
	ctx.check(evs.size() == 2 and ss.events_dropped == 2, "sess: eventos repetidos/velhos ignorados")
	ctx.check(ss.drain_events().is_empty(), "sess: drain esvazia")
	ctx.check(int(ss.result.events_by_kind["3"]) == 1 and int(ss.result.events_by_kind["4"]) == 1, "sess: contagem por kind")

	# ping/pong
	ss.ping(1000.0)
	ctx.check(sent_pings == [1000], "sess: ping enviado com client_time")
	ss.on_pong(1000, 1042.0)
	ss.on_pong(1000, 1058.0)
	ss.on_pong(5000, 1058.0)  # eco do futuro: ignorado
	ctx.check(absf(ss.result.rtt_avg_ms() - 50.0) < 0.01 and ss.last_rtt_ms == 58.0, "sess: RTT medio 50 ms")

	# desconexao apos jogar
	ss.on_disconnected()
	ctx.check(ss.state == ClientSession.State.DISCONNECTED and ss.result.disconnected, "sess: desconexao registrada")
	ctx.check(ss.send_move(Vector2.ZERO, 0.0, 0) == -1, "sess: sem envio apos desconectar")

	# reject (versao incompativel): mensagem clara, sem crash
	var rj: ClientSession = ClientSession.new()
	rj.send_hello = func(_v: int, _b: String, _n: String) -> void: pass
	rj.begin(Protocol.VERSION + 99, "dev", "Bad")
	rj.on_reject(Protocol.REJECT_VERSION, "esperado 1")
	ctx.check(rj.state == ClientSession.State.REJECTED and rj.message.contains("Versao incompativel"), "sess: reject(1) -> mensagem clara")
	ctx.check(int(rj.result.rejected["code"]) == 1, "sess: reject registrado no resultado")
	rj.on_disconnected()
	ctx.check(rj.state == ClientSession.State.REJECTED and rj.message.contains("Versao"), "sess: desconexao pos-reject preserva mensagem")
	rj.on_welcome(1, 30, 0)
	ctx.check(rj.state == ClientSession.State.REJECTED, "sess: welcome apos reject ignorado")
	for code: int in [2, 3, 4, 5, 77]:
		ctx.check(not ClientSession.reject_text(code, "").is_empty(), "sess: texto para reject %d" % code)

	# falha de conexao (nunca teve welcome)
	var cf: ClientSession = ClientSession.new()
	cf.on_disconnected()
	ctx.check(cf.message.contains("Falha ao conectar"), "sess: falha de conexao compreensivel")

	# bot: itens invalidos usam seq e seq_repeat reenvia o ultimo
	var out2: Array = []
	var bs: ClientSession = ClientSession.new()
	bs.send_hello = func(_v: int, _b: String, _n: String) -> void: pass
	bs.send_input = func(seq: int, _m: Vector2, _y: float, a: int, _c: int) -> void: out2.append([seq, a])
	bs.begin(1, "d", "b")
	bs.on_welcome(1, 30, 0)
	var items: Array[Dictionary] = [
		{"move": Vector2(0, 1), "yaw": 0.0, "actions": 0},
		{"move": Vector2(0, 1), "yaw": 0.0, "actions": 0, "seq_repeat": true},
		{"move": Vector2(NAN, 0), "yaw": 0.0, "actions": 0xF0},
	]
	bs.send_bot_items(items)
	ctx.check(out2[0][0] == 1 and out2[1][0] == 1 and out2[2][0] == 2 and out2[2][1] == 0xF0, "sess: bot seq_repeat e invalido")
	ctx.check(bs.prediction.pending_count() <= 1, "sess: inputs invalidos nao entram na predicao")
