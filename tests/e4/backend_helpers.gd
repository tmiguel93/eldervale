extends RefCounted
## Utilitarios dos testes E4 (servidor <-> backend com transporte FALSO; sem rede real).

const H = preload("res://tests/e3/server_helpers.gd")
const Fake = preload("res://tests/e4/fake_backend.gd")
const SECRET: String = "sekret-token-abc123"
const CID1: String = "11111111-1111-4111-8111-111111111111"
const CID2: String = "22222222-2222-4222-8222-222222222222"
const TICKET1: String = "eyJhbGciOiJIUzI1NiJ9.ticket-one-AAAA.sig_1"
const TICKET2: String = "eyJhbGciOiJIUzI1NiJ9.ticket-two-BBBB.sig_2"


class BRig extends RefCounted:
	var base: H.Rig
	var fake: Fake
	var client: BackendClient
	var sync: BackendSync
	var world: ServerWorld
	var session: ServerSession
	var transport: H.RecordingTransport
	var settings: ServerSettings

	func free_all() -> void:
		client.cancel_all()
		session.queue_free()
		world.queue_free()
		sync.queue_free()
		client.queue_free()


## Monta mundo + sessao + BackendClient + BackendSync com o backend falso. Registra a sessao.
static func make(tree: SceneTree, hold: bool = false, max_players: int = 4) -> BRig:
	var r: BRig = BRig.new()
	r.base = H.make_rig(tree, false, max_players, false)
	r.world = r.base.world
	r.session = r.base.session
	r.transport = r.base.transport
	r.settings = r.base.settings
	r.fake = Fake.new()
	r.client = BackendClient.new()
	tree.root.add_child(r.client)
	r.client.transport = r.fake
	r.client.backoff_base_sec = 0.0
	r.client.backoff_max_sec = 0.0
	var err: String = r.client.configure("http://127.0.0.1:8787", SECRET)
	assert(err.is_empty())
	r.sync = BackendSync.new()
	r.sync.client = r.client
	r.sync.capacity = max_players
	r.sync.heartbeat_interval_sec = 10.0
	r.sync.autosave_interval_sec = 30.0
	tree.root.add_child(r.sync)
	r.sync.set_process(false) # tempo controlado por tick() nos testes
	r.session.attach_backend(r.sync)
	r.sync.start()
	r.fake.hold = hold
	return r


static func hello(rig: BRig, peer_id: int, ticket: Variant, player_name: String = "Tester") -> void:
	rig.session.on_peer_connected(peer_id)
	rig.session.on_hello(peer_id, Protocol.VERSION, "test", player_name, ticket)


static func loadout_of(rig: BRig, peer_id: int) -> PlayerLoadout:
	var st: ServerSession.PeerState = rig.session.get_peer_state(peer_id)
	if st == null or st.entity_id == 0:
		return null
	return PlayerLoadout.find_for(rig.world.get_player_node(st.entity_id))
