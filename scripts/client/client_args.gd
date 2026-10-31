class_name ClientArgs
extends RefCounted
## Argumentos do cliente ligados ao backend (E4). Lidos a parte do NetConfig:
## --backend-url URL --email E --password P --character NOME [--session-id ID] [--bot-seconds N]
## Segredos podem vir por ambiente (ELDERVALE_EMAIL / ELDERVALE_PASSWORD), preferivel a argumentos.
## Nada aqui e logado. `errors` nunca contem valores de senha.

const KEYS: PackedStringArray = ["backend-url", "email", "password", "character", "session-id", "bot-seconds", "kill-grace"]

var backend_url: String = ""
var email: String = ""
var password: String = ""
var character: String = ""
var session_id: String = ""
var kill_grace_s: float = -1.0   # kill_enemy: espera apos a morte (<0 = padrao)
var errors: PackedStringArray = PackedStringArray()


func uses_backend() -> bool:
	return not backend_url.is_empty()


static func from_environment() -> ClientArgs:
	var env: Dictionary = {}
	for k: String in ["ELDERVALE_BACKEND_URL", "ELDERVALE_EMAIL", "ELDERVALE_PASSWORD", "ELDERVALE_CHARACTER", "ELDERVALE_SESSION_ID"]:
		if OS.has_environment(k):
			env[k] = OS.get_environment(k)
	return parse(OS.get_cmdline_user_args(), env)


static func parse(args: PackedStringArray, env: Dictionary = {}) -> ClientArgs:
	var a: ClientArgs = ClientArgs.new()
	a.backend_url = str(env.get("ELDERVALE_BACKEND_URL", "")).strip_edges()
	a.email = str(env.get("ELDERVALE_EMAIL", "")).strip_edges()
	a.password = str(env.get("ELDERVALE_PASSWORD", ""))
	a.character = str(env.get("ELDERVALE_CHARACTER", "")).strip_edges()
	a.session_id = str(env.get("ELDERVALE_SESSION_ID", "")).strip_edges()
	var i: int = 0
	while i < args.size():
		var s: String = args[i]
		i += 1
		if not s.begins_with("--"):
			continue
		var key: String = s.substr(2)
		var val: String = ""
		var has_val: bool = false
		var eq: int = key.find("=")
		if eq >= 0:
			val = key.substr(eq + 1)
			key = key.substr(0, eq)
			has_val = true
		key = key.replace("_", "-")
		if not KEYS.has(key):
			continue
		if not has_val:
			if i < args.size() and not args[i].begins_with("--"):
				val = args[i]
				i += 1
			else:
				a.errors.append("--%s sem valor" % key)
				continue
		match key:
			"backend-url": a.backend_url = val.strip_edges()
			"email": a.email = val.strip_edges()
			"password": a.password = val
			"character": a.character = val.strip_edges()
			"session-id": a.session_id = val.strip_edges()
			"kill-grace":
				if val.is_valid_float():
					a.kill_grace_s = clampf(val.to_float(), 0.0, 3600.0)
				else:
					a.errors.append("--kill-grace invalido")
	return a


## True se o NetConfig deve ignorar este aviso (chave tratada aqui).
static func is_own_warning(text: String) -> bool:
	for k: String in KEYS:
		if text.contains("--" + k) or text.contains(k.replace("-", "_")):
			return true
	return text.begins_with("argumento ignorado")


## Validacao para modo bot com backend. Lista de problemas (vazia = ok).
func bot_problems() -> PackedStringArray:
	var p: PackedStringArray = PackedStringArray()
	if backend_url.is_empty():
		return p
	if email.is_empty():
		p.append("--email obrigatorio com --backend-url")
	if password.is_empty():
		p.append("--password (ou ELDERVALE_PASSWORD) obrigatorio com --backend-url")
	if character.is_empty():
		p.append("--character obrigatorio com --backend-url")
	return p
