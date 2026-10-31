extends RefCounted
## BackendClient (transporte falso): URL/HTTPS, segredo, retry so em idempotentes, erros, cancelamento.
## Config do servidor (ServerBackendConfig) e CharacterCodec ficam aqui tambem.

const B = preload("res://tests/e4/backend_helpers.gd")
const Fake = preload("res://tests/e4/fake_backend.gd")


func run(ctx: Object) -> void:
	var tree: SceneTree = ctx as SceneTree
	await tree.process_frame # nos adicionados em _initialize ainda nao estao 'dentro da arvore'
	_test_url_validation(ctx)
	_test_configure(ctx, tree)
	await _test_retry_policy(ctx, tree)
	_test_error_mapping(ctx, tree)
	await _test_cancel(ctx, tree)
	_test_config_parse(ctx)
	_test_codec_roundtrip(ctx, tree)
	_test_http_transport_without_host(ctx)
	await tree.physics_frame


## Espera (por tempo real) ate `res` ter um resultado, ou `max_sec`; depois mais um instante para
## provar que nao ha tentativas extras.
func _until(tree: SceneTree, res: Array, max_sec: float = 3.0) -> void:
	var t0: int = Time.get_ticks_msec()
	while res.is_empty() and float(Time.get_ticks_msec() - t0) < max_sec * 1000.0:
		await tree.process_frame
	for i: int in 5:
		await tree.process_frame


func _client(tree: SceneTree, fake: Fake) -> BackendClient:
	var c: BackendClient = BackendClient.new()
	tree.root.add_child(c)
	c.transport = fake
	c.backoff_base_sec = 0.0
	c.backoff_max_sec = 0.0
	c.configure("http://localhost:8787", B.SECRET)
	return c


func _test_url_validation(ctx: Object) -> void:
	ctx.check(BackendClient.validate_url("https://api.example.com") == "", "url: https aceito")
	ctx.check(BackendClient.validate_url("https://api.example.com:8443/base") == "", "url: https com porta e caminho aceito")
	ctx.check(BackendClient.validate_url("http://localhost:8787") == "" and BackendClient.validate_url("http://127.0.0.1:3000") == "" and BackendClient.validate_url("http://[::1]:3000") == "", "url: http aceito so em localhost/127.0.0.1/::1")
	ctx.check(BackendClient.validate_url("http://api.example.com") != "", "url: http fora de localhost recusado")
	ctx.check(BackendClient.validate_url("http://localhost.evil.com") != "", "url: http://localhost.evil.com recusado")
	ctx.check(BackendClient.validate_url("ftp://x") != "" and BackendClient.validate_url("") != "" and BackendClient.validate_url("api.example.com") != "", "url: esquema invalido/vazio recusado")
	ctx.check(BackendClient.validate_url("https://user:pw@api.example.com") != "", "url: credenciais embutidas recusadas")
	ctx.check(not BackendClient.validate_url("https://user:pw@api.example.com").contains("pw"), "url: erro nao ecoa credenciais")
	ctx.check(BackendClient.validate_url("https://a b.com") != "", "url: espaco recusado")


func _test_configure(ctx: Object, tree: SceneTree) -> void:
	var c: BackendClient = BackendClient.new()
	tree.root.add_child(c)
	ctx.check(c.configure("https://api.example.com", "") != "", "configure: segredo ausente recusado")
	ctx.check(c.configure("http://api.example.com", "s3cret-value") != "", "configure: http remoto recusado")
	ctx.check(not c.is_configured(), "nao configurado ate ter URL valida + segredo + transporte")
	ctx.check(c.configure("https://api.example.com/", B.SECRET) == "" and c.base_url == "https://api.example.com", "configure: barra final removida")
	c.queue_free()


