class_name NpcDirectory
extends RefCounted
## Diretorio de NPCs (data/npcs/*.json): id, dialogo, raio de interacao e posicao no mundo.
## As posicoes de Greenwood sao PLACEHOLDER ate o hub/vila (E5 world) existir; o servidor so usa
## `in_range` para validar a distancia do jogador (anti-teleporte de interacao).

const NPCS_DIR: String = "res://data/npcs"
const MAX_RADIUS: float = 20.0

static var _shared: NpcDirectory = null

var npcs: Dictionary = {}        ## id -> {id, display_name, dialogue_id, radius, position:Vector3, region}
var load_errors: Array[String] = []


static func shared() -> NpcDirectory:
	if _shared == null:
		_shared = load_dir(NPCS_DIR)
	return _shared


static func load_dir(dir_path: String = NPCS_DIR) -> NpcDirectory:
	var d: NpcDirectory = NpcDirectory.new()
	for n: String in JsonDir.list_json(dir_path):
		var r: Dictionary = JsonDir.read_json(dir_path + "/" + n)
		if not bool(r["ok"]):
			d.load_errors.append(String(r["error"]))
			continue
		var err: String = d.add_dict(r["data"])
		if not err.is_empty():
			d.load_errors.append("%s: %s" % [n, err])
		elif n.trim_suffix(".json") != String((r["data"] as Dictionary)["id"]):
			d.load_errors.append("%s: nome do arquivo difere do id" % n)
	return d


## Adiciona um NPC a partir do dicionario do JSON. Devolve "" ou o erro.
func add_dict(raw: Variant) -> String:
	if typeof(raw) != TYPE_DICTIONARY:
		return "raiz deve ser objeto"
	var d: Dictionary = raw
	if not Protocol.is_content_id(d.get("id", null)):
		return "id invalido"
	var id: String = d["id"]
	if npcs.has(id):
		return "id duplicado: " + id
	if typeof(d.get("display_name", null)) != TYPE_STRING or (d["display_name"] as String).is_empty():
		return "display_name ausente"
	var dlg: Variant = d.get("dialogue_id", "")
	if typeof(dlg) != TYPE_STRING or (not (dlg as String).is_empty() and not Protocol.is_content_id(dlg)):
		return "dialogue_id invalido"
	var radius: Variant = d.get("interact_radius", 3.0)
	if not Protocol.is_finite_number(radius) or float(radius) <= 0.0 or float(radius) > MAX_RADIUS:
		return "interact_radius fora de (0, %.0f]" % MAX_RADIUS
	var pos: Variant = d.get("position", null)
	if typeof(pos) != TYPE_ARRAY or (pos as Array).size() != 3:
		return "position deve ser [x, y, z]"
	for c: Variant in pos:
		if not Protocol.is_finite_number(c):
			return "position nao finita"
	npcs[id] = {
		"id": id, "display_name": d["display_name"], "dialogue_id": dlg, "radius": float(radius),
		"position": Vector3(float(pos[0]), float(pos[1]), float(pos[2])), "region": String(d.get("region", "")),
	}
	return ""


func has_npc(npc_id: String) -> bool:
	return npcs.has(npc_id)


func get_npc(npc_id: String) -> Dictionary:
	return npcs.get(npc_id, {})


func dialogue_id_of(npc_id: String) -> String:
	return String(get_npc(npc_id).get("dialogue_id", ""))


func ids() -> Array[String]:
	var out: Array[String] = []
	for k: Variant in npcs:
		out.append(String(k))
	out.sort()
	return out


## Distancia horizontal (XZ) do ponto ao NPC <= raio de interacao. NPC desconhecido = false.
func in_range(npc_id: String, pos: Vector3) -> bool:
	var n: Dictionary = get_npc(npc_id)
	if n.is_empty():
		return false
	var p: Vector3 = n["position"]
	return Vector2(pos.x - p.x, pos.z - p.z).length() <= float(n["radius"]) and absf(pos.y - p.y) <= 6.0
