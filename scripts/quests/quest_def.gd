class_name QuestDef
extends RefCounted
## Definicao estatica de uma quest (data/quests/<id>.json; schema em shared/content_schemas/quest.schema.json).
## Logica pura: `parse` valida o dicionario e devolve {def, errors}; nenhum acesso a disco/rede.
## Ids sao estaveis (AGENTS 8): `[a-z][a-z0-9_]{0,47}`. Textos tem `*_key` para traducao futura.

const SCHEMA_VERSION: int = 1
const TYPES: Array[String] = ["main", "side", "exploration", "hunt", "gather", "dungeon", "story", "coop", "hidden"]
const OBJ_KILL: String = "kill"
const OBJ_COLLECT: String = "collect"
const OBJ_REACH_AREA: String = "reach_area"
const OBJ_TALK: String = "talk"
const OBJECTIVE_TYPES: Array[String] = [OBJ_KILL, OBJ_COLLECT, OBJ_REACH_AREA, OBJ_TALK]
const MAX_OBJECTIVES: int = 6
const MAX_REQUIRED: int = 999
const MAX_REWARD_XP: int = 100000
const MAX_REWARD_ITEMS: int = 8
const MAX_REWARD_QTY: int = 99
const MAX_TEXT: int = 400


class Objective extends RefCounted:
	var id: String = ""
	var type: String = ""
	var target: String = ""
	var required: int = 1
	var text: String = ""
	var text_key: String = ""


var id: String = ""
var type: String = "side"
var region: String = ""
var title: String = ""
var title_key: String = ""
var description: String = ""
var description_key: String = ""
var giver_npc: String = ""
var turn_in_npc: String = ""
var prereq_quests: Array[String] = []
var min_level: int = 1
var objectives: Array[Objective] = []
var reward_xp: int = 0
var reward_items: Array[Dictionary] = [] ## [{item_id: String, qty: int}]
var abandonable: bool = true


func objective(objective_id: String) -> Objective:
	for o: Objective in objectives:
		if o.id == objective_id:
			return o
	return null


func objective_ids() -> Array[String]:
	var out: Array[String] = []
	for o: Objective in objectives:
		out.append(o.id)
	return out


## Dicionario {xp, items} da recompensa (copia).
func rewards() -> Dictionary:
	return {"xp": reward_xp, "items": reward_items.duplicate(true)}


static func _is_int(v: Variant) -> bool:
	if typeof(v) == TYPE_INT:
		return true
	return typeof(v) == TYPE_FLOAT and Protocol.is_finite_number(v) and absf(float(v) - roundf(float(v))) < 0.000001 and absf(float(v)) < 1.0e9


static func _str(d: Dictionary, key: String, errors: Array[String], where: String, max_len: int = MAX_TEXT, required: bool = true) -> String:
	if not d.has(key):
		if required:
			errors.append("%s: campo '%s' ausente" % [where, key])
		return ""
	if typeof(d[key]) != TYPE_STRING:
		errors.append("%s: '%s' deve ser string" % [where, key])
		return ""
	var s: String = d[key]
	if s.length() > max_len or (required and s.strip_edges().is_empty()):
		errors.append("%s: '%s' vazio ou longo demais" % [where, key])
		return ""
	return s


static func _id_field(d: Dictionary, key: String, errors: Array[String], where: String) -> String:
	var s: String = _str(d, key, errors, where, 48)
	if not s.is_empty() and not Protocol.is_content_id(s):
		errors.append("%s: '%s' = '%s' nao e um id valido ([a-z][a-z0-9_]*)" % [where, key, s.substr(0, 48)])
		return ""
	return s