func _test_retry_policy(ctx: Object, tree: SceneTree) -> void:
	var fake: Fake = Fake.new()
	fake.add_character(B.CID1)
	var c: BackendClient = _client(tree, fake)
	var res: Array = []
	# GET idempotente: 2 falhas de rede e depois sucesso -> 3 tentativas
	fake.force("/internal/characters/", [Fake.NET_ERR, Fake.TIMEOUT_ERR])
	c.get_character(B.CID1, func(r: Dictionary) -> void: res.append(r))
	await _until(tree, res)
	ctx.check(res.size() == 1 and res[0]["ok"] and res[0]["attempts"] == 3 and fake.count("GET /internal/characters/") == 3, "GET: retry com backoff em rede/timeout e sucesso na 3a tentativa")
	# esgota: 3 falhas -> falha com code network
	res.clear()
	fake.requests.clear()
	fake.force("/internal/characters/", [Fake.NET_ERR, Fake.NET_ERR, Fake.NET_ERR, Fake.NET_ERR])
	c.get_character(B.CID1, func(r: Dictionary) -> void: res.append(r))
	await _until(tree, res)
	ctx.check(res.size() == 1 and not res[0]["ok"] and res[0]["code"] == "network" and fake.requests.size() == 3, "GET: desiste apos max_attempts (3) com code=network")
	# 5xx e 429 tambem repetem; 4xx nao
	res.clear()
	fake.requests.clear()
	fake.forced.clear()
	fake.force("/internal/characters/", [Fake.err(503, "unavailable"), Fake.err(429, "rate_limited")])
	c.get_character(B.CID1, func(r: Dictionary) -> void: res.append(r))
	await _until(tree, res)
	ctx.check(res.size() == 1 and res[0]["ok"] and fake.requests.size() == 3, "GET: 503 e 429 sao repetidos")
	res.clear()
	fake.requests.clear()
	fake.force("/internal/characters/", [Fake.err(404, "not_found")])
	c.get_character(B.CID1, func(r: Dictionary) -> void: res.append(r))
	await _until(tree, res, 0.3)
	ctx.check(res.size() == 1 and res[0]["status"] == 404 and res[0]["code"] == "not_found" and fake.requests.size() == 1, "GET: 404 nao e repetido")
	# NAO idempotentes: redeem e register nunca repetem
	res.clear()
	fake.requests.clear()
	fake.force("redeem", [Fake.NET_ERR, Fake.NET_ERR])
	c.redeem("tk.abc", Fake.SESSION_ID, func(r: Dictionary) -> void: res.append(r))
	await _until(tree, res, 0.3)
	ctx.check(res.size() == 1 and not res[0]["ok"] and fake.count("redeem") == 1, "redeem: SEM retry (ticket de uso unico)")
	res.clear()
	fake.requests.clear()
	fake.force("POST /internal/sessions", [Fake.NET_ERR])
	c.register_session("local", 4, 2, "127.0.0.1:24680", func(r: Dictionary) -> void: res.append(r))
	await _until(tree, res, 0.3)
	ctx.check(res.size() == 1 and not res[0]["ok"] and fake.requests.size() == 1, "register: sem retry")
	# checkpoint repete com o MESMO corpo; headers com Bearer
	res.clear()
	fake.requests.clear()
	fake.force("/checkpoint", [Fake.NET_ERR])
	c.checkpoint(B.CID1, 0, {"level": 1, "xp": 0, "stats": {}, "inventory": [], "equipment": {}}, func(r: Dictionary) -> void: res.append(r))
	await _until(tree, res, 0.3)
	ctx.check(fake.requests.size() == 2 and fake.requests[0]["raw"] == fake.requests[1]["raw"], "checkpoint: retry com corpo identico")
	ctx.check(String(fake.requests[0]["session_header"]).is_empty(), "checkpoint sem sessao registrada: sem X-Session-Id")
	c.fencing_session_id = Fake.SESSION_ID
	res.clear()
	fake.requests.clear()
	c.checkpoint(B.CID1, 0, {"level": 1, "xp": 0, "stats": {}, "inventory": [], "equipment": {}}, func(r: Dictionary) -> void: res.append(r))
	await _until(tree, res, 0.3)
	ctx.check(fake.requests.size() == 1 and fake.requests[0]["session_header"] == Fake.SESSION_ID, "checkpoint (M4): envia X-Session-Id da sessao registrada")
	ctx.check(fake.last_auth == B.SECRET, "Authorization: Bearer <segredo> enviado")
	ctx.check(not str(res).contains(B.SECRET), "resultado/erros nao carregam o segredo")
	# caminho: id invalido nao injeta caminho
	res.clear()
	fake.requests.clear()
	c.get_character("../../etc/passwd", func(r: Dictionary) -> void: res.append(r))
	ctx.check(fake.requests.size() == 1 and String(fake.requests[0]["path"]) == "/internal/characters/invalid", "id com caracteres invalidos nao altera o caminho")
	c.queue_free()


