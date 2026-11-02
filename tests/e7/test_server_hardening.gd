extends RefCounted
## E7.1 - hardening do servidor sem infra externa: limite de conexoes por endereco (M7), chave por sessao e id de correlacao no
## BackendClient (M5), metricas operacionais (series, gauges, rejeicoes, desconexoes), ServerLog (niveis, JSON, mascara de PII),
## BuildInfo e arquivo de saude. Tudo com transporte falso/relogio injetado (sem rede real).

const H = preload("res://tests/e3/server_helpers.gd")
const B = preload("res://tests/e4/backend_helpers.gd")
const Fake = preload("res://tests/e4/fake_backend.gd")


func run(ctx: Object) -> void:
	var tree: SceneTree = ctx as SceneTree
	await tree.physics_frame
	_test_ip_limit(ctx, tree)
	_test_ip_rate(ctx, tree)
	_test_metrics_series(ctx)
	await _test_ops_metrics(ctx, tree)
	_test_server_log(ctx)
	_test_build_info(ctx)
	await _test_session_key_and_rid(ctx, tree)
	_test_health_file(ctx)
	await tree.physics_frame


# ------------------------------------------------------------------ M7

func _addr_rig(tree: SceneTree, addrs: Dictionary) -> H.Rig:
	var rig: H.Rig = H.make_rig(tree, false, 8)
	rig.settings.max_conns_per_ip = 3
	rig.settings.conn_burst = 50
	rig.settings.conn_rate_per_sec = 50.0
	rig.session.address_of = func(pid: int) -> String: return String(addrs.get(pid, ""))
	return rig


func _test_ip_limit(ctx: Object, tree: SceneTree) -> void:
	var addrs: Dictionary = {1: "203.0.113.5", 2: "203.0.113.5", 3: "203.0.113.5", 4: "203.0.113.5", 5: "198.51.100.9", 6: "", 7: "", 8: "", 9: "", 10: ""}
	var rig: H.Rig = _addr_rig(tree, addrs)
	for pid: int in [1, 2, 3]:
		rig.session.on_peer_connected(pid)
	ctx.check(rig.transport.disconnects.is_empty(), "M7: ate o limite (3) do mesmo endereco todas as conexoes sao aceitas")
	rig.session.on_peer_connected(4)
	ctx.check(rig.transport.disconnects.size() == 1 and rig.transport.disconnects[0] == 4, "M7: a 4a conexao do MESMO endereco e desconectada sem processar")
	ctx.check(rig.session.get_peer_state(4).closing and rig.session.metrics.get_count("rejects", "conn_limit") == 1, "M7: peer recusado fica 'closing' e conta em rejects.conn_limit")
	rig.session.on_hello(4, Protocol.VERSION, "t", "Intruso", "")
	ctx.check(rig.transport.welcomes.is_empty() and rig.session.world.player_count() == 0, "M7: hello do peer recusado e ignorado (sem welcome, sem jogador)")
	rig.session.on_peer_connected(5)
	ctx.check(rig.transport.disconnects.size() == 1, "M7: outro endereco nao e afetado")
	for pid: int in [6, 7, 8, 9, 10]:
		rig.session.on_peer_connected(pid)
	ctx.check(rig.transport.disconnects.size() == 1, "M7: endereco desconhecido ('') nunca e limitado (testes/modo local)")
	# libera uma vaga do endereco: o recusado (4) ao sair NAO decrementa; um aceito ao sair libera
	rig.session.on_peer_disconnected(4)
	addrs[11] = "203.0.113.5"
	rig.session.on_peer_connected(11)
	ctx.check(rig.session.get_peer_state(11).closing, "M7: sair o peer RECUSADO nao libera vaga (contador correto)")
	rig.session.on_peer_disconnected(11)
	rig.session.on_peer_disconnected(1)
	addrs[12] = "203.0.113.5"
	rig.session.on_peer_connected(12)
	ctx.check(not rig.session.get_peer_state(12).closing, "M7: ao sair um peer aceito a vaga do endereco volta")
	# hello normal segue funcionando para peers aceitos
	rig.session.on_hello(2, Protocol.VERSION, "t", "Aceito", "")
	ctx.check(rig.transport.welcomes.size() == 1, "M7: peer aceito faz hello/welcome normalmente")
	# endereco nunca vai para o log
	ctx.check(not ServerLog.joined().contains("203.0.113.5"), "M7: o endereco remoto nao aparece no log")
	rig.world.queue_free()
	rig.session.queue_free()


