class_name Protocol
extends RefCounted
## Constantes e validadores puros do protocolo de rede (contrato: shared/contracts/network_protocol.md).
## Todos os validadores recebem Variant (o que chega do fio) e conferem o tipo.

## v2 (E4): c_hello passa a levar o ticket de sessao (emitido pelo backend).
const VERSION: int = 2
const DEFAULT_PORT: int = 24680
const MAX_NAME_LEN: int = 24
const MAX_BUILD_LEN: int = 32
const MAX_TYPE_LEN: int = 32
const MAX_PHASE: int = 15
const MAX_TICKET_LEN: int = 1024

const ACTION_ATTACK: int = 1
const ACTION_SKILL_1: int = 2
const ACTION_SKILL_2: int = 4
const ACTION_DODGE: int = 8
const ACTION_MASK: int = 15

const REJECT_VERSION: int = 1
const REJECT_INVALID_PAYLOAD: int = 2
const REJECT_SERVER_FULL: int = 3
const REJECT_RATE_LIMIT: int = 4
const REJECT_NOT_AUTHENTICATED: int = 5

const EVENT_PLAYER_JOINED: int = 1
const EVENT_PLAYER_LEFT: int = 2
const EVENT_DAMAGE: int = 3
const EVENT_DEATH: int = 4
const EVENT_ENEMY_SPAWN: int = 5
const EVENT_DROP: int = 6
## E5.2 (aditivo, VERSION continua 2): inimigo entrou numa nova fase `{id, phase}` (phase >= 1).
const EVENT_ENEMY_PHASE: int = 7
## E5.3 (aditivo, VERSION continua 2; docs/E5_WORLD.md): mundo de Greenwood em zonas.
## 8 zone `{id, zone, phase, pos}` (so para o jogador `id`): phase 0 = saindo (transicao iniciada), 1 = chegou em `zone`.
const EVENT_ZONE: int = 8
## 9 puzzle `{zone, puzzle, plates:[bool], open, state}` (jogadores da zona; reenviado a quem chega).
const EVENT_PUZZLE: int = 9
## 10 respawn `{id, zone, pos}` (jogadores da zona do jogador que reapareceu).
const EVENT_RESPAWN: int = 10
## 11 boss `{zone, encounter, boss, state}` (jogadores da zona): 0 armado/reiniciado, 1 ativo, 2 derrotado.
const EVENT_BOSS: int = 11
const ZONE_PHASE_LEAVING: int = 0
const ZONE_PHASE_ARRIVED: int = 1
const BOSS_ARMED: int = 0
const BOSS_ACTIVE: int = 1
const BOSS_DEFEATED: int = 2
const PUZZLE_IDLE: int = 0
const PUZZLE_PARTIAL: int = 1
const PUZZLE_OPEN: int = 2
const MAX_PLATES: int = 8

const KIND_PLAYER: int = 1
const KIND_ENEMY: int = 2

## Extensao aditiva E5.1 (quests + dialogo; VERSION continua 2, ver network_protocol.md "Revisao E5.1").
## c_quest_cmd: ops de quest. c_dialogue_cmd: ops de dialogo.
const QUEST_OP_ACCEPT: int = 1
const QUEST_OP_ABANDON: int = 2
const QUEST_OP_TURN_IN: int = 3
const DIALOGUE_OP_OPEN: int = 1
const DIALOGUE_OP_CHOOSE: int = 2
const DIALOGUE_OP_CLOSE: int = 3
## s_quest: tipos de atualizacao (dados em `data`).
const QUEST_SYNC: int = 1       ## {quests: {active, completed}} estado completo (entrada e apos mudancas grandes)
const QUEST_ACCEPTED: int = 2   ## {quest_id}
const QUEST_PROGRESS: int = 3   ## {quest_id, objective_id, value, required}
const QUEST_READY: int = 4      ## {quest_id}
const QUEST_COMPLETED: int = 5  ## {quest_id, xp, items:[{item_id, qty}]}
const QUEST_ABANDONED: int = 6  ## {quest_id}
const QUEST_ERROR: int = 7      ## {req_id, op, quest_id, code}
## s_dialogue: tipos.
const DIALOGUE_VIEW: int = 1    ## {npc_id, dialogue_id, node_id, speaker, text, text_key, choices:[{index,text,text_key}], terminal}
const DIALOGUE_END: int = 2     ## {npc_id}
const DIALOGUE_ERROR: int = 3   ## {req_id, op, code}
const MAX_CONTENT_ID_LEN: int = 48
const MAX_REQ_ID: int = 2147483647
const MAX_DIALOGUE_CHOICE: int = 15

