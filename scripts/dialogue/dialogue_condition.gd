class_name DialogueCondition
extends RefCounted
## Condicoes de dialogo (dados em JSON). Logica pura: `check(cond, ctx)` e `validate(cond)`.
## Formas:
##   {"quest": id, "state": "available"|"active"|"ready"|"completed"|"unavailable" | [estados...]}
##   {"min_level": n}
##   {"all": [cond...]} / {"any": [cond...]} / {"not": cond}
## `ctx` = {"level": int, "quests": {quest_id: estado}} (QuestTracker.dialogue_context).
## Condicao ausente/vazia = verdadeira. Condicao invalida em runtime = falsa (fail closed).

const STATES: Array[String] = ["unavailable", "available", "active", "ready", "completed"]
const MAX_DEPTH: int = 4
const MAX_ITEMS: int = 8


## Lista de erros de forma ([] = valida). `known_quests` (opcional) confere o id da quest.
static func validate(cond: Variant, known_quests: Array = [], depth: int = 0) -> Array[String]:
	var errors: Array[String] = []
	if depth > MAX_DEPTH:
		errors.append("condicao aninhada demais")
		return errors
	if typeof(cond) != TYPE_DICTIONARY:
		errors.append("condicao deve ser objeto")
		return errors
	var c: Dictionary = cond
	if c.size() != 1 and not (c.size() == 2 and c.has("quest") and c.has("state")):
		errors.append("condicao deve ter exatamente uma forma")
		return errors
	if c.has("quest"):
		if not Protocol.is_content_id(c["quest"]):
			errors.append("quest invalida")
		elif not known_quests.is_empty() and not known_quests.has(c["quest"]):
			errors.append("quest '%s' desconhecida" % c["quest"])
		var st: Variant = c.get("state", null)
		var list: Array = st if typeof(st) == TYPE_ARRAY else [st]
		if list.is_empty() or list.size() > STATES.size():
			errors.append("state invalido")
		for s: Variant in list:
			if typeof(s) != TYPE_STRING or not STATES.has(s):
				errors.append("state '%s' invalido" % str(s).substr(0, 24))
	elif c.has("min_level"):
		if typeof(c["min_level"]) not in [TYPE_INT, TYPE_FLOAT] or float(c["min_level"]) < 1.0 or float(c["min_level"]) > 1000.0:
			errors.append("min_level invalido")
	elif (c.has("all") or c.has("any") or c.has("not")) and depth >= MAX_DEPTH:
		errors.append("condicao aninhada demais")
	elif c.has("all") or c.has("any"):
		var key: String = "all" if c.has("all") else "any"
		if typeof(c[key]) != TYPE_ARRAY or (c[key] as Array).is_empty() or (c[key] as Array).size() > MAX_ITEMS:
			errors.append("'%s' deve ser lista de 1..%d" % [key, MAX_ITEMS])
		else:
			for sub: Variant in c[key]:
				errors.append_array(validate(sub, known_quests, depth + 1))
	elif c.has("not"):
		errors.append_array(validate(c["not"], known_quests, depth + 1))
	else:
		errors.append("forma de condicao desconhecida")
	return errors


static func check(cond: Variant, ctx: Dictionary, depth: int = 0) -> bool:
	if cond == null:
		return true
	if typeof(cond) != TYPE_DICTIONARY:
		return false
	var c: Dictionary = cond
	if c.is_empty():
		return true
	if depth > MAX_DEPTH:
		return false
	if c.has("quest"):
		var quests: Dictionary = ctx.get("quests", {})
		var cur: String = String(quests.get(String(c["quest"]), "unavailable"))
		var st: Variant = c.get("state", null)
		var list: Array = st if typeof(st) == TYPE_ARRAY else [st]
		return list.has(cur)
	if c.has("min_level"):
		return int(ctx.get("level", 1)) >= int(c["min_level"])
	# Conteineres no limite de profundidade: falso (fail closed; `not` nao pode inverter o corte).
	if (c.has("all") or c.has("any") or c.has("not")) and depth >= MAX_DEPTH:
		return false
	if c.has("all") and typeof(c["all"]) == TYPE_ARRAY:
		for sub: Variant in c["all"]:
			if not check(sub, ctx, depth + 1):
				return false
		return true
	if c.has("any") and typeof(c["any"]) == TYPE_ARRAY:
		for sub: Variant in c["any"]:
			if check(sub, ctx, depth + 1):
				return true
		return false
	if c.has("not"):
		return not check(c["not"], ctx, depth + 1)
	return false