func _test_error_mapping(ctx: Object, tree: SceneTree) -> void:
	var fake: Fake = Fake.new()
	var c: BackendClient = _client(tree, fake)
	var res: Array = []
	fake.force("heartbeat", [{"status": 200, "body": "isso nao e json", "error": ""}])
	c.heartbeat(Fake.SESSION_ID, func(r: Dictionary) -> void: res.append(r))
	ctx.check(res.size() == 1 and not res[0]["ok"] and res[0]["code"] == "bad_response", "2xx sem JSON valido -> bad_response")
	res.clear()
	fake.force("redeem", [Fake.err(409, "ticket_already_used")])
	c.redeem("tk", Fake.SESSION_ID, func(r: Dictionary) -> void: res.append(r))
	ctx.check(res[0]["status"] == 409 and res[0]["code"] == "ticket_already_used", "error.code do backend propagado")
	res.clear()
	fake.force("redeem", [{"status": 502, "body": "<html>", "error": ""}])
	c.redeem("tk", Fake.SESSION_ID, func(r: Dictionary) -> void: res.append(r))
	ctx.check(res[0]["code"] == "http_502", "erro sem corpo JSON -> http_<status>")
	c.queue_free()


func _test_cancel(ctx: Object, tree: SceneTree) -> void:
	var fake: Fake = Fake.new()
	fake.add_character(B.CID1)
	var c: BackendClient = _client(tree, fake)
	var res: Array = []
	fake.hold = true
	c.get_character(B.CID1, func(r: Dictionary) -> void: res.append(r))
	c.cancel_all()
	fake.hold = false
	ctx.check(res.is_empty() and fake.cancelled == 1 and c.inflight_count() == 0, "cancel_all: nenhum callback e transporte cancelado")
	# retry agendado cancelado antes de disparar
	fake.requests.clear()
	fake.force("/internal/characters/", [Fake.NET_ERR])
	c.get_character(B.CID1, func(r: Dictionary) -> void: res.append(r))
	c.cancel_all()
	await _until(tree, res, 0.3)
	ctx.check(res.is_empty() and fake.requests.size() == 1, "cancel_all: retry agendado nao dispara")
	c.queue_free()


func _test_config_parse(ctx: Object) -> void:
	var env: Dictionary = {"ELDERVALE_INTERNAL_SECRET": B.SECRET}
	var c0: ServerBackendConfig = ServerBackendConfig.parse({"dev-mode": "1"}, {}, 24680)
	ctx.check(not c0.enabled() and c0.dev_mode and c0.errors.is_empty() and c0.public_endpoint == "127.0.0.1:24680" and c0.region == "local", "config: modo dev explicito, defaults")
	var c0e: ServerBackendConfig = ServerBackendConfig.parse({}, {}, 24680)
	ctx.check(not c0e.enabled() and not c0e.dev_mode and not c0e.errors.is_empty(), "config (M6): sem backend-url e sem dev-mode = ERRO (nao abre aberto)")
	var c0f: ServerBackendConfig = ServerBackendConfig.parse({}, {"ELDERVALE_DEV_MODE": "true"}, 24680)
	ctx.check(c0f.dev_mode and c0f.errors.is_empty(), "config: ELDERVALE_DEV_MODE=true habilita dev")
	var c0g: ServerBackendConfig = ServerBackendConfig.parse({"dev-mode": "1", "backend-url": "https://api.example.com"}, env, 24680)
	ctx.check(not c0g.errors.is_empty(), "config: dev-mode junto com backend-url = erro")
	var c1: ServerBackendConfig = ServerBackendConfig.parse({"backend-url": "https://api.example.com", "region": "sa-east", "public-endpoint": "game.example.com:24680", "autosave-interval": "12", "redeem-timeout": "3", "max-pending": "5", "session-id-file": "/tmp/x.id"}, env, 24680)
	ctx.check(c1.enabled() and c1.errors.is_empty() and c1.region == "sa-east" and c1.public_endpoint == "game.example.com:24680", "config: argumentos aplicados")
	ctx.check(c1.autosave_interval_sec == 12.0 and c1.redeem_timeout_sec == 3.0 and c1.max_pending == 5 and c1.session_id_file == "/tmp/x.id" and c1.secret == B.SECRET, "config: numeros e segredo do ambiente")
	var c2: ServerBackendConfig = ServerBackendConfig.parse({}, {"ELDERVALE_BACKEND_URL": "https://env.example.com", "ELDERVALE_REGION": "us-east", "ELDERVALE_INTERNAL_SECRET": "abcd1234"}, 24680)
	ctx.check(c2.enabled() and c2.region == "us-east" and c2.backend_url == "https://env.example.com", "config: ambiente ELDERVALE_* equivalente")
	var c3: ServerBackendConfig = ServerBackendConfig.parse({"backend-url": "https://api.example.com"}, {}, 24680)
	ctx.check(not c3.errors.is_empty() and str(c3.errors).contains("ELDERVALE_INTERNAL_SECRET"), "config: backend sem segredo no ambiente = erro")
	var c4: ServerBackendConfig = ServerBackendConfig.parse({"backend-url": "http://api.example.com"}, env, 24680)
	ctx.check(not c4.errors.is_empty(), "config: http fora de localhost = erro")
	var c5: ServerBackendConfig = ServerBackendConfig.parse({"backend-url": "http://localhost:8787", "region": "BAD REGION", "public-endpoint": "semporta", "max-pending": "0", "autosave-interval": "abc"}, env, 24680)
	ctx.check(c5.errors.size() == 4 and c5.region == "local" and c5.max_pending == 8, "config: valores invalidos viram erro + default")
	ctx.check(not ServerBackendConfig.ARG_KEYS.has("internal-secret") and not str(ServerBackendConfig.ARG_KEYS).contains("secret"), "config: nao existe argumento de CLI para o segredo")
	var cfg: NetConfig = NetConfig.parse(PackedStringArray(["--internal-secret", "topsecretvalue"]))
	ctx.check(not str(cfg.errors).contains("topsecretvalue"), "NetConfig: argumento de segredo desconhecido nao ecoa o valor")
	# _split_args do server_main separa as chaves do backend
	var extras: Dictionary = {}
	var rest: PackedStringArray = ServerMain._split_args(PackedStringArray(["--port", "25000", "--backend-url", "https://a.b", "--autosave_interval=9", "--max-seconds", "5"]), extras)
	ctx.check(rest == PackedStringArray(["--port", "25000"]) and extras["backend-url"] == "https://a.b" and extras["autosave-interval"] == "9" and extras["max-seconds"] == "5", "server_main: _split_args separa chaves do servidor/backend")


