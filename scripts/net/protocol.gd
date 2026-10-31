class_name Protocol
extends RefCounted
## Constantes e validadores puros do protocolo de rede (contrato: shared/contracts/network_protocol.md).
## Todos os validadores recebem Variant (o que chega do fio) e conferem o tipo.

const VERSION: int = 1
const DEFAULT_PORT: int = 24680
const MAX_NAME_LEN: int = 24
const MAX_BUILD_LEN: int = 32
const MAX_TYPE_LEN: int = 32

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

const KIND_PLAYER: int = 1
const KIND_ENEMY: int = 2

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


static func validate_hello(version: Variant, build: Variant, player_name: Variant) -> Dictionary:
	if typeof(version) != TYPE_INT or typeof(build) != TYPE_STRING or typeof(player_name) != TYPE_STRING:
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
	return _ok({"name": n["name"]})


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
	return true
