extends RefCounted
## E8.2: todo asset referenciado pelo tema existe, carrega e tem malha; o export do cliente empacota os pacotes usados e o do
## servidor nao empacota assets.

const H = preload("res://tests/e8_scenery/e8s_helpers.gd")


func run(ctx: Variant) -> void:
	await _assets(ctx)
	_export_presets(ctx)
	_theme_schema(ctx)


func _assets(ctx: Variant) -> void:
	ModelRig.force_enabled = 1
	SceneryBuilder.clear_cache()
	var all: PackedStringArray = SceneryTheme.all_assets()
	ctx.check(all.size() > 60, "tema referencia muitos assets (%d)" % all.size())
	var missing: int = 0
	var empty: int = 0
	for path: String in all:
		if not ResourceLoader.exists(path):
			missing += 1
			print("   ausente: ", path)
			continue
		var info: Dictionary = SceneryBuilder.asset_info(path)
		if info.is_empty() or (info["parts"] as Array).is_empty():
			empty += 1
			print("   sem malha: ", path)
	ctx.check(missing == 0, "todos os assets do tema existem")
	ctx.check(empty == 0, "todos os assets do tema tem malha")
	ModelRig.force_enabled = -1
	SceneryBuilder.clear_cache()


func _export_presets(ctx: Variant) -> void:
	var f: FileAccess = FileAccess.open("res://export_presets.cfg", FileAccess.READ)
	ctx.check(f != null, "export_presets.cfg legivel")
	if f == null:
		return
	var presets: Dictionary = {}
	var cur: String = ""
	for line: String in f.get_as_text().split("\n"):
		if line.begins_with("name="):
			cur = line.substr(5).strip_edges().trim_prefix("\"").trim_suffix("\"")
		elif line.begins_with("exclude_filter=") and not cur.is_empty():
			presets[cur] = line.substr(15)
	ctx.check(presets.has("Windows Client") and presets.has("Windows Server"), "presets Client e Server encontrados")
	var client: String = str(presets.get("Windows Client", ""))
	var server: String = str(presets.get("Windows Server", ""))
	for pk: String in SceneryTheme.PACKAGES:
		ctx.check(not client.contains("third_party/%s/" % pk), "cliente empacota " + pk)
	ctx.check(client.contains("third_party/game_icons/"), "cliente ainda exclui pacotes nao usados")
	ctx.check(server.contains("assets/*"), "servidor nao empacota assets/*")


func _theme_schema(ctx: Variant) -> void:
	var keys: PackedStringArray = ["sky_top", "sky_horizon", "sky_ground", "sun_color", "sun_energy", "sun_pitch", "sun_yaw",
		"ambient_color", "ambient_energy", "fog_color", "fog_density", "exposure", "white", "glow_intensity", "glow_bloom",
		"glow_threshold", "saturation", "contrast"]
	for zid: String in SceneryTheme.zone_ids():
		var t: Dictionary = SceneryTheme.for_zone(zid)
		for k: String in keys:
			ctx.check((t["mood"] as Dictionary).has(k), "%s: humor tem %s" % [zid, k])
		ctx.check(float((t["mood"] as Dictionary)["fog_density"]) <= 0.0025, "%s: nevoa abaixo do limite de saturacao do Compatibility" % zid)
	ctx.check(SceneryTheme.for_zone("zone_inexistente").is_empty(), "zona sem tema devolve vazio")
