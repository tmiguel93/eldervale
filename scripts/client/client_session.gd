class_name ClientSession
extends RefCounted
## Logica de sessao do cliente, independente de rede e de nos: maquina de estados, hello/welcome/
## reject, snapshots -> interpolador/predicao, eventos (dedupe), ping/RTT, envio de input com seq.
## O transporte e injetado por Callables (testavel sem rede). O cliente nunca decide combate.

enum State { IDLE, HELLO_SENT, PLAYING, REJECTED, DISCONNECTED }

const INPUT_DT: float = 1.0 / LocalInput.SEND_HZ

var state: State = State.IDLE
var message: String = ""
var player_id: int = -1
var tick_rate: int = 30
var session_seed: int = 0
var entity_count: int = 0
var last_rtt_ms: float = -1.0
var last_event_id: int = 0
var events_dropped: int = 0
var entities_rejected: int = 0
## E5.7: snapshot compacto. `send_caps(caps:int)` e injetado (c_caps); partes chegam por `on_snapshot_part` e so viram um
## snapshot quando completas (SnapshotAssembler). `compact_snapshots` conta snapshots completos recebidos por este caminho.
var send_caps: Callable
var snapshot_assembler: SnapshotAssembler = SnapshotAssembler.new()
var compact_snapshots: int = 0

var interpolator: SnapshotInterpolator = SnapshotInterpolator.new()
var prediction: Prediction = Prediction.new()
var input: LocalInput = LocalInput.new()
var result: BotResult = BotResult.new()
var local_entity: Dictionary = {}
var last_input_seq_ack: int = 0
var last_entities: Array = []      # entidades validadas do ultimo snapshot (para bots)
var _used_ticket: bool = false
## E5.3: espelho (somente leitura) do mundo: zona atual, ultimo estado do puzzle/chefe da zona.
var zone_id: String = ""
var puzzle_state: Dictionary = {}
var boss_state: int = -1
var world_events_rejected: int = 0

## Callables injetados: send_hello(version:int, build:String, name:String, ticket:String),
## send_input(seq:int, move:Vector2, yaw:float, actions:int, client_tick:int), send_ping(client_time_ms:int).
var send_hello: Callable
var send_input: Callable
var send_ping: Callable
## E5.1: send_quest_cmd(req_id:int, op:int, quest_id:String); send_dialogue_cmd(req_id:int, op:int, npc_id:String, choice:int).
var send_quest_cmd: Callable
var send_dialogue_cmd: Callable
## E5.4: send_craft_cmd(req_id:int, recipe_id:String). O resultado chega em `craft_finished` (o servidor decide tudo).
var send_craft_cmd: Callable
signal craft_finished(ok: bool, data: Dictionary)
var crafts_rejected: int = 0
## E5.6: inventario COMPLETO sincronizado pelo servidor (s_inventory). `inventory_data` = ultimo payload valido
## ({capacity, slots, equipment}; vazio ate o primeiro). A UI escuta `inventory_synced`.
signal inventory_synced(data: Dictionary)
var inventory_data: Dictionary = {}
var inventory_updates: int = 0
var inventory_rejected: int = 0

## E6.1: classe do personagem informada pelo servidor (s_class; so o dono recebe). Vazio ate chegar. O cliente NAO escolhe nem muda
## a classe nem as habilidades: so usa o id para o HUD (catalogo local). Id desconhecido localmente e descartado e contado.
signal class_synced(class_id: String)
var class_id: String = ""
var class_updates: int = 0
var class_rejected: int = 0

## E6.2: talentos. send_talent_cmd(req_id:int, op:int, arg:String). `talents_state` = ultimo s_talents(STATE) valido (vazio ate chegar):
## {spec, ranks, respecs, level, points_total, points_spent, points_available, req_id}. O cliente so PEDE; o servidor decide tudo.
var send_talent_cmd: Callable
signal talents_changed(state: Dictionary)
signal talents_error(req_id: int, op: int, code: String)
var talents_state: Dictionary = {}
var talents_updates: int = 0
var talents_rejected: int = 0

## E5.1: espelho do diario de quests e do dialogo atual (somente leitura; a UI escuta os sinais).
signal dialogue_changed(view: Dictionary)   ## view vazio = dialogo encerrado
signal dialogue_error(req_id: int, op: int, code: String)
var quest_log: ClientQuestLog = ClientQuestLog.new()
var dialogue_view: Dictionary = {}
var _next_req_id: int = 1

