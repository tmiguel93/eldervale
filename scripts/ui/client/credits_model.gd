class_name CreditsModel
extends RefCounted
## E8.4: modelo (puro, testavel) da tela de Creditos. Le os pacotes de assets/ASSET_MANIFEST.json (`packages`) e os rotulos/avisos de
## atribuicao de data/ui/credits.json, e agrupa por licenca (CC BY primeiro: atribuicao obrigatoria). TODO pacote do manifest aparece.

const MANIFEST_PATH: String = "res://assets/ASSET_MANIFEST.json"
const CREDITS_PATH: String = "res://data/ui/credits.json"


static func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed as Dictionary if parsed is Dictionary else {}


## {title, intro, groups:[{license, label, url, notices:[String], entries:[{id, name, author, source, license}]}], package_ids:[String]}
static func build(manifest_path: String = MANIFEST_PATH, credits_path: String = CREDITS_PATH) -> Dictionary:
	var manifest: Dictionary = _read(manifest_path)
	var cfg: Dictionary = _read(credits_path)
	var packages: Dictionary = manifest.get("packages", {}) as Dictionary
	var labels: Dictionary = cfg.get("license_labels", {}) as Dictionary
	var urls: Dictionary = cfg.get("license_urls", {}) as Dictionary
	var notices: Dictionary = cfg.get("notices", {}) as Dictionary
	var by_license: Dictionary = {}
	var ids: Array[String] = []
	var pkg_ids: Array = packages.keys()
	pkg_ids.sort()
	for pid: Variant in pkg_ids:
		var p: Dictionary = packages[pid] as Dictionary
		var lic: String = String(p.get("license", "?"))
		var entry: Dictionary = {"id": String(pid), "name": String(p.get("name", pid)), "author": String(p.get("author", "")), "source": String(p.get("source", "")), "license": lic}
		(by_license.get_or_add(lic, []) as Array).append(entry)
		ids.append(String(pid))
	for ex: Variant in cfg.get("extras", []):
		if ex is Dictionary:
			var lic2: String = String((ex as Dictionary).get("license", "?"))
			(by_license.get_or_add(lic2, []) as Array).append({"id": "extra:" + String((ex as Dictionary).get("name", "")), "name": String((ex as Dictionary).get("name", "")),
				"author": String((ex as Dictionary).get("author", "")), "source": String((ex as Dictionary).get("source", "")), "license": lic2})
	var order: Array[String] = []
	for l: Variant in cfg.get("license_order", []):
		if by_license.has(String(l)):
			order.append(String(l))
	for l2: Variant in by_license.keys():
		if not order.has(String(l2)):
			order.append(String(l2))
	var groups: Array[Dictionary] = []
	for lic3: String in order:
		var entries: Array = by_license[lic3]
		var g_notices: Array[String] = []
		for e: Variant in entries:
			var n: String = String(notices.get(String((e as Dictionary)["id"]), ""))
			if not n.is_empty() and not g_notices.has(n):
				g_notices.append(n)
		groups.append({"license": lic3, "label": String(labels.get(lic3, lic3)), "url": String(urls.get(lic3, "")), "notices": g_notices, "entries": entries})
	return {"title": String(cfg.get("title", "Creditos")), "intro": String(cfg.get("intro", "")), "groups": groups, "package_ids": ids}


## Ids de pacote que NAO aparecem em nenhum grupo (deve ser vazio).
static func missing_packages(model: Dictionary) -> Array[String]:
	var seen: Dictionary = {}
	for g: Variant in model.get("groups", []):
		for e: Variant in (g as Dictionary)["entries"]:
			seen[String((e as Dictionary)["id"])] = true
	var out: Array[String] = []
	for pid: Variant in model.get("package_ids", []):
		if not seen.has(String(pid)):
			out.append(String(pid))
	return out
