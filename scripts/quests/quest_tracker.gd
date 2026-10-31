class_name QuestTracker
extends RefCounted
## Regras de quests de UM personagem (logica pura, sem rede/no). O progresso so avanca por eventos
## do SERVIDOR (`on_enemy_killed`, `on_item_gained`, `on_area_entered`, `on_npc_talked`); aceitar,
## abandonar e entregar sao pedidos validados aqui. Quem aplica recompensas (inventario/XP) e
## persiste e o QuestService. Sinais servem de API para a UI (via mensagens do servidor).
##
## Estados de uma quest para o personagem (`status_of`):
##   unavailable (prerequisito/nivel nao atendido ou quest desconhecida) -> available -> active ->
##   ready (todos os objetivos completos, ainda nao entregue) -> completed (entregue; nao repete).
## Abandonar uma quest ativa a devolve a `available` e ZERA o progresso (nao ha reaproveitamento).

signal quest_accepted(quest_id: String)
signal objective_progressed(quest_id: String, objective_id: String, value: int, required: int)
signal quest_ready(quest_id: String)
signal quest_completed(quest_id: String)
signal quest_abandoned(quest_id: String)

const STATUS_UNAVAILABLE: String = "unavailable"
const STATUS_AVAILABLE: String = "available"
const STATUS_ACTIVE: String = "active"
const STATUS_READY: String = "ready"
const STATUS_COMPLETED: String = "completed"

## Limite de quests ativas ao mesmo tempo (espelha CHARACTER_MAX_ACTIVE_QUESTS do backend, padrao 10).
const MAX_ACTIVE: int = 10

var catalog: QuestCatalog
var state: QuestState


func _init(p_catalog: QuestCatalog, p_state: QuestState = null) -> void:
	catalog = p_catalog
	state = p_state if p_state != null else QuestState.new()


## Chave de idempotencia ESTAVEL da recompensa (a mesma em qualquer retry/replay/reconexao).
static func reward_key(quest_id: String, character_id: String) -> String:
	return "quest:%s:%s" % [quest_id, character_id]


# ------------------------------------------------------------------ consulta

func is_ready(quest_id: String) -> bool:
	var def: QuestDef = catalog.get_quest(quest_id)
	if def == null or not state.is_active(quest_id):
		return false
	for o: QuestDef.Objective in def.objectives:
		if state.progress_of(quest_id, o.id) < o.required:
			return false
	return true


func status_of(quest_id: String, level: int) -> String:
	var def: QuestDef = catalog.get_quest(quest_id)
	if def == null:
		return STATUS_UNAVAILABLE
	if state.is_completed(quest_id):
		return STATUS_COMPLETED
	if state.is_active(quest_id):
		return STATUS_READY if is_ready(quest_id) else STATUS_ACTIVE
	return STATUS_AVAILABLE if prerequisites_met(def, level) else STATUS_UNAVAILABLE


func prerequisites_met(def: QuestDef, level: int) -> bool:
	if level < def.min_level:
		return false
	for pre: String in def.prereq_quests:
		if not state.is_completed(pre):
			return false
	return true


func active_ids() -> Array[String]:
	var out: Array[String] = []
	for k: Variant in state.active:
		out.append(String(k))
	out.sort()
	return out


## Contexto para condicoes de dialogo: {"level": int, "quests": {quest_id: status}} (todas as quests do catalogo).
func dialogue_context(level: int) -> Dictionary:
	var statuses: Dictionary = {}
	for id: String in catalog.ids():
		statuses[id] = status_of(id, level)
	return {"level": level, "quests": statuses}


# ------------------------------------------------------------------ comandos

static func _ok(extra: Dictionary = {}) -> Dictionary:
	var r: Dictionary = {"ok": true, "code": ""}
	r.merge(extra, true)
	return r


static func _fail(code: String) -> Dictionary:
	return {"ok": false, "code": code}