func _test_ip_rate(ctx: Object, tree: SceneTree) -> void:
	var rig: H.Rig = H.make_rig(tree, false, 8)
	rig.settings.max_conns_per_ip = 10
	rig.settings.conn_burst = 3
	rig.settings.conn_rate_per_sec = 0.0 # sem reposicao: o balde so esvazia
	rig.session.address_of = func(_pid: int) -> String: return "192.0.2.77"
	for pid: int in [1, 2, 3]:
		rig.session.on_peer_connected(pid)
		rig.session.on_peer_disconnected(pid) # abre e fecha em loop (ocupa nada, mas gasta o balde)
	rig.session.on_peer_connected(4)
	ctx.check(rig.session.get_peer_state(4).closing and rig.transport.disconnects.has(4), "M7: reconexoes em loop do mesmo endereco esgotam o balde (backoff) mesmo sem conexoes abertas")
	rig.world.queue_free()
	rig.session.queue_free()


# ------------------------------------------------------------------ metricas operacionais

func _test_metrics_series(ctx: Object) -> void:
	var m: ServerMetrics = ServerMetrics.new(60.0, 0)
	for i: int in 100:
		m.observe("tick_ms", float(i + 1)) # 1..100
	var st: Dictionary = m.series_stats("tick_ms")
	ctx.check(int(st["count"]) == 100 and float(st["p50"]) == 51.0 and float(st["p95"]) == 96.0 and float(st["max"]) == 100.0, "series: p50/p95/max por posto (%s)" % str(st))
	m.observe("tick_ms", NAN)
	m.observe("tick_ms", -1.0)
	m.observe("tick_ms", INF)
	m.observe("serie_inexistente", 5.0)
	ctx.check(int(m.series_stats("tick_ms")["count"]) == 100 and int(m.series_stats("serie_inexistente")["count"]) == 0, "series: NaN/negativo/inf/nome desconhecido ignorados")
	for i: int in ServerMetrics.SERIES_MAX + 50:
		m.observe("snapshot_bytes", float(i))
	var sb: Dictionary = m.series_stats("snapshot_bytes")
	ctx.check(int(sb["count"]) == ServerMetrics.SERIES_MAX and float(sb["max"]) == float(ServerMetrics.SERIES_MAX + 49), "series: janela deslizante limitada a SERIES_MAX (memoria constante)")
	var snap: Dictionary = m.snapshot(1000)
	ctx.check(snap.has("timings") and snap.has("gauges") and snap.has("counters") and snap.has("uptime_s") and snap.has("dropped_keys"), "snapshot: formato E6.5 preservado + timings + gauges")
	var parsed: Variant = JSON.parse_string(m.line(1000).trim_prefix("[metrics] "))
	ctx.check(typeof(parsed) == TYPE_DICTIONARY and (parsed as Dictionary).has("timings"), "linha [metrics] continua JSON valido")


func _test_ops_metrics(ctx: Object, tree: SceneTree) -> void:
	var rig: H.Rig = H.make_rig(tree, false, 4)
	var m: ServerMetrics = rig.session.metrics
	var eid: int = H.join(rig, 1, "Aria")
	H.join(rig, 2, "Bruno")
	var g: Dictionary = m.snapshot(2000)["gauges"]
	ctx.check(eid != 0 and int(g["players_online"]) == 2 and int(g["peers"]) == 2 and int(g["pending"]) == 0, "gauges: jogadores online/peers/pendentes (%s)" % str(g))
	# rejeicao por codigo
	rig.session.on_peer_connected(3)
	rig.session.on_hello(3, 999, "t", "Velho", "") # versao errada
	ctx.check(m.total("rejects") == 1, "rejects contados por codigo de protocolo")
	var names: Array = (m.snapshot(2000)["counters"] as Dictionary).get("rejects", {}).keys()
	ctx.check(names.size() == 1 and String(names[0]).begins_with("code_"), "nome da rejeicao = code_N (sem dado livre)")
	rig.session.on_peer_disconnected(2)
	ctx.check(m.get_count("disconnects", "player") == 1 and int(m.snapshot(2000)["gauges"]["players_online"]) == 1, "desconexao de jogador conta e atualiza o gauge")
	# tick e snapshot alimentam as series (via _physics_process real e snapshots)
	rig.session.set_physics_process(true)
	for i: int in 30:
		await tree.physics_frame
	rig.session.set_physics_process(false)
	var tm: Dictionary = m.snapshot(3000)["timings"]
	ctx.check(int((tm["tick_ms"] as Dictionary)["count"]) >= 20 and int((tm["tick_dt_ms"] as Dictionary)["count"]) >= 19, "tick_ms/tick_dt_ms alimentados a cada tick fisico")
	ctx.check(float((tm["tick_ms"] as Dictionary)["p95"]) < 50.0, "tick_ms p95 plausivel (%s ms) na arena vazia" % str((tm["tick_ms"] as Dictionary)["p95"]))
	# nada de dado pessoal no que sai no log
	var line: String = m.line(3000)
	ctx.check(not line.contains("Aria") and not line.contains("Bruno"), "linha [metrics] nao carrega nomes de jogadores")
	rig.world.queue_free()
	rig.session.queue_free()


