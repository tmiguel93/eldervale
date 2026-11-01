class_name ZoneDef
extends RefCounted
## Definicao de uma zona do mundo (parse/validacao de uma entrada de `zones` em
## data/areas/world/<regiao>_world.json). Dados puros: coordenadas em MUNDO (absolutas), 1 unidade = 1 m.
## Os limites sao um retangulo no plano XZ (`center` +- `size`/2). Sem nos, sem fisica.

const MAX_SIZE: float = 400.0
const MAX_PROPS: int = 200
const MAX_ENEMIES: int = 60
const MAX_PLATES: int = 4

var id: String = ""
var display_name: String = ""
var center: Vector3 = Vector3.ZERO
var size: Vector2 = Vector2(60.0, 60.0)
## Zonas `sticky` ficam sempre carregadas (o hub nao tem inimigos nem estado a descarregar).
var sticky: bool = false
var floor_color: Color = Color(0.35, 0.4, 0.3)
var wall_color: Color = Color(0.45, 0.4, 0.35)
var spawns: Dictionary = {}          ## nome -> Array[Vector3]
var checkpoint: String = ""          ## nome de `spawns` usado no respawn
var portals: Array[Dictionary] = []  ## {id, pos:Vector3, radius, to_zone, to_spawn, label}
var npcs: Array[String] = []
var props: Array[Dictionary] = []    ## {kind, name, pos, ... , color:Color, occluder, collide}
var enemies: Array[Dictionary] = []  ## {type:StringName, pos:Vector3}
## {} = sem puzzle. {id, plates:[{pos:Vector3, radius}], latch_time, gate_pos:Vector3, gate_size:Vector3}
var puzzle: Dictionary = {}
## {} = sem chefe. {id, boss:StringName, spawn:Vector3, trigger_center:Vector3, trigger_radius}
var encounter: Dictionary = {}


## Devolve "" ou a descricao do primeiro erro.
func parse(raw: Variant) -> String:
	if typeof(raw) != TYPE_DICTIONARY:
		return "zona deve ser objeto"
	var d: Dictionary = raw
	if not Protocol.is_content_id(d.get("id", null)):
		return "id de zona invalido"
	id = String(d["id"])
	display_name = String(d.get("display_name", id))
	var c: Variant = _vec3(d.get("center", null))
	if c == null:
		return "%s: center deve ser [x, y, z]" % id
	center = c
	var sz: Variant = d.get("size", null)
	if typeof(sz) != TYPE_ARRAY or (sz as Array).size() != 2 or not Protocol.is_finite_number(sz[0]) or not Protocol.is_finite_number(sz[1]):
		return "%s: size deve ser [x, z]" % id
	size = Vector2(float(sz[0]), float(sz[1]))
	if size.x < 10.0 or size.y < 10.0 or size.x > MAX_SIZE or size.y > MAX_SIZE:
		return "%s: size fora de [10, %.0f]" % [id, MAX_SIZE]
	sticky = bool(d.get("sticky", false))
	floor_color = _color(d.get("floor_color", ""), floor_color)
	wall_color = _color(d.get("wall_color", ""), wall_color)
	var err: String = _parse_spawns(d)
	if err.is_empty():
		err = _parse_portals(d)
	if err.is_empty():
		err = _parse_props(d)
	if err.is_empty():
		err = _parse_enemies(d)
	if err.is_empty():
		err = _parse_puzzle(d)
	if err.is_empty():
		err = _parse_encounter(d)
	if err.is_empty():
		var ns: Variant = d.get("npcs", [])
		if typeof(ns) != TYPE_ARRAY:
			return "%s: npcs deve ser lista" % id
		for n: Variant in ns:
			if not Protocol.is_content_id(n):
				return "%s: npc invalido" % id
			npcs.append(String(n))
	return err


# ------------------------------------------------------------------ consulta

## Dentro do retangulo da zona (plano XZ), com margem opcional.
func contains(pos: Vector3, margin: float = 0.0) -> bool:
	return absf(pos.x - center.x) <= size.x * 0.5 + margin and absf(pos.z - center.z) <= size.y * 0.5 + margin


func spawn_names() -> Array[String]:
	var out: Array[String] = []
	for k: Variant in spawns:
		out.append(String(k))
	out.sort()
	return out


