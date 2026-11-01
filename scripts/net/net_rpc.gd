class_name NetRpc
extends Node
## Unico no com todos os @rpc do contrato; IDENTICO em servidor e cliente (mesmo script, mesmo nome
## "NetRpc" na raiz). Os @rpc so validam remetente/tipos basicos e emitem sinais. Sem logica de jogo.
## Os parametros @rpc sao Variant de proposito: o que chega do fio nao e confiavel.

## v2: hello_received carrega o ticket de sessao (NUNCA logar). M5b: send_hello agora tem 4 parametros.
signal hello_received(peer_id: int, version: int, build: String, player_name: String, ticket: String)
signal input_received(peer_id: int, seq: int, move: Vector2, yaw: float, actions: int, client_tick: int)
signal ping_received(peer_id: int, client_time_ms: int)
signal welcome_received(player_id: int, tick_rate: int, session_seed: int)
signal reject_received(code: int, message: String)
signal snapshot_received(server_tick: int, last_input_seq: int, entities: Array)
signal event_received(event_id: int, kind: int, data: Dictionary)
signal pong_received(client_time_ms: int)
## Extensao aditiva E5.1 (quests + dialogo). Os sinais NAO validam o conteudo (Protocol.validate_*).
signal quest_cmd_received(peer_id: int, req_id: int, op: int, quest_id: String)
signal dialogue_cmd_received(peer_id: int, req_id: int, op: int, npc_id: String, choice: int)
signal quest_update_received(kind: int, data: Dictionary)
signal dialogue_received(kind: int, data: Dictionary)
## Extensao aditiva E5.4 (crafting). `craft_cmd_received` NAO valida o conteudo (Protocol.validate_craft_cmd).
signal craft_cmd_received(peer_id: int, req_id: int, recipe_id: String)
signal craft_update_received(kind: int, data: Dictionary)

const NODE_NAME: String = "NetRpc"
const SERVER_PEER_ID: int = 1
const MAX_STRING: int = 256
const MAX_TICKET: int = 1024
const MAX_MESSAGE: int = 512
const MAX_ENTITIES: int = 256
const CH_ORDERED: int = 1

## Opcional: se definido, todo envio passa por ele (latencia/perda simuladas).
var sim: NetSim = null


## Cria (uma vez) o no "NetRpc" na raiz. Idempotente. Chame fora do setup da cena inicial
## (ex.: `NetRpc.install.call_deferred(get_tree())` dentro de _ready e obtenha depois via get_instance).
static func install(tree: SceneTree) -> NetRpc:
	var existing: NetRpc = get_instance(tree)
	if existing != null:
		return existing
	var node: NetRpc = NetRpc.new()
	node.name = NODE_NAME
	tree.root.add_child(node)
	return node


static func get_instance(tree: SceneTree) -> NetRpc:
	return tree.root.get_node_or_null(NODE_NAME) as NetRpc


func _process(_delta: float) -> void:
	if sim != null:
		sim.pump(Time.get_ticks_msec())


# ---------------------------------------------------------------- recepcao (C -> S)

@rpc("any_peer", "call_remote", "reliable")
func c_hello(version: Variant, build: Variant, player_name: Variant, ticket: Variant) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	if not multiplayer.is_server() or sender == 0:
		return
	if typeof(version) != TYPE_INT or typeof(build) != TYPE_STRING or typeof(player_name) != TYPE_STRING or typeof(ticket) != TYPE_STRING:
		return
	var b: String = build
	var n: String = player_name
	var t: String = ticket
	if b.length() > MAX_STRING or n.length() > MAX_STRING or t.length() > MAX_TICKET:
		return
	hello_received.emit(sender, int(version), b, n, t)


@rpc("any_peer", "call_remote", "unreliable_ordered", CH_ORDERED)
func c_input(seq: Variant, move: Variant, yaw: Variant, actions: Variant, client_tick: Variant) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	if not multiplayer.is_server() or sender == 0:
		return
	if typeof(seq) != TYPE_INT or typeof(move) != TYPE_VECTOR2 or typeof(actions) != TYPE_INT or typeof(client_tick) != TYPE_INT:
		return
	if not Protocol.is_finite_number(yaw):
		return
	input_received.emit(sender, int(seq), move as Vector2, float(yaw), int(actions), int(client_tick))


