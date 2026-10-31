class_name ServerLog
extends RefCounted
## Log do servidor com depuracao de segredos. Registre segredos (ex.: o Bearer interno) com
## `add_secret`; qualquer linha que os contenha sai com "[redacted]". O codigo do servidor NUNCA
## deve formatar ticket/segredo em mensagens; a depuracao e so defesa em profundidade.
## Testes ligam `capturing` para inspecionar o que foi logado.

static var capturing: bool = false
static var captured: PackedStringArray = PackedStringArray()
static var _secrets: PackedStringArray = PackedStringArray()


static func add_secret(secret: String) -> void:
	if secret.length() >= 4 and not _secrets.has(secret):
		_secrets.append(secret)


static func clear_secrets() -> void:
	_secrets = PackedStringArray()


static func reset_capture() -> void:
	captured = PackedStringArray()


static func scrub(msg: String) -> String:
	var out: String = msg
	for s: String in _secrets:
		out = out.replace(s, "[redacted]")
	return out


static func info(msg: String) -> void:
	var line: String = scrub(msg)
	print(line)
	if capturing:
		captured.append(line)


static func warn(msg: String) -> void:
	info("[warn] " + msg)


static func joined() -> String:
	return "\n".join(captured)
