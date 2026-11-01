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
## E5.4 (aditivo, VERSION continua 2): pickup de loot INDIVIDUAL. So existe no snapshot do DONO: o servidor nunca
## envia pickups alheios. Campos: type = item_id, qty = quantidade (hp/max_hp/state/yaw sempre 0).
const KIND_PICKUP: int = 3
const MAX_PICKUP_QTY: int = 999

## E5.4 (aditivo): 12 pickup `{id, item_id, qty}` (so para o dono): o pickup `id` foi coletado e o item entrou no inventario.
## O evento 6 (drop) ganha o campo OPCIONAL `id` (id do pickup) e, no modo de loot individual, tambem so vai ao dono.
const EVENT_PICKUP: int = 12

## E5.4 (aditivo): crafting. c_craft_cmd(req_id, recipe_id) / s_craft(kind, data).
const CRAFT_OK: int = 1      ## {req_id, recipe_id, results:[{item_id, qty}]}
const CRAFT_ERROR: int = 2   ## {req_id, recipe_id, code}
const MAX_CRAFT_RESULTS: int = 4

## E5.6 (aditivo, VERSION continua 2): INVENTARIO SINCRONIZADO. s_inventory(data) (servidor -> SO o dono, reliable):
## `{capacity:int 1..MAX_INVENTORY_SLOTS, slots:[{item_id, qty}] (<= capacity entradas, uma por pilha), equipment:{weapon?,armor?,trinket?}}`.
## E o estado COMPLETO e autoritativo (substitui o anterior); enviado no welcome e depois so quando muda (coalescido).
const MAX_INVENTORY_SLOTS: int = 200
const INVENTORY_EQUIP_SLOTS: Array[String] = ["weapon", "armor", "trinket"]

## E5.7 (aditivo, VERSION continua 2): SNAPSHOT COMPACTO. O cliente anuncia capacidades com `c_caps(caps)` (reliable, apos o
## welcome); se `CAP_SNAPSHOT_COMPACT` estiver ligada o servidor envia `s_snapshot_c(tick, last_input_seq, part, parts, blob)`
## (unreliable_ordered) em vez de `s_snapshot`. Codificacao em `SnapshotCodec`, mescla em `SnapshotAssembler`.
## Sem a capacidade (cliente antigo/bot antigo) o servidor continua enviando o `s_snapshot` legado.
const CAP_SNAPSHOT_COMPACT: int = 1
const CAPS_KNOWN_MASK: int = 1
const MAX_SNAPSHOT_PARTS: int = 16
## MTU de payload considerado (ENet/UDP sem fragmentar); nenhuma mensagem unreliable de snapshot compacto passa disso.
const MTU_PAYLOAD: int = 1392

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
	if kind != KIND_PLAYER and kind != KIND_ENEMY and kind != KIND_PICKUP:
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
	# E5.4: pickup individual: `type` e um id de item e `qty` (obrigatorio) esta em 1..MAX_PICKUP_QTY.
	if kind == KIND_PICKUP:
		if not is_content_id(e["type"]) or typeof(e.get("qty", null)) != TYPE_INT or int(e["qty"]) < 1 or int(e["qty"]) > MAX_PICKUP_QTY:
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


## E5.4: evento 6 (drop) `{pos, item_id, qty, id?}`. `id` (opcional) e o id do pickup individual.
static func validate_drop_event(d: Variant) -> bool:
	if typeof(d) != TYPE_DICTIONARY:
		return false
	var e: Dictionary = d
	if typeof(e.get("pos", null)) != TYPE_VECTOR3 or not _vec3_finite(e["pos"]) or not is_content_id(e.get("item_id", null)):
		return false
	var q: Variant = e.get("qty", null)
	if typeof(q) != TYPE_INT or int(q) < 1 or int(q) > MAX_PICKUP_QTY:
		return false
	return not e.has("id") or typeof(e["id"]) == TYPE_INT


## E5.4: evento 12 (pickup coletado) `{id, item_id, qty}`.
static func validate_pickup_event(d: Variant) -> bool:
	if typeof(d) != TYPE_DICTIONARY:
		return false
	var e: Dictionary = d
	var q: Variant = e.get("qty", null)
	return typeof(e.get("id", null)) == TYPE_INT and is_content_id(e.get("item_id", null)) \
		and typeof(q) == TYPE_INT and int(q) >= 1 and int(q) <= MAX_PICKUP_QTY


## E5.4: c_craft_cmd(req_id, recipe_id). Retorna {ok, code, message, req_id, recipe_id}. Invalido = abuso.
static func validate_craft_cmd(req_id: Variant, recipe_id: Variant) -> Dictionary:
	if not _valid_req_id(req_id):
		return _fail(REJECT_INVALID_PAYLOAD, "req_id invalido no comando de crafting")
	if not is_content_id(recipe_id):
		return _fail(REJECT_INVALID_PAYLOAD, "recipe_id invalido")
	return _ok({"req_id": int(req_id), "recipe_id": String(recipe_id)})


