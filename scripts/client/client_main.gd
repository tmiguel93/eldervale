class_name ClientMain
extends Node
## Ponto de entrada do cliente. Le NetConfig (args apos `--`), conecta via ENet, instala NetRpc e
## liga os sinais a ClientSession. Modo normal: mundo/HUD/camera. Modo bot (--bot): headless,
## sem render nem Input, escreve o relatorio JSON em --out e sai (0 ok, 1 erro de script,
## 2 bot desconhecido, 3 nao conectou, 4 falha no fluxo de backend/argumentos).
## Com --backend-url: login -> personagem -> sessao -> join-ticket -> ENet -> hello v2 (ticket).
## Sem --backend-url: conexao direta (--host/--port) com ticket vazio (dev).

const BUILD: String = "dev-e4"
const CONNECT_TIMEOUT_S: float = 10.0
const DEFAULT_BOT_SECONDS: float = 10.0
const PING_INTERVAL_S: float = 0.5
const POST_REJECT_GRACE_S: float = 0.5
const REPLAY_HOLD_S: float = 1.0       # replay_ticket: tempo jogando na 1a conexao
const REPLAY_GAP_S: float = 0.6        # pausa entre as conexoes
const KILL_GRACE_S: float = 2.0        # kill_enemy: espera apos a morte (recompensa/checkpoint)
const FINAL_WAIT_S: float = 2.0        # espera antes do GET final do personagem (autosave/checkpoint)

var cfg: NetConfig
var args: ClientArgs
var api: BackendApi
var login_screen: LoginScreen
var session: ClientSession = ClientSession.new()
var is_bot: bool = false
var bot_seconds: float = DEFAULT_BOT_SECONDS

var _rpc: NetRpc
var _peer: ENetMultiplayerPeer
var _world: ClientWorld
var _hud: ClientHud
var _camera: IsoCamera
var _fader: OcclusionFader
var _send_acc: float = 0.0
var _ping_acc: float = 0.0
var _elapsed: float = 0.0
var _play_elapsed: float = 0.0
var _tick: int = 0
var _finished: bool = false
var _after_reject: float = -1.0
var _connect_failed: bool = false
var _conn: Dictionary = {}              # {ticket, host, port, session_id, character_id} (ticket nunca logado)
var _flow_info: Dictionary = {}         # login_ok, character_id, session_id, flow_error
var _attempts: Array = []
var _replay_phase: int = 0              # 0 = nao e replay, 1 = 1a conexao, 2 = pausa, 3 = 2a conexao
var _replay_timer: float = 0.0
var _kill_target: int = -1
var _kill_done_at: float = -1.0
var _tour_memo: Dictionary = {}         # world_tour: estagio do puzzle
var _tour_done_at: float = -1.0
var _signals_wired: bool = false
var _return_to_login: bool = false


func _ready() -> void:
	cfg = NetConfig.from_environment()
	args = ClientArgs.from_environment()
	is_bot = not cfg.bot_script.is_empty()
	bot_seconds = _read_bot_seconds()
	for e: String in cfg.errors:
		if not ClientArgs.is_own_warning(e):
			push_warning("NetConfig: " + e)
	session = _new_session()
	if is_bot and not BotScript.is_known(cfg.bot_script):
		push_error("Bot desconhecido: " + cfg.bot_script)
		session.result.errors.append("bot desconhecido: " + cfg.bot_script)
		_finish.call_deferred(2)
		return
	if is_bot and BotScript.needs_backend(cfg.bot_script) and not args.uses_backend():
		session.result.errors.append("bot %s exige --backend-url" % cfg.bot_script)
		_finish.call_deferred(4)
		return
	if is_bot and args.uses_backend():
		var problems: PackedStringArray = args.bot_problems()
		if not problems.is_empty():
			session.result.errors.append_array(problems)
			_finish.call_deferred(4)
			return
	_start.call_deferred()


func _new_session() -> ClientSession:
	var ss: ClientSession = ClientSession.new()
	ss.result.bot = cfg.bot_script
	ss.result.login_ok = bool(_flow_info.get("login_ok", false))
	ss.result.character_id = String(_flow_info.get("character_id", ""))
	ss.result.session_id = String(_flow_info.get("session_id", ""))
	ss.result.flow_error = String(_flow_info.get("flow_error", ""))
	if _rpc != null:
		_wire_session(ss)
	return ss


