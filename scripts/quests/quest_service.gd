class_name QuestService
extends RefCounted
## Cola de servidor para quests e dialogo (E5.1). Une QuestTracker (regras), DialogueRunner (arvore),
## NpcDirectory (proximidade), AreaWatcher (entrada em areas), mensagens ao cliente (ServerTransport)
## e persistencia (BackendSync, opcional). SERVIDOR AUTORITATIVO: o cliente so envia pedidos (aceitar/
## abandonar/entregar/abrir dialogo/escolher); o progresso so avanca por eventos do servidor
## (`on_enemy_killed`, `on_items_gained`, `tick` para areas, abrir dialogo para `talk`).
## Recompensa: aplicada na memoria do servidor (itens atomicos, depois XP) e enviada ao backend com a
## chave estavel `quest:<quest_id>:<character_id>` (replay nunca duplica; o backend tambem marca a quest
## como concluida na MESMA transacao). Veja docs/E5_QUESTS.md.

var transport: ServerTransport
var catalog: QuestCatalog
var npcs: NpcDirectory
var dialogues: DialogueCatalog
var areas: AreaSet
## Opcional (null = modo dev: nada persiste).
var sync: BackendSync = null
## false desliga a checagem de distancia ao NPC (testes/mundo sem NPCs posicionados).
var enforce_range: bool = true
## (entity_id: int) -> Vector3 | null  (posicao autoritativa do jogador no servidor).
var position_of: Callable
## A cada quantos ticks as areas sao verificadas.
var area_check_interval_ticks: int = 5

var _players: Dictionary = {}   ## entity_id -> PlayerCtx
var _ticks: int = 0


class PlayerCtx extends RefCounted:
	var entity_id: int = 0
	var peer_id: int = 0
	var character_id: String = ""
	var loadout: PlayerLoadout
	var tracker: QuestTracker
	var watcher: AreaWatcher
	var runner: DialogueRunner = null
	var dialogue_npc: String = ""
	var req_id: int = 0 ## req_id do comando em andamento (para erros)
	var op: int = 0


func _init(p_transport: ServerTransport = null) -> void:
	transport = p_transport
	catalog = QuestCatalog.shared()
	npcs = NpcDirectory.shared()
	dialogues = DialogueCatalog.shared()
	areas = AreaSet.shared()


# ------------------------------------------------------------------ ciclo de vida

func has_player(entity_id: int) -> bool:
	return _players.has(entity_id)


func tracker_of(entity_id: int) -> QuestTracker:
	var pc: PlayerCtx = _players.get(entity_id) as PlayerCtx
	return pc.tracker if pc != null else null


## Liga o jogador (ja com `loadout.quest_state` restaurado). Envia o estado completo ao cliente.
func attach(entity_id: int, peer_id: int, character_id: String, loadout: PlayerLoadout) -> void:
	if _players.has(entity_id) or loadout == null:
		return
	var pc: PlayerCtx = PlayerCtx.new()
	pc.entity_id = entity_id
	pc.peer_id = peer_id
	pc.character_id = character_id
	pc.loadout = loadout
	pc.tracker = QuestTracker.new(catalog, loadout.quest_state)
	pc.watcher = AreaWatcher.new(areas)
	pc.tracker.quest_accepted.connect(_on_accepted.bind(pc))
	pc.tracker.objective_progressed.connect(_on_progressed.bind(pc))
	pc.tracker.quest_ready.connect(_on_ready.bind(pc))
	pc.tracker.quest_completed.connect(_on_completed.bind(pc))
	pc.tracker.quest_abandoned.connect(_on_abandoned.bind(pc))
	_players[entity_id] = pc
	_send_sync(pc)


## Reenvia o estado completo (ex.: apos o backend reaplicar o estado por conflito de revision).
func resync(entity_id: int) -> void:
	var pc: PlayerCtx = _players.get(entity_id) as PlayerCtx
	if pc != null:
		_send_sync(pc)