## Ponto de chegada `name` (indice rotativo para nao empilhar jogadores). Sem o nome: checkpoint.
func spawn_point(name: String, index: int = 0) -> Vector3:
	var list: Array = spawns.get(name, spawns.get(checkpoint, []))
	if list.is_empty():
		return center + Vector3(0.0, 0.05, 0.0)
	return list[posmod(index, list.size())] as Vector3


func checkpoint_point(index: int = 0) -> Vector3:
	return spawn_point(checkpoint, index)


func portal_by_id(portal_id: String) -> Dictionary:
	for p: Dictionary in portals:
		if String(p["id"]) == portal_id:
			return p
	return {}


# ------------------------------------------------------------------ parse (partes)

func _parse_spawns(d: Dictionary) -> String:
	var sp: Variant = d.get("spawns", null)
	if typeof(sp) != TYPE_DICTIONARY or (sp as Dictionary).is_empty():
		return "%s: spawns ausente" % id
	for k: Variant in sp:
		if not Protocol.is_content_id(k) or typeof(sp[k]) != TYPE_ARRAY or (sp[k] as Array).is_empty() or (sp[k] as Array).size() > 8:
			return "%s: spawn '%s' invalido (1..8 pontos)" % [id, str(k)]
		var pts: Array[Vector3] = []
		for p: Variant in sp[k]:
			var v: Variant = _vec3(p)
			if v == null:
				return "%s: ponto de spawn invalido em '%s'" % [id, str(k)]
			pts.append(v)
		spawns[String(k)] = pts
	checkpoint = String(d.get("checkpoint", ""))
	if not spawns.has(checkpoint):
		return "%s: checkpoint '%s' nao existe em spawns" % [id, checkpoint]
	return ""


func _parse_portals(d: Dictionary) -> String:
	var ps: Variant = d.get("portals", [])
	if typeof(ps) != TYPE_ARRAY:
		return "%s: portals deve ser lista" % id
	for raw: Variant in ps:
		if typeof(raw) != TYPE_DICTIONARY:
			return "%s: portal invalido" % id
		var p: Dictionary = raw
		var pos: Variant = _vec3(p.get("pos", null))
		var radius: Variant = p.get("radius", null)
		if not Protocol.is_content_id(p.get("id", null)) or pos == null or not Protocol.is_finite_number(radius) or float(radius) < 0.5 or float(radius) > 10.0:
			return "%s: portal invalido (id/pos/radius)" % id
		if not Protocol.is_content_id(p.get("to_zone", null)) or not Protocol.is_content_id(p.get("to_spawn", null)):
			return "%s: portal %s sem to_zone/to_spawn validos" % [id, String(p["id"])]
		portals.append({"id": String(p["id"]), "pos": pos, "radius": float(radius), "to_zone": String(p["to_zone"]),
			"to_spawn": String(p["to_spawn"]), "label": String(p.get("label", ""))})
	return ""


func _parse_props(d: Dictionary) -> String:
	var ps: Variant = d.get("props", [])
	if typeof(ps) != TYPE_ARRAY or (ps as Array).size() > MAX_PROPS:
		return "%s: props invalido (max %d)" % [id, MAX_PROPS]
	for raw: Variant in ps:
		if typeof(raw) != TYPE_DICTIONARY:
			return "%s: prop invalido" % id
		var p: Dictionary = raw
		var kind: String = String(p.get("kind", ""))
		var pos: Variant = _vec3(p.get("pos", null))
		if pos == null or not ["box", "cylinder", "tree"].has(kind) or typeof(p.get("name", null)) != TYPE_STRING:
			return "%s: prop invalido (kind/pos/name)" % id
		var prop: Dictionary = {"kind": kind, "name": String(p["name"]), "pos": pos,
			"color": _color(p.get("color", ""), Color(0.5, 0.5, 0.5)), "occluder": bool(p.get("occluder", false)), "collide": bool(p.get("collide", true))}
		if kind == "box":
			var s: Variant = _vec3(p.get("size", null))
			if s == null or (s as Vector3).x <= 0.0 or (s as Vector3).y <= 0.0 or (s as Vector3).z <= 0.0:
				return "%s: prop %s sem size valido" % [id, String(p["name"])]
			prop["size"] = s
		elif kind == "cylinder":
			if not Protocol.is_finite_number(p.get("radius", null)) or not Protocol.is_finite_number(p.get("height", null)) or float(p["radius"]) <= 0.0 or float(p["height"]) <= 0.0:
				return "%s: prop %s sem radius/height validos" % [id, String(p["name"])]
			prop["radius"] = float(p["radius"])
			prop["height"] = float(p["height"])
		else:
			prop["occluder"] = bool(p.get("occluder", true))
		props.append(prop)
	return ""


