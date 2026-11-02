class_name ServerLog
extends RefCounted
## Log do servidor com depuracao de segredos e PII. Registre segredos (ex.: o Bearer interno, a chave da sessao) com
## `add_secret`; qualquer linha que os contenha sai com "[redacted]". Alem disso `scrub` mascara SEMPRE e-mails completos
## e tokens JWT-like (defesa em profundidade; o codigo do servidor nunca deve formatar ticket/segredo/e-mail em mensagens).
## E7.1: niveis (debug/info/warn/error; `min_level` filtra) e formato JSON opcional (`--log-format json`: uma linha por
## evento `{"t","level","msg"}`; texto continua o padrao para nao quebrar os harnesses que leem stdout).
## Testes ligam `capturing` para inspecionar o que foi logado.

enum Level { DEBUG, INFO, WARN, ERROR }

static var capturing: bool = false
static var captured: PackedStringArray = PackedStringArray()
static var min_level: int = Level.INFO
static var json_mode: bool = false
static var _secrets: PackedStringArray = PackedStringArray()
static var _email_re: RegEx = null
static var _jwt_re: RegEx = null


static func add_secret(secret: String) -> void:
	if secret.length() >= 4 and not _secrets.has(secret):
		_secrets.append(secret)


static func clear_secrets() -> void:
	_secrets = PackedStringArray()


static func reset_capture() -> void:
	captured = PackedStringArray()


## "debug"|"info"|"warn"|"error" -> Level; invalido => -1.
static func parse_level(name: String) -> int:
	match name.strip_edges().to_lower():
		"debug":
			return Level.DEBUG
		"info":
			return Level.INFO
		"warn", "warning":
			return Level.WARN
		"error":
			return Level.ERROR
	return -1


static func scrub(msg: String) -> String:
	var out: String = msg
	for s: String in _secrets:
		out = out.replace(s, "[redacted]")
	if _email_re == null:
		_email_re = RegEx.new()
		_email_re.compile("[A-Za-z0-9._%+\\-]+@[A-Za-z0-9.\\-]+\\.[A-Za-z]{2,}")
		_jwt_re = RegEx.new()
		_jwt_re.compile("eyJ[A-Za-z0-9_\\-]{5,}\\.[A-Za-z0-9_\\-]{5,}\\.[A-Za-z0-9_\\-]*")
	if out.contains("@"):
		out = _email_re.sub(out, "[email]", true)
	if out.contains("eyJ"):
		out = _jwt_re.sub(out, "[redacted]", true)
	return out


static func _format(level: int, msg: String) -> String:
	var text: String = scrub(msg)
	if not json_mode:
		return text
	return JSON.stringify({"t": Time.get_datetime_string_from_system(true) + "Z", "level": ["debug", "info", "warn", "error"][level], "msg": text}, "", false)


static func _emit(level: int, line: String) -> void:
	if level >= Level.ERROR:
		printerr(line)
	else:
		print(line)
	if capturing:
		captured.append(line)


static func debug(msg: String) -> void:
	if min_level <= Level.DEBUG:
		_emit(Level.DEBUG, _format(Level.DEBUG, msg))


static func info(msg: String) -> void:
	if min_level <= Level.INFO:
		_emit(Level.INFO, _format(Level.INFO, msg))


static func warn(msg: String) -> void:
	if min_level <= Level.WARN:
		_emit(Level.WARN, _format(Level.WARN, msg if json_mode else "[warn] " + msg))


static func error(msg: String) -> void:
	_emit(Level.ERROR, _format(Level.ERROR, msg))


static func joined() -> String:
	return "\n".join(captured)
