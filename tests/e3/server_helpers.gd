extends RefCounted
## Utilitarios dos testes do servidor (nao e um teste: nome sem prefixo test_). SEM rede real:
## o ServerSession recebe chamadas diretas dos handlers e fala com um transporte gravador.

const GRUNT_SCENE: String = "res://scenes/enemy/melee_grunt.tscn"


class RecordingTransport extends ServerTransport:
	var welcomes: Array[Dictionary] = []
	var rejects: Array[Dictionary] = []
	var snapshots: Array[Dictionary] = []
	var events: Array[Dictionary] = []
	var pongs: Array[Dictionary] = []
	var disconnects: Array[int] = []
	## E5.1: mensagens de quest/dialogo gravadas ({peer, kind, data}).
	var quest_updates: Array[Dictionary] = []
	var dialogues: Array[Dictionary] = []

	func send_quest_update(peer_id: int, kind: int, data: Dictionary) -> void:
		quest_updates.append({"peer": peer_id, "kind": kind, "data": data})

	func send_dialogue(peer_id: int, kind: int, data: Dictionary) -> void:
		dialogues.append({"peer": peer_id, "kind": kind, "data": data})

	## Dados das atualizacoes de quest de um tipo para um peer, em ordem.
	func quest_msgs(peer_id: int, kind: int) -> Array[Dictionary]:
		var out: Array[Dictionary] = []
		for u: Dictionary in quest_updates:
			if int(u["peer"]) == peer_id and int(u["kind"]) == kind:
				out.append(u["data"])
		return out

	func dialogue_msgs(peer_id: int, kind: int) -> Array[Dictionary]:
		var out: Array[Dictionary] = []
		for u: Dictionary in dialogues:
			if int(u["peer"]) == peer_id and int(u["kind"]) == kind:
				out.append(u["data"])
		return out

	func send_welcome(peer_id: int, player_id: int, tick_rate: int, session_seed: int) -> void:
		welcomes.append({"peer": peer_id, "player_id": player_id, "tick_rate": tick_rate, "seed": session_seed})

	func send_reject(peer_id: int, code: int, message: String) -> void:
		rejects.append({"peer": peer_id, "code": code, "message": message})

	func send_snapshot(peer_id: int, server_tick: int, last_input_seq: int, entities: Array) -> void:
		snapshots.append({"peer": peer_id, "tick": server_tick, "last_seq": last_input_seq, "entities": entities})

	func send_event(peer_id: int, event_id: int, kind: int, data: Dictionary) -> void:
		events.append({"peer": peer_id, "id": event_id, "kind": kind, "data": data})

	func send_pong(peer_id: int, client_time_ms: int) -> void:
		pongs.append({"peer": peer_id, "t": client_time_ms})

	func disconnect_peer(peer_id: int) -> void:
		disconnects.append(peer_id)

	func reject_codes(peer_id: int) -> Array[int]:
		var out: Array[int] = []
		for r: Dictionary in rejects:
			if int(r["peer"]) == peer_id:
				out.append(int(r["code"]))
		return out

	func events_of(peer_id: int, kind: int) -> Array[Dictionary]:
		var out: Array[Dictionary] = []
		for e: Dictionary in events:
			if int(e["peer"]) == peer_id and int(e["kind"]) == kind:
				out.append(e)
		return out

	func all_events_of_kind(kind: int) -> Array[Dictionary]:
		var out: Array[Dictionary] = []
		for e: Dictionary in events:
			if int(e["kind"]) == kind:
				out.append(e)
		return out


class Rig extends RefCounted:
	var settings: ServerSettings
	var world: ServerWorld
	var session: ServerSession
	var transport: RecordingTransport
	var tree: SceneTree

	func free_all() -> void:
		session.shutdown()
		session.queue_free()
		world.queue_free()


## Monta mundo + sessao na arvore. `auto_tick` = a sessao avanca sozinha no physics_process.
static func make_rig(tree: SceneTree, spawn_enemies: bool = false, max_players: int = 4, auto_tick: bool = false, world_id: String = "") -> Rig:
	var rig: Rig = Rig.new()
	rig.tree = tree
	rig.settings = ServerSettings.new()
	rig.settings.world_id = world_id # E5.3: "greenwood" = mundo em zonas; "" = arena de teste
	rig.settings.spawn_enemies = spawn_enemies
	rig.settings.max_players = max_players
	rig.settings.session_seed = 12345
	rig.world = ServerWorld.new()
	rig.world.settings = rig.settings
	tree.root.add_child(rig.world)
	rig.session = ServerSession.new()
	tree.root.add_child(rig.session)
	rig.transport = RecordingTransport.new()
	rig.session.setup(rig.settings, rig.world, rig.transport)
	rig.session.set_physics_process(auto_tick)
	rig.session.test_now_msec = 1000
	return rig


## Conecta e envia um hello valido. Devolve o entity_id (0 se nao entrou).
static func join(rig: Rig, peer_id: int, player_name: String = "Tester") -> int:
	rig.session.on_peer_connected(peer_id)
	rig.session.on_hello(peer_id, Protocol.VERSION, "test", player_name, "")
	var st: ServerSession.PeerState = rig.session.get_peer_state(peer_id)
	return st.entity_id if st != null else 0
