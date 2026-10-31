class_name ServerSession
extends Node
## Sessao do servidor: ciclo de vida de peers (hello/welcome/reject), validacao e rate limit do
## input, snapshots e replicacao de eventos. Nao conhece ENet: recebe chamadas de handlers
## (`on_*`, ligados aos sinais do NetRpc) e envia por um ServerTransport.
## Regras (contrato): hello unico por conexao; input so apos welcome; payload invalido -> descarta +
## contador; reincidencia -> reject(4) + disconnect; peer sem hello valido no prazo -> desconecta.
## Tempo: now_msec() (relogio injetavel via test_now_msec para testes deterministicos).

signal player_joined(peer_id: int, entity_id: int)
signal player_left(peer_id: int, entity_id: int)

class PeerState extends RefCounted:
	var peer_id: int = 0
	var connected_msec: int = 0
	var welcomed: bool = false
	var closing: bool = false
	var entity_id: int = 0
	var player_name: String = ""
	var last_seq: int = -1
	var invalid_in_window: int = 0
	var window_start_msec: int = 0
	var dropped_invalid: int = 0
	var dropped_stale: int = 0
	var dropped_rate: int = 0
	var accepted_inputs: int = 0
	var hello_limiter: RateLimiter
	var input_limiter: RateLimiter
	var ping_limiter: RateLimiter


var settings: ServerSettings
var world: ServerWorld
var transport: ServerTransport
## >= 0 substitui o relogio real (testes).
var test_now_msec: int = -1

var _peers: Dictionary = {} ## peer_id -> PeerState
var _next_event_id: int = 1


func setup(p_settings: ServerSettings, p_world: ServerWorld, p_transport: ServerTransport) -> void:
	settings = p_settings
	world = p_world
	transport = p_transport
	world.event_emitted.connect(_broadcast_event)
	process_physics_priority = 20 # depois de jogadores/inimigos


func now_msec() -> int:
	return test_now_msec if test_now_msec >= 0 else Time.get_ticks_msec()


func _physics_process(_delta: float) -> void:
	step_tick()


## Fim de tick: contagem, timeouts de hello e (a cada N ticks) snapshots.
func step_tick() -> void:
	world.server_tick += 1
	check_timeouts()
	if world.server_tick % settings.snapshot_divisor() == 0:
		send_snapshots()


# ------------------------------------------------------------------ consulta

func peer_count() -> int:
	return _peers.size()


func welcomed_count() -> int:
	var n: int = 0
	for p: PeerState in _peers.values():
		if p.welcomed and not p.closing:
			n += 1
	return n


func has_peer(peer_id: int) -> bool:
	return _peers.has(peer_id)


func get_peer_state(peer_id: int) -> PeerState:
	return _peers.get(peer_id) as PeerState


# ------------------------------------------------------------------ conexao

func on_peer_connected(peer_id: int) -> void:
	if _peers.has(peer_id):
		return
	var p: PeerState = PeerState.new()
	p.peer_id = peer_id
	p.connected_msec = now_msec()
	p.window_start_msec = p.connected_msec
	p.hello_limiter = RateLimiter.new(settings.hello_rate_per_sec, settings.hello_burst)
	p.input_limiter = RateLimiter.new(settings.input_rate_per_sec, settings.input_burst)
	p.ping_limiter = RateLimiter.new(settings.ping_rate_per_sec, settings.ping_burst)
	_peers[peer_id] = p
	print("[server] peer %d conectou (%d conexoes)" % [peer_id, _peers.size()])


func on_peer_disconnected(peer_id: int) -> void:
	_drop_peer(peer_id, "desconectou")


func check_timeouts() -> void:
	var now: int = now_msec()
	var limit: int = int(settings.hello_timeout_sec * 1000.0)
	for p: PeerState in _peers.values():
		if not p.welcomed and not p.closing and now - p.connected_msec >= limit:
			_reject_and_close(p, Protocol.REJECT_NOT_AUTHENTICATED, "hello nao recebido a tempo")


# ------------------------------------------------------------------ hello

