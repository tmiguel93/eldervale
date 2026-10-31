class_name ClientMain
extends Node
## Ponto de entrada do cliente. Le NetConfig (args apos `--`), conecta via ENet, instala NetRpc e
## liga os sinais a ClientSession. Modo normal: mundo/HUD/camera. Modo bot (--bot): headless,
## sem render nem Input, escreve o relatorio JSON em --out e sai (0 ok, 1 erro de script,
## 2 bot desconhecido, 3 nao conectou).

const BUILD: String = "dev-e3"
const CONNECT_TIMEOUT_S: float = 10.0
const DEFAULT_BOT_SECONDS: float = 10.0
const PING_INTERVAL_S: float = 0.5
const POST_REJECT_GRACE_S: float = 0.5

var cfg: NetConfig
var session: ClientSession = ClientSession.new()
var is_bot: bool = false
var bot_seconds: float = DEFAULT_BOT_SECONDS

var _rpc: NetRpc
var _peer: ENetMultiplayerPeer
var _world: ClientWorld
var _hud: ClientHud
var _camera: IsoCamera
var _send_acc: float = 0.0
var _ping_acc: float = 0.0
var _elapsed: float = 0.0
var _play_elapsed: float = 0.0
var _tick: int = 0
var _finished: bool = false
var _after_reject: float = -1.0
var _connect_failed: bool = false


func _ready() -> void:
	cfg = NetConfig.from_environment()
	is_bot = not cfg.bot_script.is_empty()
	bot_seconds = _read_bot_seconds()
	for e: String in cfg.errors:
		if not e.contains("bot-seconds") and not e.begins_with("argumento ignorado"):  # --bot-seconds e lido aqui
			push_warning("NetConfig: " + e)
	session.result.bot = cfg.bot_script
	if is_bot and not BotScript.is_known(cfg.bot_script):
		push_error("Bot desconhecido: " + cfg.bot_script)
		session.result.errors.append("bot desconhecido: " + cfg.bot_script)
		_finish.call_deferred(2)
		return
	_start.call_deferred()


func _read_bot_seconds() -> float:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for i: int in args.size():
		var a: String = args[i]
		if a == "--bot-seconds" and i + 1 < args.size() and args[i + 1].is_valid_float():
			return clampf(args[i + 1].to_float(), 0.5, 3600.0)
		if a.begins_with("--bot-seconds=") and a.substr(14).is_valid_float():
			return clampf(a.substr(14).to_float(), 0.5, 3600.0)
	return DEFAULT_BOT_SECONDS


func _start() -> void:
	_rpc = NetRpc.install(get_tree())
	if cfg.sim_latency_ms > 0 or cfg.sim_loss_pct > 0.0:
		var sim: NetSim = NetSim.new()
		sim.configure(cfg.sim_latency_ms, cfg.sim_jitter_ms, cfg.sim_loss_pct, 1)
		_rpc.sim = sim
	session.send_hello = Callable(_rpc, "send_hello")
	session.send_input = Callable(_rpc, "send_input")
	session.send_ping = Callable(_rpc, "send_ping")
	_rpc.welcome_received.connect(_on_welcome)
	_rpc.reject_received.connect(_on_reject)
	_rpc.snapshot_received.connect(_on_snapshot)
	_rpc.event_received.connect(_on_event)
	_rpc.pong_received.connect(_on_pong)
	_peer = ENetMultiplayerPeer.new()
	var err: int = _peer.create_client(cfg.host, cfg.port)
	if err != OK:
		session.message = "Nao foi possivel iniciar o cliente (erro %d)." % err
		session.result.errors.append(session.message)
		_connect_failed = true
		if is_bot:
			_finish(3)
		return
	multiplayer.multiplayer_peer = _peer
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	session.message = "Conectando a %s:%d..." % [cfg.host, cfg.port]
	if not is_bot:
		_build_presentation()


func _build_presentation() -> void:
	_world = ClientWorld.new()
	_world.name = "ClientWorld"
	add_child(_world)
	_world.notice.connect(func(t: String) -> void:
		if _hud != null:
			_hud.show_notice(t))
	_hud = ClientHud.new()
	add_child(_hud)
	var cam_scene: PackedScene = load("res://scenes/camera/iso_camera.tscn") as PackedScene
	if cam_scene != null:
		_camera = cam_scene.instantiate() as IsoCamera
		add_child(_camera)


func _on_connected() -> void:
	session.begin(Protocol.VERSION if not is_bot else BotScript.hello_version(cfg.bot_script, Protocol.VERSION), BUILD, cfg.name)