@rpc("any_peer", "call_remote", "unreliable")
func c_ping(client_time_ms: Variant) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	if not multiplayer.is_server() or sender == 0:
		return
	if typeof(client_time_ms) != TYPE_INT:
		return
	ping_received.emit(sender, int(client_time_ms))


@rpc("any_peer", "call_remote", "reliable")
func c_quest_cmd(req_id: Variant, op: Variant, quest_id: Variant) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	if not multiplayer.is_server() or sender == 0:
		return
	if typeof(req_id) != TYPE_INT or typeof(op) != TYPE_INT or typeof(quest_id) != TYPE_STRING:
		return
	var q: String = quest_id
	if q.length() > MAX_STRING:
		return
	quest_cmd_received.emit(sender, int(req_id), int(op), q)


@rpc("any_peer", "call_remote", "reliable")
func c_dialogue_cmd(req_id: Variant, op: Variant, npc_id: Variant, choice: Variant) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	if not multiplayer.is_server() or sender == 0:
		return
	if typeof(req_id) != TYPE_INT or typeof(op) != TYPE_INT or typeof(npc_id) != TYPE_STRING or typeof(choice) != TYPE_INT:
		return
	var n: String = npc_id
	if n.length() > MAX_STRING:
		return
	dialogue_cmd_received.emit(sender, int(req_id), int(op), n, int(choice))


@rpc("any_peer", "call_remote", "reliable")
func c_craft_cmd(req_id: Variant, recipe_id: Variant) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	if not multiplayer.is_server() or sender == 0:
		return
	if typeof(req_id) != TYPE_INT or typeof(recipe_id) != TYPE_STRING:
		return
	var r: String = recipe_id
	if r.length() > MAX_STRING:
		return
	craft_cmd_received.emit(sender, int(req_id), r)


# ---------------------------------------------------------------- recepcao (S -> C)

func _from_server() -> bool:
	return not multiplayer.is_server() and multiplayer.get_remote_sender_id() == SERVER_PEER_ID


@rpc("authority", "call_remote", "reliable")
func s_welcome(player_id: Variant, tick_rate: Variant, session_seed: Variant) -> void:
	if not _from_server():
		return
	if typeof(player_id) != TYPE_INT or typeof(tick_rate) != TYPE_INT or typeof(session_seed) != TYPE_INT:
		return
	welcome_received.emit(int(player_id), int(tick_rate), int(session_seed))


@rpc("authority", "call_remote", "reliable")
func s_reject(code: Variant, message: Variant) -> void:
	if not _from_server():
		return
	if typeof(code) != TYPE_INT or typeof(message) != TYPE_STRING:
		return
	var m: String = message
	reject_received.emit(int(code), m.substr(0, MAX_MESSAGE))


@rpc("authority", "call_remote", "unreliable_ordered", CH_ORDERED)
func s_snapshot(server_tick: Variant, last_input_seq: Variant, entities: Variant) -> void:
	if not _from_server():
		return
	if typeof(server_tick) != TYPE_INT or typeof(last_input_seq) != TYPE_INT or typeof(entities) != TYPE_ARRAY:
		return
	var arr: Array = entities
	if arr.size() > MAX_ENTITIES:
		return
	snapshot_received.emit(int(server_tick), int(last_input_seq), arr)


@rpc("authority", "call_remote", "reliable")
func s_event(event_id: Variant, kind: Variant, data: Variant) -> void:
	if not _from_server():
		return
	if typeof(event_id) != TYPE_INT or typeof(kind) != TYPE_INT or typeof(data) != TYPE_DICTIONARY:
		return
	event_received.emit(int(event_id), int(kind), data as Dictionary)


@rpc("authority", "call_remote", "unreliable")
func s_pong(client_time_ms: Variant) -> void:
	if not _from_server():
		return
	if typeof(client_time_ms) != TYPE_INT:
		return
	pong_received.emit(int(client_time_ms))


@rpc("authority", "call_remote", "reliable")
func s_quest(kind: Variant, data: Variant) -> void:
	if not _from_server():
		return
	if typeof(kind) != TYPE_INT or typeof(data) != TYPE_DICTIONARY:
		return
	quest_update_received.emit(int(kind), data as Dictionary)


