extends BackendTransport
## Backend FALSO em memoria para testes (sem rede): implementa o contrato interno (E4_SESSIONS /
## E4_CHARACTERS) o bastante para exercitar o servidor Godot. Nao e um teste (sem prefixo test_).
## `hold = true` segura as respostas ate `flush()` (simula latencia / serializacao).
## `forced[needle]` = fila de respostas forcadas para caminhos que contem `needle`.

const SESSION_ID: String = "aaaaaaaa-0000-4000-8000-000000000001"
const NET_ERR: Dictionary = {"status": 0, "body": "", "error": "network"}
const TIMEOUT_ERR: Dictionary = {"status": 0, "body": "", "error": "timeout"}

var requests: Array[Dictionary] = []
var hold: bool = false
var held: Array = [] ## [[cb, resp], ...]
var tickets: Dictionary = {} ## ticket -> character_id
var chars: Dictionary = {} ## character_id -> Dictionary (visao interna do backend)
var forced: Dictionary = {}
var claims: Dictionary = {} ## idempotency_key -> true
var last_session_header: String = ""
var last_auth: String = ""
var cancelled: int = 0


static func err(status: int, code: String) -> Dictionary:
	return {"status": status, "body": JSON.stringify({"error": {"code": code, "message": "x"}}), "error": ""}


static func ok(data: Dictionary, status: int = 200) -> Dictionary:
	return {"status": status, "body": JSON.stringify(data), "error": ""}


func add_character(cid: String, level: int = 1, xp: int = 0, inventory: Array = [], equipment: Dictionary = {"weapon": "sword_basic", "armor": "armor_leather"}, revision: int = 0, char_name: String = "Hero") -> void:
	chars[cid] = {
		"account_id": "acc", "id": cid, "name": char_name, "class_id": "warrior", "level": level, "xp": xp,
		"stats": {"max_health": 100, "max_resource": 50, "resource_regen": 5, "attack_power": 10, "defense": 0, "resistance": 0, "move_speed": 5},
		"schema_version": 1, "revision": revision, "inventory_capacity": 24, "inventory": inventory.duplicate(true), "equipment": equipment.duplicate(true),
	}


func force(needle: String, responses: Array) -> void:
	forced[needle] = responses


func send(req: Dictionary, cb: Callable) -> void:
	var url: String = String(req["url"])
	var path: String = url.substr(url.find("/internal"))
	var body: Dictionary = {}
	if not String(req.get("body", "")).is_empty():
		var parsed: Variant = JSON.parse_string(String(req["body"]))
		if typeof(parsed) == TYPE_DICTIONARY:
			body = parsed
	var session_header: String = ""
	for h: String in req.get("headers", PackedStringArray()):
		if h.begins_with("Authorization: Bearer "):
			last_auth = h.substr(22)
		if h.begins_with("X-Session-Id: "):
			session_header = h.substr(14)
	last_session_header = session_header
	requests.append({"method": String(req["method"]), "path": path, "body": body, "raw": String(req.get("body", "")), "session_header": session_header})
	var resp: Dictionary = {}
	for needle: String in forced:
		var q: Array = forced[needle]
		if (String(req["method"]) + " " + path).contains(needle) and not q.is_empty():
			resp = q.pop_front()
			break
	if resp.is_empty():
		resp = _route(String(req["method"]), path, body)
	if hold:
		held.append([cb, resp])
	else:
		cb.call(resp)


func flush(max_n: int = -1) -> int:
	var n: int = 0
	while not held.is_empty() and (max_n < 0 or n < max_n):
		var item: Array = held.pop_front()
		(item[0] as Callable).call(item[1])
		n += 1
	return n


func cancel_all() -> void:
	cancelled += 1
	held.clear()


func count(needle: String) -> int:
	var n: int = 0
	for r: Dictionary in requests:
		if (String(r["method"]) + " " + String(r["path"])).contains(needle):
			n += 1
	return n


func count_path(path: String) -> int:
	var n: int = 0
	for r: Dictionary in requests:
		if String(r["path"]) == path:
			n += 1
	return n


func find_all(needle: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for r: Dictionary in requests:
		if (String(r["method"]) + " " + String(r["path"])).contains(needle):
			out.append(r)
	return out


func order() -> Array[String]:
	var out: Array[String] = []
	for r: Dictionary in requests:
		out.append(String(r["method"]) + " " + String(r["path"]))
	return out


func _cid(path: String) -> String:
	return path.split("/")[3]


func _route(method: String, path: String, body: Dictionary) -> Dictionary:
	if path == "/internal/sessions":
		return ok({"session_id": SESSION_ID, "status": "open", "heartbeat_timeout_seconds": 30, "reconnect_window_seconds": 90}, 201)
	if path.ends_with("/heartbeat"):
		return ok({"locks_refreshed": 0})
	if path.begins_with("/internal/sessions/") and path.ends_with("/close"):
		return ok({"locks_released": 0})
	if path == "/internal/tickets/redeem":
		var t: String = String(body.get("ticket", ""))
		if not tickets.has(t):
			return err(401, "unauthorized")
		return ok({"character_id": tickets[t], "account_id": "acc", "session_id": SESSION_ID, "reconnected": false})
	if path.begins_with("/internal/characters/"):
		var cid: String = _cid(path)
		var ch: Dictionary = chars.get(cid, {})
		if ch.is_empty():
			return err(404, "not_found")
		if method == "GET":
			return ok({"character": ch})
		if (path.ends_with("/checkpoint") or path.ends_with("/rewards")) and last_session_header != SESSION_ID:
			return err(409, "session_fenced")
		if path.ends_with("/checkpoint"):
			if int(body.get("expected_revision", -1)) != int(ch["revision"]):
				return err(409, "revision_conflict")
			var st: Dictionary = body["state"]
			for k: String in ["level", "xp", "stats", "inventory", "equipment"]:
				ch[k] = st[k]
			ch["revision"] = int(ch["revision"]) + 1
			return ok({"character": ch})
		if path.ends_with("/rewards"):
			var key: String = String(body.get("idempotency_key", ""))
			var replay: bool = claims.has(key)
			if not replay:
				claims[key] = true
				ch["xp"] = int(ch["xp"]) + int(body.get("xp", 0))
				for it: Variant in body.get("items", []):
					(ch["inventory"] as Array).append({"slot": (ch["inventory"] as Array).size(), "item_id": (it as Dictionary)["item_id"], "qty": (it as Dictionary)["qty"]})
				ch["revision"] = int(ch["revision"]) + 1
			return ok({"replayed": replay, "result": {}, "character": ch})
		if path.ends_with("/disconnect"):
			return ok({"reconnect_until": "2030-01-01T00:00:00Z"})
		if path.ends_with("/release"):
			return ok({"released": true})
	return err(404, "not_found")