var _events: Array[Dictionary] = []
var _client_tick: int = 0
var _last_sent_seq: int = 0


## Hello v2: o ticket (join ticket do backend, uso unico) vai so no c_hello e nao e guardado.
func begin(version: int, build: String, player_name: String, ticket: String = "") -> void:
	state = State.HELLO_SENT
	message = "Conectando..."
	_used_ticket = not ticket.is_empty()
	if send_hello.is_valid():
		send_hello.call(version, build, player_name, ticket)


func on_welcome(p_player_id: int, p_tick_rate: int, p_seed: int) -> void:
	if state != State.HELLO_SENT:
		return  # nao pedimos hello (ou ja recebemos): ignora, conforme contrato
	player_id = p_player_id
	tick_rate = maxi(p_tick_rate, 1)
	session_seed = p_seed
	state = State.PLAYING
	message = "Conectado (id %d)" % player_id
	interpolator.configure(tick_rate)
	snapshot_assembler.reset()
	if send_caps.is_valid():
		send_caps.call(Protocol.CAP_SNAPSHOT_COMPACT)
	result.on_welcome(player_id, tick_rate)
	result.ticket_used_ok = _used_ticket


func on_reject(code: int, text: String) -> void:
	state = State.REJECTED
	message = reject_text(code, text)
	result.on_reject(code, text)


func on_disconnected() -> void:
	result.disconnected = true
	if state != State.REJECTED:
		state = State.DISCONNECTED
		message = "Desconectado do servidor." if player_id >= 0 else "Falha ao conectar ao servidor."


func on_snapshot(server_tick: int, last_input_seq: int, raw_entities: Array, now_ms: float) -> void:
	if state != State.PLAYING:
		return
	var entities: Array = []
	for e0: Variant in raw_entities:
		if Protocol.validate_entity_dict(e0):
			entities.append(e0)
		else:
			entities_rejected += 1
	if not interpolator.push(server_tick, now_ms, entities):
		return
	result.on_snapshot(now_ms, server_tick, entities)
	entity_count = entities.size()
	last_entities = entities
	last_input_seq_ack = last_input_seq
	local_entity = {}
	for e: Variant in entities:
		if e is Dictionary and int((e as Dictionary).get("id", -1)) == player_id:
			local_entity = e
			break
	if not local_entity.is_empty():
		var p: Variant = local_entity.get("pos", null)
		if p is Vector3:
			prediction.reconcile(p, last_input_seq)


## E5.7: uma parte de s_snapshot_c. Descarta/conta parte malformada, duplicada ou velha; ao completar o tick entrega o
## snapshot mesclado ao mesmo caminho do legado (validacao por entidade, interpolacao, reconciliacao).
func on_snapshot_part(server_tick: int, last_input_seq: int, part: int, parts: int, blob: PackedByteArray, now_ms: float) -> void:
	if state != State.PLAYING:
		return
	var r: Dictionary = snapshot_assembler.push(server_tick, last_input_seq, part, parts, blob)
	if not bool(r["complete"]):
		return
	compact_snapshots += 1
	result.compact_snapshots = compact_snapshots
	on_snapshot(int(r["tick"]), int(r["last_seq"]), r["entities"], now_ms)


func on_event(event_id: int, kind: int, data: Dictionary) -> void:
	if event_id <= last_event_id:
		events_dropped += 1
		return
	last_event_id = event_id
	if not Protocol.validate_world_event(kind, data):
		world_events_rejected += 1 # evento de mundo malformado: nao chega a apresentacao
		return
	result.on_event(kind)
	_track_world_event(kind, data)
	_events.append({"id": event_id, "kind": kind, "data": data})


## E5.3: guarda o estado de mundo anunciado pelo servidor. Teleporte (zona/respawn) do jogador local
## invalida a predicao: ela e refeita a partir da posicao do proximo snapshot.
func _track_world_event(kind: int, data: Dictionary) -> void:
	match kind:
		Protocol.EVENT_ZONE:
			if int(data["id"]) == player_id and int(data["phase"]) == Protocol.ZONE_PHASE_ARRIVED:
				zone_id = String(data["zone"])
				puzzle_state = {}
				boss_state = -1
				prediction.initialized = false
		Protocol.EVENT_PUZZLE:
			if String(data["zone"]) == zone_id or zone_id.is_empty():
				puzzle_state = data
		Protocol.EVENT_BOSS:
			if String(data["zone"]) == zone_id or zone_id.is_empty():
				boss_state = int(data["state"])
		Protocol.EVENT_RESPAWN:
			if int(data["id"]) == player_id:
				prediction.initialized = false


