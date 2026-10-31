extends RefCounted
## BackendApi com transporte falso: HTTPS, login, renovacao no 401, erros, nenhum segredo vazando.

const PW: String = "senha-super-secreta-123"
const ACCESS1: String = "ACCESS_TOKEN_ONE_xyz"
const ACCESS2: String = "ACCESS_TOKEN_TWO_xyz"
const REFRESH1: String = "REFRESH_TOKEN_ONE_xyz"
const REFRESH2: String = "REFRESH_TOKEN_TWO_xyz"
const TICKET: String = "aaa.bbb.TICKET_SECRET_ccc"


func _login_body(a: String, r: String) -> Dictionary:
	return {"status": 200, "body": {"access_token": a, "token_type": "Bearer", "expires_in": 900, "refresh_token": r, "refresh_expires_in": 100}}


func _api(ft: FakeTransport) -> BackendApi:
	var api: BackendApi = BackendApi.new()
	api.transport = ft.handle
	api.set_base_url("http://127.0.0.1:8787")
	return api


func run(ctx: Object) -> void:
	var api0: BackendApi = BackendApi.new()
	ctx.check(api0.set_base_url("https://api.exemplo.com/") == "" and api0.base_url == "https://api.exemplo.com", "api: https aceito e barra final removida")
	ctx.check(api0.set_base_url("http://localhost:8787") == "" and api0.set_base_url("http://127.0.0.1:1") == "" and api0.set_base_url("http://[::1]:8787") == "", "api: http aceito em localhost/127.0.0.1/::1")
	ctx.check(api0.set_base_url("http://api.exemplo.com") != "" and api0.set_base_url("http://localhost.evil.com") != "", "api: http fora de localhost recusado")
	ctx.check(api0.set_base_url("ftp://x") != "" and api0.set_base_url("https://u:p@host") != "" and api0.set_base_url("host") != "", "api: esquema invalido / credenciais na URL recusados")
	api0.free()

	var ft: FakeTransport = FakeTransport.new()
	var api: BackendApi = _api(ft)
	var everything: Array = []  # tudo que o chamador ve; verificado contra segredos no fim

	# autenticada sem login: nao chama a rede
	var r0: Dictionary = await api.list_characters()
	everything.append(r0)
	ctx.check(not r0["ok"] and r0["code"] == "not_logged_in" and ft.requests.is_empty(), "api: sem login nao faz requisicao")

	# registro e login
	ft.on("POST /v1/auth/register", [{"status": 202, "body": {"status": "accepted"}}])
	var rr: Dictionary = await api.register("a@b.com", PW)
	ctx.check(rr["ok"] and rr["status"] == 202 and not api.is_logged_in(), "api: register 202 sem tokens")
	ft.on("POST /v1/auth/login", [_login_body(ACCESS1, REFRESH1)])
	var lr: Dictionary = await api.login("a@b.com", PW)
	everything.append(lr)
	ctx.check(lr["ok"] and api.is_logged_in() and api.has_refresh_token(), "api: login guarda tokens em memoria")
	ctx.check(not JSON.stringify(lr).contains(ACCESS1) and not JSON.stringify(lr).contains(REFRESH1), "api: resultado do login nao expoe tokens")
	ctx.check(not str(api).contains(ACCESS1) and not str(api).contains(REFRESH1), "api: to_string sem tokens")

	# chamada autenticada leva o Bearer
	ft.on("GET /v1/characters", [{"status": 200, "body": {"characters": [{"id": "c1", "name": "Ana", "level": 1}]}}])
	var lc: Dictionary = await api.list_characters()
	ctx.check(lc["ok"] and lc["data"].size() == 1 and ft.requests[ft.requests.size() - 1]["auth"] == "Bearer " + ACCESS1, "api: GET /v1/characters com Bearer; lista extraida")

	# 401 -> refresh -> retry
	ft.on("GET /v1/characters", [FakeTransport.err(401, "unauthorized"), {"status": 200, "body": {"characters": []}}])
	ft.on("POST /v1/auth/refresh", [_login_body(ACCESS2, REFRESH2)])
	var before: int = ft.requests.size()
	var lc2: Dictionary = await api.list_characters()
	ctx.check(lc2["ok"] and ft.count("POST /v1/auth/refresh") == 1, "api: 401 renova token e repete a chamada")
	ctx.check(ft.requests[before + 1]["body"].contains(REFRESH1) and ft.requests[before + 2]["auth"] == "Bearer " + ACCESS2, "api: refresh usa o refresh atual e o retry usa o novo access")

	# 401 persistente depois do refresh: sem loop infinito
	ft.on("GET /v1/characters", [FakeTransport.err(401, "unauthorized")])
	ft.on("POST /v1/auth/refresh", [_login_body("ACC3_token", "REF3_token")])
	var cnt0: int = ft.count("GET /v1/characters")
	var lc3: Dictionary = await api.list_characters()
	ctx.check(not lc3["ok"] and lc3["status"] == 401 and ft.count("GET /v1/characters") - cnt0 == 2, "api: no maximo uma repeticao apos refresh")

	# refresh recusado: tokens limpos
	ft.on("POST /v1/auth/refresh", [FakeTransport.err(401, "invalid_refresh")])
	var lc4: Dictionary = await api.list_characters()
	ctx.check(not lc4["ok"] and not api.is_logged_in() and not api.has_refresh_token(), "api: refresh recusado limpa a sessao")

	# erros
	var api2: BackendApi = _api(ft)
	ft.on("POST /v1/auth/login", [FakeTransport.err(401, "invalid_credentials")])
	var bad: Dictionary = await api2.login("a@b.com", PW)
	everything.append(bad)
	ctx.check(not bad["ok"] and bad["status"] == 401 and bad["code"] == "invalid_credentials" and not api2.is_logged_in(), "api: erro 401 parseado ({error:{code}})")
	ft.on("POST /v1/auth/login", [{"status": 200, "body": {"foo": 1}}])
	var weird: Dictionary = await api2.login("a@b.com", PW)
	ctx.check(not weird["ok"] and weird["code"] == "bad_response" and not api2.is_logged_in(), "api: login com corpo sem tokens = erro")
	ft.on("POST /v1/auth/login", [{"status": 502, "body": "<html>bad gateway</html>"}])
	var html: Dictionary = await api2.login("a@b.com", PW)
	ctx.check(not html["ok"] and html["code"] == "http_502", "api: corpo nao-JSON -> http_<status>")
	ft.on("POST /v1/auth/login", [{"error": ERR_CANT_CONNECT, "status": 0, "body": ""}])
	var net: Dictionary = await api2.login("a@b.com", PW)
	ctx.check(not net["ok"] and net["code"] == "network_error" and net["status"] == 0, "api: falha de rede -> network_error")
	var api3: BackendApi = BackendApi.new()
	api3.transport = ft.handle
	var nb: Dictionary = await api3.login("a@b.com", PW)
	ctx.check(not nb["ok"] and nb["code"] == "no_base_url", "api: sem URL base")

	# demais rotas: sessoes, ticket, personagem
	ft.on("POST /v1/auth/login", [_login_body(ACCESS1, REFRESH1)])
	await api2.login("a@b.com", PW)
	ft.on("GET /v1/sessions", [{"status": 200, "body": {"sessions": [{"id": "s1", "free_slots": 2}]}}])
	var ls: Dictionary = await api2.list_sessions()
	ctx.check(ls["ok"] and ls["data"].size() == 1, "api: GET /v1/sessions extrai lista")
	ft.on("POST /v1/sessions/s1/join-ticket", [{"status": 201, "body": {"ticket": TICKET, "expires_at": "x", "session": {"endpoint": "127.0.0.1:24680"}}}])
	var jt: Dictionary = await api2.join_ticket("s1", "c1")
	ctx.check(jt["ok"] and jt["data"]["ticket"] == TICKET, "api: join-ticket devolve ticket ao chamador (uso imediato)")
	ctx.check(ft.requests[ft.requests.size() - 1]["body"].contains("c1"), "api: join-ticket envia character_id")
	ft.on("POST /v1/characters", [{"status": 201, "body": {"character": {"id": "c9", "name": "Bia"}}}])
	var cc: Dictionary = await api2.create_character("Bia")
	ctx.check(cc["ok"] and cc["data"]["id"] == "c9" and ft.requests[ft.requests.size() - 1]["body"].contains("warrior"), "api: POST /v1/characters (classe warrior)")
	ft.on("GET /v1/characters/c9", [{"status": 200, "body": {"character": {"id": "c9", "xp": 100, "level": 2}}}])
	var gc: Dictionary = await api2.get_character("c9")
	ctx.check(gc["ok"] and gc["data"]["xp"] == 100, "api: GET /v1/characters/:id desembrulha 'character'")
	ft.on("GET /v1/characters/zz", [FakeTransport.err(404, "not_found")])
	var nf: Dictionary = await api2.get_character("zz")
	ctx.check(not nf["ok"] and nf["status"] == 404, "api: 404 de personagem")
	everything.append(jt.duplicate(true))
	everything.append(nf)

	# nenhum segredo em mensagens/erros devolvidos (o ticket so aparece no resultado de join_ticket, de proposito)
	var leak: bool = false
	for item: Variant in everything:
		if item is Dictionary and (item as Dictionary).has("message"):
			var m: String = String(item["message"]) + String(item["code"])
			if m.contains(PW) or m.contains(ACCESS1) or m.contains(REFRESH1) or m.contains("TICKET_SECRET"):
				leak = true
	ctx.check(not leak, "api: mensagens de erro sem senha/token/ticket")
	api.free()
	api2.free()
	api3.free()
