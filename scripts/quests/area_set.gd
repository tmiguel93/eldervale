class_name AreaSet
extends RefCounted
## Areas de gatilho (data/areas/*.json): cilindros {id, center, radius, height}. Posicoes de Greenwood
## sao PLACEHOLDER ate as ruinas existirem. Usado pelo AreaWatcher (servidor) para o objetivo reach_area.

const AREAS_DIR: String = "res://data/areas"

static var _shared: AreaSet = null

var areas: Dictionary = {}       ## id -> {id, center:Vector3, radius:float, height:float}
var load_errors: Array[String] = []


static func shared() -> AreaSet:
	if _shared == null:
		_shared = load_dir(AREAS_DIR)
	return _shared


static func load_dir(dir_path: String = AREAS_DIR) -> AreaSet:
	var s: AreaSet = AreaSet.new()
	for n: String in JsonDir.list_json(dir_path):
		var r: Dictionary = JsonDir.read_json(dir_path + "/" + n)
		if not bool(r["ok"]):
			s.load_errors.append(String(r["error"]))
			continue
		if typeof(r["data"]) != TYPE_DICTIONARY or typeof((r["data"] as Dictionary).get("areas", null)) != TYPE_ARRAY:
			s.load_errors.append("%s: 'areas' ausente" % n)
			continue
		for a: Variant in (r["data"] as Dictionary)["areas"]:
			var err: String = s.add_dict(a)
			if not err.is_empty():
				s.load_errors.append("%s: %s" % [n, err])
	return s


func add_dict(raw: Variant) -> String:
	if typeof(raw) != TYPE_DICTIONARY:
		return "area invalida"
	var d: Dictionary = raw
	if not Protocol.is_content_id(d.get("id", null)):
		return "id de area invalido"
	var id: String = d["id"]
	if areas.has(id):
		return "area duplicada: " + id
	var c: Variant = d.get("center", null)
	if typeof(c) != TYPE_ARRAY or (c as Array).size() != 3:
		return "%s: center deve ser [x, y, z]" % id
	for v: Variant in c:
		if not Protocol.is_finite_number(v):
			return "%s: center nao finito" % id
	var radius: Variant = d.get("radius", null)
	var height: Variant = d.get("height", 6.0)
	if not Protocol.is_finite_number(radius) or float(radius) <= 0.0 or float(radius) > 200.0:
		return "%s: radius fora de (0, 200]" % id
	if not Protocol.is_finite_number(height) or float(height) <= 0.0 or float(height) > 200.0:
		return "%s: height fora de (0, 200]" % id
	areas[id] = {
		"id": id, "center": Vector3(float(c[0]), float(c[1]), float(c[2])),
		"radius": float(radius), "height": float(height),
	}
	return ""


func has_area(area_id: String) -> bool:
	return areas.has(area_id)


func ids() -> Array[String]:
	var out: Array[String] = []
	for k: Variant in areas:
		out.append(String(k))
	out.sort()
	return out


func contains(area_id: String, pos: Vector3) -> bool:
	var a: Dictionary = areas.get(area_id, {})
	if a.is_empty():
		return false
	var c: Vector3 = a["center"]
	return Vector2(pos.x - c.x, pos.z - c.z).length() <= float(a["radius"]) and absf(pos.y - c.y) <= float(a["height"])