func detach(entity_id: int) -> void:
	var pc: PlayerCtx = _players.get(entity_id) as PlayerCtx
	if pc == null:
		return
	_players.erase(entity_id)
	# Quebra o ciclo pc -> tracker -> conexao -> pc.
	pc.tracker.quest_accepted.disconnect(_on_accepted.bind(pc))
	pc.tracker.objective_progressed.disconnect(_on_progressed.bind(pc))
	pc.tracker.quest_ready.disconnect(_on_ready.bind(pc))
	pc.tracker.quest_completed.disconnect(_on_completed.bind(pc))
	pc.tracker.quest_abandoned.disconnect(_on_abandoned.bind(pc))
	pc.runner = null


# ------------------------------------------------------------------ eventos do servidor

func on_enemy_killed(entity_id: int, enemy_type: String) -> void:
	var pc: PlayerCtx = _players.get(entity_id) as PlayerCtx
	if pc != null:
		pc.tracker.on_enemy_killed(enemy_type)


## `items`: [{item_id: String, qty: int}] REALMENTE adicionados ao inventario do jogador.
func on_items_gained(entity_id: int, items: Array) -> void:
	var pc: PlayerCtx = _players.get(entity_id) as PlayerCtx
	if pc == null:
		return
	for it: Variant in items:
		if typeof(it) == TYPE_DICTIONARY:
			pc.tracker.on_item_gained(String((it as Dictionary).get("item_id", "")), int((it as Dictionary).get("qty", 0)))


## Chamado a cada tick de simulacao; verifica entrada em areas de tempos em tempos.
func tick() -> void:
	_ticks += 1
	if area_check_interval_ticks > 1 and _ticks % area_check_interval_ticks != 0:
		return
	if not position_of.is_valid():
		return
	for eid: int in _players.keys():
		var pc: PlayerCtx = _players[eid] as PlayerCtx
		var pos: Variant = position_of.call(eid)
		if typeof(pos) != TYPE_VECTOR3:
			continue
		for area_id: String in pc.watcher.update(pos as Vector3):
			pc.tracker.on_area_entered(area_id)


# ------------------------------------------------------------------ comandos de quest

## Pedido do cliente (JA validado por Protocol.validate_quest_cmd). Devolve {ok, code}.
func cmd_quest(entity_id: int, req_id: int, op: int, quest_id: String) -> Dictionary:
	var pc: PlayerCtx = _players.get(entity_id) as PlayerCtx
	if pc == null:
		return {"ok": false, "code": "no_player"}
	pc.req_id = req_id
	pc.op = op
	var res: Dictionary
	match op:
		Protocol.QUEST_OP_ACCEPT:
			res = _accept(pc, quest_id, "")
		Protocol.QUEST_OP_ABANDON:
			res = pc.tracker.abandon(quest_id)
			if bool(res["ok"]):
				_persist_now(pc)
		Protocol.QUEST_OP_TURN_IN:
			res = _turn_in(pc, quest_id, "")
		_:
			res = {"ok": false, "code": "bad_op"}
	if not bool(res["ok"]):
		_send_quest_error(pc, quest_id, String(res["code"]))
	return res


func _level(pc: PlayerCtx) -> int:
	return pc.loadout.progress.level


func _near(pc: PlayerCtx, npc_id: String) -> bool:
	if not enforce_range:
		return npcs.has_npc(npc_id)
	if not position_of.is_valid():
		return false
	var pos: Variant = position_of.call(pc.entity_id)
	return typeof(pos) == TYPE_VECTOR3 and npcs.in_range(npc_id, pos as Vector3)


## `via_npc` != "" quando vem de um dialogo: o NPC do dialogo deve ser o doador da quest.
func _accept(pc: PlayerCtx, quest_id: String, via_npc: String) -> Dictionary:
	var def: QuestDef = catalog.get_quest(quest_id)
	if def == null:
		return {"ok": false, "code": "unknown_quest"}
	if not via_npc.is_empty() and via_npc != def.giver_npc:
		return {"ok": false, "code": "wrong_npc"}
	if not _near(pc, def.giver_npc):
		return {"ok": false, "code": "too_far"}
	var res: Dictionary = pc.tracker.accept(quest_id, _level(pc))
	if bool(res["ok"]):
		_persist_now(pc)
	return res