func _wire_session(ss: ClientSession) -> void:
	ss.send_hello = Callable(_rpc, "send_hello")
	ss.send_input = Callable(_rpc, "send_input")
	ss.send_ping = Callable(_rpc, "send_ping")
	ss.send_quest_cmd = Callable(_rpc, "send_quest_cmd")
	ss.send_dialogue_cmd = Callable(_rpc, "send_dialogue_cmd")


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
	_wire_session(session)
	if not _signals_wired:
		_signals_wired = true
		_rpc.welcome_received.connect(_on_welcome)
		_rpc.reject_received.connect(_on_reject)
		_rpc.snapshot_received.connect(_on_snapshot)
		_rpc.event_received.connect(_on_event)
		_rpc.pong_received.connect(_on_pong)
		_rpc.quest_update_received.connect(func(kind: int, data: Dictionary) -> void: session.on_quest_update(kind, data))
		_rpc.dialogue_received.connect(func(kind: int, data: Dictionary) -> void: session.on_dialogue(kind, data))
		multiplayer.connected_to_server.connect(_on_connected)
		multiplayer.connection_failed.connect(_on_connection_failed)
		multiplayer.server_disconnected.connect(_on_server_disconnected)
	if args.uses_backend():
		api = BackendApi.new()
		add_child(api)
		var err: String = api.set_base_url(args.backend_url)
		if not err.is_empty():
			_flow_failed("bad_backend_url", err)
			return
		if is_bot:
			_run_bot_flow()
		else:
			_build_presentation()
			_show_login()
		return
	if not is_bot:
		_build_presentation()
	_connect(cfg.host, cfg.port)


func _flow_failed(code: String, text: String) -> void:
	session.message = text
	session.result.flow_error = code
	session.result.errors.append("fluxo de backend: " + code)
	_flow_info["flow_error"] = code
	if is_bot:
		_finish(4)
	elif login_screen != null:
		login_screen.show_message(text)


func _run_bot_flow() -> void:
	var flow: BackendFlow = BackendFlow.new(api)
	var r: Dictionary = await flow.run_full(args.email, args.password, args.character, args.session_id, true, true)
	_flow_info["login_ok"] = bool(r["login_ok"])
	_flow_info["character_id"] = String(r["character_id"])
	_flow_info["session_id"] = String(r["session_id"])
	session.result.login_ok = bool(r["login_ok"])
	session.result.character_id = String(r["character_id"])
	session.result.session_id = String(r["session_id"])
	args.password = ""  # nao precisa mais
	if not bool(r["ok"]):
		_flow_failed(flow.last_error_code, flow.last_error)
		return
	_conn = r["conn"]
	if cfg.bot_script == "replay_ticket":
		_replay_phase = 1
	_connect(String(_conn["host"]), int(_conn["port"]))


func _show_login() -> void:
	var scene: PackedScene = load("res://scenes/client/login.tscn") as PackedScene
	login_screen = scene.instantiate() as LoginScreen
	login_screen.setup(api, args.session_id)
	login_screen.play_requested.connect(_on_play_requested)
	add_child(login_screen)


func _on_play_requested(conn: Dictionary) -> void:
	_conn = conn
	_flow_info["character_id"] = String(conn.get("character_id", ""))
	_flow_info["session_id"] = String(conn.get("session_id", ""))
	_return_to_login = true
	login_screen.visible = false
	_after_reject = -1.0
	_connect_failed = false
	session = _new_session()
	_play_elapsed = 0.0
	_elapsed = 0.0
	_connect(String(conn["host"]), int(conn["port"]))


func _connect(host: String, port: int) -> void:
	_peer = ENetMultiplayerPeer.new()
	var err: int = _peer.create_client(host, port)
	if err != OK:
		session.message = "Nao foi possivel iniciar o cliente (erro %d)." % err
		session.result.errors.append(session.message)
		_connect_failed = true
		if is_bot:
			_finish(3)
		return
	multiplayer.multiplayer_peer = _peer
	session.message = "Conectando a %s:%d..." % [host, port]