## Limite de comprimento do vetor de movimento (contrato: <= 1.001, clamp a 1.0).
const MOVE_TOLERANCE: float = 1.001


static func _ok(extra: Dictionary = {}) -> Dictionary:
	var r: Dictionary = {"ok": true, "code": 0, "message": ""}
	r.merge(extra, true)
	return r


static func _fail(code: int, message: String) -> Dictionary:
	return {"ok": false, "code": code, "message": message}


static func is_finite_number(v: Variant) -> bool:
	var t: int = typeof(v)
	if t == TYPE_INT:
		return true
	if t == TYPE_FLOAT:
		var f: float = v
		return not is_nan(f) and not is_inf(f)
	return false


static func _valid_name_chars(s: String) -> bool:
	for i: int in s.length():
		var c: int = s.unicode_at(i)
		var okc: bool = (c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c == 32 or c == 95 or c == 45
		if not okc:
			return false
	return true


## Valida um nome de jogador (1..24, [A-Za-z0-9 _-], sem espacos nas pontas). Retorna {ok, name}.
static func validate_name(player_name: Variant) -> Dictionary:
	if typeof(player_name) != TYPE_STRING:
		return {"ok": false, "name": ""}
	var s: String = (player_name as String).strip_edges()
	if s.is_empty() or s.length() > MAX_NAME_LEN or not _valid_name_chars(s):
		return {"ok": false, "name": ""}
	return {"ok": true, "name": s}


## Ticket de sessao: String <= 1024 chars, charset [A-Za-z0-9._-] (JWT compacto). Vazio e valido
## aqui; exigir (ou nao) o ticket e politica do servidor (modo dev x modo com backend).
static func validate_ticket(ticket: Variant) -> bool:
	if typeof(ticket) != TYPE_STRING:
		return false
	var t: String = ticket
	if t.length() > MAX_TICKET_LEN:
		return false
	for i: int in t.length():
		var c: int = t.unicode_at(i)
		var okc: bool = (c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c == 46 or c == 95 or c == 45
		if not okc:
			return false
	return true


## Retorna {ok, code, message, name, ticket}. NUNCA inclua o ticket em mensagens de erro/log.
static func validate_hello(version: Variant, build: Variant, player_name: Variant, ticket: Variant) -> Dictionary:
	if typeof(version) != TYPE_INT or typeof(build) != TYPE_STRING or typeof(player_name) != TYPE_STRING or typeof(ticket) != TYPE_STRING:
		return _fail(REJECT_INVALID_PAYLOAD, "tipos invalidos no hello")
	var v: int = version
	if v != VERSION:
		return _fail(REJECT_VERSION, "versao incompativel (servidor=%d)" % VERSION)
	var b: String = build
	if b.length() > MAX_BUILD_LEN:
		return _fail(REJECT_INVALID_PAYLOAD, "build longo demais")
	var n: Dictionary = validate_name(player_name)
	if not bool(n["ok"]):
		return _fail(REJECT_INVALID_PAYLOAD, "nome invalido")
	if not validate_ticket(ticket):
		return _fail(REJECT_INVALID_PAYLOAD, "ticket invalido")
	return _ok({"name": n["name"], "ticket": ticket})


## Retorna {ok, code, message, move, yaw}. Em input velho (seq <= last_seq) ok=false e "stale"=true
## (descartar sem contar como abuso).
static func validate_input(seq: Variant, move: Variant, yaw: Variant, actions: Variant, last_seq: int) -> Dictionary:
	if typeof(seq) != TYPE_INT or typeof(actions) != TYPE_INT:
		return _fail(REJECT_INVALID_PAYLOAD, "tipos invalidos no input")
	if typeof(move) != TYPE_VECTOR2 or not is_finite_number(yaw):
		return _fail(REJECT_INVALID_PAYLOAD, "tipos invalidos no input")
	var s: int = seq
	if s <= last_seq:
		var r: Dictionary = _fail(REJECT_INVALID_PAYLOAD, "seq antigo")
		r["stale"] = true
		return r
	var a: int = actions
	if a < 0 or (a & ~ACTION_MASK) != 0:
		return _fail(REJECT_INVALID_PAYLOAD, "acoes desconhecidas")
	var m: Vector2 = move
	if is_nan(m.x) or is_nan(m.y) or is_inf(m.x) or is_inf(m.y):
		return _fail(REJECT_INVALID_PAYLOAD, "move nao finito")
	if m.length() > MOVE_TOLERANCE:
		m = m.normalized()
	var y: float = float(yaw)
	if absf(y) > 1000.0:
		return _fail(REJECT_INVALID_PAYLOAD, "yaw fora de faixa")
	y = wrapf(y, -PI, PI)
	return _ok({"move": m, "yaw": y})


## Id de conteudo estavel: `[a-z][a-z0-9_]*`, 1..MAX_CONTENT_ID_LEN. Aceita Variant (do fio).
static func is_content_id(v: Variant) -> bool:
	if typeof(v) != TYPE_STRING:
		return false
	var s: String = v
	if s.is_empty() or s.length() > MAX_CONTENT_ID_LEN:
		return false
	for i: int in s.length():
		var c: int = s.unicode_at(i)
		var is_lower: bool = c >= 97 and c <= 122
		var is_digit: bool = c >= 48 and c <= 57
		if not (is_lower or ((is_digit or c == 95) and i > 0)):
			return false
	return true


static func _valid_req_id(v: Variant) -> bool:
	return typeof(v) == TYPE_INT and int(v) >= 0 and int(v) <= MAX_REQ_ID


## c_quest_cmd(req_id, op, quest_id). Retorna {ok, code, message, req_id, op, quest_id}. Invalido = abuso.
static func validate_quest_cmd(req_id: Variant, op: Variant, quest_id: Variant) -> Dictionary:
	if not _valid_req_id(req_id) or typeof(op) != TYPE_INT:
		return _fail(REJECT_INVALID_PAYLOAD, "tipos invalidos no comando de quest")
	var o: int = op
	if o < QUEST_OP_ACCEPT or o > QUEST_OP_TURN_IN:
		return _fail(REJECT_INVALID_PAYLOAD, "operacao de quest desconhecida")
	if not is_content_id(quest_id):
		return _fail(REJECT_INVALID_PAYLOAD, "quest_id invalido")
	return _ok({"req_id": int(req_id), "op": o, "quest_id": String(quest_id)})


## c_dialogue_cmd(req_id, op, npc_id, choice). `npc_id` so vale em OPEN (vazio nas outras ops);
## `choice` so vale em CHOOSE (0 nas outras). Retorna {ok, code, message, req_id, op, npc_id, choice}.
static func validate_dialogue_cmd(req_id: Variant, op: Variant, npc_id: Variant, choice: Variant) -> Dictionary:
	if not _valid_req_id(req_id) or typeof(op) != TYPE_INT or typeof(npc_id) != TYPE_STRING or typeof(choice) != TYPE_INT:
		return _fail(REJECT_INVALID_PAYLOAD, "tipos invalidos no comando de dialogo")
	var o: int = op
	if o < DIALOGUE_OP_OPEN or o > DIALOGUE_OP_CLOSE:
		return _fail(REJECT_INVALID_PAYLOAD, "operacao de dialogo desconhecida")
	var c: int = choice
	if o == DIALOGUE_OP_OPEN and not is_content_id(npc_id):
		return _fail(REJECT_INVALID_PAYLOAD, "npc_id invalido")
	if o != DIALOGUE_OP_OPEN and not (npc_id as String).is_empty():
		return _fail(REJECT_INVALID_PAYLOAD, "npc_id so vale ao abrir")
	if o == DIALOGUE_OP_CHOOSE and (c < 0 or c > MAX_DIALOGUE_CHOICE):
		return _fail(REJECT_INVALID_PAYLOAD, "escolha fora de faixa")
	if o != DIALOGUE_OP_CHOOSE and c != 0:
		return _fail(REJECT_INVALID_PAYLOAD, "escolha so vale em choose")
	return _ok({"req_id": int(req_id), "op": o, "npc_id": String(npc_id), "choice": c})


static func _vec3_finite(v: Vector3) -> bool:
	return is_finite_number(v.x) and is_finite_number(v.y) and is_finite_number(v.z)


## Entidade do snapshot: {id, kind(1|2), pos:Vector3, yaw, hp, max_hp, state, type:String}.
static func validate_entity_dict(d: Variant) -> bool:
	if typeof(d) != TYPE_DICTIONARY:
		return false
	var e: Dictionary = d
	for key: String in ["id", "kind", "pos", "yaw", "hp", "max_hp", "state", "type"]:
		if not e.has(key):
			return false
	if typeof(e["id"]) != TYPE_INT or typeof(e["kind"]) != TYPE_INT or typeof(e["state"]) != TYPE_INT:
		return false
	var kind: int = e["kind"]
	if kind != KIND_PLAYER and kind != KIND_ENEMY:
		return false
	if typeof(e["pos"]) != TYPE_VECTOR3 or not _vec3_finite(e["pos"]):
		return false
	if not is_finite_number(e["yaw"]) or not is_finite_number(e["hp"]) or not is_finite_number(e["max_hp"]):
		return false
	if float(e["hp"]) < 0.0 or float(e["max_hp"]) < 0.0:
		return false
	if typeof(e["type"]) != TYPE_STRING or (e["type"] as String).length() > MAX_TYPE_LEN:
		return false
	# E5.2: campos OPCIONAIS de inimigo (clientes antigos ignoram): fase 0..MAX_PHASE e id do ataque em telegrafo.
	if e.has("phase") and (typeof(e["phase"]) != TYPE_INT or int(e["phase"]) < 0 or int(e["phase"]) > MAX_PHASE):
		return false
	if e.has("atk") and (typeof(e["atk"]) != TYPE_STRING or (e["atk"] as String).length() > MAX_TYPE_LEN):
		return false
	return true


## E5.3: valida os dados de um evento do mundo vindo do fio (o cliente descarta o que falhar).
static func validate_zone_event(d: Variant) -> bool:
	if typeof(d) != TYPE_DICTIONARY:
		return false
	var e: Dictionary = d
	if typeof(e.get("id", null)) != TYPE_INT or not is_content_id(e.get("zone", null)):
		return false
	var phase: Variant = e.get("phase", null)
	if typeof(phase) != TYPE_INT or int(phase) < ZONE_PHASE_LEAVING or int(phase) > ZONE_PHASE_ARRIVED:
		return false
	return typeof(e.get("pos", null)) == TYPE_VECTOR3 and _vec3_finite(e["pos"])


static func validate_puzzle_event(d: Variant) -> bool:
	if typeof(d) != TYPE_DICTIONARY:
		return false
	var e: Dictionary = d
	if not is_content_id(e.get("zone", null)) or not is_content_id(e.get("puzzle", null)) or typeof(e.get("open", null)) != TYPE_BOOL:
		return false
	var state: Variant = e.get("state", null)
	if typeof(state) != TYPE_INT or int(state) < PUZZLE_IDLE or int(state) > PUZZLE_OPEN:
		return false
	var plates: Variant = e.get("plates", null)
	if typeof(plates) != TYPE_ARRAY or (plates as Array).is_empty() or (plates as Array).size() > MAX_PLATES:
		return false
	for p: Variant in plates:
		if typeof(p) != TYPE_BOOL:
			return false
	return true


static func validate_respawn_event(d: Variant) -> bool:
	if typeof(d) != TYPE_DICTIONARY:
		return false
	var e: Dictionary = d
	return typeof(e.get("id", null)) == TYPE_INT and is_content_id(e.get("zone", null)) \
		and typeof(e.get("pos", null)) == TYPE_VECTOR3 and _vec3_finite(e["pos"])


static func validate_boss_event(d: Variant) -> bool:
	if typeof(d) != TYPE_DICTIONARY:
		return false
	var e: Dictionary = d
	var state: Variant = e.get("state", null)
	return is_content_id(e.get("zone", null)) and is_content_id(e.get("encounter", null)) and is_content_id(e.get("boss", null)) \
		and typeof(state) == TYPE_INT and int(state) >= BOSS_ARMED and int(state) <= BOSS_DEFEATED


## Valida um evento pelo `kind` (kinds sem validador especifico passam: sao tratados como antes).
static func validate_world_event(kind: int, d: Variant) -> bool:
	match kind:
		EVENT_ZONE: return validate_zone_event(d)
		EVENT_PUZZLE: return validate_puzzle_event(d)
		EVENT_RESPAWN: return validate_respawn_event(d)
		EVENT_BOSS: return validate_boss_event(d)
	return true
