class_name ClientQuestLog
extends RefCounted
## Espelho SOMENTE-LEITURA do diario de quests do jogador local, alimentado pelas mensagens `s_quest`
## do servidor (Protocol.QUEST_*). Nao decide nada: a UI (outro modulo) le daqui e escuta os sinais.
## Mensagens malformadas sao ignoradas (o servidor e confiavel, mas o parser nao confia em tipos).

signal changed()                                       ## qualquer mudanca (redesenhar o diario)
signal quest_accepted(quest_id: String)
signal objective_progressed(quest_id: String, objective_id: String, value: int, required: int)
signal quest_ready(quest_id: String)
signal quest_completed(quest_id: String, xp: int, items: Array)
signal quest_abandoned(quest_id: String)
signal quest_error(req_id: int, op: int, quest_id: String, code: String)

var active: Dictionary = {}        ## quest_id -> {objective_id: int}
var completed: Array[String] = []
var ready: Dictionary = {}         ## quest_id -> true (pronta para entregar)
var statuses: Dictionary = {}      ## quest_id -> "unavailable"|"available"|"active"|"ready"|"completed" (ultimo sync)
var updates_ignored: int = 0


## Aplica uma mensagem do servidor. Devolve true se foi entendida.
func apply(kind: int, data: Dictionary) -> bool:
	match kind:
		Protocol.QUEST_SYNC:
			return _apply_sync(data)
		Protocol.QUEST_ACCEPTED:
			var qid: String = _qid(data)
			if qid.is_empty():
				return _ignore()
			active[qid] = _zero_objectives(qid)
			ready.erase(qid)
			quest_accepted.emit(qid)
		Protocol.QUEST_PROGRESS:
			var q2: String = _qid(data)
			var oid: Variant = data.get("objective_id", null)
			if q2.is_empty() or not Protocol.is_content_id(oid) or not Protocol.is_finite_number(data.get("value", null)) or not Protocol.is_finite_number(data.get("required", null)):
				return _ignore()
			if not active.has(q2):
				active[q2] = {}
			(active[q2] as Dictionary)[String(oid)] = int(data["value"])
			objective_progressed.emit(q2, String(oid), int(data["value"]), int(data["required"]))
		Protocol.QUEST_READY:
			var q3: String = _qid(data)
			if q3.is_empty():
				return _ignore()
			ready[q3] = true
			quest_ready.emit(q3)
		Protocol.QUEST_COMPLETED:
			var q4: String = _qid(data)
			if q4.is_empty():
				return _ignore()
			active.erase(q4)
			ready.erase(q4)
			if not completed.has(q4):
				completed.append(q4)
			var items: Array = data.get("items", []) if typeof(data.get("items", [])) == TYPE_ARRAY else []
			quest_completed.emit(q4, int(data.get("xp", 0)) if Protocol.is_finite_number(data.get("xp", 0)) else 0, items)
		Protocol.QUEST_ABANDONED:
			var q5: String = _qid(data)
			if q5.is_empty():
				return _ignore()
			active.erase(q5)
			ready.erase(q5)
			quest_abandoned.emit(q5)
		Protocol.QUEST_ERROR:
			if not Protocol.is_finite_number(data.get("req_id", null)) or typeof(data.get("code", null)) != TYPE_STRING:
				return _ignore()
			quest_error.emit(int(data["req_id"]), int(data.get("op", 0)), String(data.get("quest_id", "")), (data["code"] as String).substr(0, 48))
			return true
		_:
			return _ignore()
	changed.emit()
	return true


func status_of(quest_id: String) -> String:
	if completed.has(quest_id):
		return "completed"
	if active.has(quest_id):
		return "ready" if ready.has(quest_id) else "active"
	return String(statuses.get(quest_id, "unavailable"))


func _ignore() -> bool:
	updates_ignored += 1
	return false


func _qid(data: Dictionary) -> String:
	var v: Variant = data.get("quest_id", null)
	return String(v) if Protocol.is_content_id(v) else ""


func _zero_objectives(quest_id: String) -> Dictionary:
	var out: Dictionary = {}
	var def: QuestDef = QuestCatalog.shared().get_quest(quest_id)
	if def != null:
		for o: QuestDef.Objective in def.objectives:
			out[o.id] = 0
	return out


func _apply_sync(data: Dictionary) -> bool:
	var q: Variant = data.get("quests", null)
	if not QuestState.shape_error(q).is_empty():
		return _ignore()
	var state: QuestState = QuestState.new()
	state.restore(q, QuestCatalog.shared())
	active = state.active.duplicate(true)
	completed = state.completed.duplicate()
	ready = {}
	var cat: QuestCatalog = QuestCatalog.shared()
	for qid: String in active:
		var def: QuestDef = cat.get_quest(qid)
		var all_done: bool = def != null
		if def != null:
			for o: QuestDef.Objective in def.objectives:
				if int((active[qid] as Dictionary).get(o.id, 0)) < o.required:
					all_done = false
		if all_done:
			ready[qid] = true
	statuses = {}
	var st: Variant = data.get("statuses", {})
	if typeof(st) == TYPE_DICTIONARY:
		for k: Variant in st:
			if Protocol.is_content_id(k) and typeof(st[k]) == TYPE_STRING:
				statuses[String(k)] = String(st[k])
	changed.emit()
	return true