@rpc("authority", "call_remote", "reliable")
func s_dialogue(kind: Variant, data: Variant) -> void:
	if not _from_server():
		return
	if typeof(kind) != TYPE_INT or typeof(data) != TYPE_DICTIONARY:
		return
	dialogue_received.emit(int(kind), data as Dictionary)


@rpc("authority", "call_remote", "reliable")
func s_craft(kind: Variant, data: Variant) -> void:
	if not _from_server():
		return
	if typeof(kind) != TYPE_INT or typeof(data) != TYPE_DICTIONARY:
		return
	craft_update_received.emit(int(kind), data as Dictionary)


# ---------------------------------------------------------------- envio

func _can_send() -> bool:
	if not is_inside_tree():
		return false
	var peer: MultiplayerPeer = multiplayer.multiplayer_peer
	return peer != null and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func _dispatch(callable: Callable, reliable: bool) -> void:
	if sim != null:
		sim.submit(callable, reliable, Time.get_ticks_msec())
	else:
		callable.call()


## Executado no momento da entrega (apos a latencia simulada): reconfere a conexao.
func _deliver(peer: int, method: StringName, args: Array) -> void:
	if not _can_send():
		return
	# Peer pode ter desconectado durante o atraso simulado: descarta em vez de gerar erro.
	if peer != 0 and multiplayer.is_server() and not multiplayer.get_peers().has(peer):
		return
	var full: Array = [peer, method]
	full.append_array(args)
	callv_rpc_id(full)


func callv_rpc_id(full: Array) -> void:
	# rpc_id(peer, method, ...args) via callv, pois a aridade varia por metodo.
	callv("rpc_id", full)


func _send(peer: int, method: StringName, args: Array, reliable: bool) -> void:
	if not _can_send():
		return
	_dispatch(_deliver.bind(peer, method, args), reliable)


# Cliente -> servidor
func send_hello(version: int, build: String, player_name: String, ticket: String) -> void:
	_send(SERVER_PEER_ID, &"c_hello", [version, build, player_name, ticket], true)


func send_input(seq: int, move: Vector2, yaw: float, actions: int, client_tick: int) -> void:
	_send(SERVER_PEER_ID, &"c_input", [seq, move, yaw, actions, client_tick], false)


func send_ping(client_time_ms: int) -> void:
	_send(SERVER_PEER_ID, &"c_ping", [client_time_ms], false)


func send_quest_cmd(req_id: int, op: int, quest_id: String) -> void:
	_send(SERVER_PEER_ID, &"c_quest_cmd", [req_id, op, quest_id], true)


func send_dialogue_cmd(req_id: int, op: int, npc_id: String, choice: int) -> void:
	_send(SERVER_PEER_ID, &"c_dialogue_cmd", [req_id, op, npc_id, choice], true)


func send_craft_cmd(req_id: int, recipe_id: String) -> void:
	_send(SERVER_PEER_ID, &"c_craft_cmd", [req_id, recipe_id], true)


# Servidor -> cliente
func send_craft_update(peer: int, kind: int, data: Dictionary) -> void:
	_send(peer, &"s_craft", [kind, data], true)


func send_quest_update(peer: int, kind: int, data: Dictionary) -> void:
	_send(peer, &"s_quest", [kind, data], true)


func send_dialogue(peer: int, kind: int, data: Dictionary) -> void:
	_send(peer, &"s_dialogue", [kind, data], true)


func send_welcome(peer: int, player_id: int, tick_rate: int, session_seed: int) -> void:
	_send(peer, &"s_welcome", [player_id, tick_rate, session_seed], true)


func send_reject(peer: int, code: int, message: String) -> void:
	_send(peer, &"s_reject", [code, message], true)


func send_snapshot(peer: int, server_tick: int, last_seq: int, entities: Array) -> void:
	_send(peer, &"s_snapshot", [server_tick, last_seq, entities], false)


func send_event(peer: int, event_id: int, kind: int, data: Dictionary) -> void:
	_send(peer, &"s_event", [event_id, kind, data], true)


func send_pong(peer: int, client_time_ms: int) -> void:
	_send(peer, &"s_pong", [client_time_ms], false)
