class_name BackendApi
extends Node
## Cliente HTTP assincrono das rotas PUBLICAS do backend (/v1/*). Tokens ficam so em memoria.
## Todas as chamadas sao corrotinas (use `await`) e devolvem {ok, status, data, code, message}.
## Transporte injetavel: Callable(method:String, url:String, headers:PackedStringArray, body:String)
## -> Dictionary {error:int, status:int, body:String} (pode ser corrotina). Padrao: HTTPRequest.
## Nunca registra senha, tokens nem ticket (nenhum print/push_* contem esses valores).
## Limite conhecido: chamadas autenticadas concorrentes que recebam 401 ao mesmo tempo podem
## disputar o refresh (o servidor trata refresh repetido como reuso); use as chamadas em serie.

const TIMEOUT_S: float = 15.0
const MAX_BODY_BYTES: int = 262144
const LOCAL_HOSTS: PackedStringArray = ["localhost", "127.0.0.1", "::1", "[::1]"]

var transport: Callable = Callable()
var base_url: String = ""
var _access: String = ""
var _refresh: String = ""


## Define a URL base. HTTPS e obrigatorio, exceto para localhost/127.0.0.1/::1. Devolve "" se ok, senao o erro.
func set_base_url(url: String) -> String:
	var u: String = url.strip_edges()
	var scheme: String = ""
	if u.begins_with("https://"):
		scheme = "https"
		u = u.substr(8)
	elif u.begins_with("http://"):
		scheme = "http"
		u = u.substr(7)
	else:
		return "URL do backend deve comecar com https:// (ou http:// em localhost)"
	while u.ends_with("/"):
		u = u.substr(0, u.length() - 1)
	var authority: String = u.get_slice("/", 0)
	if authority.is_empty() or authority.contains("@") or authority.contains(" ") or authority.contains("?") or authority.contains("#"):
		return "URL do backend invalida"
	var host: String = authority
	if authority.begins_with("["):
		host = authority.substr(0, authority.find("]") + 1) if authority.contains("]") else authority
	elif authority.contains(":"):
		host = authority.get_slice(":", 0)
	if scheme == "http" and not LOCAL_HOSTS.has(host.to_lower()):
		return "HTTP so e permitido em localhost; use HTTPS"
	base_url = scheme + "://" + u
	return ""


func is_logged_in() -> bool:
	return not _access.is_empty()


func has_refresh_token() -> bool:
	return not _refresh.is_empty()


func clear_tokens() -> void:
	_access = ""
	_refresh = ""


func _to_string() -> String:
	return "BackendApi(%s, logged_in=%s)" % [base_url, str(is_logged_in())]


# ------------------------------------------------------------------ rotas publicas

func register(email: String, password: String) -> Dictionary:
	return await _request("POST", "/v1/auth/register", {"email": email, "password": password}, false)


func login(email: String, password: String) -> Dictionary:
	var r: Dictionary = await _request("POST", "/v1/auth/login", {"email": email, "password": password}, false)
	if r["ok"]:
		if not _store_tokens(r["data"]):
			return _fail(0, "bad_response", "Resposta de login invalida.")
	return _scrub(r)


func refresh() -> Dictionary:
	if _refresh.is_empty():
		return _fail(0, "no_refresh_token", "Sem refresh token.")
	var r: Dictionary = await _request("POST", "/v1/auth/refresh", {"refresh_token": _refresh}, false)
	if r["ok"]:
		if not _store_tokens(r["data"]):
			clear_tokens()
			return _fail(0, "bad_response", "Resposta de refresh invalida.")
	else:
		clear_tokens()  # refresh recusado: sessao perdida
	return _scrub(r)


func list_characters() -> Dictionary:
	var r: Dictionary = await _request("GET", "/v1/characters", null, true)
	if r["ok"]:
		r["data"] = _array_field(r["data"], "characters")
	return r


func get_character(character_id: String) -> Dictionary:
	var r: Dictionary = await _request("GET", "/v1/characters/" + character_id.uri_encode(), null, true)
	if r["ok"] and r["data"] is Dictionary and (r["data"] as Dictionary).get("character") is Dictionary:
		r["data"] = (r["data"] as Dictionary)["character"]
	return r


func create_character(char_name: String, class_id: String = "warrior") -> Dictionary:
	var r: Dictionary = await _request("POST", "/v1/characters", {"name": char_name, "class_id": class_id}, true)
	if r["ok"] and r["data"] is Dictionary and (r["data"] as Dictionary).get("character") is Dictionary:
		r["data"] = (r["data"] as Dictionary)["character"]
	return r