func _turn_in(pc: PlayerCtx, quest_id: String, via_npc: String) -> Dictionary:
	var def: QuestDef = catalog.get_quest(quest_id)
	if def == null:
		return {"ok": false, "code": "unknown_quest"}
	if not via_npc.is_empty() and via_npc != def.turn_in_npc:
		return {"ok": false, "code": "wrong_npc"}
	if not _near(pc, def.turn_in_npc):
		return {"ok": false, "code": "too_far"}
	var chk: Dictionary = pc.tracker.check_turn_in(quest_id)
	if not bool(chk["ok"]):
		return chk
	# Itens: tudo-ou-nada (rollback pelo snapshot). Sem espaco => nada muda e a quest continua pronta.
	var inv: Inventory = pc.loadout.inventory
	var snap: Array[ItemStack] = inv.snapshot()
	for it: Dictionary in def.reward_items:
		if inv.add(StringName(it["item_id"]), int(it["qty"])) > 0:
			inv.restore(snap)
			return {"ok": false, "code": "inventory_full"}
	if def.reward_xp > 0:
		pc.loadout.grant_xp(def.reward_xp)
	var done: Dictionary = pc.tracker.complete(quest_id) # emite quest_completed -> mensagem ao cliente
	if sync != null and not pc.character_id.is_empty():
		# Chave ESTAVEL: retry/replay/reconexao reenviam a mesma; o backend nao duplica.
		sync.enqueue_reward(pc.character_id, QuestTracker.reward_key(quest_id, pc.character_id), def.reward_xp, def.reward_items.duplicate(true), quest_id)
	_send_sync(pc) # novas quests podem ter ficado disponiveis
	return done


func _persist_now(pc: PlayerCtx) -> void:
	if sync != null and not pc.character_id.is_empty():
		sync.enqueue_checkpoint(pc.character_id, CharacterCodec.capture(pc.loadout), false)


# ------------------------------------------------------------------ dialogo

## Pedido do cliente (JA validado por Protocol.validate_dialogue_cmd). Devolve {ok, code}.
func cmd_dialogue(entity_id: int, req_id: int, op: int, npc_id: String, choice: int) -> Dictionary:
	var pc: PlayerCtx = _players.get(entity_id) as PlayerCtx
	if pc == null:
		return {"ok": false, "code": "no_player"}
	pc.req_id = req_id
	pc.op = op
	var res: Dictionary = {"ok": true, "code": ""}
	match op:
		Protocol.DIALOGUE_OP_OPEN:
			res = _dialogue_open(pc, npc_id)
		Protocol.DIALOGUE_OP_CHOOSE:
			res = _dialogue_choose(pc, choice)
		Protocol.DIALOGUE_OP_CLOSE:
			_end_dialogue(pc, true)
		_:
			res = {"ok": false, "code": "bad_op"}
	if not bool(res["ok"]):
		_send_dialogue(pc, Protocol.DIALOGUE_ERROR, {"req_id": req_id, "op": op, "code": String(res["code"])})
	return res


func _dialogue_open(pc: PlayerCtx, npc_id: String) -> Dictionary:
	if not npcs.has_npc(npc_id):
		return {"ok": false, "code": "unknown_npc"}
	if not _near(pc, npc_id):
		return {"ok": false, "code": "too_far"}
	var def: DialogueDef = dialogues.for_npc(npc_id)
	if def == null:
		return {"ok": false, "code": "no_dialogue"}
	pc.tracker.on_npc_talked(npc_id) # objetivo "talk": so quem abre o dialogo (perto do NPC) conta
	pc.runner = DialogueRunner.new(def)
	pc.dialogue_npc = npc_id
	pc.runner.start(pc.tracker.dialogue_context(_level(pc)))
	_present(pc)
	return {"ok": true, "code": ""}


