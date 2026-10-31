class_name DialogueDef
extends RefCounted
## Arvore de dialogo (data/dialogues/<id>.json; schema em shared/content_schemas/dialogue.schema.json).
##   entries: lista ordenada de {if?, node}; vale a primeira cuja condicao passa (a ultima nao tem `if`).
##   nodes: {node_id: {speaker, text, text_key, on_enter?: [efeito], choices?: [{text, text_key, if?, effects?, next}]}}
##   `next: null` encerra. No sem `choices` e TERMINAL (mostra a fala e encerra).
## Efeitos: {"type": "accept_quest"|"turn_in_quest", "quest_id": id}.
## Parse e validacao puros (sem disco): `parse(raw, known_quests)` -> {def, errors}.

const SCHEMA_VERSION: int = 1
const EFFECT_TYPES: Array[String] = ["accept_quest", "turn_in_quest"]
const MAX_NODES: int = 64
const MAX_CHOICES: int = 6
const MAX_ENTRIES: int = 16
const MAX_EFFECTS: int = 4
const MAX_TEXT: int = 500

var id: String = ""
var npc_id: String = ""
var entries: Array[Dictionary] = []   ## [{if: Variant, node: String}]
var nodes: Dictionary = {}            ## node_id -> {speaker, text, text_key, on_enter:Array, choices:Array[Dictionary]}


static func _text(d: Dictionary, key: String, errors: Array[String], where: String, max_len: int) -> String:
	if typeof(d.get(key, null)) != TYPE_STRING or (d[key] as String).strip_edges().is_empty() or (d[key] as String).length() > max_len:
		errors.append("%s: '%s' ausente/vazio/longo demais" % [where, key])
		return ""
	return d[key]


static func _parse_effects(raw: Variant, errors: Array[String], where: String, known_quests: Array) -> Array:
	var out: Array = []
	if raw == null:
		return out
	if typeof(raw) != TYPE_ARRAY or (raw as Array).size() > MAX_EFFECTS:
		errors.append("%s: effects deve ser lista de ate %d" % [where, MAX_EFFECTS])
		return out
	for e: Variant in raw:
		if typeof(e) != TYPE_DICTIONARY or (e as Dictionary).size() != 2 or not EFFECT_TYPES.has((e as Dictionary).get("type", null)) \
				or not Protocol.is_content_id((e as Dictionary).get("quest_id", null)):
			errors.append("%s: efeito invalido" % where)
			continue
		if not known_quests.is_empty() and not known_quests.has((e as Dictionary)["quest_id"]):
			errors.append("%s: efeito referencia quest desconhecida '%s'" % [where, (e as Dictionary)["quest_id"]])
			continue
		out.append({"type": String((e as Dictionary)["type"]), "quest_id": String((e as Dictionary)["quest_id"])})
	return out


