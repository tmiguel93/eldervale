extends RefCounted
## Revisao de seguranca E4 (docs/E4_SECURITY_REVIEW.md): validadores de rede sob entrada hostil,
## URL/segredo do backend e o achado "modo dev abre sem backend". Marcados [ACHADO] = comportamento
## ABERTO documentado (inverter o teste quando corrigido).

const B = preload("res://tests/e4/backend_helpers.gd")


func run(ctx: Object) -> void:
	var tree: SceneTree = ctx as SceneTree
	_test_hello_fuzz(ctx)
	_test_input_fuzz(ctx)
	_test_entity_fuzz(ctx)
	_test_backend_url(ctx)
	_test_secret_only_env(ctx)
	_test_dev_mode_open(ctx, tree)
	await tree.physics_frame


func _test_hello_fuzz(ctx: Object) -> void:
	var big: String = "A".repeat(200000)
	var cases: Array = [
		[null, "b", "n", "t"], [2.0, "b", "n", "t"], [2, 5, "n", "t"], [2, "b", [], "t"], [2, "b", "n", {}],
		[2, "b", "n", big], [2, big, "n", "t"], [2, "b", big, "t"], [2, "b", "bad\nname", "t"],
		[2, "b", "ok", "tick\net"], [2, "b", "ok", "tick" + String.chr(1) + "et"], [2, "b", "ok", "té"], [2, "b", "<b>x</b>", "t"],
		[2, "b", "[b]x[/b]", "t"], [-1, "b", "ok", "t"], [3, "b", "ok", "t"], [2, "b", "", "t"],
	]
	var accepted: int = 0
	for c: Array in cases:
		var r: Dictionary = Protocol.validate_hello(c[0], c[1], c[2], c[3])
		if bool(r["ok"]):
			accepted += 1
	ctx.check(accepted == 0, "hello hostil (tipos errados, 200 KB, controle, BBCode, versao) => nenhum aceito")
	var good: Dictionary = Protocol.validate_hello(2, "b", "Ok_Name-1", "aaa.bbb.ccc")
	ctx.check(bool(good["ok"]), "hello legitimo continua aceito")


func _test_input_fuzz(ctx: Object) -> void:
	var bad: Array = [
		[1, Vector2(NAN, 0), 0.0, 0], [1, Vector2(INF, 0), 0.0, 0], [1, Vector2.ZERO, NAN, 0], [1, Vector2.ZERO, INF, 0],
		[1, Vector2.ZERO, 1.0e9, 0], [1, Vector2.ZERO, 0.0, -1], [1, Vector2.ZERO, 0.0, 16], [1, Vector2.ZERO, 0.0, 1.5],
		[1.5, Vector2.ZERO, 0.0, 0], ["1", Vector2.ZERO, 0.0, 0], [1, Vector3.ZERO, 0.0, 0], [1, [1, 2], 0.0, 0], [1, null, 0.0, 0],
	]
	var ok_count: int = 0
	for c: Array in bad:
		if bool(Protocol.validate_input(c[0], c[1], c[2], c[3], 0)["ok"]):
			ok_count += 1
	ctx.check(ok_count == 0, "input hostil (NaN/inf/yaw gigante/mascara/tipos) => nenhum aceito")
	var huge: Dictionary = Protocol.validate_input(1, Vector2(1.0e30, 1.0e30), 0.0, 1, 0)
	ctx.check(bool(huge["ok"]) and (huge["move"] as Vector2).length() <= 1.001, "move gigante e normalizado a <= 1.001 (sem velocidade extra)")
	var replay: Dictionary = Protocol.validate_input(5, Vector2.ZERO, 0.0, 0, 5)
	ctx.check(not bool(replay["ok"]) and bool(replay.get("stale", false)), "seq repetido/antigo => descartado (replay)")


func _test_entity_fuzz(ctx: Object) -> void:
	var base: Dictionary = {"id": 1, "kind": 1, "pos": Vector3.ZERO, "yaw": 0.0, "hp": 10.0, "max_hp": 10.0, "state": 0, "type": "player"}
	ctx.check(Protocol.validate_entity_dict(base), "entidade valida aceita")
	var mutations: Array = [
		{"pos": Vector3(NAN, 0, 0)}, {"pos": Vector2.ZERO}, {"hp": -1.0}, {"hp": INF}, {"kind": 9}, {"id": "1"},
		{"type": "x".repeat(33)}, {"type": 5}, {"state": 1.5}, {"yaw": NAN},
	]
	var accepted: int = 0
	for m: Dictionary in mutations:
		var e: Dictionary = base.duplicate()
		e.merge(m, true)
		if Protocol.validate_entity_dict(e):
			accepted += 1
	var missing: Dictionary = base.duplicate()
	missing.erase("pos")
	ctx.check(accepted == 0 and not Protocol.validate_entity_dict(missing) and not Protocol.validate_entity_dict("x"), "entidade de snapshot malformada => rejeitada pelo cliente")