## E5.4: s_craft(kind, data) vindo do fio (o cliente descarta o que falhar).
static func validate_craft_update(kind: Variant, d: Variant) -> bool:
	if typeof(kind) != TYPE_INT or typeof(d) != TYPE_DICTIONARY:
		return false
	var e: Dictionary = d
	if typeof(e.get("req_id", null)) != TYPE_INT or not is_content_id(e.get("recipe_id", null)):
		return false
	if int(kind) == CRAFT_ERROR:
		return typeof(e.get("code", null)) == TYPE_STRING and (e["code"] as String).length() <= MAX_TYPE_LEN
	if int(kind) != CRAFT_OK:
		return false
	var res: Variant = e.get("results", null)
	if typeof(res) != TYPE_ARRAY or (res as Array).is_empty() or (res as Array).size() > MAX_CRAFT_RESULTS:
		return false
	for r: Variant in res:
		if typeof(r) != TYPE_DICTIONARY or not is_content_id((r as Dictionary).get("item_id", null)):
			return false
		var q: Variant = (r as Dictionary).get("qty", null)
		if typeof(q) != TYPE_INT or int(q) < 1 or int(q) > MAX_PICKUP_QTY:
			return false
	return true


## E5.6: s_inventory(data) vindo do fio (o cliente descarta o que falhar). Limites: capacity 1..200, ate `capacity` pilhas,
## item_id de conteudo, qty 1..999, so os 3 slots de equipamento conhecidos com item de conteudo.
static func validate_inventory_update(d: Variant) -> bool:
	if typeof(d) != TYPE_DICTIONARY:
		return false
	var e: Dictionary = d
	var cap: Variant = e.get("capacity", null)
	if typeof(cap) != TYPE_INT or int(cap) < 1 or int(cap) > MAX_INVENTORY_SLOTS:
		return false
	var slots: Variant = e.get("slots", null)
	if typeof(slots) != TYPE_ARRAY or (slots as Array).size() > int(cap):
		return false
	for s: Variant in slots:
		if typeof(s) != TYPE_DICTIONARY or not is_content_id((s as Dictionary).get("item_id", null)):
			return false
		var q: Variant = (s as Dictionary).get("qty", null)
		if typeof(q) != TYPE_INT or int(q) < 1 or int(q) > MAX_PICKUP_QTY:
			return false
	var eq: Variant = e.get("equipment", null)
	if typeof(eq) != TYPE_DICTIONARY or (eq as Dictionary).size() > INVENTORY_EQUIP_SLOTS.size():
		return false
	for k: Variant in (eq as Dictionary):
		if typeof(k) != TYPE_STRING or not INVENTORY_EQUIP_SLOTS.has(String(k)) or not is_content_id((eq as Dictionary)[k]):
			return false
	return true


## E5.7: c_caps(caps) vindo do cliente. Retorna {ok, code, message, caps}; bits desconhecidos sao IGNORADOS (mascarados) para
## permitir clientes mais novos; tipo errado ou fora de 0..0xFFFF e invalido (abuso).
static func validate_caps(caps: Variant) -> Dictionary:
	if typeof(caps) != TYPE_INT or int(caps) < 0 or int(caps) > 0xFFFF:
		return _fail(REJECT_INVALID_PAYLOAD, "caps invalido")
	return _ok({"caps": int(caps) & CAPS_KNOWN_MASK})


## E5.7: cabecalho de uma parte de snapshot compacto vindo do fio: tick >= 0, last_input_seq inteiro, 0 <= part < parts <=
## MAX_SNAPSHOT_PARTS e blob PackedByteArray de 1..MTU_PAYLOAD bytes. O conteudo do blob e validado por `SnapshotCodec.decode_part`.
static func validate_snapshot_part(server_tick: Variant, last_input_seq: Variant, part: Variant, parts: Variant, blob: Variant) -> bool:
	if typeof(server_tick) != TYPE_INT or typeof(last_input_seq) != TYPE_INT or typeof(part) != TYPE_INT or typeof(parts) != TYPE_INT:
		return false
	if int(server_tick) < 0 or int(parts) < 1 or int(parts) > MAX_SNAPSHOT_PARTS or int(part) < 0 or int(part) >= int(parts):
		return false
	if typeof(blob) != TYPE_PACKED_BYTE_ARRAY:
		return false
	var n: int = (blob as PackedByteArray).size()
	return n >= 1 and n <= MTU_PAYLOAD


## Valida um evento pelo `kind` (kinds sem validador especifico passam: sao tratados como antes).
static func validate_world_event(kind: int, d: Variant) -> bool:
	match kind:
		EVENT_DROP: return validate_drop_event(d)
		EVENT_PICKUP: return validate_pickup_event(d)
		EVENT_ZONE: return validate_zone_event(d)
		EVENT_PUZZLE: return validate_puzzle_event(d)
		EVENT_RESPAWN: return validate_respawn_event(d)
		EVENT_BOSS: return validate_boss_event(d)
	return true