## `known_quests` (opcional, ids) ativa a checagem de referencias a quests.
static func parse(raw: Variant, known_quests: Array = []) -> Dictionary:
	var errors: Array[String] = []
	if typeof(raw) != TYPE_DICTIONARY:
		return {"def": null, "errors": ["dialogo: raiz deve ser objeto"] as Array[String]}
	var d: Dictionary = raw
	var def: DialogueDef = DialogueDef.new()
	if typeof(d.get("schema_version", null)) not in [TYPE_INT, TYPE_FLOAT] or int(d.get("schema_version", 0)) != SCHEMA_VERSION:
		errors.append("dialogo: schema_version deve ser %d" % SCHEMA_VERSION)
	if not Protocol.is_content_id(d.get("id", null)) or not Protocol.is_content_id(d.get("npc_id", null)):
		errors.append("dialogo: id/npc_id invalidos")
		return {"def": null, "errors": errors}
	def.id = d["id"]
	def.npc_id = d["npc_id"]
	var w: String = "dialogo '%s'" % def.id
	var nodes_raw: Variant = d.get("nodes", null)
	if typeof(nodes_raw) != TYPE_DICTIONARY or (nodes_raw as Dictionary).is_empty() or (nodes_raw as Dictionary).size() > MAX_NODES:
		errors.append("%s: 'nodes' deve ser objeto com 1..%d nos" % [w, MAX_NODES])
		return {"def": null, "errors": errors}
	for nid: Variant in (nodes_raw as Dictionary):
		if not Protocol.is_content_id(nid):
			errors.append("%s: id de no invalido" % w)
			continue
		var nw: String = "%s no '%s'" % [w, nid]
		var n: Variant = (nodes_raw as Dictionary)[nid]
		if typeof(n) != TYPE_DICTIONARY:
			errors.append("%s: no invalido" % nw)
			continue
		var nd: Dictionary = n
		var node: Dictionary = {
			"speaker": _text(nd, "speaker", errors, nw, 48), "text": _text(nd, "text", errors, nw, MAX_TEXT),
			"text_key": _text(nd, "text_key", errors, nw, 96),
			"on_enter": _parse_effects(nd.get("on_enter", null), errors, nw + " on_enter", known_quests),
			"choices": [],
		}
		var ch_raw: Variant = nd.get("choices", [])
		if typeof(ch_raw) != TYPE_ARRAY or (ch_raw as Array).size() > MAX_CHOICES:
			errors.append("%s: choices deve ser lista de ate %d" % [nw, MAX_CHOICES])
		else:
			for c: Variant in ch_raw:
				if typeof(c) != TYPE_DICTIONARY or not (c as Dictionary).has("next"):
					errors.append("%s: escolha invalida (campo 'next' obrigatorio)" % nw)
					continue
				var cd: Dictionary = c
				var nxt: Variant = cd["next"]
				if nxt != null and not Protocol.is_content_id(nxt):
					errors.append("%s: 'next' invalido" % nw)
					continue
				var cond: Variant = cd.get("if", null)
				if cond != null:
					for e: String in DialogueCondition.validate(cond, known_quests):
						errors.append("%s: if: %s" % [nw, e])
				node["choices"].append({
					"text": _text(cd, "text", errors, nw + " escolha", 160), "text_key": _text(cd, "text_key", errors, nw + " escolha", 96),
					"if": cond, "effects": _parse_effects(cd.get("effects", null), errors, nw + " escolha", known_quests), "next": nxt,
				})
		def.nodes[String(nid)] = node
	# referencias internas
	for nid: String in def.nodes:
		for c: Dictionary in def.nodes[nid]["choices"]:
			if c["next"] != null and not def.nodes.has(c["next"]):
				errors.append("%s no '%s': next '%s' inexistente" % [w, nid, c["next"]])
	var entries_raw: Variant = d.get("entries", null)
	if typeof(entries_raw) != TYPE_ARRAY or (entries_raw as Array).is_empty() or (entries_raw as Array).size() > MAX_ENTRIES:
		errors.append("%s: 'entries' deve ser lista de 1..%d" % [w, MAX_ENTRIES])
	else:
		var i: int = 0
		for e: Variant in entries_raw:
			i += 1
			if typeof(e) != TYPE_DICTIONARY or not Protocol.is_content_id((e as Dictionary).get("node", null)) or not def.nodes.has((e as Dictionary)["node"]):
				errors.append("%s: entrada %d invalida ou aponta para no inexistente" % [w, i])
				continue
			var cond2: Variant = (e as Dictionary).get("if", null)
			if cond2 != null:
				for er: String in DialogueCondition.validate(cond2, known_quests):
					errors.append("%s entrada %d: %s" % [w, i, er])
			elif i != (entries_raw as Array).size():
				errors.append("%s: so a ULTIMA entrada pode ficar sem 'if'" % w)
			def.entries.append({"if": cond2, "node": String((e as Dictionary)["node"])})
		if not (entries_raw as Array).is_empty() and typeof((entries_raw as Array).back()) == TYPE_DICTIONARY and (((entries_raw as Array).back() as Dictionary).has("if")):
			errors.append("%s: a ultima entrada deve ser o fallback (sem 'if')" % w)
	return {"def": def if errors.is_empty() else null, "errors": errors}
