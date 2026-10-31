class_name QuestState
extends RefCounted
## Estado PERSISTIDO de quests de um personagem (espelha `quests` do backend, docs/E5_QUESTS.md):
##   {"active": {quest_id: {objective_id: int}}, "completed": [quest_id, ...]}
## "ready" (pronta para entregar) NAO e persistido: e derivado (todos os objetivos completos).
## Sem logica de regras aqui (ver QuestTracker): so representacao, (de)serializacao e validacao de forma.

var active: Dictionary = {}          ## quest_id -> {objective_id -> int}
var completed: Array[String] = []    ## ordem de conclusao


func is_active(quest_id: String) -> bool:
	return active.has(quest_id)


func is_completed(quest_id: String) -> bool:
	return completed.has(quest_id)


func progress_of(quest_id: String, objective_id: String) -> int:
	if not active.has(quest_id):
		return 0
	return int((active[quest_id] as Dictionary).get(objective_id, 0))


func clear() -> void:
	active = {}
	completed = []


## Serializacao deterministica (chaves ordenadas; `completed` em ordem alfabetica, como o backend).
func to_dict() -> Dictionary:
	var act: Dictionary = {}
	var ids: Array = active.keys()
	ids.sort()
	for qid: Variant in ids:
		var objs: Dictionary = active[qid]
		var oids: Array = objs.keys()
		oids.sort()
		var o: Dictionary = {}
		for oid: Variant in oids:
			o[String(oid)] = int(objs[oid])
		act[String(qid)] = {"objectives": o}
	var done: Array = completed.duplicate()
	done.sort()
	return {"active": act, "completed": done}


## Erro de FORMA do dicionario recebido ("" = ok). Nao consulta o catalogo (ids desconhecidos sao
## tratados pelo `restore`, que e leniente).
static func shape_error(d: Variant) -> String:
	if typeof(d) != TYPE_DICTIONARY:
		return "quests deve ser objeto"
	var dd: Dictionary = d
	var act: Variant = dd.get("active", {})
	var done: Variant = dd.get("completed", [])
	if typeof(act) != TYPE_DICTIONARY or typeof(done) != TYPE_ARRAY:
		return "quests.active/completed invalidos"
	for qid: Variant in (act as Dictionary):
		if typeof(qid) != TYPE_STRING or not Protocol.is_content_id(qid):
			return "quests.active: id invalido"
		var entry: Variant = (act as Dictionary)[qid]
		if typeof(entry) != TYPE_DICTIONARY or typeof((entry as Dictionary).get("objectives", null)) != TYPE_DICTIONARY:
			return "quests.active: entrada invalida"
		for oid: Variant in (entry as Dictionary)["objectives"]:
			if typeof(oid) != TYPE_STRING or not Protocol.is_content_id(oid) or not Protocol.is_finite_number((entry as Dictionary)["objectives"][oid]):
				return "quests.active: objetivo invalido"
	for c: Variant in (done as Array):
		if typeof(c) != TYPE_STRING or not Protocol.is_content_id(c):
			return "quests.completed: id invalido"
	return ""


## Restaura IN-PLACE (preserva a referencia usada pelo tracker). Leniente: ids de quest/objetivo
## desconhecidos sao descartados (conteudo removido), progresso e limitado a [0, required]; uma
## quest concluida nunca fica ativa. Devolve avisos (vazio = nada descartado).
func restore(d: Variant, catalog: QuestCatalog) -> Array[String]:
	var warnings: Array[String] = []
	clear()
	if shape_error(d) != "":
		if typeof(d) == TYPE_DICTIONARY and not (d as Dictionary).is_empty():
			warnings.append("quests: forma invalida; estado vazio")
		return warnings
	var dd: Dictionary = d
	for c: Variant in (dd.get("completed", []) as Array):
		var cid: String = c
		if catalog != null and catalog.get_quest(cid) == null:
			warnings.append("quest concluida desconhecida descartada: " + cid)
		elif not completed.has(cid):
			completed.append(cid)
	for qid: Variant in (dd.get("active", {}) as Dictionary):
		var id: String = qid
		var def: QuestDef = catalog.get_quest(id) if catalog != null else null
		if def == null:
			warnings.append("quest ativa desconhecida descartada: " + id)
			continue
		if completed.has(id):
			continue
		var saved: Dictionary = ((dd["active"] as Dictionary)[qid] as Dictionary)["objectives"]
		var objs: Dictionary = {}
		for o: QuestDef.Objective in def.objectives:
			objs[o.id] = clampi(int(saved.get(o.id, 0)), 0, o.required)
		active[id] = objs
	return warnings