func drain_events() -> Array[Dictionary]:
	var out: Array[Dictionary] = _events
	_events = []
	return out


func on_pong(client_time_ms: int, now_ms: float) -> void:
	var rtt: float = now_ms - float(client_time_ms)
	if rtt < 0.0 or rtt > 60000.0:
		return
	last_rtt_ms = rtt
	result.on_rtt(rtt)


func ping(now_ms: float) -> void:
	if state == State.PLAYING and send_ping.is_valid():
		send_ping.call(int(now_ms))


## Envia um input (seq crescente) e preve o movimento local. Retorna o seq usado.
func send_move(move: Vector2, yaw: float, actions: int) -> int:
	if state != State.PLAYING:
		return -1
	var s: int = input.next_seq()
	_dispatch(s, move, yaw, actions)
	if not prediction.initialized and not local_entity.is_empty() and local_entity.get("pos") is Vector3:
		prediction.init_at(local_entity["pos"])
	prediction.apply_input(s, move.limit_length(1.0) if move.is_finite() else Vector2.ZERO, yaw if is_finite(yaw) else 0.0, INPUT_DT)
	return s


## Envia itens de roteiro de bot (podem ser invalidos de proposito; so predizem os validos).
func send_bot_items(items: Array[Dictionary]) -> void:
	if state != State.PLAYING:
		return
	for it: Dictionary in items:
		var move: Vector2 = it.get("move", Vector2.ZERO)
		var yaw: float = float(it.get("yaw", 0.0))
		var actions: int = int(it.get("actions", 0))
		var valid: bool = move.is_finite() and is_finite(yaw) and move.length() <= 1.001 and (actions & ~15) == 0 and not it.has("seq_repeat")
		if valid:
			send_move(move, yaw, actions)
		elif it.has("seq_repeat"):
			_dispatch(_last_sent_seq, move, yaw, actions)
		else:
			var s: int = input.next_seq()
			_dispatch(s, move, yaw, actions)


func _dispatch(seq: int, move: Vector2, yaw: float, actions: int) -> void:
	_last_sent_seq = seq
	_client_tick += 1
	result.inputs_sent += 1
	if send_input.is_valid():
		send_input.call(seq, move, yaw, actions, _client_tick)


static func reject_text(code: int, server_message: String) -> String:
	var base: String
	match code:
		1: base = "Versao incompativel com o servidor. Atualize o jogo."
		2: base = "Servidor recusou dados invalidos."
		3: base = "Servidor cheio."
		4: base = "Desconectado por excesso de mensagens (rate limit)."
		5: base = "Sessao nao autorizada / ordem de mensagens invalida."
		_: base = "Conexao recusada (codigo %d)." % code
	return base if server_message.is_empty() else base + " (" + server_message + ")"


# ------------------------------------------------------------------ quests / dialogo (E5.1)

## s_quest do servidor (so aceito em PLAYING).
func on_quest_update(kind: int, data: Dictionary) -> void:
	if state == State.PLAYING:
		quest_log.apply(kind, data)


## s_dialogue do servidor.
func on_dialogue(kind: int, data: Dictionary) -> void:
	if state != State.PLAYING:
		return
	match kind:
		Protocol.DIALOGUE_VIEW:
			if typeof(data.get("choices", null)) != TYPE_ARRAY or typeof(data.get("text", null)) != TYPE_STRING:
				return
			dialogue_view = data
			dialogue_changed.emit(dialogue_view)
		Protocol.DIALOGUE_END:
			dialogue_view = {}
			dialogue_changed.emit(dialogue_view)
		Protocol.DIALOGUE_ERROR:
			dialogue_error.emit(int(data.get("req_id", 0)), int(data.get("op", 0)), String(data.get("code", "")).substr(0, 48))


## s_craft do servidor (so aceito em PLAYING; malformado e descartado e contado).
func on_craft_update(kind: int, data: Dictionary) -> void:
	if state != State.PLAYING:
		return
	if not Protocol.validate_craft_update(kind, data):
		crafts_rejected += 1
		return
	craft_finished.emit(kind == Protocol.CRAFT_OK, data)


