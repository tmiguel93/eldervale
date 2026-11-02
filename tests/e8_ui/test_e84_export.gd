extends RefCounted
## E8.4: export_presets.cfg - o cliente leva SO os icones/fontes usados (lista gerada por tools/gen_export_filter.py) e o servidor
## continua sem nenhum asset.

const CFG: String = "res://export_presets.cfg"
const ICONS: String = "assets/third_party/game_icons/"
const FONTS: String = "assets/third_party/google_fonts/"


func run(ctx: Variant) -> void:
	await (ctx as SceneTree).physics_frame
	var presets: Dictionary = _parse()
	ctx.check(presets.has("Windows Client") and presets.has("Windows Server"), "presets Windows Client e Windows Server existem")
	var client: PackedStringArray = _items(String(presets.get("Windows Client", "")))
	var server: PackedStringArray = _items(String(presets.get("Windows Server", "")))
	ctx.check(server.has("assets/*"), "servidor: assets/* excluido (nao leva arte)")
	ctx.check(not client.has("assets/*"), "cliente: assets/* NAO excluido")
	ctx.check(not client.has(ICONS + "*") and not client.has(FONTS + "*"), "cliente: sem exclusao global de game_icons/fontes")
	ctx.check(client.has("assets/third_party/oculus_audio_pack/*"), "cliente: audio nao usado continua fora")
	# usados entram, nao usados saem
	var used: Dictionary = {}
	for ref: String in UiIcons.all_refs():
		used[ICONS + ref + ".svg"] = true
	for kind: String in NorseFonts.PATHS:
		used[String(NorseFonts.PATHS[kind]).trim_prefix("res://")] = true
	var excluded: Dictionary = {}
	for it: String in client:
		excluded[it] = true
	for u: String in used:
		ctx.check(not excluded.has(u), "usado vai para o cliente: " + u.get_file())
	var total: int = 0
	var leaked: Array[String] = []
	for pair: Array in [[ICONS, ".svg"], [FONTS, ".ttf"]]:
		for f: String in _files("res://" + String(pair[0]), String(pair[1])):
			total += 1
			if not used.has(f) and not excluded.has(f):
				leaked.append(f)
	ctx.check(total > 700, "inventario de icones/fontes lido (%d arquivos)" % total)
	ctx.check(leaked.is_empty(), "todo icone/fonte NAO usado esta excluido do cliente (vazando %d: %s)" % [leaked.size(), leaked.slice(0, 3)])
	ctx.check(not excluded.has(ICONS + "ATTRIBUTION.txt") and not excluded.has(ICONS + "license.txt"), "licenca/atribuicao do game-icons seguem no cliente")


## nome do preset -> texto do exclude_filter
func _parse() -> Dictionary:
	var out: Dictionary = {}
	var cur: String = ""
	for ln: String in FileAccess.get_file_as_string(CFG).split("\n"):
		if ln.begins_with("name=\""):
			cur = ln.trim_prefix("name=\"").trim_suffix("\"")
		elif ln.begins_with("exclude_filter=\"") and not cur.is_empty():
			out[cur] = ln.trim_prefix("exclude_filter=\"").trim_suffix("\"")
	return out


func _items(text: String) -> PackedStringArray:
	var out: PackedStringArray = []
	for s: String in text.split(","):
		var t: String = s.strip_edges()
		if not t.is_empty():
			out.append(t)
	return out


func _files(dir: String, ext: String) -> Array[String]:
	var out: Array[String] = []
	var d: DirAccess = DirAccess.open(dir)
	if d == null:
		return out
	for sub: String in d.get_directories():
		out.append_array(_files(dir.path_join(sub), ext))
	for f: String in d.get_files():
		if f.ends_with(ext):
			out.append(dir.path_join(f).trim_prefix("res://"))
	return out
