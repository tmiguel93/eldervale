class_name ServerTransport
extends RefCounted
## Saida do servidor para a rede. A base e um no-op; NetRpcTransport envia por NetRpc e os testes
## injetam um gravador. A sessao nunca fala com ENet/RPC diretamente.


func send_welcome(_peer_id: int, _player_id: int, _tick_rate: int, _session_seed: int) -> void:
	pass


func send_reject(_peer_id: int, _code: int, _message: String) -> void:
	pass


func send_snapshot(_peer_id: int, _server_tick: int, _last_input_seq: int, _entities: Array) -> void:
	pass


## E5.7: parte de snapshot compacto (unreliable). Ver SnapshotCodec / Protocol.CAP_SNAPSHOT_COMPACT.
func send_snapshot_part(_peer_id: int, _server_tick: int, _last_input_seq: int, _part: int, _parts: int, _blob: PackedByteArray) -> void:
	pass


func send_event(_peer_id: int, _event_id: int, _kind: int, _data: Dictionary) -> void:
	pass


func send_pong(_peer_id: int, _client_time_ms: int) -> void:
	pass


## E5.1: atualizacao de quests do jogador (reliable, so para este peer). Ver Protocol.QUEST_*.
func send_quest_update(_peer_id: int, _kind: int, _data: Dictionary) -> void:
	pass


## E5.1: estado do dialogo do jogador (reliable, so para este peer). Ver Protocol.DIALOGUE_*.
func send_dialogue(_peer_id: int, _kind: int, _data: Dictionary) -> void:
	pass


## E5.4: resultado de crafting do jogador (reliable, so para este peer). Ver Protocol.CRAFT_*.
func send_craft_update(_peer_id: int, _kind: int, _data: Dictionary) -> void:
	pass


## E5.6: inventario + equipamento completos do jogador (reliable, so para este peer). Ver Protocol.validate_inventory_update.
func send_inventory(_peer_id: int, _data: Dictionary) -> void:
	pass


## E6.1: classe do personagem (reliable, so para este peer). Ver Protocol.validate_class_update.
func send_class(_peer_id: int, _data: Dictionary) -> void:
	pass


func disconnect_peer(_peer_id: int) -> void:
	pass
