extends RefCounted
## BackendFlow (login/registro, personagem, sessao, ticket) e LoginScreen, tudo com transporte falso.

const TICKET: String = "aaa.bbb.TICKET_SECRET_ccc"
const PW: String = "senha-super-secreta-123"


func _login_ok() -> Dictionary:
	return {"status": 200, "body": {"access_token": "ACC", "token_type": "Bearer", "expires_in": 900, "refresh_token": "REF", "refresh_expires_in": 9}}


func _session(id: String, free: int, ver: int = 2, ep: String = "127.0.0.1:24680") -> Dictionary:
	return {"id": id, "region": "local", "capacity": 4, "free_slots": free, "protocol_version": ver, "endpoint": ep}


func _setup(ft: FakeTransport) -> BackendApi:
	var api: BackendApi = BackendApi.new()
	api.transport = ft.handle
	api.set_base_url("http://127.0.0.1:8787")
	return api


func run(ctx: Object) -> void:
	# ---- funcoes puras
	ctx.check(BackendFlow.parse_endpoint("127.0.0.1:24680") == {"host": "127.0.0.1", "port": 24680}, "flow: endpoint host:porta")
	ctx.check(BackendFlow.parse_endpoint("game.exemplo.com:1").get("port") == 1, "flow: endpoint dns")
	for bad: String in ["", "x", "x:", ":80", "h:0", "h:70000", "h:abc", "a b:80", "h/x:80"]:
		ctx.check(BackendFlow.parse_endpoint(bad).is_empty(), "flow: endpoint invalido '%s'" % bad)
	var list: Array = [_session("a", 1), _session("b", 3), _session("c", 4, 99), _session("d", 0), _session("e", 2, Protocol.VERSION, "lixo")]
	list[0]["protocol_version"] = Protocol.VERSION
	list[1]["protocol_version"] = Protocol.VERSION
	list[3]["protocol_version"] = Protocol.VERSION
	ctx.check(BackendFlow.pick_session(list, "", Protocol.VERSION).get("id") == "b", "flow: escolhe a sessao compativel com mais vagas")
	ctx.check(BackendFlow.pick_session(list, "a", Protocol.VERSION).get("id") == "a", "flow: respeita session-id pedido")
	ctx.check(BackendFlow.pick_session(list, "c", Protocol.VERSION).is_empty() and BackendFlow.pick_session(list, "d", Protocol.VERSION).is_empty(), "flow: pedida incompativel/cheia -> nenhuma")
	ctx.check(BackendFlow.pick_session(list, "zzz", Protocol.VERSION).is_empty() and BackendFlow.pick_session([], "", 2).is_empty() and BackendFlow.pick_session("x", "", 2).is_empty(), "flow: pedida inexistente/lista vazia/lixo")
	ctx.check(BackendFlow.find_character([{"name": "Ana"}, {"name": "Bia"}], "bia").get("name") == "Bia" and BackendFlow.find_character([], "x").is_empty(), "flow: find_character ignora caixa")

	# ---- login com registro automatico
	var ft: FakeTransport = FakeTransport.new()
	var api: BackendApi = _setup(ft)
	var flow: BackendFlow = BackendFlow.new(api)
	ft.on("POST /v1/auth/login", [FakeTransport.err(401, "invalid_credentials"), _login_ok()])
	ft.on("POST /v1/auth/register", [{"status": 202, "body": {"status": "accepted"}}])
	ctx.check(await flow.login("a@b.com", PW, true), "flow: login falha -> registra -> loga")
	ctx.check(ft.count("POST /v1/auth/register") == 1 and ft.count("POST /v1/auth/login") == 2, "flow: 1 registro + 2 logins")
	var api_b: BackendApi = _setup(ft)
	var flow_b: BackendFlow = BackendFlow.new(api_b)
	ft.on("POST /v1/auth/login", [FakeTransport.err(401, "invalid_credentials")])
	var rc: int = ft.count("POST /v1/auth/register")
	ctx.check(not await flow_b.login("a@b.com", PW, false) and ft.count("POST /v1/auth/register") == rc, "flow: sem auto-registro nao registra")
	ctx.check(flow_b.last_error == "E-mail ou senha incorretos." and not flow_b.last_error.contains(PW), "flow: erro amigavel, sem senha")
	ft.on("POST /v1/auth/login", [FakeTransport.err(429, "rate_limited")])
	ctx.check(not await flow_b.login("a@b.com", PW, true) and flow_b.last_error_code == "rate_limited", "flow: 429 nao tenta registrar")

	# ---- personagem
	ft.on("GET /v1/characters", [{"status": 200, "body": {"characters": [{"id": "c1", "name": "Ana"}]}}])
	ctx.check((await flow.ensure_character("ana", false)).get("id") == "c1", "flow: acha personagem existente")
	ctx.check((await flow.ensure_character("Zed", false)).is_empty() and flow.last_error_code == "not_found", "flow: ausente sem criar -> erro")
	ft.on("POST /v1/characters", [{"status": 201, "body": {"character": {"id": "c2", "name": "Zed"}}}])
	ctx.check((await flow.ensure_character("Zed", true)).get("id") == "c2", "flow: cria personagem ausente")
	ft.on("POST /v1/characters", [FakeTransport.err(409, "name_taken")])
	ctx.check((await flow.ensure_character("Zed", true)).is_empty() and flow.last_error == "Esse nome de personagem ja existe.", "flow: name_taken -> mensagem amigavel")

	# ---- sessao + ticket
	ft.on("GET /v1/sessions", [{"status": 200, "body": {"sessions": [_session("s1", 3, Protocol.VERSION, "10.0.0.5:24999")]}}])
	var sess: Dictionary = await flow.choose_session("")
	ctx.check(sess.get("id") == "s1", "flow: choose_session")
	ft.on("POST /v1/sessions/s1/join-ticket", [{"status": 201, "body": {"ticket": TICKET, "expires_at": "x", "session": {"endpoint": "10.0.0.5:24999"}}}])
	var conn: Dictionary = await flow.request_ticket(sess, "c1")
	ctx.check(conn.get("ticket") == TICKET and conn.get("host") == "10.0.0.5" and conn.get("port") == 24999 and conn.get("session_id") == "s1", "flow: ticket + endpoint")
	ft.on("GET /v1/sessions", [{"status": 200, "body": {"sessions": []}}])
	ctx.check((await flow.choose_session("")).is_empty() and flow.last_error_code == "no_session", "flow: nenhuma sessao -> erro claro")
	ft.on("POST /v1/sessions/s1/join-ticket", [FakeTransport.err(409, "character_locked")])
	ctx.check((await flow.request_ticket(sess, "c1")).is_empty() and flow.last_error == "Esse personagem ja esta em jogo.", "flow: character_locked amigavel")
	ft.on("POST /v1/sessions/s1/join-ticket", [{"status": 201, "body": {"expires_at": "x"}}])
	ctx.check((await flow.request_ticket(sess, "c1")).is_empty() and flow.last_error_code == "bad_response", "flow: resposta sem ticket = erro")
	ft.on("GET /v1/sessions", [{"status": 200, "body": {"sessions": [_session("s1", 3, Protocol.VERSION, "10.0.0.5:24999")]}}])
	ft.on("POST /v1/sessions/s1/join-ticket", [{"status": 201, "body": {"ticket": TICKET, "session": {"endpoint": "10.0.0.5:24999"}}}])

	# ---- fluxo completo
	ft.on("POST /v1/auth/login", [_login_ok()])
	ft.on("GET /v1/characters", [{"status": 200, "body": {"characters": [{"id": "c1", "name": "Ana"}]}}])
	var full: Dictionary = await flow.run_full("a@b.com", PW, "Ana", "", true, true)
	ctx.check(full["ok"] and full["login_ok"] and full["character_id"] == "c1" and full["session_id"] == "s1" and full["conn"]["ticket"] == TICKET, "flow: run_full ok")
	ft.on("GET /v1/sessions", [{"status": 200, "body": {"sessions": []}}])
	var full2: Dictionary = await flow.run_full("a@b.com", PW, "Ana", "", true, true)
	ctx.check(not full2["ok"] and full2["login_ok"] and full2["character_id"] == "c1" and full2["conn"].is_empty(), "flow: run_full parcial preserva login_ok/character_id")
	ctx.check(not (flow.last_error + flow.last_error_code).contains(PW) and not (flow.last_error + flow.last_error_code).contains(TICKET), "flow: erros sem senha/ticket")

	# ---- tela de login (instanciacao + logica)
	ft.on("GET /v1/sessions", [{"status": 200, "body": {"sessions": [_session("s1", 3, Protocol.VERSION, "10.0.0.5:24999")]}}])
	ft.on("GET /v1/characters", [{"status": 200, "body": {"characters": [{"id": "c1", "name": "Ana", "level": 3}]}}])
	var scene: PackedScene = load("res://scenes/client/login.tscn") as PackedScene
	ctx.check(scene != null, "login: cena carrega")
	var screen: LoginScreen = scene.instantiate() as LoginScreen
	ctx.check(screen != null, "login: instancia LoginScreen")
	var api_c: BackendApi = _setup(ft)
	screen.setup(api_c, "")
	(ctx as SceneTree).root.add_child(screen)  # _ready monta a UI
	var plays: Array = []
	screen.play_requested.connect(func(c: Dictionary) -> void: plays.append(c))
	ctx.check(not await screen.do_play(), "login: Jogar sem login nao faz nada")
	ft.on("POST /v1/auth/login", [FakeTransport.err(401, "invalid_credentials")])
	ctx.check(not await screen.do_login("a@b.com", PW) and screen.status_text == "E-mail ou senha incorretos." and not screen.busy, "login: credenciais erradas -> mensagem")
	ctx.check(not await screen.do_login("", ""), "login: campos vazios")
	ft.on("POST /v1/auth/login", [_login_ok()])
	ctx.check(await screen.do_login("a@b.com", PW) and screen.characters.size() == 1 and screen.selected == 0, "login: entrou e listou personagens")
	ft.on("POST /v1/characters", [{"status": 201, "body": {"character": {"id": "c2", "name": "Bia"}}}])
	ft.on("GET /v1/characters", [{"status": 200, "body": {"characters": [{"id": "c1", "name": "Ana"}, {"id": "c2", "name": "Bia"}]}}])
	ctx.check(await screen.do_create("Bia") and screen.characters.size() == 2 and screen.selected == 1, "login: criou personagem e o selecionou")
	ctx.check(await screen.do_play() and plays.size() == 1, "login: Jogar emite play_requested")
	ctx.check(plays[0]["ticket"] == TICKET and plays[0]["character_id"] == "c2" and plays[0]["host"] == "10.0.0.5" and plays[0]["port"] == 24999, "login: conn com ticket/endpoint/personagem")
	ctx.check(not screen.status_text.contains(TICKET) and not screen.status_text.contains(PW), "login: status sem ticket/senha")
	screen.queue_free()
	api_c.free()
	api.free()
	api_b.free()
