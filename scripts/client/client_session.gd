class_name ClientSession
extends RefCounted
## Logica de sessao do cliente, independente de rede e de nos: maquina de estados, hello/welcome/
## reject, snapshots -> interpolador/predicao, eventos (dedupe), ping/RTT, envio de input com seq.
## O transporte e injetado por Callables (testavel sem rede). O cliente nunca decide combate.

enum State { IDLE, HELLO_SENT, PLAYING, REJECTED, DISCONNECTED }

const INPUT_DT: float = 1.0 / LocalInput.SEND_HZ

var state: State = State.IDLE
var message: String = ""
var player_id: int = -1
var tick_rate: int = 30
var session_seed: int = 0
var entity_count: int = 0
var last_rtt_ms: float = -1.0
var last_event_id: int = 0
var events_dropped: int = 0
var entities_rejected: int = 0

var interpolator: SnapshotInterpolator = SnapshotInterpolator.new()
var prediction: Prediction = Prediction.new()
var input: LocalInput = LocalInput.new()
var result: BotResult = BotResult.new()
var local_entity: Dictionary = {}
var last_input_seq_ack: int = 0
var last_entities: Array = []      # entidades validadas do ultimo snapshot (para bots)
var _used_ticket: bool = false

## Callables injetados: send_hello(version:int, build:String, name:String, ticket:String),
## send_input(seq:int, move:Vector2, yaw:float, actions:int, client_tick:int), send_ping(client_time_ms:int).
var send_hello: Callable
var send_input: Callable
var send_ping: Callable

var _events: Array[Dictionary] = []
var _client_tick: int = 0
var _last_sent_seq: int = 0


## Hello v2: o ticket (join ticket do backend, uso unico) vai so no c_hello e nao e guardado.
func begin(version: int, build: String, player_name: String, ticket: String = "") -> void:
	state = State.HELLO_SENT
	message = "Conectando..."
	_used_ticket = not ticket.is_empty()
	if send_hello.is_valid():
		send_hello.call(version, build, player_name, ticket)


func on_welcome(p_player_id: int, p_tick_rate: int, p_seed: int) -> void:
	if state != State.HELLO_SENT:
		return  # nao pedimos hello (ou ja recebemos): ignora, conforme contrato
	player_id = p_player_id
	tick_rate = maxi(p_tick_rate, 1)
	session_seed = p_seed
	state = State.PLAYING
	message = "Conectado (id %d)" % player_id
	interpolator.configure(tick_rate)
	result.on_welcome(player_id, tick_rate)
	result.ticket_used_ok = _used_ticket


func on_reject(code: int, text: String) -> void:
	state = State.REJECTED
	message = reject_text(code, text)
	result.on_reject(code, text)


func on_disconnected() -> void:
	result.disconnected = true
	if state != State.REJECTED:
		state = State.DISCONNECTED
		message = "Desconectado do servidor." if player_id >= 0 else "Falha ao conectar ao servidor."


func on_snapshot(server_tick: int, last_input_seq: int, raw_entities: Array, now_ms: float) -> void:
	if state != State.PLAYING:
		return
	var entities: Array = []
	for e0: Variant in raw_entities:
		if Protocol.validate_entity_dict(e0):
			entities.append(e0)
		else:
			entities_rejected += 1
	if not interpolator.push(server_tick, now_ms, entities):
		return
	result.on_snapshot(now_ms, server_tick, entities)
	entity_count = entities.size()
	last_entities = entities
	last_input_seq_ack = last_input_seq
	local_entity = {}
	for e: Variant in entities:
		if e is Dictionary and int((e as Dictionary).get("id", -1)) == player_id:
			local_entity = e
			break
	if not local_entity.is_empty():
		var p: Variant = local_entity.get("pos", null)
		if p is Vector3:
			prediction.reconcile(p, last_input_seq)


func on_event(event_id: int, kind: int, data: Dictionary) -> void:
	if event_id <= last_event_id:
		events_dropped += 1
		return
	last_event_id = event_id
	result.on_event(kind)
	_events.append({"id": event_id, "kind": kind, "data": data})


func drain_events() -> Array[Dictionary]:
	var out: Array[Dictionary] = _events
	_events = []
	return out


func on_pong(client_time_ms: int, now_ms: float) -> void:
	var rtt: float = now_ms - float(client_time_ms)
	if rtt < 0.0 or rtt > 60000.0:
		return
	last_rtt_ms = rtt
	result.on_rtt(rtt)


func ping(now_ms: float) -> void:
	if state == State.PLAYING and send_ping.is_valid():
		send_ping.call(int(now_ms))


## Envia um input (seq crescente) e preve o movimento local. Retorna o seq usado.
func send_move(move: Vector2, yaw: float, actions: int) -> int:
	if state != State.PLAYING:
		return -1
	var s: int = input.next_seq()
	_dispatch(s, move, yaw, actions)
	if not prediction.initialized and not local_entity.is_empty() and local_entity.get("pos") is Vector3:
		prediction.init_at(local_entity["pos"])
	prediction.apply_input(s, move.limit_length(1.0) if move.is_finite() else Vector2.ZERO, yaw if is_finite(yaw) else 0.0, INPUT_DT)
	return s


## Envia itens de roteiro de bot (podem ser invalidos de proposito; so predizem os validos).
func send_bot_items(items: Array[Dictionary]) -> void:
	if state != State.PLAYING:
		return
	for it: Dictionary in items:
		var move: Vector2 = it.get("move", Vector2.ZERO)
		var yaw: float = float(it.get("yaw", 0.0))
		var actions: int = int(it.get("actions", 0))
		var valid: bool = move.is_finite() and is_finite(yaw) and move.length() <= 1.001 and (actions & ~15) == 0 and not it.has("seq_repeat")
		if valid:
			send_move(move, yaw, actions)
		elif it.has("seq_repeat"):
			_dispatch(_last_sent_seq, move, yaw, actions)
		else:
			var s: int = input.next_seq()
			_dispatch(s, move, yaw, actions)


func _dispatch(seq: int, move: Vector2, yaw: float, actions: int) -> void:
	_last_sent_seq = seq
	_client_tick += 1
	result.inputs_sent += 1
	if send_input.is_valid():
		send_input.call(seq, move, yaw, actions, _client_tick)


static func reject_text(code: int, server_message: String) -> String:
	var base: String
	match code:
		1: base = "Versao incompativel com o servidor. Atualize o jogo."
		2: base = "Servidor recusou dados invalidos."
		3: base = "Servidor cheio."
		4: base = "Desconectado por excesso de mensagens (rate limit)."
		5: base = "Sessao nao autorizada / ordem de mensagens invalida."
		_: base = "Conexao recusada (codigo %d)." % code
	return base if server_message.is_empty() else base + " (" + server_message + ")"
