class_name QuestCatalog
extends RefCounted
## Catalogo de quests carregado de data/quests/*.json (arquivos que comecam com "_" sao ignorados;
## `_pending_refs.json` lista ids referenciados que ainda nao existem em data/).
## `validate_refs` confere as referencias cruzadas (itens, inimigos, NPCs, areas, prerequisitos).

const QUESTS_DIR: String = "res://data/quests"
const PENDING_REFS_PATH: String = "res://data/quests/_pending_refs.json"

static var _shared: QuestCatalog = null

var quests: Dictionary = {}       ## id -> QuestDef
var load_errors: Array[String] = []


## Catalogo padrao (cache de processo). Testes que precisam de outro catalogo usam load_dir/add.
static func shared() -> QuestCatalog:
	if _shared == null:
		_shared = load_dir(QUESTS_DIR)
	return _shared


static func load_dir(dir_path: String = QUESTS_DIR) -> QuestCatalog:
	var c: QuestCatalog = QuestCatalog.new()
	for n: String in JsonDir.list_json(dir_path):
		var r: Dictionary = JsonDir.read_json(dir_path + "/" + n)
		if not bool(r["ok"]):
			c.load_errors.append(String(r["error"]))
			continue
		var p: Dictionary = QuestDef.parse(r["data"])
		if p["def"] == null:
			for e: String in (p["errors"] as Array):
				c.load_errors.append("%s: %s" % [n, e])
			continue
		var def: QuestDef = p["def"]
		if n.trim_suffix(".json") != def.id:
			c.load_errors.append("%s: nome do arquivo difere do id '%s'" % [n, def.id])
			continue
		c.add(def)
	return c


func add(def: QuestDef) -> void:
	if quests.has(def.id):
		load_errors.append("quest id duplicado: " + def.id)
		return
	quests[def.id] = def


func get_quest(quest_id: String) -> QuestDef:
	return quests.get(quest_id) as QuestDef


func ids() -> Array[String]:
	var out: Array[String] = []
	for k: Variant in quests:
		out.append(String(k))
	out.sort()
	return out


func quests_of_npc(npc_id: String) -> Array[QuestDef]:
	var out: Array[QuestDef] = []
	for id: String in ids():
		var q: QuestDef = quests[id]
		if q.giver_npc == npc_id or q.turn_in_npc == npc_id:
			out.append(q)
	return out


## Ids pendentes ({"enemies": [...], "items": [...]}) de data/quests/_pending_refs.json.
static func load_pending_refs(path: String = PENDING_REFS_PATH) -> Dictionary:
	var out: Dictionary = {"enemies": [] as Array[String], "items": [] as Array[String]}
	var r: Dictionary = JsonDir.read_json(path)
	if not bool(r["ok"]) or typeof(r["data"]) != TYPE_DICTIONARY:
		return out
	for key: String in ["enemies", "items"]:
		var arr: Variant = (r["data"] as Dictionary).get(key, [])
		if typeof(arr) == TYPE_ARRAY:
			for e: Variant in arr:
				if typeof(e) == TYPE_STRING:
					(out[key] as Array[String]).append(e)
	return out


## Referencias cruzadas. `pending` = resultado de load_pending_refs (ids aceitos mesmo sem existir).
## Devolve a lista de erros (vazia = consistente). Detecta ciclos de prerequisitos.
func validate_refs(registry: ContentRegistry, npcs: NpcDirectory, areas: AreaSet, pending: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	errors.append_array(load_errors)
	var pending_enemies: Array = pending.get("enemies", [])
	var pending_items: Array = pending.get("items", [])
	for id: String in ids():
		var q: QuestDef = quests[id]
		var w: String = "quest '%s'" % id
		if not npcs.has_npc(q.giver_npc):
			errors.append("%s: giver_npc '%s' inexistente" % [w, q.giver_npc])
		if not npcs.has_npc(q.turn_in_npc):
			errors.append("%s: turn_in_npc '%s' inexistente" % [w, q.turn_in_npc])
		for pre: String in q.prereq_quests:
			if not quests.has(pre):
				errors.append("%s: prerequisito '%s' inexistente" % [w, pre])
			elif pre == id:
				errors.append("%s: prerequisito de si mesma" % w)
		for o: QuestDef.Objective in q.objectives:
			var ow: String = "%s objetivo '%s'" % [w, o.id]
			match o.type:
				QuestDef.OBJ_KILL:
					if not registry.enemies.has(StringName(o.target)) and not pending_enemies.has(o.target):
						errors.append("%s: inimigo '%s' inexistente e nao listado como pendente" % [ow, o.target])
				QuestDef.OBJ_COLLECT:
					if not registry.items.has(StringName(o.target)) and not pending_items.has(o.target):
						errors.append("%s: item '%s' inexistente e nao listado como pendente" % [ow, o.target])
				QuestDef.OBJ_REACH_AREA:
					if not areas.has_area(o.target):
						errors.append("%s: area '%s' inexistente" % [ow, o.target])
				QuestDef.OBJ_TALK:
					if not npcs.has_npc(o.target):
						errors.append("%s: npc '%s' inexistente" % [ow, o.target])
		for it: Dictionary in q.reward_items:
			if not registry.items.has(StringName(it["item_id"])) and not pending_items.has(it["item_id"]):
				errors.append("%s: item de recompensa '%s' inexistente" % [w, it["item_id"]])
	for id: String in ids():
		if _has_prereq_cycle(id):
			errors.append("quest '%s': ciclo de prerequisitos" % id)
	return errors


func _has_prereq_cycle(start: String) -> bool:
	var stack: Array[String] = [start]
	var visited: Dictionary = {}
	while not stack.is_empty():
		var cur: String = stack.pop_back()
		var q: QuestDef = get_quest(cur)
		if q == null:
			continue
		for pre: String in q.prereq_quests:
			if pre == start:
				return true
			if not visited.has(pre):
				visited[pre] = true
				stack.append(pre)
	return false