func _drop_connection() -> void:
	if _peer != null:
		_peer.close()
	multiplayer.multiplayer_peer = null
	_peer = null


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
	var ticket: String = String(_conn.get("ticket", ""))
	if cfg.bot_script == "bad_ticket":
		ticket = BotScript.tamper_ticket(ticket)
	var shown_name: String = cfg.name
	if args.uses_backend() and not args.character.is_empty() and Protocol.validate_name(args.character)["ok"]:
		shown_name = args.character
	session.begin(Protocol.VERSION if not is_bot else BotScript.hello_version(cfg.bot_script, Protocol.VERSION), BUILD, shown_name, ticket)


func _on_connection_failed() -> void:
	_connect_failed = true
	session.message = "Falha ao conectar ao servidor."
	session.state = ClientSession.State.DISCONNECTED
	session.result.errors.append(session.message)
	if _replay_phase == 3:
		_attempts.append(_attempt_summary())
		_finish(0)
	elif is_bot:
		_finish(3)


func _on_server_disconnected() -> void:
	session.on_disconnected()
	if _replay_phase == 1 or _replay_phase == 3:
		return  # tratado em _process (registra tentativa)
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


func _attempt_summary() -> Dictionary:
	return {"connected": session.result.connected, "ticket_used_ok": session.result.ticket_used_ok,
		"rejected": session.result.rejected, "disconnected": session.result.disconnected}


func _process(delta: float) -> void:
	if _finished or _rpc == null:
		return
	_elapsed += delta
	session.result.elapsed_s = _elapsed
	if _replay_phase > 0 and _process_replay(delta):
		return
	if _after_reject >= 0.0:
		_after_reject += delta
		if is_bot and _after_reject >= POST_REJECT_GRACE_S:
			_finish(0)
		elif not is_bot and _return_to_login and _after_reject >= POST_REJECT_GRACE_S:
			_back_to_login()
		return
	if is_bot and session.state != ClientSession.State.PLAYING and _elapsed > CONNECT_TIMEOUT_S and session.state != ClientSession.State.DISCONNECTED:
		session.result.errors.append("timeout de conexao")
		_finish(3)
		return
	if not is_bot and _return_to_login and session.state == ClientSession.State.DISCONNECTED:
		_back_to_login()
		return
	if session.state == ClientSession.State.PLAYING:
		_play_elapsed += delta
		_tick_playing(delta)
	var now: float = float(Time.get_ticks_msec())
	if _world != null and (login_screen == null or not login_screen.visible):
		_update_presentation(delta, now)
	if _hud != null:
		_hud.refresh(session, delta)


func _back_to_login() -> void:
	var text: String = session.message
	_drop_connection()
	_conn = {}  # ticket de uso unico descartado
	_after_reject = -1.0
	session = _new_session()
	if login_screen != null:
		login_screen.show_message(text)


## replay_ticket: 1a conexao joga REPLAY_HOLD_S, fecha; apos uma pausa, 2a conexao com o MESMO ticket
## ate welcome/reject/timeout. Devolve true se consumiu o frame.
func _process_replay(delta: float) -> bool:
	match _replay_phase:
		1:
			var done: bool = false
			if session.state == ClientSession.State.PLAYING:
				done = _play_elapsed >= REPLAY_HOLD_S  # _play_elapsed avanca no fluxo normal
			elif session.state == ClientSession.State.REJECTED:
				_after_reject += delta
				done = _after_reject >= POST_REJECT_GRACE_S  # deixa o servidor desconectar primeiro
			elif session.state == ClientSession.State.DISCONNECTED:
				done = true
			elif _elapsed > CONNECT_TIMEOUT_S:
				done = true
			if not done:
				return session.state == ClientSession.State.REJECTED
			_attempts.append(_attempt_summary())
			_drop_connection()
			_after_reject = -1.0
			_replay_phase = 2
			_replay_timer = 0.0
			return true
		2:
			_replay_timer += delta
			if _replay_timer >= REPLAY_GAP_S:
				session = _new_session()
				_after_reject = -1.0
				_elapsed = 0.0
				_play_elapsed = 0.0
				_replay_phase = 3
				_connect(String(_conn["host"]), int(_conn["port"]))
			return true
		3:
			var finished_attempt: bool = false
			if session.state == ClientSession.State.PLAYING:
				_play_elapsed += delta
				if _play_elapsed >= 1.0:
					finished_attempt = true
			elif session.state == ClientSession.State.REJECTED:
				_after_reject += delta
				finished_attempt = _after_reject >= POST_REJECT_GRACE_S
			elif session.state == ClientSession.State.DISCONNECTED:
				finished_attempt = true
			elif _elapsed > CONNECT_TIMEOUT_S:
				session.result.errors.append("timeout de conexao")
				finished_attempt = true
			if finished_attempt:
				_attempts.append(_attempt_summary())
				_finish(0)
			return true
	return false


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
			if cfg.bot_script == "kill_enemy":
				_kill_enemy_tick()
			elif cfg.bot_script == "world_tour":
				_world_tour_tick()
			else:
				session.send_bot_items(BotScript.step(cfg.bot_script, _play_elapsed, _tick))
		else:
			session.input.yaw = _movement_yaw()
			session.send_move(LocalInput.read_move(), LocalInput.normalize_yaw(session.input.yaw), LocalInput.read_actions())
	session.prediction.update(delta)
	if is_bot:
		_bot_drain_events()
		if not session.local_entity.is_empty():
			session.result.sample_position(_play_elapsed, session.local_entity["pos"])
		var grace: float = args.kill_grace_s if args.kill_grace_s >= 0.0 else KILL_GRACE_S
		if _kill_done_at >= 0.0 and _play_elapsed - _kill_done_at >= grace:
			_finish(0)
		elif _tour_done_at >= 0.0 and _play_elapsed - _tour_done_at >= 1.0:
			_finish(0)
		elif _play_elapsed >= bot_seconds:
			_finish(0)


