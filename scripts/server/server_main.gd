class_name ServerMain
extends Node
## Servidor dedicado headless (E3). Le NetConfig (args apos `--` e ELDERVALE_*), abre ENet,
## instala o NetRpc e liga mundo + sessao. Uso (ver docs/E3_SERVER.md):
##   godot --headless --path . res://scenes/server/server_boot.tscn -- --port 24680 --max-seconds 60
## Argumentos extras do servidor: --max-seconds N (0 = sem limite), --max-invalid N, --hello-timeout S.
## Tick de simulacao = tick de fisica do Godot (Engine.physics_ticks_per_second = tick_rate).
## Nenhuma funcao administrativa e exposta pela rede; o unico canal e o contrato (NetRpc).

## Conexoes ENet alem de max_players, para poder responder reject(3) a quem chega com o servidor cheio.
const PENDING_SLACK: int = 4
const EXTRA_KEYS: Array[String] = ["max-seconds", "max-invalid", "hello-timeout", "backend-url", "public-endpoint", "region", "session-id-file", "heartbeat-interval", "autosave-interval", "redeem-timeout", "max-pending", "shutdown-timeout", "dev-mode", "world", "individual-loot", "test-hp-mult", "test-speed-mult", "measure-snapshots"]

var cfg: NetConfig
var settings: ServerSettings
var peer: ENetMultiplayerPeer
var rpc: NetRpc
var world: ServerWorld
var session: ServerSession
var backend_cfg: ServerBackendConfig
var backend_client: BackendClient
var sync: BackendSync

var _max_seconds: float = 0.0
var _elapsed: float = 0.0
var _running: bool = false
var _quitting: bool = false
var _finalizing: bool = false ## aguardando checkpoint/release/close no backend


func _ready() -> void:
	# O NetRpc entra na raiz fora do setup da cena inicial (raiz ocupada), por isso adiado.
	_start.call_deferred()


func _start() -> void:
	var extras: Dictionary = {}
	var net_args: PackedStringArray = _split_args(OS.get_cmdline_user_args(), extras)
	cfg = NetConfig.parse(net_args, _read_env())
	for e: String in cfg.errors:
		print("[server] config: %s" % e)
	settings = ServerSettings.from_net_config(cfg)
	_apply_extras(extras)
	backend_cfg = ServerBackendConfig.parse(extras, _read_env_all(), cfg.port)
	ServerLog.add_secret(backend_cfg.secret)
	if backend_cfg.enabled():
		for e: String in backend_cfg.errors:
			printerr("[server] backend config: %s" % e)
		if not backend_cfg.errors.is_empty():
			get_tree().quit(2)
			return
		settings.redeem_timeout_sec = backend_cfg.redeem_timeout_sec
		settings.max_pending = backend_cfg.max_pending
	else:
		if not backend_cfg.errors.is_empty():
			for e: String in backend_cfg.errors:
				printerr("[server] backend config: %s" % e)
			get_tree().quit(2)
			return
	settings.session_seed = randi()

	Engine.physics_ticks_per_second = cfg.tick_rate
	Engine.max_fps = maxi(cfg.tick_rate * 2, 60)

	peer = ENetMultiplayerPeer.new()
	var err: int = peer.create_server(cfg.port, cfg.max_players + PENDING_SLACK)
	if err != OK:
		printerr("[server] falha ao abrir a porta %d (erro %d)" % [cfg.port, err])
		get_tree().quit(1)
		return
	multiplayer.multiplayer_peer = peer
	rpc = NetRpc.install(get_tree())
	if cfg.sim_latency_ms > 0 or cfg.sim_jitter_ms > 0 or cfg.sim_loss_pct > 0.0:
		rpc.sim = NetSim.new()
		rpc.sim.configure(cfg.sim_latency_ms, cfg.sim_jitter_ms, cfg.sim_loss_pct, settings.session_seed)
		print("[server] NetSim ativo: %d ms, jitter %d ms, perda %.1f%%" % [cfg.sim_latency_ms, cfg.sim_jitter_ms, cfg.sim_loss_pct])

	world = ServerWorld.new()
	world.name = "World"
	world.settings = settings
	add_child(world)
	session = ServerSession.new()
	session.name = "Session"
	add_child(session)
	session.setup(settings, world, NetRpcTransport.new(rpc))
	_start_backend()

	rpc.hello_received.connect(session.on_hello)
	rpc.input_received.connect(session.on_input)
	rpc.ping_received.connect(session.on_ping)
	rpc.quest_cmd_received.connect(session.on_quest_cmd)
	rpc.dialogue_cmd_received.connect(session.on_dialogue_cmd)
	rpc.craft_cmd_received.connect(session.on_craft_cmd)
	multiplayer.peer_connected.connect(session.on_peer_connected)
	multiplayer.peer_disconnected.connect(session.on_peer_disconnected)

	_running = true
	print("[server] escutando na porta %d (max %d jogadores, tick %d Hz, snapshot %d Hz, protocolo %d)" % [
		cfg.port, cfg.max_players, cfg.tick_rate, cfg.snapshot_rate, Protocol.VERSION])