func _on_connection_failed() -> void:
	_connect_failed = true
	session.message = "Falha ao conectar a %s:%d." % [cfg.host, cfg.port]
	session.state = ClientSession.State.DISCONNECTED
	session.result.errors.append(session.message)
	if is_bot:
		_finish(3)


func _on_server_disconnected() -> void:
	session.on_disconnected()
	if is_bot and _after_reject < 0.0:
		_finish(0)


func _on_welcome(player_id: int, tick_rate: int, session_seed: int) -> void:
	session.on_welcome(player_id, tick_rate, session_seed)


func _on_reject(code: int, message: String) -> void:
	session.on_reject(code, message)
	_after_reject = 0.0


func _on_snapshot(server_tick: int, last_seq: int, entities: Array) -> void:
	session.on_snapshot(server_tick, last_seq, entities, float(Time.get_ticks_msec()))


func _on_event(event_id: int, kind: int, data: Dictionary) -> void:
	session.on_event(event_id, kind, data)


func _on_pong(client_time_ms: int) -> void:
	session.on_pong(client_time_ms, float(Time.get_ticks_msec()))


func _process(delta: float) -> void:
	if _finished or _rpc == null:
		return
	_elapsed += delta
	session.result.elapsed_s = _elapsed
	if _after_reject >= 0.0:
		_after_reject += delta
		if is_bot and _after_reject >= POST_REJECT_GRACE_S:
			_finish(0)
		return
	if is_bot and session.state != ClientSession.State.PLAYING and _elapsed > CONNECT_TIMEOUT_S and session.state != ClientSession.State.DISCONNECTED:
		session.result.errors.append("timeout de conexao")
		_finish(3)
		return
	if session.state == ClientSession.State.PLAYING:
		_play_elapsed += delta
		_tick_playing(delta)
	var now: float = float(Time.get_ticks_msec())
	if _world != null:
		_update_presentation(delta, now)
	if _hud != null:
		_hud.refresh(session, delta)


func _tick_playing(delta: float) -> void:
	_ping_acc += delta
	if _ping_acc >= PING_INTERVAL_S:
		_ping_acc = 0.0
		session.ping(float(Time.get_ticks_msec()))
	_send_acc += delta
	var step: float = 1.0 / LocalInput.SEND_HZ
	var guard: int = 0
	while _send_acc >= step and guard < 5:
		_send_acc -= step
		guard += 1
		_tick += 1
		if is_bot:
			session.send_bot_items(BotScript.step(cfg.bot_script, _play_elapsed, _tick))
		else:
			session.input.yaw = _movement_yaw()
			session.send_move(LocalInput.read_move(), LocalInput.normalize_yaw(session.input.yaw), LocalInput.read_actions())
	session.prediction.update(delta)
	if is_bot:
		if not session.local_entity.is_empty():
			session.result.sample_position(_play_elapsed, session.local_entity["pos"])
		if _play_elapsed >= bot_seconds:
			_finish(0)


func _movement_yaw() -> float:
	if _camera != null and is_instance_valid(_camera):
		return _camera.get_yaw()
	return deg_to_rad(45.0)


func _update_presentation(delta: float, now: float) -> void:
	for ev: Dictionary in session.drain_events():
		_world.apply_event(int(ev["kind"]), ev["data"])
	var samples: Dictionary = session.interpolator.sample(now)
	var local_pos: Variant = null
	if session.prediction.initialized and samples.has(session.player_id):
		local_pos = session.prediction.pos
	_world.update_frame(samples, session.player_id, local_pos, delta)
	if _camera != null and _world.local_avatar != null and _camera.target != _world.local_avatar:
		_camera.set_target(_world.local_avatar)


func _finish(code: int) -> void:
	if _finished:
		return
	_finished = true
	if not session.result.connected and code == 0 and session.result.rejected.is_empty():
		pass  # idle sem conexao e um resultado valido; o JSON registra connected=false
	var path: String = cfg.out_path if cfg != null else ""
	var json: String = session.result.to_json()
	if not path.is_empty():
		var dir: String = path.get_base_dir()
		if not dir.is_empty() and dir != ".":
			DirAccess.make_dir_recursive_absolute(dir)
		var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			push_error("Nao foi possivel escrever " + path)
			code = 1
		else:
			f.store_string(json)
			f.close()
	else:
		print(json)
	if _peer != null:
		_peer.close()
	get_tree().quit(code)
