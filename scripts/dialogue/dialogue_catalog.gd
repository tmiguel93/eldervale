class_name DialogueCatalog
extends RefCounted
## Dialogos carregados de data/dialogues/*.json. Um dialogo por NPC (`for_npc`).

const DIALOGUES_DIR: String = "res://data/dialogues"

static var _shared: DialogueCatalog = null

var dialogues: Dictionary = {}   ## id -> DialogueDef
var load_errors: Array[String] = []


static func shared() -> DialogueCatalog:
	if _shared == null:
		_shared = load_dir(DIALOGUES_DIR, QuestCatalog.shared().ids())
	return _shared


static func load_dir(dir_path: String = DIALOGUES_DIR, known_quests: Array = []) -> DialogueCatalog:
	var c: DialogueCatalog = DialogueCatalog.new()
	for n: String in JsonDir.list_json(dir_path):
		var r: Dictionary = JsonDir.read_json(dir_path + "/" + n)
		if not bool(r["ok"]):
			c.load_errors.append(String(r["error"]))
			continue
		var p: Dictionary = DialogueDef.parse(r["data"], known_quests)
		if p["def"] == null:
			for e: String in (p["errors"] as Array):
				c.load_errors.append("%s: %s" % [n, e])
			continue
		c.add(p["def"], n)
	return c


func add(def: DialogueDef, file_name: String = "") -> void:
	if dialogues.has(def.id):
		load_errors.append("dialogo id duplicado: " + def.id)
		return
	if not file_name.is_empty() and file_name.trim_suffix(".json") != def.id:
		load_errors.append("%s: nome do arquivo difere do id" % file_name)
		return
	dialogues[def.id] = def


func get_dialogue(dialogue_id: String) -> DialogueDef:
	return dialogues.get(dialogue_id) as DialogueDef


func for_npc(npc_id: String) -> DialogueDef:
	for id: Variant in dialogues:
		if (dialogues[id] as DialogueDef).npc_id == npc_id:
			return dialogues[id]
	return null


func ids() -> Array[String]:
	var out: Array[String] = []
	for k: Variant in dialogues:
		out.append(String(k))
	out.sort()
	return out