func _start_backend() -> void:
	if not backend_cfg.enabled():
		print("[server] AVISO: sem --backend-url -> MODO DEV: tickets nao exigidos, nada e persistido")
		return
	backend_client = BackendClient.new()
	backend_client.name = "BackendClient"
	add_child(backend_client)
	var err: String = backend_client.configure(backend_cfg.backend_url, backend_cfg.secret)
	if not err.is_empty():
		printerr("[server] backend config: %s" % err)
		get_tree().quit(2)
		return
	backend_client.transport = HttpBackendTransport.new(backend_client)
	sync = BackendSync.new()
	sync.name = "BackendSync"
	sync.client = backend_client
	sync.region = backend_cfg.region
	sync.capacity = cfg.max_players
	sync.endpoint = backend_cfg.public_endpoint
	sync.heartbeat_interval_sec = backend_cfg.heartbeat_interval_sec
	sync.autosave_interval_sec = backend_cfg.autosave_interval_sec
	sync.shutdown_timeout_sec = backend_cfg.shutdown_timeout_sec
	sync.session_id_file = backend_cfg.session_id_file
	add_child(sync)
	session.attach_backend(sync)
	sync.start()
	print("[server] backend configurado (%s); ticket OBRIGATORIO, autosave %.0fs, heartbeat %.0fs" % [
		backend_cfg.backend_url.get_slice("/", 2), backend_cfg.autosave_interval_sec, sync.heartbeat_interval_sec])


func _process(delta: float) -> void:
	if _finalizing:
		if sync == null or sync.is_shutdown_complete():
			print("[server] encerrado")
			get_tree().quit(0)
			_finalizing = false
		return
	if not _running or _quitting:
		return
	_elapsed += delta
	if _max_seconds > 0.0 and _elapsed >= _max_seconds:
		print("[server] --max-seconds atingido")
		shutdown()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		print("[server] pedido de encerramento recebido")
		shutdown()


## Encerramento limpo: checkpoint de todos + release + close da sessao no backend (com prazo),
## fecha peers e sai com codigo 0.
func shutdown() -> void:
	if _quitting:
		return
	_quitting = true
	_running = false
	if session != null:
		if settings.measure_snapshots:
			print("[server] snapshots: %s" % JSON.stringify(session.snapshot_stats))
		session.shutdown()
	if peer != null:
		peer.close()
	if sync != null:
		sync.begin_shutdown()
		_finalizing = true
		return
	print("[server] encerrado")
	get_tree().quit(0)