## Aceita a quest. Codigos de erro: unknown_quest, already_completed, already_active, level_too_low,
## prereq_missing, quest_log_full.
func accept(quest_id: String, level: int) -> Dictionary:
	var def: QuestDef = catalog.get_quest(quest_id)
	if def == null:
		return _fail("unknown_quest")
	if state.is_completed(quest_id):
		return _fail("already_completed")
	if state.is_active(quest_id):
		return _fail("already_active")
	if level < def.min_level:
		return _fail("level_too_low")
	for pre: String in def.prereq_quests:
		if not state.is_completed(pre):
			return _fail("prereq_missing")
	if state.active.size() >= MAX_ACTIVE:
		return _fail("quest_log_full")
	var objs: Dictionary = {}
	for o: QuestDef.Objective in def.objectives:
		objs[o.id] = 0
	state.active[quest_id] = objs
	quest_accepted.emit(quest_id)
	return _ok()


## Abandona (zera o progresso). Codigos: unknown_quest, not_active, not_abandonable.
func abandon(quest_id: String) -> Dictionary:
	var def: QuestDef = catalog.get_quest(quest_id)
	if def == null:
		return _fail("unknown_quest")
	if not state.is_active(quest_id):
		return _fail("not_active")
	if not def.abandonable:
		return _fail("not_abandonable")
	state.active.erase(quest_id)
	quest_abandoned.emit(quest_id)
	return _ok()


## Confere se da para entregar (NAO altera nada). Codigos: unknown_quest, already_completed,
## not_active, not_ready. Em sucesso devolve {rewards: {xp, items}}.
func check_turn_in(quest_id: String) -> Dictionary:
	var def: QuestDef = catalog.get_quest(quest_id)
	if def == null:
		return _fail("unknown_quest")
	if state.is_completed(quest_id):
		return _fail("already_completed")
	if not state.is_active(quest_id):
		return _fail("not_active")
	if not is_ready(quest_id):
		return _fail("not_ready")
	return _ok({"rewards": def.rewards()})


## Conclui a quest (ativa -> concluida). O CHAMADOR ja aplicou as recompensas; chamar so depois de
## `check_turn_in` ok. Repetir devolve erro (recompensa unica).
func complete(quest_id: String) -> Dictionary:
	var chk: Dictionary = check_turn_in(quest_id)
	if not bool(chk["ok"]):
		return chk
	state.active.erase(quest_id)
	state.completed.append(quest_id)
	quest_completed.emit(quest_id)
	return chk


# ------------------------------------------------------------------ eventos do servidor

## Soma `amount` aos objetivos ativos de `obj_type` com alvo `target`. Devolve quantos objetivos mudaram.
func _advance(obj_type: String, target: String, amount: int) -> int:
	if amount <= 0:
		return 0
	var changed: int = 0
	for qid: String in active_ids():
		var def: QuestDef = catalog.get_quest(qid)
		if def == null:
			continue
		var was_ready: bool = is_ready(qid)
		var objs: Dictionary = state.active[qid]
		var moved: bool = false
		for o: QuestDef.Objective in def.objectives:
			if o.type != obj_type or o.target != target:
				continue
			var cur: int = int(objs.get(o.id, 0))
			if cur >= o.required:
				continue
			var nxt: int = mini(cur + amount, o.required)
			objs[o.id] = nxt
			changed += 1
			moved = true
			objective_progressed.emit(qid, o.id, nxt, o.required)
		if moved and not was_ready and is_ready(qid):
			quest_ready.emit(qid)
	return changed


func on_enemy_killed(enemy_type: String) -> int:
	return _advance(QuestDef.OBJ_KILL, enemy_type, 1)


func on_item_gained(item_id: String, qty: int) -> int:
	return _advance(QuestDef.OBJ_COLLECT, item_id, qty)


func on_area_entered(area_id: String) -> int:
	return _advance(QuestDef.OBJ_REACH_AREA, area_id, 1)


func on_npc_talked(npc_id: String) -> int:
	return _advance(QuestDef.OBJ_TALK, npc_id, 1)
