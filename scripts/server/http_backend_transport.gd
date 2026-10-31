class_name HttpBackendTransport
extends BackendTransport
## Transporte real sobre HTTPRequest (assincrono; nunca bloqueia o tick). Cada requisicao e um
## no HTTPRequest filho de `host`, liberado ao concluir. Sem redirecionamento, sem gzip, corpo
## de resposta limitado. Nao ha como testar rede real nos testes headless (usam fake).

const MAX_RESPONSE_BYTES: int = 1048576

var host: Node
var _live: Array[HTTPRequest] = []


func _init(p_host: Node = null) -> void:
	host = p_host


func send(req: Dictionary, cb: Callable) -> void:
	if host == null or not is_instance_valid(host) or not host.is_inside_tree():
		cb.call({"status": 0, "body": "", "error": "cancelled"})
		return
	var r: HTTPRequest = HTTPRequest.new()
	r.timeout = maxf(0.5, float(req.get("timeout_sec", 5.0)))
	r.max_redirects = 0
	r.accept_gzip = false
	r.body_size_limit = MAX_RESPONSE_BYTES
	host.add_child(r)
	_live.append(r)
	r.request_completed.connect(_on_completed.bind(r, cb), CONNECT_ONE_SHOT)
	var method: int = HTTPClient.METHOD_POST if String(req.get("method", "GET")) == "POST" else HTTPClient.METHOD_GET
	var err: int = r.request(String(req["url"]), req.get("headers", PackedStringArray()) as PackedStringArray, method, String(req.get("body", "")))
	if err != OK:
		_live.erase(r)
		r.queue_free()
		cb.call({"status": 0, "body": "", "error": "network"})


func _on_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, r: HTTPRequest, cb: Callable) -> void:
	_live.erase(r)
	r.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS:
		var kind: String = "timeout" if result == HTTPRequest.RESULT_TIMEOUT else "network"
		cb.call({"status": 0, "body": "", "error": kind})
		return
	cb.call({"status": code, "body": body.get_string_from_utf8(), "error": ""})


func cancel_all() -> void:
	for r: HTTPRequest in _live:
		if is_instance_valid(r):
			r.cancel_request()
			r.queue_free()
	_live.clear()