func _dialogue_choose(pc: PlayerCtx, choice: int) -> Dictionary:
	if pc.runner == null:
		return {"ok": false, "code": "no_dialogue"}
	if not _near(pc, pc.dialogue_npc):
		_end_dialogue(pc, true)
		return {"ok": false, "code": "too_far"}
	var res: Dictionary = pc.runner.choose(choice, pc.tracker.dialogue_context(_level(pc)))
	if not bool(res["ok"]):
		return {"ok": false, "code": String(res["code"])}
	_apply_effects(pc, res["effects"] as Array)
	if bool(res["ended"]):
		_end_dialogue(pc, true)
	else:
		_present(pc)
	return {"ok": true, "code": ""}


## Aplica os efeitos `on_enter` do no atual e envia a fala; dialogo terminal encerra apos a fala.
func _present(pc: PlayerCtx) -> void:
	_apply_effects(pc, pc.runner.take_enter_effects())
	var view: Dictionary = pc.runner.view(pc.tracker.dialogue_context(_level(pc)))
	if view.is_empty():
		_end_dialogue(pc, true)
		return
	_send_dialogue(pc, Protocol.DIALOGUE_VIEW, view)
	if pc.runner.is_finished():
		pc.runner = null
		pc.dialogue_npc = ""


func _apply_effects(pc: PlayerCtx, effects: Array) -> void:
	for e: Variant in effects:
		var eff: Dictionary = e
		var qid: String = String(eff["quest_id"])
		var res: Dictionary
		if String(eff["type"]) == "accept_quest":
			res = _accept(pc, qid, pc.dialogue_npc)
		else:
			res = _turn_in(pc, qid, pc.dialogue_npc)
		if not bool(res["ok"]):
			_send_quest_error(pc, qid, String(res["code"]))


func _end_dialogue(pc: PlayerCtx, notify: bool) -> void:
	var was_open: bool = pc.runner != null
	var npc: String = pc.dialogue_npc
	pc.runner = null
	pc.dialogue_npc = ""
	if was_open and notify:
		_send_dialogue(pc, Protocol.DIALOGUE_END, {"npc_id": npc})


# ------------------------------------------------------------------ mensagens ao cliente

func _send_quest(pc: PlayerCtx, kind: int, data: Dictionary) -> void:
	if transport != null:
		transport.send_quest_update(pc.peer_id, kind, data)


func _send_dialogue(pc: PlayerCtx, kind: int, data: Dictionary) -> void:
	if transport != null:
		transport.send_dialogue(pc.peer_id, kind, data)


func _send_quest_error(pc: PlayerCtx, quest_id: String, code: String) -> void:
	_send_quest(pc, Protocol.QUEST_ERROR, {"req_id": pc.req_id, "op": pc.op, "quest_id": quest_id, "code": code})


func _send_sync(pc: PlayerCtx) -> void:
	_send_quest(pc, Protocol.QUEST_SYNC, {"quests": pc.tracker.state.to_dict(), "statuses": pc.tracker.dialogue_context(_level(pc))["quests"]})


func _on_accepted(quest_id: String, pc: PlayerCtx) -> void:
	_send_quest(pc, Protocol.QUEST_ACCEPTED, {"quest_id": quest_id})


func _on_progressed(quest_id: String, objective_id: String, value: int, required: int, pc: PlayerCtx) -> void:
	_send_quest(pc, Protocol.QUEST_PROGRESS, {"quest_id": quest_id, "objective_id": objective_id, "value": value, "required": required})


func _on_ready(quest_id: String, pc: PlayerCtx) -> void:
	_send_quest(pc, Protocol.QUEST_READY, {"quest_id": quest_id})


func _on_completed(quest_id: String, pc: PlayerCtx) -> void:
	var def: QuestDef = catalog.get_quest(quest_id)
	_send_quest(pc, Protocol.QUEST_COMPLETED, {"quest_id": quest_id, "xp": def.reward_xp if def != null else 0,
		"items": def.reward_items.duplicate(true) if def != null else []})


func _on_abandoned(quest_id: String, pc: PlayerCtx) -> void:
	_send_quest(pc, Protocol.QUEST_ABANDONED, {"quest_id": quest_id})