func _kill_enemy_tick() -> void:
	if session.local_entity.is_empty() or _kill_done_at >= 0.0:
		return
	var r: Dictionary = BotScript.kill_enemy_step(session.local_entity["pos"], session.last_entities, _kill_target)
	_kill_target = int(r["target_id"])
	session.send_bot_items(r["items"])


func _world_tour_tick() -> void:
	if session.local_entity.is_empty() or _tour_done_at >= 0.0:
		return
	var r: Dictionary = BotScript.world_tour_step(session.local_entity["pos"], _tour_memo)
	session.send_bot_items(r["items"])
	if bool(r["done"]):
		_tour_done_at = _play_elapsed
		session.result.tour_done = true


## Bots nao tem apresentacao: consomem os eventos aqui (contam mortes do alvo do kill_enemy).
func _bot_drain_events() -> void:
	for ev: Dictionary in session.drain_events():
		session.result.on_world_event(int(ev["kind"]), ev["data"] as Dictionary, session.player_id)
		if int(ev["kind"]) == Protocol.EVENT_DEATH and cfg.bot_script == "kill_enemy":
			var d: Variant = ev["data"]
			if d is Dictionary and int((d as Dictionary).get("id", -2)) == _kill_target and _kill_target >= 0:
				session.result.kills += 1
				_kill_done_at = _play_elapsed


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
	_ensure_occlusion_fader()


## E5.3: com o mundo em zonas ha muralhas/pilares/arvores (grupo occluder): o fader do E1 liga ao avatar local.
func _ensure_occlusion_fader() -> void:
	if _camera == null or _world == null or _world.local_avatar == null:
		return
	if _fader != null:
		if _fader.target != _world.local_avatar:
			_fader.target = _world.local_avatar
		return
	var cam: Camera3D = _camera.get_camera()
	if cam == null:
		return
	_fader = OcclusionFader.new()
	_fader.name = "OcclusionFader"
	_fader.camera = cam
	_fader.target = _world.local_avatar
	add_child(_fader)


func _finish(code: int) -> void:
	if _finished:
		return
	_finished = true
	_finalize(code)


func _finalize(code: int) -> void:
	session.result.attempts = _attempts
	_drop_connection()
	# GET final do personagem (XP/nivel/itens persistidos), apos dar tempo ao checkpoint do servidor.
	if is_bot and api != null and api.is_logged_in() and not String(_flow_info.get("character_id", "")).is_empty() and code == 0:
		await get_tree().create_timer(FINAL_WAIT_S).timeout
		var r: Dictionary = await api.get_character(String(_flow_info["character_id"]))
		if r["ok"] and r["data"] is Dictionary:
			session.result.set_character_final(r["data"])
		else:
			session.result.errors.append("GET personagem final falhou: " + String(r.get("code", "")))
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
	get_tree().quit(code)
