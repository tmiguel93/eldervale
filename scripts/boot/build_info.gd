class_name BuildInfo
extends RefCounted
## E7.1: versao e identificador de build, visiveis ao jogador (tela de login, `--version`) e ao operador (hello do protocolo,
## log de boot do servidor, arquivo de saude). A versao do jogo e constante no codigo; o `build_id` (commit curto + data)
## vem de `res://build_info.json`, gravado por `tools/build_windows.py` ANTES da exportacao (nao versionado). Sem o arquivo
## (editor, testes, execucao a partir do codigo-fonte) o id e "dev". Nada aqui e segredo nem dado pessoal.

const GAME_VERSION: String = "0.7.0-alpha.1"
const DEFAULT_BUILD_ID: String = "dev"
const INFO_PATH: String = "res://build_info.json"
const MAX_BUILD_ID_LEN: int = 24 ## cabe com folga em Protocol.MAX_BUILD_LEN (32)

static var _cached: Dictionary = {}


## Mantem so [A-Za-z0-9._-] e trunca; vazio vira "dev".
static func sanitize_id(raw: String) -> String:
	var out: String = ""
	for i: int in mini(raw.length(), MAX_BUILD_ID_LEN):
		var c: String = raw.substr(i, 1)
		out += c if (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9") or c == "." or c == "_" or c == "-" else "_"
	return out if not out.is_empty() else DEFAULT_BUILD_ID


## {version, build_id, built_at, protocol, godot}. `built_at` e "" sem build_info.json.
static func info() -> Dictionary:
	if not _cached.is_empty():
		return _cached
	var build_id: String = DEFAULT_BUILD_ID
	var built_at: String = ""
	if FileAccess.file_exists(INFO_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(INFO_PATH))
		if typeof(parsed) == TYPE_DICTIONARY:
			build_id = sanitize_id(String((parsed as Dictionary).get("build_id", "")))
			built_at = String((parsed as Dictionary).get("built_at", "")).left(32)
	_cached = {"version": GAME_VERSION, "build_id": build_id, "built_at": built_at, "protocol": Protocol.VERSION,
		"godot": String(Engine.get_version_info().get("string", "?"))}
	return _cached


static func build_id() -> String:
	return String(info()["build_id"])


## Texto para o hello do protocolo (<= Protocol.MAX_BUILD_LEN).
static func hello_build() -> String:
	return ("%s+%s" % [GAME_VERSION, build_id()]).left(Protocol.MAX_BUILD_LEN)


## Texto curto para a UI: "v0.7.0-alpha.1 (a1b2c3d)".
static func display() -> String:
	return "v%s (%s)" % [GAME_VERSION, build_id()]


static func reset_cache_for_tests() -> void:
	_cached = {}
