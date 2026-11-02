class_name AssetAliases
extends RefCounted
## E8.1: resolve referencias de asset (alias do manifest, id de asset ou caminho res://) para caminhos res://.
## Le assets/ASSET_MANIFEST.json (chaves `aliases` e `assets`) uma unica vez por processo. SO o cliente usa isto
## (o servidor nunca carrega arte; no build do servidor o manifest nem e empacotado).

const MANIFEST_PATH: String = "res://assets/ASSET_MANIFEST.json"

static var _paths: Dictionary = {}   ## alias|id -> "res://assets/..."
static var _loaded_from: String = ""


## "res://..." volta igual; alias (`class.warrior`) ou id (`model.kaykit_adventurers.knight`) viram o caminho do manifest. "" = desconhecido.
static func resolve(ref: String, manifest_path: String = MANIFEST_PATH) -> String:
	if ref.begins_with("res://"):
		return ref
	_ensure(manifest_path)
	return String(_paths.get(ref, ""))


static func has_ref(ref: String, manifest_path: String = MANIFEST_PATH) -> bool:
	return not resolve(ref, manifest_path).is_empty()


static func _ensure(manifest_path: String) -> void:
	if _loaded_from == manifest_path:
		return
	_loaded_from = manifest_path
	_paths = {}
	if not FileAccess.file_exists(manifest_path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var assets: Dictionary = (parsed as Dictionary).get("assets", {})
	for id: Variant in assets:
		var entry: Variant = assets[id]
		if typeof(entry) == TYPE_DICTIONARY and (entry as Dictionary).has("path"):
			_paths[String(id)] = "res://" + String((entry as Dictionary)["path"])
	var aliases: Dictionary = (parsed as Dictionary).get("aliases", {})
	for alias: Variant in aliases:
		var target: String = String(_paths.get(String(aliases[alias]), ""))
		if not target.is_empty():
			_paths[String(alias)] = target


## Testes: descarta o cache.
static func reset() -> void:
	_paths = {}
	_loaded_from = ""