func _parse_enemies(d: Dictionary) -> String:
	var es: Variant = d.get("enemies", [])
	if typeof(es) != TYPE_ARRAY or (es as Array).size() > MAX_ENEMIES:
		return "%s: enemies invalido (max %d)" % [id, MAX_ENEMIES]
	for raw: Variant in es:
		if typeof(raw) != TYPE_DICTIONARY:
			return "%s: inimigo invalido" % id
		var e: Dictionary = raw
		var pos: Variant = _vec3(e.get("pos", null))
		if not EnemyCatalog.is_valid_id(String(e.get("type", ""))) or pos == null:
			return "%s: inimigo invalido (type/pos)" % id
		enemies.append({"type": StringName(String(e["type"])), "pos": pos})
	return ""


func _parse_puzzle(d: Dictionary) -> String:
	if not d.has("puzzle"):
		return ""
	var p: Variant = d["puzzle"]
	if typeof(p) != TYPE_DICTIONARY:
		return "%s: puzzle deve ser objeto" % id
	var pd: Dictionary = p
	var plates_raw: Variant = pd.get("plates", null)
	if not Protocol.is_content_id(pd.get("id", null)) or typeof(plates_raw) != TYPE_ARRAY or (plates_raw as Array).size() < 1 or (plates_raw as Array).size() > MAX_PLATES:
		return "%s: puzzle invalido (id/plates 1..%d)" % [id, MAX_PLATES]
	var plates: Array[Dictionary] = []
	for pr: Variant in plates_raw:
		if typeof(pr) != TYPE_DICTIONARY:
			return "%s: placa invalida" % id
		var pos: Variant = _vec3((pr as Dictionary).get("pos", null))
		var radius: Variant = (pr as Dictionary).get("radius", null)
		if pos == null or not Protocol.is_finite_number(radius) or float(radius) < 0.5 or float(radius) > 6.0:
			return "%s: placa invalida (pos/radius)" % id
		plates.append({"pos": pos, "radius": float(radius)})
	var latch: Variant = pd.get("latch_time", 10.0)
	var gp: Variant = _vec3(pd.get("gate_pos", null))
	var gs: Variant = _vec3(pd.get("gate_size", null))
	if not Protocol.is_finite_number(latch) or float(latch) < 0.0 or float(latch) > 120.0 or gp == null or gs == null:
		return "%s: puzzle invalido (latch_time/gate)" % id
	puzzle = {"id": String(pd["id"]), "plates": plates, "latch_time": float(latch), "gate_pos": gp, "gate_size": gs}
	return ""


func _parse_encounter(d: Dictionary) -> String:
	if not d.has("encounter"):
		return ""
	var e: Variant = d["encounter"]
	if typeof(e) != TYPE_DICTIONARY:
		return "%s: encounter deve ser objeto" % id
	var ed: Dictionary = e
	var sp: Variant = _vec3(ed.get("spawn", null))
	var tc: Variant = _vec3(ed.get("trigger_center", null))
	var tr: Variant = ed.get("trigger_radius", null)
	if not Protocol.is_content_id(ed.get("id", null)) or not EnemyCatalog.is_valid_id(String(ed.get("boss", ""))) or sp == null or tc == null \
			or not Protocol.is_finite_number(tr) or float(tr) <= 0.0 or float(tr) > 60.0:
		return "%s: encounter invalido" % id
	encounter = {"id": String(ed["id"]), "boss": StringName(String(ed["boss"])), "spawn": sp, "trigger_center": tc, "trigger_radius": float(tr)}
	return ""


static func _vec3(v: Variant) -> Variant:
	if typeof(v) != TYPE_ARRAY or (v as Array).size() != 3:
		return null
	for c: Variant in v:
		if not Protocol.is_finite_number(c):
			return null
	return Vector3(float(v[0]), float(v[1]), float(v[2]))


static func _color(v: Variant, fallback: Color) -> Color:
	if typeof(v) == TYPE_STRING and (v as String).begins_with("#") and Color.html_is_valid(v):
		return Color.html(v)
	return fallback
