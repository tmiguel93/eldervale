class_name ExplorationCatalog
extends RefCounted
## Pontos de exploracao (E6.4, data/exploration/*.json): marcos, baus e segredos descobertos por PROXIMIDADE.
## Logica pura de dados; o servidor (QuestService.tick) usa a posicao AUTORITATIVA do jogador, nunca a do cliente.
## Cada ponto e descoberto uma unica vez por personagem (recompensa unica, chave `explore:<poi_id>:<personagem>`).
## Espelha tools/gen_quests_catalog.mjs (validateExploration) e backend/src/quests/catalog.ts.

const DIR: String = "res://data/exploration"
const KINDS: Array[String] = ["landmark", "chest", "secret"]
const MAX_XP: int = 5000
const MAX_ITEMS: int = 4
const MAX_QTY: int = 20

static var _shared: ExplorationCatalog = null

var points: Dictionary = {}     ## id -> {id, kind, zone, display_name, text, center:Vector3, radius, height, min_level, requires_quests:Array[String], xp, items:Array}
var load_errors: Array[String] = []


static func shared() -> ExplorationCatalog:
	if _shared == null:
		_shared = load_dir(DIR)
	return _shared


static func load_dir(dir_path: String = DIR) -> ExplorationCatalog:
	var c: ExplorationCatalog = ExplorationCatalog.new()
	for n: String in JsonDir.list_json(dir_path):
		var r: Dictionary = JsonDir.read_json(dir_path + "/" + n)
		if not bool(r["ok"]):
			c.load_errors.append(String(r["error"]))
			continue
		if typeof(r["data"]) != TYPE_DICTIONARY or typeof((r["data"] as Dictionary).get("points", null)) != TYPE_ARRAY:
			c.load_errors.append("%s: 'points' ausente" % n)
			continue
		for p: Variant in (r["data"] as Dictionary)["points"]:
			var err: String = c.add_dict(p)
			if not err.is_empty():
				c.load_errors.append("%s: %s" % [n, err])
	return c


