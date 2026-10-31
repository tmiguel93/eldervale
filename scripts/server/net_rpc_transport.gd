class_name NetRpcTransport
extends ServerTransport
## Transporte real: delega a NetRpc (que aplica o NetSim, se configurado, a todo envio).

const DISCONNECT_GRACE_SEC: float = 0.25

var rpc: NetRpc


func _init(p_rpc: NetRpc = null) -> void:
	rpc = p_rpc


func send_welcome(peer_id: int, player_id: int, tick_rate: int, session_seed: int) -> void:
	rpc.send_welcome(peer_id, player_id, tick_rate, session_seed)


func send_reject(peer_id: int, code: int, message: String) -> void:
	rpc.send_reject(peer_id, code, message)


func send_snapshot(peer_id: int, server_tick: int, last_input_seq: int, entities: Array) -> void:
	rpc.send_snapshot(peer_id, server_tick, last_input_seq, entities)


func send_event(peer_id: int, event_id: int, kind: int, data: Dictionary) -> void:
	rpc.send_event(peer_id, event_id, kind, data)


func send_pong(peer_id: int, client_time_ms: int) -> void:
	rpc.send_pong(peer_id, client_time_ms)


## Desconecta DEPOIS do s_reject: com NetSim a desconexao entra na mesma fila reliable (mesma
## ordem); sem NetSim espera uma folga curta para o ENet entregar o reject.
func disconnect_peer(peer_id: int) -> void:
	if rpc == null or not rpc.is_inside_tree():
		return
	var mp: MultiplayerPeer = rpc.multiplayer.multiplayer_peer
	if mp == null:
		return
	var do_it: Callable = func() -> void:
		if mp != null and mp.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			mp.disconnect_peer(peer_id)
	if rpc.sim != null:
		rpc.sim.submit(do_it, true, Time.get_ticks_msec())
	else:
		rpc.get_tree().create_timer(DISCONNECT_GRACE_SEC).timeout.connect(do_it)
