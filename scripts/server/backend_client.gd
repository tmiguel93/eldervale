class_name BackendClient
extends Node
## Cliente assincrono do CONTRATO HTTP INTERNO do backend (docs/E4_SESSIONS.md, E4_CHARACTERS.md).
## - Nunca bloqueia: toda chamada devolve por callback `cb(result)`, result =
##   {ok: bool, status: int, data: Dictionary, code: String, attempts: int}
##   (`code` = error.code do backend, ou "network"/"timeout"/"cancelled"/"bad_response" sem resposta util).
## - Retry com backoff exponencial SO em operacoes idempotentes (GET, checkpoint com revision
##   esperada, rewards com idempotency_key, disconnect, release, close, heartbeat) e SO para erro de
##   rede/timeout, 5xx e 429. O resgate de ticket (redeem) e a criacao de sessao NAO tem retry.
## - Segredo: recebido por `configure` (origem: env ELDERVALE_INTERNAL_SECRET), guardado so aqui,
##   usado so no cabecalho Authorization; nunca em log nem em mensagem de erro.
## - HTTPS obrigatorio, exceto para localhost/127.0.0.1/::1 (`validate_url`).
## - Ciclo de vida: `cancel_all()` invalida callbacks pendentes (sem chama-los) e timers de retry.

var transport: BackendTransport
var base_url: String = ""
var timeout_sec: float = 5.0
var max_attempts: int = 3
var backoff_base_sec: float = 0.25
var backoff_max_sec: float = 2.0

var _secret: String = ""
var _epoch: int = 0
var _inflight: int = 0


## Devolve "" se a URL e aceitavel, senao o motivo (sem eco de credenciais embutidas).
static func validate_url(url: String) -> String:
	var u: String = url.strip_edges()
	if u.is_empty():
		return "backend-url vazia"
	var scheme: String = ""
	var rest: String = ""
	if u.begins_with("https://"):
		scheme = "https"
		rest = u.substr(8)
	elif u.begins_with("http://"):
		scheme = "http"
		rest = u.substr(7)
	else:
		return "backend-url deve comecar com https:// (ou http:// so para localhost)"
	var host_part: String = rest.get_slice("/", 0)
	if host_part.is_empty() or host_part.contains("@"):
		return "backend-url invalida (host ausente ou credenciais embutidas)"
	var host: String = host_part
	if host.begins_with("["):
		host = host.substr(0, host.find("]") + 1)
	else:
		host = host.get_slice(":", 0)
	if scheme == "http" and not is_local_host(host):
		return "backend-url sem TLS so e permitida para localhost"
	for i: int in u.length():
		var c: int = u.unicode_at(i)
		if c <= 32 or c == 127:
			return "backend-url com caractere invalido"
	return ""


static func is_local_host(host: String) -> bool:
	var h: String = host.to_lower()
	return h == "localhost" or h == "127.0.0.1" or h == "[::1]"


## Configura URL + segredo. Devolve "" ou o motivo do erro.
func configure(url: String, secret: String) -> String:
	var err: String = validate_url(url)
	if not err.is_empty():
		return err
	if secret.strip_edges().is_empty():
		return "segredo interno ausente (ELDERVALE_INTERNAL_SECRET)"
	base_url = url.strip_edges().trim_suffix("/")
	_secret = secret
	ServerLog.add_secret(secret)
	return ""


func is_configured() -> bool:
	return not base_url.is_empty() and not _secret.is_empty() and transport != null


func inflight_count() -> int:
	return _inflight


## Invalida callbacks e retries pendentes (nenhum cb e chamado depois disto).
func cancel_all() -> void:
	_epoch += 1
	_inflight = 0
	if transport != null:
		transport.cancel_all()


# ------------------------------------------------------------------ operacoes tipadas

func register_session(region: String, capacity: int, protocol_version: int, endpoint: String, cb: Callable) -> void:
	_request("POST", "/internal/sessions", {"region": region, "capacity": capacity, "protocol_version": protocol_version, "endpoint": endpoint}, false, cb)


func heartbeat(session_id: String, cb: Callable) -> void:
	_request("POST", "/internal/sessions/%s/heartbeat" % _id(session_id), {}, true, cb)


func close_session(session_id: String, cb: Callable) -> void:
	_request("POST", "/internal/sessions/%s/close" % _id(session_id), {}, true, cb)


## NAO idempotente (ticket de uso unico): sem retry.
func redeem(ticket: String, session_id: String, cb: Callable) -> void:
	_request("POST", "/internal/tickets/redeem", {"ticket": ticket, "session_id": session_id}, false, cb)


func get_character(character_id: String, cb: Callable) -> void:
	_request("GET", "/internal/characters/%s" % _id(character_id), null, true, cb)


