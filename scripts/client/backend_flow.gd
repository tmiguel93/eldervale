class_name BackendFlow
extends RefCounted
## Orquestracao do fluxo de entrada: login (registra se preciso) -> personagem -> sessao -> join-ticket.
## Usa BackendApi (transporte injetavel). Nunca guarda nem registra senha; o ticket vive so no
## dicionario devolvido por `request_ticket` e deve ser descartado apos o hello.

var api: BackendApi
var last_error: String = ""      # mensagem amigavel, sem dados sensiveis
var last_error_code: String = ""


func _init(p_api: BackendApi) -> void:
	api = p_api


## Login; com `register_if_needed`, se as credenciais falharem (401) tenta registrar e logar de novo.
## Devolve true em caso de sucesso.
func login(email: String, password: String, register_if_needed: bool) -> bool:
	var r: Dictionary = await api.login(email, password)
	if r["ok"]:
		return true
	if register_if_needed and int(r["status"]) == 401:
		var reg: Dictionary = await api.register(email, password)
		if not reg["ok"]:
			return _fail(reg)
		r = await api.login(email, password)
		if r["ok"]:
			return true
	return _fail(r)


## Procura o personagem pelo nome (sem diferenciar maiusculas); cria se `create_if_missing`.
## Devolve o dicionario do personagem ou {} em erro.
func ensure_character(char_name: String, create_if_missing: bool) -> Dictionary:
	var r: Dictionary = await api.list_characters()
	if not r["ok"]:
		_fail(r)
		return {}
	var found: Dictionary = find_character(r["data"], char_name)
	if not found.is_empty():
		return found
	if not create_if_missing:
		_set_error("not_found", "Personagem nao encontrado.")
		return {}
	var c: Dictionary = await api.create_character(char_name, "warrior")
	if not c["ok"]:
		_fail(c)
		return {}
	return c["data"] if c["data"] is Dictionary else {}


## Escolhe a sessao: a pedida (se existir e tiver vaga) ou a de mais vagas compativel com o protocolo.
## Devolve {} se nao houver.
func choose_session(wanted_id: String = "") -> Dictionary:
	var r: Dictionary = await api.list_sessions()
	if not r["ok"]:
		_fail(r)
		return {}
	var s: Dictionary = pick_session(r["data"], wanted_id, Protocol.VERSION)
	if s.is_empty():
		_set_error("no_session", "Nenhuma sessao aberta disponivel.")
	return s


## Pede o join-ticket. Devolve {ticket, host, port, session_id} ou {} em erro.
func request_ticket(session: Dictionary, character_id: String) -> Dictionary:
	var sid: String = String(session.get("id", ""))
	var r: Dictionary = await api.join_ticket(sid, character_id)
	if not r["ok"]:
		_fail(r)
		return {}
	var d: Variant = r["data"]
	var ticket: String = String((d as Dictionary).get("ticket", "")) if d is Dictionary else ""
	var endpoint: String = String(session.get("endpoint", ""))
	if d is Dictionary and (d as Dictionary).get("session") is Dictionary:
		var ep: String = String(((d as Dictionary)["session"] as Dictionary).get("endpoint", ""))
		if not ep.is_empty():
			endpoint = ep
	var hp: Dictionary = parse_endpoint(endpoint)
	if ticket.is_empty() or hp.is_empty():
		_set_error("bad_response", "Resposta de ticket invalida.")
		return {}
	return {"ticket": ticket, "host": hp["host"], "port": hp["port"], "session_id": sid}


## Fluxo completo. Devolve {ok, character, session, conn:{ticket,host,port,session_id}} .
func run_full(email: String, password: String, char_name: String, wanted_session: String, auto_register: bool, auto_create: bool) -> Dictionary:
	var out: Dictionary = {"ok": false, "login_ok": false, "character_id": "", "session_id": "", "conn": {}}
	if not await login(email, password, auto_register):
		return out
	out["login_ok"] = true
	var ch: Dictionary = await ensure_character(char_name, auto_create)
	if ch.is_empty():
		return out
	out["character_id"] = String(ch.get("id", ""))
	var s: Dictionary = await choose_session(wanted_session)
	if s.is_empty():
		return out
	out["session_id"] = String(s.get("id", ""))
	var conn: Dictionary = await request_ticket(s, String(out["character_id"]))
	if conn.is_empty():
		return out
	out["conn"] = conn
	out["ok"] = true
	return out


# ------------------------------------------------------------------ puros

static func find_character(list: Variant, char_name: String) -> Dictionary:
	if not (list is Array):
		return {}
	var want: String = char_name.strip_edges().to_lower()
	for c: Variant in list:
		if c is Dictionary and String((c as Dictionary).get("name", "")).to_lower() == want and not want.is_empty():
			return c
	return {}


static func pick_session(list: Variant, wanted_id: String, protocol_version: int) -> Dictionary:
	if not (list is Array):
		return {}
	var best: Dictionary = {}
	var best_free: int = 0
	for s: Variant in list:
		if not (s is Dictionary):
			continue
		var d: Dictionary = s
		if int(d.get("protocol_version", -1)) != protocol_version or int(d.get("free_slots", 0)) <= 0:
			continue
		if parse_endpoint(String(d.get("endpoint", ""))).is_empty():
			continue
		if not wanted_id.is_empty():
			if String(d.get("id", "")) == wanted_id:
				return d
			continue
		if int(d["free_slots"]) > best_free:
			best = d
			best_free = int(d["free_slots"])
	return best


## "host:porta" -> {host, port} ou {} se invalido.
static func parse_endpoint(endpoint: String) -> Dictionary:
	var i: int = endpoint.rfind(":")
	if i <= 0 or i == endpoint.length() - 1:
		return {}
	var host: String = endpoint.substr(0, i)
	var ps: String = endpoint.substr(i + 1)
	if not ps.is_valid_int():
		return {}
	var port: int = ps.to_int()
	if port < 1 or port > 65535 or host.length() > 253:
		return {}
	for k: int in host.length():
		var c: int = host.unicode_at(k)
		if not ((c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c == 46 or c == 45 or c == 95):
			return {}
	return {"host": host, "port": port}


## Texto amigavel por codigo de erro do backend.
static func friendly(code: String, fallback: String) -> String:
	match code:
		"invalid_credentials": return "E-mail ou senha incorretos."
		"rate_limited": return "Muitas tentativas. Aguarde um instante."
		"network_error": return "Sem conexao com o servidor de contas."
		"name_taken": return "Esse nome de personagem ja existe."
		"character_limit": return "Limite de personagens atingido."
		"character_locked", "character_already_connected": return "Esse personagem ja esta em jogo."
		"session_full": return "Sessao cheia."
		"party_in_other_session": return "Seu grupo esta em outra sessao."
		_: return fallback


func _fail(r: Dictionary) -> bool:
	_set_error(String(r.get("code", "error")), friendly(String(r.get("code", "")), String(r.get("message", "Erro."))))
	return false


func _set_error(code: String, msg: String) -> void:
	last_error_code = code
	last_error = msg