func list_sessions() -> Dictionary:
	var r: Dictionary = await _request("GET", "/v1/sessions", null, true)
	if r["ok"]:
		r["data"] = _array_field(r["data"], "sessions")
	return r


func join_ticket(session_id: String, character_id: String) -> Dictionary:
	return await _request("POST", "/v1/sessions/" + session_id.uri_encode() + "/join-ticket", {"character_id": character_id}, true)


# ------------------------------------------------------------------ nucleo

func _request(method: String, path: String, body: Variant, authed: bool, retried: bool = false) -> Dictionary:
	if base_url.is_empty():
		return _fail(0, "no_base_url", "URL do backend nao configurada.")
	if authed and _access.is_empty():
		return _fail(0, "not_logged_in", "Faca login primeiro.")
	var headers: PackedStringArray = PackedStringArray(["Accept: application/json"])
	var payload: String = ""
	if body != null:
		headers.append("Content-Type: application/json")
		payload = JSON.stringify(body)
	if authed:
		headers.append("Authorization: Bearer " + _access)
	var raw: Dictionary = await _send(method, base_url + path, headers, payload)
	var res: Dictionary = _parse(raw)
	if res["status"] == 401 and authed and not retried and not _refresh.is_empty():
		var rr: Dictionary = await refresh()
		if rr["ok"]:
			return await _request(method, path, body, authed, true)
	return res


func _send(method: String, url: String, headers: PackedStringArray, payload: String) -> Dictionary:
	if transport.is_valid():
		var out: Variant = await transport.call(method, url, headers, payload)
		return out if out is Dictionary else {"error": ERR_BUG, "status": 0, "body": ""}
	return await _http_transport(method, url, headers, payload)


func _http_transport(method: String, url: String, headers: PackedStringArray, payload: String) -> Dictionary:
	if not is_inside_tree():
		return {"error": ERR_UNCONFIGURED, "status": 0, "body": ""}
	var req: HTTPRequest = HTTPRequest.new()
	req.timeout = TIMEOUT_S
	req.body_size_limit = MAX_BODY_BYTES
	add_child(req)
	var m: int = HTTPClient.METHOD_GET
	match method:
		"POST": m = HTTPClient.METHOD_POST
		"DELETE": m = HTTPClient.METHOD_DELETE
	var err: int = req.request(url, headers, m, payload)
	if err != OK:
		req.queue_free()
		return {"error": err, "status": 0, "body": ""}
	var r: Array = await req.request_completed  # [result, code, headers, body]
	req.queue_free()
	return {"error": int(r[0]), "status": int(r[1]), "body": (r[3] as PackedByteArray).get_string_from_utf8()}


func _parse(raw: Dictionary) -> Dictionary:
	var status: int = int(raw.get("status", 0))
	if int(raw.get("error", 0)) != OK or status == 0:
		return _fail(0, "network_error", "Nao foi possivel falar com o servidor.")
	var text: String = String(raw.get("body", ""))
	var data: Variant = null
	var trimmed: String = text.strip_edges()
	if trimmed.begins_with("{") or trimmed.begins_with("["):
		var parsed: Variant = JSON.parse_string(text)
		if parsed != null:
			data = parsed
	if status >= 200 and status < 300:
		return {"ok": true, "status": status, "data": data, "code": "", "message": ""}
	var code: String = "http_%d" % status
	var msg: String = "Erro %d." % status
	if data is Dictionary and (data as Dictionary).get("error") is Dictionary:
		var e: Dictionary = (data as Dictionary)["error"]
		code = String(e.get("code", code))
		msg = String(e.get("message", msg))
	return _fail(status, code, msg)


func _store_tokens(data: Variant) -> bool:
	if not (data is Dictionary):
		return false
	var d: Dictionary = data
	var a: Variant = d.get("access_token", null)
	var r: Variant = d.get("refresh_token", null)
	if not (a is String) or (a as String).is_empty() or not (r is String) or (r as String).is_empty():
		return false
	_access = a
	_refresh = r
	return true


## Remove os tokens do dicionario devolvido ao chamador (ficam so em memoria privada).
func _scrub(r: Dictionary) -> Dictionary:
	if r.get("ok", false):
		r["data"] = {"expires_in": int((r["data"] as Dictionary).get("expires_in", 0))}
	return r


static func _array_field(data: Variant, key: String) -> Array:
	if data is Array:
		return data
	if data is Dictionary and (data as Dictionary).get(key) is Array:
		return (data as Dictionary)[key]
	return []


static func _fail(status: int, code: String, message: String) -> Dictionary:
	return {"ok": false, "status": status, "data": null, "code": code, "message": message}