func checkpoint(character_id: String, expected_revision: int, state: Dictionary, cb: Callable) -> void:
	_request("POST", "/internal/characters/%s/checkpoint" % _id(character_id), {"expected_revision": expected_revision, "state": state}, true, cb)


## Retry sempre com a MESMA idempotency_key (o corpo e identico).
func rewards(character_id: String, idempotency_key: String, xp: int, items: Array, cb: Callable) -> void:
	_request("POST", "/internal/characters/%s/rewards" % _id(character_id), {"idempotency_key": idempotency_key, "xp": xp, "items": items}, true, cb)


func disconnect_character(character_id: String, session_id: String, cb: Callable) -> void:
	_request("POST", "/internal/characters/%s/disconnect" % _id(character_id), {"session_id": session_id}, true, cb)


func release_character(character_id: String, session_id: String, cb: Callable) -> void:
	_request("POST", "/internal/characters/%s/release" % _id(character_id), {"session_id": session_id}, true, cb)


# ------------------------------------------------------------------ nucleo

## Ids vao no caminho: so [A-Za-z0-9-] (evita injecao de caminho); invalido vira um id inexistente.
static func _id(raw: String) -> String:
	if raw.is_empty() or raw.length() > 64:
		return "invalid"
	for i: int in raw.length():
		var c: int = raw.unicode_at(i)
		if not ((c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c == 45):
			return "invalid"
	return raw


func _request(method: String, path: String, body: Variant, idempotent: bool, cb: Callable) -> void:
	var ctx: Dictionary = {
		"method": method, "path": path, "body": body, "idempotent": idempotent,
		"cb": cb, "attempt": 1, "epoch": _epoch,
	}
	_inflight += 1
	_dispatch(ctx)


func _dispatch(ctx: Dictionary) -> void:
	if transport == null or not is_configured():
		_finish(ctx, {"status": 0, "body": "", "error": "cancelled"})
		return
	var headers: PackedStringArray = PackedStringArray([
		"Authorization: Bearer " + _secret, "Accept: application/json",
	])
	var payload: String = ""
	if ctx["body"] != null:
		headers.append("Content-Type: application/json")
		payload = JSON.stringify(ctx["body"])
	var req: Dictionary = {
		"method": ctx["method"], "url": base_url + String(ctx["path"]), "headers": headers,
		"body": payload, "timeout_sec": timeout_sec,
	}
	transport.send(req, _on_response.bind(ctx))


func _on_response(resp: Dictionary, ctx: Dictionary) -> void:
	if int(ctx["epoch"]) != _epoch:
		return # cancelado (encerramento): nao chama o cb
	var status: int = int(resp.get("status", 0))
	var retryable: bool = status == 0 or status == 429 or status >= 500
	var attempt: int = int(ctx["attempt"])
	if bool(ctx["idempotent"]) and retryable and attempt < max_attempts and String(resp.get("error", "")) != "cancelled":
		ctx["attempt"] = attempt + 1
		var delay: float = minf(backoff_max_sec, backoff_base_sec * pow(2.0, float(attempt - 1)))
		if is_inside_tree():
			get_tree().create_timer(maxf(delay, 0.0)).timeout.connect(_retry.bind(ctx), CONNECT_ONE_SHOT)
			return
	_finish(ctx, resp)


func _retry(ctx: Dictionary) -> void:
	if int(ctx["epoch"]) != _epoch:
		return
	_dispatch(ctx)


func _finish(ctx: Dictionary, resp: Dictionary) -> void:
	if int(ctx["epoch"]) != _epoch:
		return
	_inflight = maxi(0, _inflight - 1)
	var status: int = int(resp.get("status", 0))
	var data: Dictionary = {}
	var code: String = ""
	var text: String = String(resp.get("body", ""))
	if not text.is_empty():
		var json: JSON = JSON.new() # parse() silencioso (parse_string imprime ERROR em corpo invalido)
		if json.parse(text) == OK and typeof(json.data) == TYPE_DICTIONARY:
			data = json.data
	var ok: bool = status >= 200 and status < 300
	if status == 0:
		code = String(resp.get("error", "network"))
		if code.is_empty():
			code = "network"
	elif not ok:
		var err: Variant = data.get("error", null)
		if typeof(err) == TYPE_DICTIONARY and typeof((err as Dictionary).get("code", null)) == TYPE_STRING:
			code = String((err as Dictionary)["code"]).substr(0, 64)
		else:
			code = "http_%d" % status
	elif data.is_empty() and status != 204:
		ok = false
		code = "bad_response"
	var result: Dictionary = {"ok": ok, "status": status, "data": data, "code": code, "attempts": int(ctx["attempt"])}
	var cb: Callable = ctx["cb"]
	if cb.is_valid():
		cb.call(result)