# ------------------------------------------------------------------ ServerLog

func _test_server_log(ctx: Object) -> void:
	var prev_level: int = ServerLog.min_level
	var prev_json: bool = ServerLog.json_mode
	var prev_cap: bool = ServerLog.capturing
	ServerLog.capturing = true
	ServerLog.reset_capture()
	ServerLog.min_level = ServerLog.Level.WARN
	ServerLog.info("linha info filtrada")
	ServerLog.debug("linha debug filtrada")
	ServerLog.warn("aviso visivel")
	ServerLog.error("erro visivel")
	ctx.check(ServerLog.captured.size() == 2 and ServerLog.captured[0] == "[warn] aviso visivel" and ServerLog.captured[1] == "erro visivel", "niveis: min_level=WARN filtra info/debug; texto preserva o prefixo [warn]")
	ctx.check(ServerLog.parse_level("WARN") == ServerLog.Level.WARN and ServerLog.parse_level("tudo") == -1, "parse_level aceita nomes e recusa invalido")
	ServerLog.min_level = ServerLog.Level.INFO
	ServerLog.reset_capture()
	ServerLog.json_mode = true
	ServerLog.info("peer 3 entrou")
	ServerLog.warn("algo estranho")
	var j0: Variant = JSON.parse_string(ServerLog.captured[0])
	var j1: Variant = JSON.parse_string(ServerLog.captured[1])
	ctx.check(typeof(j0) == TYPE_DICTIONARY and (j0 as Dictionary).has("t") and (j0 as Dictionary)["level"] == "info" and (j0 as Dictionary)["msg"] == "peer 3 entrou", "JSON: {t, level, msg} por linha")
	ctx.check(typeof(j1) == TYPE_DICTIONARY and (j1 as Dictionary)["level"] == "warn" and (j1 as Dictionary)["msg"] == "algo estranho", "JSON: warn sem prefixo textual")
	ServerLog.reset_capture()
	ServerLog.add_secret("chave-secreta-xyz-123")
	ServerLog.info("login de pessoa.real@example.com com chave-secreta-xyz-123 e token eyJhbGciOiJIUzI1NiJ9.AAAAAAAAAA.BBBBBBBBBB fim")
	var all: String = ServerLog.joined()
	ctx.check(not all.contains("pessoa.real@example.com") and not all.contains("chave-secreta-xyz-123") and not all.contains("eyJhbGci"), "scrub: e-mail completo, segredo registrado e JWT nunca saem")
	ctx.check(all.contains("[email]") and all.contains("[redacted]"), "scrub: marcadores de mascara presentes")
	ServerLog.json_mode = prev_json
	ServerLog.min_level = prev_level
	ServerLog.clear_secrets()
	ServerLog.reset_capture()
	ServerLog.capturing = prev_cap


# ------------------------------------------------------------------ BuildInfo

func _test_build_info(ctx: Object) -> void:
	BuildInfo.reset_cache_for_tests()
	ctx.check(BuildInfo.sanitize_id("a1b2c3d") == "a1b2c3d" and BuildInfo.sanitize_id("") == "dev" and BuildInfo.sanitize_id("x y/z;") == "x_y_z_", "BuildInfo.sanitize_id: so [A-Za-z0-9._-]")
	ctx.check(BuildInfo.sanitize_id("0123456789012345678901234567890123456789").length() == BuildInfo.MAX_BUILD_ID_LEN, "BuildInfo.sanitize_id: trunca")
	var info: Dictionary = BuildInfo.info()
	ctx.check(info["version"] == BuildInfo.GAME_VERSION and int(info["protocol"]) == Protocol.VERSION and not String(info["godot"]).is_empty(), "BuildInfo.info: versao do jogo, protocolo e Godot")
	ctx.check(BuildInfo.hello_build().length() <= Protocol.MAX_BUILD_LEN, "hello_build cabe em Protocol.MAX_BUILD_LEN")
	var v: Dictionary = Protocol.validate_hello(Protocol.VERSION, BuildInfo.hello_build(), "Aria", "")
	ctx.check(bool(v["ok"]), "o build embutido passa em Protocol.validate_hello")
	ctx.check(BuildInfo.display().begins_with("v%s (" % BuildInfo.GAME_VERSION), "display: 'v<versao> (<build>)' para a UI e relatos de bug")