func _test_backend_url(ctx: Object) -> void:
	var rejected: Array[String] = [
		"http://localhost.evil.com", "http://127.0.0.1.evil.com:8787", "http://127.0.0.1@evil.com", "https://user:pw@host/", "http://evil.com",
		"ftp://x", "//evil.com", "https://", "https://ho st", "http://[::1]@evil.com", "http://0.0.0.0:80", "http://localhost" + String.chr(1) + ".evil.com",
	]
	var leaked: Array[String] = []
	for u: String in rejected:
		if BackendClient.validate_url(u).is_empty():
			leaked.append(u)
	ctx.check(leaked.is_empty(), "servidor: validate_url recusa HTTP remoto/credenciais embutidas/esquemas estranhos %s" % str(leaked))
	var api: BackendApi = BackendApi.new()
	var api_leaked: Array[String] = []
	for u: String in rejected:
		if api.set_base_url(u).is_empty():
			api_leaked.append(u)
	api.free()
	ctx.check(api_leaked.is_empty(), "cliente: set_base_url recusa os mesmos casos %s" % str(api_leaked))
	ctx.check(BackendClient.validate_url("https://api.exemplo.com/x").is_empty() and BackendClient.validate_url("http://127.0.0.1:8787").is_empty(), "https remoto e http loopback continuam aceitos")


func _test_secret_only_env(ctx: Object) -> void:
	# O segredo NAO e aceito por CLI (nem por chave "secret" nem "internal-secret").
	var cli: Dictionary = {"backend-url": "https://api.exemplo.com", "secret": "cli-secret-xyz", "internal-secret": "cli-secret-xyz"}
	var cfg: ServerBackendConfig = ServerBackendConfig.parse(cli, {}, 24680)
	ctx.check(cfg.secret.is_empty() and not cfg.errors.is_empty(), "segredo por CLI ignorado => erro de config (servidor nao sobe)")
	var env_cfg: ServerBackendConfig = ServerBackendConfig.parse({}, {"ELDERVALE_BACKEND_URL": "https://api.exemplo.com", "ELDERVALE_INTERNAL_SECRET": "env-secret-xyz"}, 24680)
	ctx.check(env_cfg.errors.is_empty() and env_cfg.secret == "env-secret-xyz", "segredo por ambiente aceito")
	var extras: Dictionary = {}
	var rest: PackedStringArray = ServerMain._split_args(PackedStringArray(["--secret", "cli-secret-xyz", "--port", "24700"]), extras)
	var nc: NetConfig = NetConfig.parse(rest, {})
	ctx.check(not "\n".join(nc.errors).contains("cli-secret-xyz"), "NetConfig nao ecoa o valor de um argumento desconhecido (segredo digitado errado no CLI)")
	ServerLog.add_secret("env-secret-xyz")
	ctx.check(ServerLog.scrub("Authorization: Bearer env-secret-xyz").find("env-secret-xyz") == -1, "ServerLog.scrub remove o segredo registrado")
	ServerLog.clear_secrets()


func _test_dev_mode_open(ctx: Object, tree: SceneTree) -> void:
	# [CORRIGIDO M6] URL do backend ausente (typo/ambiente vazio) nao abre mais o servidor sem ticket:
	# exige --dev-mode 1 / ELDERVALE_DEV_MODE=1 explicito.
	var only_secret: ServerBackendConfig = ServerBackendConfig.parse({}, {"ELDERVALE_INTERNAL_SECRET": "env-secret-xyz"}, 24680)
	ctx.check(not only_secret.enabled() and not only_secret.errors.is_empty(), "[M6] segredo presente + URL ausente => ERRO de configuracao (servidor nao sobe aberto)")
	var explicit: ServerBackendConfig = ServerBackendConfig.parse({"dev-mode": "1"}, {}, 24680)
	ctx.check(explicit.dev_mode and explicit.errors.is_empty(), "[M6] modo dev so com flag explicita")
	var dev: Object = B.H.make_rig(tree)
	var id: int = B.H.join(dev, 7, "Anon")
	ctx.check(id > 0 and dev.session.sync == null, "em modo dev explicito qualquer peer entra sem ticket")
	dev.free_all()