func _test_codec_roundtrip(ctx: Object, tree: SceneTree) -> void:
	var rig: Object = B.H.make_rig(tree)
	var id: int = B.H.join(rig, 1)
	var lo: PlayerLoadout = PlayerLoadout.find_for(rig.world.get_player_node(id))
	var ch: Dictionary = {
		"level": 5, "xp": 1500, "revision": 2, "inventory_capacity": 24,
		"stats": {"max_health": 120, "max_resource": 50, "resource_regen": 5, "attack_power": 12, "defense": 1, "resistance": 0, "move_speed": 5},
		"inventory": [{"slot": 3, "item_id": "potion_minor", "qty": 12}, {"slot": 0, "item_id": "armor_leather", "qty": 1}],
		"equipment": {"weapon": "sword_basic", "trinket": "amulet_vigor"},
	}
	var reg: ContentRegistry = ContentRegistry.new()
	reg.load_all()
	ctx.check(CharacterCodec.validate(ch, reg) == "", "codec: personagem valido aceito")
	CharacterCodec.apply(lo, ch)
	var out: Dictionary = CharacterCodec.capture(lo)
	ctx.check(out["level"] == 5 and out["xp"] == 1500 and out["stats"]["max_health"] == 120.0 and out["stats"]["attack_power"] == 12.0, "codec: nivel/xp/stats ida e volta")
	ctx.check(out["equipment"] == {"weapon": "sword_basic", "trinket": "amulet_vigor"}, "codec: equipamento ida e volta")
	var inv_total: int = 0
	for e: Dictionary in out["inventory"]:
		inv_total += int(e["qty"])
	ctx.check(inv_total == 13 and out["inventory"][0]["slot"] == 0 and out["inventory"].size() == 2, "codec: inventario compactado com slots 0..n (13 itens)")
	var reg_check: ContentRegistry = reg
	ctx.check(CharacterCodec.validate(out, reg_check) != "inexistente", "codec: capture produz estrutura validavel")
	var bad: Dictionary = ch.duplicate(true)
	bad["inventory"] = [{"slot": 0, "item_id": "potion_minor", "qty": 999}]
	ctx.check(CharacterCodec.validate(bad, reg) != "", "codec: qty acima do max_stack recusada")
	bad = ch.duplicate(true)
	bad["equipment"] = {"weapon": "armor_leather"}
	ctx.check(CharacterCodec.validate(bad, reg) != "", "codec: item no slot errado recusado")
	bad = ch.duplicate(true)
	bad["level"] = 99
	ctx.check(CharacterCodec.validate(bad, reg) != "", "codec: nivel fora de faixa recusado")
	rig.free_all()


func _test_http_transport_without_host(ctx: Object) -> void:
	var t: HttpBackendTransport = HttpBackendTransport.new(null)
	var got: Array = []
	t.send({"method": "GET", "url": "http://127.0.0.1:1/x", "headers": PackedStringArray(), "body": "", "timeout_sec": 1.0}, func(r: Dictionary) -> void: got.append(r))
	ctx.check(got.size() == 1 and got[0]["status"] == 0 and got[0]["error"] == "cancelled", "HttpBackendTransport sem host valido: falha imediata, sem travar")
