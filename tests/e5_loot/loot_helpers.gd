extends RefCounted
## Utilitarios dos testes E5.4 (loot individual + crafting). Nao e um teste (sem prefixo test_).
## Servidor + sessao + BackendClient/BackendSync com backend FALSO, 1..4 jogadores com personagem.

const B = preload("res://tests/e4/backend_helpers.gd")
const Fake = preload("res://tests/e4/fake_backend.gd")

const CIDS: Array[String] = [
	"11111111-1111-4111-8111-111111111111", "22222222-2222-4222-8222-222222222222",
	"33333333-3333-4333-8333-333333333333", "44444444-4444-4444-8444-444444444444",
]
const TICKETS: Array[String] = [
	"eyJhbGciOiJIUzI1NiJ9.ticket-one-AAAA.sig_1", "eyJhbGciOiJIUzI1NiJ9.ticket-two-BBBB.sig_2",
	"eyJhbGciOiJIUzI1NiJ9.ticket-three-CCCC.sig_3", "eyJhbGciOiJIUzI1NiJ9.ticket-four-DDDD.sig_4",
]
const GRUNT: String = "res://scenes/enemy/melee_grunt.tscn"
const MINI_BOSS: String = "res://scenes/enemy/thorn_alpha.tscn"
## Perto da bancada do hub (data/areas/world/greenwood_world.json: estacao em (6, 0, -4), raio 3.5).
const STATION_POS: Vector3 = Vector3(6.0, 0.05, -4.0)
const FAR_POS: Vector3 = Vector3(-20.0, 0.05, 10.0)
const ENEMY_POS: Vector3 = Vector3(30.0, 0.05, 30.0)
const PEER0: int = 101


## Monta o servidor com `n` jogadores logados (peer 101..). world_id "" = arena; "greenwood" = mundo.
static func make(tree: SceneTree, n: int, world_id: String = "", individual: bool = true, inventories: Array = [], hold: bool = false) -> B.BRig:
	var rig: B.BRig = B.make(tree, hold, 4, world_id)
	rig.settings.individual_loot = individual
	rig.world.loot.base_seed = 777
	for i: int in n:
		var inv: Array = inventories[i] if i < inventories.size() else []
		rig.fake.add_character(CIDS[i], 1, 0, inv, {"weapon": "sword_basic", "armor": "armor_leather"}, 0, "Hero%d" % i)
		rig.fake.tickets[TICKETS[i]] = CIDS[i]
		B.hello(rig, PEER0 + i, TICKETS[i], "Hero%d" % i)
	return rig


static func eid(rig: B.BRig, i: int) -> int:
	var st: ServerSession.PeerState = rig.session.get_peer_state(PEER0 + i)
	return st.entity_id if st != null else 0


static func node(rig: B.BRig, i: int) -> Player:
	return rig.world.get_player_node(eid(rig, i))


static func loadout(rig: B.BRig, i: int) -> PlayerLoadout:
	return B.loadout_of(rig, PEER0 + i)


static func hit(enemy: Enemy, source: Node, amount: float) -> void:
	enemy.health.apply_damage(DamageInfo.make(amount, source, Hitbox.new_hit_id()))


static func spawn(rig: B.BRig, scene: String = GRUNT, pos: Vector3 = ENEMY_POS) -> Enemy:
	return rig.world.get_enemy_node(rig.world.spawn_enemy(scene, pos))


## Pickups do dono (ids ordenados).
static func pickups_of(rig: B.BRig, i: int) -> Array[LootManager.LootPickup]:
	return rig.world.loot.pickups_of(eid(rig, i))


## Itens [{item_id, qty}] (ordem do roll) que o dono `i` DEVERIA receber do inimigo `enemy_id` com a semente atual.
static func expected_drops(rig: B.BRig, table: LootTable, enemy_id: int, i: int) -> Array:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = LootManager.seed_for(rig.world.loot.base_seed, enemy_id, eid(rig, i))
	var out: Array = []
	for d: LootDrop in table.roll(rng):
		out.append({"item_id": String(d.item_id), "qty": d.quantity})
	return out


static func drops_of(pks: Array[LootManager.LootPickup]) -> Array:
	var out: Array = []
	for p: LootManager.LootPickup in pks:
		out.append({"item_id": p.item_id, "qty": p.qty})
	return out


## Procura uma semente-base em que TODOS os jogadores de `idxs` rolam algo contra `enemy_id` (testes que precisam de pickups).
static func seed_all_roll(rig: B.BRig, table: LootTable, enemy_id: int, idxs: Array) -> int:
	for base: int in range(1, 400):
		rig.world.loot.base_seed = base
		var all_ok: bool = true
		for i: Variant in idxs:
			if expected_drops(rig, table, enemy_id, int(i)).is_empty():
				all_ok = false
				break
		if all_ok:
			return base
	return -1


## Ids de pickup que aparecem no ULTIMO snapshot enviado ao peer.
static func snapshot_pickup_ids(rig: B.BRig, peer: int) -> Array[int]:
	var out: Array[int] = []
	for k: int in range(rig.transport.snapshots.size() - 1, -1, -1):
		var s: Dictionary = rig.transport.snapshots[k]
		if int(s["peer"]) != peer:
			continue
		for e: Variant in s["entities"]:
			if int((e as Dictionary)["kind"]) == Protocol.KIND_PICKUP:
				out.append(int((e as Dictionary)["id"]))
		break
	out.sort()
	return out


static func send_snapshots(rig: B.BRig) -> void:
	rig.transport.snapshots.clear()
	rig.session.send_snapshots()


static func total(ch: Dictionary, item_id: String) -> int:
	var n: int = 0
	for e: Variant in ch["inventory"]:
		if (e as Dictionary)["item_id"] == item_id:
			n += int((e as Dictionary)["qty"])
	return n
