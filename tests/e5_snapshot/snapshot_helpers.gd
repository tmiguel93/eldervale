extends RefCounted
## Utilitarios dos testes E5.7 (snapshot compacto). Nao e um teste (sem prefixo test_).

const POS_TOL: float = 0.0051   ## 0,5 cm por eixo (+ folga de float32)
const YAW_TOL: float = 5.0e-5   ## 2*PI/65536/2 = 4,8e-5


static func ent(id: int, kind: int, pos: Vector3, hp: float = 100.0, max_hp: float = 100.0, type: String = "melee_grunt", yaw: float = 0.0, state: int = 0, extra: Dictionary = {}) -> Dictionary:
	var d: Dictionary = {"id": id, "kind": kind, "pos": pos, "yaw": yaw, "hp": hp, "max_hp": max_hp, "state": state, "type": type}
	d.merge(extra, true)
	return d


static func player(id: int, pos: Vector3, hp: float = 100.0, max_hp: float = 100.0, yaw: float = 0.0) -> Dictionary:
	return ent(id, Protocol.KIND_PLAYER, pos, hp, max_hp, "player", yaw)


static func enemy(id: int, pos: Vector3, hp: float = 60.0, max_hp: float = 60.0, type: String = "melee_grunt", phase: int = 0, atk: String = "", state: int = 1) -> Dictionary:
	return ent(id, Protocol.KIND_ENEMY, pos, hp, max_hp, type, 0.3, state, {"phase": phase, "atk": atk})


static func pickup(id: int, pos: Vector3, item: String, qty: int) -> Dictionary:
	return ent(id, Protocol.KIND_PICKUP, pos, 0.0, 0.0, item, 0.0, 0, {"qty": qty})


## Conjunto realista de `n` entidades (>= 1): 4 jogadores no maximo, o resto inimigos de tipos variados, 1 chefe em fase 2.
static func crowd(n: int, seed_value: int = 7) -> Array:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	var types: Array[String] = ["melee_grunt", "bow_scout", "root_sprout", "forest_stalker", "ranged_caster", "bark_brute", "thorn_alpha"]
	var out: Array = []
	for i: int in n:
		var p: Vector3 = Vector3(rng.randf_range(-45.0, 45.0), rng.randf_range(0.0, 0.3), rng.randf_range(-45.0, 45.0))
		if i < mini(n, 4):
			out.append(player(i + 1, p, rng.randf_range(1.0, 150.0), 150.0, rng.randf_range(-PI, PI)))
		elif i == 4:
			out.append(enemy(i + 1, p, 3000.5, 4200.0, "blight_treant", 2, "slam"))
		else:
			out.append(enemy(i + 1, p, rng.randf_range(1.0, 80.0), 80.0, types[i % types.size()], 0, "swing" if i % 3 == 0 else "", i % 5))
	return out


## Tamanho aproximado (Variant) de UMA mensagem s_snapshot_c com `blob`.
static func msg_bytes(tick: int, last_seq: int, part: int, parts: int, blob: PackedByteArray) -> int:
	return var_to_bytes(tick).size() + var_to_bytes(last_seq).size() + var_to_bytes(part).size() + var_to_bytes(parts).size() + var_to_bytes(blob).size()


static func by_id(ents: Array) -> Dictionary:
	var m: Dictionary = {}
	for e: Variant in ents:
		m[int((e as Dictionary)["id"])] = e
	return m


## Compara uma entidade decodificada com a original dentro das tolerancias da quantizacao. "" se igual, senao o motivo.
static func diff(orig: Dictionary, got: Dictionary) -> String:
	for k: String in ["id", "kind", "state", "type"]:
		if orig[k] != got[k]:
			return "campo %s: %s != %s" % [k, orig[k], got[k]]
	var po: Vector3 = orig["pos"]
	var pg: Vector3 = got["pos"]
	if absf(po.x - pg.x) > POS_TOL or absf(po.y - pg.y) > POS_TOL or absf(po.z - pg.z) > POS_TOL:
		return "pos %s != %s" % [po, pg]
	if absf(angle_difference(float(orig["yaw"]), float(got["yaw"]))) > YAW_TOL:
		return "yaw %s != %s" % [orig["yaw"], got["yaw"]]
	var hp: float = float(orig["hp"])
	var want_hp: float = 0.0 if hp <= 0.0 else maxf(1.0, roundf(hp))
	if float(got["hp"]) != want_hp:
		return "hp %s -> %s (esperado %s)" % [hp, got["hp"], want_hp]
	var mx: float = float(orig["max_hp"])
	var want_mx: float = 0.0 if mx <= 0.0 else maxf(1.0, roundf(mx))
	if float(got["max_hp"]) != want_mx:
		return "max_hp %s -> %s" % [mx, got["max_hp"]]
	if int(orig["kind"]) == Protocol.KIND_ENEMY:
		if int(orig.get("phase", 0)) != int(got.get("phase", -1)) or String(orig.get("atk", "")) != String(got.get("atk", "?")):
			return "phase/atk %s/%s != %s/%s" % [orig.get("phase"), orig.get("atk"), got.get("phase"), got.get("atk")]
	elif got.has("phase") or got.has("atk"):
		return "phase/atk indevido em nao-inimigo"
	if int(orig["kind"]) == Protocol.KIND_PICKUP and int(orig["qty"]) != int(got.get("qty", -1)):
		return "qty"
	return ""


## Codifica tudo e junta as partes decodificadas (id -> entidade). {} se alguma parte falhar.
static func roundtrip(ents: Array, max_bytes: int = SnapshotCodec.MAX_PART_BYTES) -> Dictionary:
	var enc: Dictionary = SnapshotCodec.encode(ents, max_bytes)
	var all: Array = []
	for blob: PackedByteArray in enc["parts"]:
		var dec: Dictionary = SnapshotCodec.decode_part(blob)
		if not bool(dec["ok"]):
			return {}
		all.append_array(dec["entities"])
	return by_id(all)