## s_inventory do servidor (so aceito em PLAYING; malformado e descartado e contado). Substitui o estado anterior.
func on_inventory_update(data: Dictionary) -> void:
	if state != State.PLAYING:
		return
	if not Protocol.validate_inventory_update(data):
		inventory_rejected += 1
		return
	inventory_data = data
	inventory_updates += 1
	result.on_inventory(data)
	inventory_synced.emit(data)


## s_class do servidor (so aceito em PLAYING; malformado ou de classe desconhecida e descartado e contado).
func on_class_update(data: Dictionary) -> void:
	if state != State.PLAYING:
		return
	if not Protocol.validate_class_update(data) or not ClassCatalog.shared().has_class(data["class_id"]):
		class_rejected += 1
		return
	class_id = String(data["class_id"])
	class_updates += 1
	result.on_class(class_id)
	class_synced.emit(class_id)


## s_talents do servidor (so aceito em PLAYING; malformado e descartado e contado).
func on_talents_update(kind: int, data: Dictionary) -> void:
	if state != State.PLAYING:
		return
	if not Protocol.validate_talents_update(kind, data):
		talents_rejected += 1
		return
	if kind == Protocol.TALENTS_ERROR:
		result.on_talents_error(data)
		talents_error.emit(int(data["req_id"]), int(data["op"]), String(data["code"]))
		return
	talents_state = data
	talents_updates += 1
	result.on_talents(data)
	talents_changed.emit(data)


## Pede uma operacao de talentos (alocar no / respec / escolher especializacao). O servidor valida tudo e responde por
## `talents_changed`/`talents_error`. Devolve o req_id (-1 se nao enviou).
func talent_cmd(op: int, arg: String = "") -> int:
	if state != State.PLAYING or not send_talent_cmd.is_valid():
		return -1
	var r: int = _next_req()
	send_talent_cmd.call(r, op, arg)
	return r


func talent_allocate(node_id: String) -> int:
	return talent_cmd(Protocol.TALENT_OP_ALLOCATE, node_id)


func talent_respec() -> int:
	return talent_cmd(Protocol.TALENT_OP_RESPEC, "")


func talent_choose_spec(spec_id: String) -> int:
	return talent_cmd(Protocol.TALENT_OP_CHOOSE_SPEC, spec_id)


## Pede para fabricar `recipe_id` (precisa estar perto da estacao; o servidor valida). Devolve o req_id (-1 se nao enviou).
func craft(recipe_id: String) -> int:
	if state != State.PLAYING or not send_craft_cmd.is_valid() or not Protocol.is_content_id(recipe_id):
		return -1
	var r: int = _next_req()
	send_craft_cmd.call(r, recipe_id)
	return r


func _next_req() -> int:
	var r: int = _next_req_id
	_next_req_id = (_next_req_id % Protocol.MAX_REQ_ID) + 1
	return r


## Pedidos (o servidor decide; resposta chega por quest_log/dialogue_*). Devolvem o req_id (-1 se nao enviou).
func quest_accept(quest_id: String) -> int:
	return _send_quest(Protocol.QUEST_OP_ACCEPT, quest_id)


func quest_abandon(quest_id: String) -> int:
	return _send_quest(Protocol.QUEST_OP_ABANDON, quest_id)


func quest_turn_in(quest_id: String) -> int:
	return _send_quest(Protocol.QUEST_OP_TURN_IN, quest_id)


func _send_quest(op: int, quest_id: String) -> int:
	if state != State.PLAYING or not send_quest_cmd.is_valid() or not Protocol.is_content_id(quest_id):
		return -1
	var r: int = _next_req()
	send_quest_cmd.call(r, op, quest_id)
	return r


func dialogue_open(npc_id: String) -> int:
	if not Protocol.is_content_id(npc_id):
		return -1
	return _send_dialogue(Protocol.DIALOGUE_OP_OPEN, npc_id, 0)


func dialogue_choose(index: int) -> int:
	if index < 0 or index > Protocol.MAX_DIALOGUE_CHOICE:
		return -1
	return _send_dialogue(Protocol.DIALOGUE_OP_CHOOSE, "", index)


func dialogue_close() -> int:
	return _send_dialogue(Protocol.DIALOGUE_OP_CLOSE, "", 0)


func _send_dialogue(op: int, npc_id: String, choice: int) -> int:
	if state != State.PLAYING or not send_dialogue_cmd.is_valid():
		return -1
	var r: int = _next_req()
	send_dialogue_cmd.call(r, op, npc_id, choice)
	return r
