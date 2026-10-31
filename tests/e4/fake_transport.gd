class_name FakeTransport
extends RefCounted
## Transporte HTTP falso para BackendApi (sem rede). Rotas: "METHOD /caminho" -> Array de respostas
## ({status, body:Dictionary|String}); consumidas em ordem, a ultima se repete.

var routes: Dictionary = {}
var requests: Array = []   # [{method, path, auth, body}]


func on(route: String, responses: Array) -> void:
	routes[route] = responses


func handle(method: String, url: String, headers: PackedStringArray, body: String) -> Dictionary:
	var path: String = url
	var i: int = url.find("://")
	if i >= 0:
		var rest: String = url.substr(i + 3)
		path = rest.substr(rest.find("/")) if rest.contains("/") else "/"
	var auth: String = ""
	for h: String in headers:
		if h.begins_with("Authorization: "):
			auth = h.substr(15)
	requests.append({"method": method, "path": path, "auth": auth, "body": body})
	var key: String = method + " " + path
	if not routes.has(key):
		return {"error": OK, "status": 404, "body": JSON.stringify({"error": {"code": "not_found", "message": "x"}})}
	var list: Array = routes[key]
	var r: Dictionary = list[0] if list.size() == 1 else list.pop_front()
	var b: Variant = r.get("body", "")
	return {"error": int(r.get("error", OK)), "status": int(r["status"]), "body": b if b is String else JSON.stringify(b)}


func count(route: String) -> int:
	var n: int = 0
	for r: Dictionary in requests:
		if (r["method"] + " " + r["path"]) == route:
			n += 1
	return n


static func err(status: int, code: String) -> Dictionary:
	return {"status": status, "body": {"error": {"code": code, "message": "mensagem " + code}}}