## Valida e constroi. Retorna {"def": QuestDef | null, "errors": Array[String]}.
static func parse(raw: Variant) -> Dictionary:
	var errors: Array[String] = []
	if typeof(raw) != TYPE_DICTIONARY:
		return {"def": null, "errors": ["quest: raiz deve ser um objeto"] as Array[String]}
	var d: Dictionary = raw
	var q: QuestDef = QuestDef.new()
	q.id = _id_field(d, "id", errors, "quest")
	var where: String = "quest '%s'" % q.id
	if not d.has("schema_version") or not _is_int(d["schema_version"]) or int(d["schema_version"]) != SCHEMA_VERSION:
		errors.append("%s: schema_version deve ser %d" % [where, SCHEMA_VERSION])
	q.type = _str(d, "type", errors, where, 24)
	if not q.type.is_empty() and not TYPES.has(q.type):
		errors.append("%s: type '%s' invalido" % [where, q.type])
	q.region = _id_field(d, "region", errors, where)
	q.title = _str(d, "title", errors, where, 80)
	q.title_key = _str(d, "title_key", errors, where, 96)
	q.description = _str(d, "description", errors, where)
	q.description_key = _str(d, "description_key", errors, where, 96)
	q.giver_npc = _id_field(d, "giver_npc", errors, where)
	q.turn_in_npc = _id_field(d, "turn_in_npc", errors, where)
	q.abandonable = bool(d.get("abandonable", true)) if typeof(d.get("abandonable", true)) == TYPE_BOOL else true
	if d.has("abandonable") and typeof(d["abandonable"]) != TYPE_BOOL:
		errors.append("%s: 'abandonable' deve ser bool" % where)
	# pre-requisitos
	var pre: Variant = d.get("prerequisites", {})
	if typeof(pre) != TYPE_DICTIONARY:
		errors.append("%s: 'prerequisites' deve ser objeto" % where)
	else:
		var pq: Variant = (pre as Dictionary).get("quests", [])
		if typeof(pq) != TYPE_ARRAY:
			errors.append("%s: prerequisites.quests deve ser lista" % where)
		else:
			for e: Variant in pq:
				if typeof(e) != TYPE_STRING or not Protocol.is_content_id(e):
					errors.append("%s: prerequisito invalido" % where)
				elif q.prereq_quests.has(e):
					errors.append("%s: prerequisito duplicado '%s'" % [where, e])
				else:
					q.prereq_quests.append(e)
		var ml: Variant = (pre as Dictionary).get("min_level", 1)
		if not _is_int(ml) or int(ml) < 1 or int(ml) > CharacterProgress.MAX_LEVEL:
			errors.append("%s: prerequisites.min_level fora de 1..%d" % [where, CharacterProgress.MAX_LEVEL])
		else:
			q.min_level = int(ml)
	# objetivos
	var objs: Variant = d.get("objectives", null)
	if typeof(objs) != TYPE_ARRAY or (objs as Array).is_empty() or (objs as Array).size() > MAX_OBJECTIVES:
		errors.append("%s: 'objectives' deve ser lista de 1..%d" % [where, MAX_OBJECTIVES])
	else:
		var seen: Dictionary = {}
		for o_raw: Variant in objs:
			if typeof(o_raw) != TYPE_DICTIONARY:
				errors.append("%s: objetivo invalido" % where)
				continue
			var od: Dictionary = o_raw
			var o: Objective = Objective.new()
			var ow: String = where + " objetivo"
			o.id = _id_field(od, "id", errors, ow)
			ow = "%s objetivo '%s'" % [where, o.id]
			o.type = _str(od, "type", errors, ow, 24)
			if not o.type.is_empty() and not OBJECTIVE_TYPES.has(o.type):
				errors.append("%s: type '%s' invalido" % [ow, o.type])
			o.target = _id_field(od, "target", errors, ow)
			var req: Variant = od.get("required", 1)
			if not _is_int(req) or int(req) < 1 or int(req) > MAX_REQUIRED:
				errors.append("%s: required fora de 1..%d" % [ow, MAX_REQUIRED])
			else:
				o.required = int(req)
			if (o.type == OBJ_REACH_AREA or o.type == OBJ_TALK) and o.required != 1:
				errors.append("%s: objetivos %s exigem required = 1" % [ow, o.type])
			o.text = _str(od, "text", errors, ow, 120)
			o.text_key = _str(od, "text_key", errors, ow, 96)
			if not o.id.is_empty():
				if seen.has(o.id):
					errors.append("%s: id de objetivo duplicado" % ow)
				seen[o.id] = true
			q.objectives.append(o)
	# recompensas
	var rw: Variant = d.get("rewards", null)
	if typeof(rw) != TYPE_DICTIONARY:
		errors.append("%s: 'rewards' deve ser objeto" % where)
	else:
		var xp: Variant = (rw as Dictionary).get("xp", 0)
		if not _is_int(xp) or int(xp) < 0 or int(xp) > MAX_REWARD_XP:
			errors.append("%s: rewards.xp fora de 0..%d" % [where, MAX_REWARD_XP])
		else:
			q.reward_xp = int(xp)
		var items: Variant = (rw as Dictionary).get("items", [])
		if typeof(items) != TYPE_ARRAY or (items as Array).size() > MAX_REWARD_ITEMS:
			errors.append("%s: rewards.items deve ser lista de ate %d" % [where, MAX_REWARD_ITEMS])
		else:
			var item_seen: Dictionary = {}
			for it: Variant in items:
				if typeof(it) != TYPE_DICTIONARY or typeof((it as Dictionary).get("item_id", null)) != TYPE_STRING or not Protocol.is_content_id((it as Dictionary)["item_id"]):
					errors.append("%s: item de recompensa invalido" % where)
					continue
				var qty: Variant = (it as Dictionary).get("qty", 0)
				if not _is_int(qty) or int(qty) < 1 or int(qty) > MAX_REWARD_QTY:
					errors.append("%s: qty de recompensa fora de 1..%d" % [where, MAX_REWARD_QTY])
					continue
				var iid: String = (it as Dictionary)["item_id"]
				if item_seen.has(iid):
					errors.append("%s: item de recompensa repetido '%s'" % [where, iid])
					continue
				item_seen[iid] = true
				q.reward_items.append({"item_id": iid, "qty": int(qty)})
		if q.reward_xp == 0 and q.reward_items.is_empty():
			errors.append("%s: recompensa vazia" % where)
	return {"def": q if errors.is_empty() else null, "errors": errors}