func _apply_extras(extras: Dictionary) -> void:
	if extras.has("max-seconds") and String(extras["max-seconds"]).is_valid_float():
		_max_seconds = maxf(0.0, float(extras["max-seconds"]))
	if extras.has("max-invalid") and String(extras["max-invalid"]).is_valid_float():
		settings.max_invalid_inputs = clampi(int(float(extras["max-invalid"])), 1, 100000)
	if extras.has("world"): # E5.3: --world greenwood (mundo em zonas) | arena (padrao: arena de teste do E1/E3)
		var w: String = String(extras["world"]).strip_edges()
		settings.world_id = "" if w == "arena" or w.is_empty() else w
		print("[server] mundo: %s" % ("arena de teste" if settings.world_id.is_empty() else settings.world_id))
		settings.individual_loot = not settings.world_id.is_empty() # E5.4: o mundo usa loot individual (arena: legado E3/E4)
	if extras.has("individual-loot"): # E5.4: --individual-loot 0|1 forca o modo (padrao: ligado so com --world)
		settings.individual_loot = String(extras["individual-loot"]).strip_edges() in ["1", "true", "on"]
		print("[server] loot individual: %s" % ("ligado" if settings.individual_loot else "desligado"))
	# E5.6: parametros SO de teste. Sem ELDERVALE_TEST_MODE=1 sao ignorados (com aviso): nunca valem em producao por engano.
	var test_mode: bool = OS.get_environment("ELDERVALE_TEST_MODE") == "1"
	for k: String in ["test-hp-mult", "test-speed-mult"]:
		if not extras.has(k):
			continue
		if not test_mode:
			print("[server] AVISO: --%s ignorado (exige ELDERVALE_TEST_MODE=1)" % k)
			continue
		if String(extras[k]).is_valid_float():
			if k == "test-hp-mult":
				settings.test_enemy_hp_mult = clampf(float(extras[k]), 0.02, 1.0)
			else:
				settings.test_move_speed_mult = clampf(float(extras[k]), 1.0, 3.0)
	if test_mode and (settings.test_enemy_hp_mult != 1.0 or settings.test_move_speed_mult != 1.0):
		print("[server] MODO DE TESTE: vida dos inimigos x%.2f, velocidade dos jogadores x%.2f (NAO usar em producao)" % [settings.test_enemy_hp_mult, settings.test_move_speed_mult])
	if extras.has("measure-snapshots"):
		settings.measure_snapshots = String(extras["measure-snapshots"]).strip_edges() in ["1", "true", "on"]
	if extras.has("hello-timeout") and String(extras["hello-timeout"]).is_valid_float():
		settings.hello_timeout_sec = clampf(float(extras["hello-timeout"]), 0.5, 600.0)


## Separa as chaves exclusivas do servidor dos argumentos entregues ao NetConfig.
static func _split_args(args: PackedStringArray, extras: Dictionary) -> PackedStringArray:
	var rest: PackedStringArray = PackedStringArray()
	var i: int = 0
	while i < args.size():
		var a: String = args[i]
		i += 1
		var key: String = a.substr(2) if a.begins_with("--") else ""
		var val: String = ""
		var has_eq: bool = key.contains("=")
		if has_eq:
			val = key.substr(key.find("=") + 1)
			key = key.substr(0, key.find("="))
		key = key.replace("_", "-")
		if EXTRA_KEYS.has(key):
			if not has_eq and i < args.size() and not args[i].begins_with("--"):
				val = args[i]
				i += 1
			extras[key] = val
			continue
		rest.append(a)
	return rest


static func _read_env() -> Dictionary:
	var env: Dictionary = {}
	for k: String in NetConfig._ENV_KEYS:
		var ev: String = NetConfig._ENV_KEYS[k]
		if OS.has_environment(ev):
			env[ev] = OS.get_environment(ev)
	return env


## Ambiente completo do servidor (NetConfig + backend). O segredo so existe aqui, em memoria.
static func _read_env_all() -> Dictionary:
	var env: Dictionary = _read_env()
	for k: String in ServerBackendConfig.ENV_KEYS:
		var ev: String = ServerBackendConfig.ENV_KEYS[k]
		if OS.has_environment(ev):
			env[ev] = OS.get_environment(ev)
	if OS.has_environment(ServerBackendConfig.SECRET_ENV):
		env[ServerBackendConfig.SECRET_ENV] = OS.get_environment(ServerBackendConfig.SECRET_ENV)
	return env