## Valida e adiciona um ponto. Devolve "" ou o erro.
func add_dict(raw: Variant) -> String:
	if typeof(raw) != TYPE_DICTIONARY:
		return "ponto invalido"
	var d: Dictionary = raw
	if not Protocol.is_content_id(d.get("id", null)):
		return "id de ponto invalido"
	var id: String = d["id"]
	if points.has(id):
		return "ponto duplicado: " + id
	var w: String = "ponto '%s'" % id
	if not KINDS.has(String(d.get("kind", ""))):
		return "%s: kind invalido" % w
	if not Protocol.is_content_id(d.get("zone", null)):
		return "%s: zone invalida" % w
	for k: String in ["display_name", "text"]:
		if typeof(d.get(k, null)) != TYPE_STRING or (d[k] as String).strip_edges().is_empty() or (d[k] as String).length() > 200:
			return "%s: '%s' ausente/vazio/longo demais" % [w, k]
	var c: Variant = d.get("center", null)
	if typeof(c) != TYPE_ARRAY or (c as Array).size() != 3:
		return "%s: center deve ser [x, y, z]" % w
	for v: Variant in c:
		if not Protocol.is_finite_number(v):
			return "%s: center nao finito" % w
	var radius: Variant = d.get("radius", null)
	var height: Variant = d.get("height", 4.0)
	if not Protocol.is_finite_number(radius) or float(radius) <= 0.0 or float(radius) > 20.0:
		return "%s: radius fora de (0, 20]" % w
	if not Protocol.is_finite_number(height) or float(height) <= 0.0 or float(height) > 20.0:
		return "%s: height fora de (0, 20]" % w
	var ml: Variant = d.get("min_level", 1)
	if not QuestDef._is_int(ml) or int(ml) < 1 or int(ml) > CharacterProgress.MAX_LEVEL:
		return "%s: min_level fora de 1..%d" % [w, CharacterProgress.MAX_LEVEL]
	var req: Array[String] = []
	var rq: Variant = d.get("requires_quests", [])
	if typeof(rq) != TYPE_ARRAY:
		return "%s: requires_quests deve ser lista" % w
	for q: Variant in rq:
		if not Protocol.is_content_id(q) or req.has(String(q)):
			return "%s: requires_quests invalido/duplicado" % w
		req.append(String(q))
	var rw: Variant = d.get("rewards", null)
	if typeof(rw) != TYPE_DICTIONARY:
		return "%s: rewards deve ser objeto" % w
	var xp: Variant = (rw as Dictionary).get("xp", 0)
	if not QuestDef._is_int(xp) or int(xp) < 0 or int(xp) > MAX_XP:
		return "%s: rewards.xp fora de 0..%d" % [w, MAX_XP]
	var items: Array = []
	var its: Variant = (rw as Dictionary).get("items", [])
	if typeof(its) != TYPE_ARRAY or (its as Array).size() > MAX_ITEMS:
		return "%s: rewards.items deve ser lista de ate %d" % [w, MAX_ITEMS]
	var seen: Dictionary = {}
	for it: Variant in its:
		if typeof(it) != TYPE_DICTIONARY or not Protocol.is_content_id((it as Dictionary).get("item_id", null)):
			return "%s: item de recompensa invalido" % w
		var qty: Variant = (it as Dictionary).get("qty", 0)
		if not QuestDef._is_int(qty) or int(qty) < 1 or int(qty) > MAX_QTY:
			return "%s: qty fora de 1..%d" % [w, MAX_QTY]
		var iid: String = (it as Dictionary)["item_id"]
		if seen.has(iid):
			return "%s: item repetido" % w
		seen[iid] = true
		items.append({"item_id": iid, "qty": int(qty)})
	if int(xp) == 0 and items.is_empty():
		return "%s: recompensa vazia" % w
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a["item_id"]) < String(b["item_id"]))
	points[id] = {
		"id": id, "kind": String(d["kind"]), "zone": String(d["zone"]), "display_name": String(d["display_name"]), "text": String(d["text"]),
		"center": Vector3(float(c[0]), float(c[1]), float(c[2])), "radius": float(radius), "height": float(height),
		"min_level": int(ml), "requires_quests": req, "xp": int(xp), "items": items,
	}
	return ""


func has_point(poi_id: String) -> bool:
	return points.has(poi_id)


func get_point(poi_id: String) -> Dictionary:
	return points.get(poi_id, {})


func ids() -> Array[String]:
	var out: Array[String] = []
	for k: Variant in points:
		out.append(String(k))
	out.sort()
	return out


## Cilindro de descoberta (distancia horizontal + altura).
func contains(poi_id: String, pos: Vector3) -> bool:
	var p: Dictionary = get_point(poi_id)
	if p.is_empty():
		return false
	var c: Vector3 = p["center"]
	return Vector2(pos.x - c.x, pos.z - c.z).length() <= float(p["radius"]) and absf(pos.y - c.y) <= float(p["height"])


## Referencias cruzadas: zonas (e posicao dentro do retangulo da zona), itens, quests exigidas.
func validate_refs(registry: ContentRegistry, world: WorldDef, quest_catalog: QuestCatalog) -> Array[String]:
	var errs: Array[String] = load_errors.duplicate()
	for id: String in ids():
		var p: Dictionary = points[id]
		var w: String = "ponto '%s'" % id
		var z: ZoneDef = world.get_zone(String(p["zone"])) if world != null else null
		if z == null:
			errs.append("%s: zona '%s' inexistente" % [w, p["zone"]])
		elif not z.contains(p["center"] as Vector3, -1.0):
			errs.append("%s: fora da zona '%s'" % [w, p["zone"]])
		for it: Dictionary in (p["items"] as Array):
			if not registry.items.has(StringName(it["item_id"])):
				errs.append("%s: item de recompensa '%s' inexistente" % [w, it["item_id"]])
		for q: String in (p["requires_quests"] as Array):
			if quest_catalog.get_quest(q) == null:
				errs.append("%s: quest exigida '%s' inexistente" % [w, q])
	return errs