# ------------------------------------------------------------------ M5 no BackendClient

func _test_session_key_and_rid(ctx: Object, tree: SceneTree) -> void:
	var rig: B.BRig = B.make(tree)
	var fake: Fake = rig.fake
	var client: BackendClient = rig.client
	await tree.physics_frame
	ctx.check(client.fencing_session_key == Fake.SESSION_KEY, "M5: BackendSync guarda a session_key devolvida no registro")
	var reg: Dictionary = fake.requests[0]
	ctx.check(String(reg["path"]) == "/internal/sessions" and String(reg["key_header"]).is_empty(), "M5: o registro NAO envia X-Session-Key (ainda nao existe)")
	fake.requests.clear()
	var res: Array = []
	client.heartbeat(Fake.SESSION_ID, func(r: Dictionary) -> void: res.append(r))
	client.redeem(B.TICKET1, Fake.SESSION_ID, func(r: Dictionary) -> void: res.append(r))
	client.checkpoint(B.CID1, 0, {"level": 1, "xp": 0, "stats": {}, "inventory": [], "equipment": {}}, func(r: Dictionary) -> void: res.append(r))
	client.release_character(B.CID1, Fake.SESSION_ID, func(r: Dictionary) -> void: res.append(r))
	var all_keyed: bool = fake.requests.size() == 4
	for q: Dictionary in fake.requests:
		all_keyed = all_keyed and String(q["key_header"]) == Fake.SESSION_KEY
	ctx.check(all_keyed, "M5: heartbeat, redeem, checkpoint e release enviam X-Session-Key")
	# id de correlacao: formato aceito pelo backend, unico por chamada, estavel nos retries, devolvido no resultado
	var rids: Dictionary = {}
	var fmt_ok: bool = true
	var re: RegEx = RegEx.new()
	re.compile("^[A-Za-z0-9_-]{8,64}$")
	for q: Dictionary in fake.requests:
		rids[String(q["rid_header"])] = true
		fmt_ok = fmt_ok and re.search(String(q["rid_header"])) != null
	ctx.check(fmt_ok and rids.size() == 4, "request id: formato [A-Za-z0-9_-]{8,64}, um por chamada")
	ctx.check(res.size() == 4 and not String(res[0].get("request_id", "")).is_empty() and String(res[0]["request_id"]) == String(fake.requests[0]["rid_header"]), "request id: devolvido no resultado para correlacionar com o log do backend")
	fake.requests.clear()
	fake.force("/heartbeat", [Fake.NET_ERR])
	client.heartbeat(Fake.SESSION_ID, func(_r: Dictionary) -> void: pass)
	await tree.create_timer(0.2).timeout
	ctx.check(fake.requests.size() == 2 and String(fake.requests[0]["rid_header"]) == String(fake.requests[1]["rid_header"]), "request id: o retry da MESMA chamada reusa o id")
	# a chave nunca vai ao log; limpeza ao perder a sessao
	ServerLog.capturing = true
	ServerLog.reset_capture()
	ServerLog.info("teste " + Fake.SESSION_KEY)
	ctx.check(not ServerLog.joined().contains(Fake.SESSION_KEY), "M5: a session_key e registrada como segredo no ServerLog")
	ServerLog.capturing = false
	ServerLog.clear_secrets()
	rig.free_all()


# ------------------------------------------------------------------ saude

func _test_health_file(ctx: Object) -> void:
	var sm: ServerMain = ServerMain.new()
	sm._health_file = "user://e7_health_test.json"
	sm._write_health("ready")
	var txt: String = FileAccess.get_file_as_string("user://e7_health_test.json")
	var d: Variant = JSON.parse_string(txt)
	ctx.check(typeof(d) == TYPE_DICTIONARY and (d as Dictionary)["status"] == "ready" and (d as Dictionary)["backend"] == "dev", "health-file: JSON com status/backend gravado")
	var keys: Array = (d as Dictionary).keys()
	keys.sort()
	ctx.check(keys == ["backend", "build", "players_online", "protocol", "status", "tick", "ts", "uptime_s"], "health-file: so campos operacionais (%s)" % str(keys))
	ctx.check(not FileAccess.file_exists("user://e7_health_test.json.tmp"), "health-file: gravacao atomica (sem .tmp residual)")
	sm._health_file = ""
	sm.free()