func on_hello(peer_id: int, version: Variant, build: Variant, player_name: Variant) -> void:
	var p: PeerState = _peers.get(peer_id) as PeerState
	if p == null or p.closing:
		return
	if p.welcomed:
		_reject_and_close(p, Protocol.REJECT_NOT_AUTHENTICATED, "hello repetido")
		return
	if not p.hello_limiter.allow(now_msec()):
		_reject_and_close(p, Protocol.REJECT_RATE_LIMIT, "hello rapido demais")
		return
	var v: Dictionary = Protocol.validate_hello(version, build, player_name)
	if not bool(v["ok"]):
		_reject_and_close(p, int(v["code"]), String(v["message"]))
		return
	if world.player_count() >= settings.max_players:
		_reject_and_close(p, Protocol.REJECT_SERVER_FULL, "servidor cheio")
		return
	var entity_id: int = world.add_player(peer_id, String(v["name"]))
	if entity_id == 0:
		_reject_and_close(p, Protocol.REJECT_SERVER_FULL, "sem vaga")
		return
	p.entity_id = entity_id
	p.player_name = String(v["name"])
	p.welcomed = true
	transport.send_welcome(peer_id, entity_id, settings.tick_rate, settings.session_seed)
	# Estado atual para quem chegou agora (eventos novos, ids crescentes so para este peer).
	for other: PeerState in _peers.values():
		if other != p and other.welcomed and not other.closing:
			_send_event_to(p, Protocol.EVENT_PLAYER_JOINED, {"id": other.entity_id, "name": other.player_name})
	for data: Dictionary in world.enemy_spawn_events():
		_send_event_to(p, Protocol.EVENT_ENEMY_SPAWN, data)
	print("[server] peer %d entrou como '%s' (jogador %d)" % [peer_id, p.player_name, entity_id])
	player_joined.emit(peer_id, entity_id)


# ------------------------------------------------------------------ input / ping

func on_input(peer_id: int, seq: Variant, move: Variant, yaw: Variant, actions: Variant, _client_tick: Variant = 0) -> void:
	var p: PeerState = _peers.get(peer_id) as PeerState
	if p == null or p.closing:
		return
	if not p.welcomed:
		_reject_and_close(p, Protocol.REJECT_NOT_AUTHENTICATED, "input antes do welcome")
		return
	if not p.input_limiter.allow(now_msec()):
		p.dropped_rate += 1
		_count_invalid(p, "rate limit de input")
		return
	var v: Dictionary = Protocol.validate_input(seq, move, yaw, actions, p.last_seq)
	if not bool(v["ok"]):
		if bool(v.get("stale", false)):
			p.dropped_stale += 1 # reordenacao/duplicata: descarta sem contar como abuso
			return
		p.dropped_invalid += 1
		_count_invalid(p, String(v["message"]))
		return
	p.last_seq = int(seq)
	p.accepted_inputs += 1
	world.set_input(p.entity_id, v["move"] as Vector2, float(v["yaw"]), int(actions))


func on_ping(peer_id: int, client_time_ms: Variant) -> void:
	var p: PeerState = _peers.get(peer_id) as PeerState
	if p == null or p.closing or typeof(client_time_ms) != TYPE_INT:
		return
	if not p.ping_limiter.allow(now_msec()):
		return
	transport.send_pong(peer_id, int(client_time_ms))


func _count_invalid(p: PeerState, reason: String) -> void:
	var now: int = now_msec()
	if now - p.window_start_msec >= int(settings.invalid_window_sec * 1000.0):
		p.window_start_msec = now
		p.invalid_in_window = 0
	p.invalid_in_window += 1
	if p.invalid_in_window > settings.max_invalid_inputs:
		print("[server] peer %d acima do limite de mensagens invalidas (%s)" % [p.peer_id, reason])
		_reject_and_close(p, Protocol.REJECT_RATE_LIMIT, "mensagens invalidas em excesso")


# ------------------------------------------------------------------ snapshots / eventos

func send_snapshots() -> void:
	if welcomed_count() == 0:
		return
	var entities: Array = world.build_entities()
	for p: PeerState in _peers.values():
		if p.welcomed and not p.closing:
			transport.send_snapshot(p.peer_id, world.server_tick, p.last_seq, entities)


func _broadcast_event(kind: int, data: Dictionary) -> void:
	var event_id: int = _next_event_id
	_next_event_id += 1
	for p: PeerState in _peers.values():
		if p.welcomed and not p.closing:
			transport.send_event(p.peer_id, event_id, kind, data)


func _send_event_to(p: PeerState, kind: int, data: Dictionary) -> void:
	var event_id: int = _next_event_id
	_next_event_id += 1
	transport.send_event(p.peer_id, event_id, kind, data)


# ------------------------------------------------------------------ encerramento de peers

func _reject_and_close(p: PeerState, code: int, message: String) -> void:
	if p.closing:
		return
	p.closing = true
	print("[server] peer %d rejeitado (codigo %d: %s)" % [p.peer_id, code, message])
	transport.send_reject(p.peer_id, code, message)
	transport.disconnect_peer(p.peer_id)
	_drop_peer(p.peer_id, "")


func _drop_peer(peer_id: int, reason: String) -> void:
	var p: PeerState = _peers.get(peer_id) as PeerState
	if p == null:
		return
	_peers.erase(peer_id)
	if not reason.is_empty():
		print("[server] peer %d %s" % [peer_id, reason])
	if p.entity_id != 0:
		world.remove_player(p.entity_id) # emite player_left para os demais
		player_left.emit(peer_id, p.entity_id)


## Chamado no encerramento do servidor.
func shutdown() -> void:
	for id: int in _peers.keys():
		_drop_peer(id, "")
