extends RefCounted
## Utilitarios dos testes E5.5 (UI do cliente). Nao e um teste (sem prefixo test_).
## Sessao de cliente PLAYING com comandos capturados em `sent` e teclas sinteticas.

const HUB_ORLA: Vector3 = Vector3(10.0, 0.05, -8.0)
const HUB_STATION: Vector3 = Vector3(6.0, 0.05, -4.0)
const HUB_FAR: Vector3 = Vector3(-20.0, 0.05, 10.0)

static var _event_id: int = 1000


## {session, sent}. `sent` recebe ["quest", op, quest_id], ["dlg", op, npc, choice], ["craft", recipe_id].
static func make_session(player_id: int = 7) -> Dictionary:
	var sent: Array = []
	var ss: ClientSession = ClientSession.new()
	ss.send_quest_cmd = func(_r: int, op: int, qid: String) -> void: sent.append(["quest", op, qid])
	ss.send_dialogue_cmd = func(_r: int, op: int, npc: String, choice: int) -> void: sent.append(["dlg", op, npc, choice])
	ss.send_craft_cmd = func(_r: int, rid: String) -> void: sent.append(["craft", rid])
	ss.begin(Protocol.VERSION, "test", "Tester")
	ss.on_welcome(player_id, 30, 1)
	return {"session": ss, "sent": sent}


static func player(id: int, pos: Vector3, hp: float = 100.0, max_hp: float = 100.0) -> Dictionary:
	return {"id": id, "kind": Protocol.KIND_PLAYER, "pos": pos, "yaw": 0.0, "hp": hp, "max_hp": max_hp, "state": 0, "type": "player"}


static func enemy(id: int, type: String, pos: Vector3, hp: float = 50.0, max_hp: float = 50.0, phase: int = 0) -> Dictionary:
	return {"id": id, "kind": Protocol.KIND_ENEMY, "pos": pos, "yaw": 0.0, "hp": hp, "max_hp": max_hp, "state": 0, "type": type, "phase": phase, "atk": ""}


static var _tick: int = 1


## Entrega um snapshot (o 1o com o jogador local) e devolve o tick usado.
static func snapshot(ss: ClientSession, entities: Array) -> void:
	_tick += 1
	ss.on_snapshot(_tick, 0, entities, float(_tick) * 33.0)


static func world_event(ss: ClientSession, kind: int, data: Dictionary) -> void:
	_event_id += 1
	ss.on_event(_event_id, kind, data)


static func key(code: Key, echo: bool = false) -> InputEventKey:
	var e: InputEventKey = InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = true
	e.echo = echo
	return e


static func make_ui(tree: SceneTree, ss: ClientSession) -> ClientUi:
	var ui: ClientUi = ClientUi.new()
	tree.root.add_child(ui)
	ui.bind(ss)
	return ui


static func free_ui(tree: SceneTree, ui: ClientUi) -> void:
	tree.root.remove_child(ui)
	ui.queue_free()


static func quest_sync(log: ClientQuestLog, active: Dictionary, completed: Array, statuses: Dictionary) -> void:
	log.apply(Protocol.QUEST_SYNC, {"quests": {"active": active, "completed": completed}, "statuses": statuses})
