extends RefCounted
## E8.2: presets de qualidade (Baixo/Medio/Alto): chaves, padrao seguro, --quality, ConfigFile e ambiente por humor.

var TMP: String = "user://e8s_settings_test_%d.cfg" % Time.get_ticks_usec() # nome unico: remocao pode falhar onde rm e bloqueado


func run(ctx: Variant) -> void:
	_presets(ctx)
	_args_and_config(ctx)
	_caps(ctx)
	_env(ctx)


func _presets(ctx: Variant) -> void:
	var keys: PackedStringArray = ["shadows", "shadow_size", "ssao", "glow", "msaa", "scale", "decor_density", "view_distance", "max_lights", "shadow_distance", "volumetric_fog", "ssil"]
	for p: int in [QualitySettings.Preset.LOW, QualitySettings.Preset.MEDIUM, QualitySettings.Preset.HIGH]:
		var d: Dictionary = QualitySettings.data(p)
		for k: String in keys:
			ctx.check(d.has(k), "preset %d tem %s" % [p, k])
	var lo: Dictionary = QualitySettings.data(QualitySettings.Preset.LOW)
	var md: Dictionary = QualitySettings.data(QualitySettings.Preset.MEDIUM)
	var hi: Dictionary = QualitySettings.data(QualitySettings.Preset.HIGH)
	ctx.check(float(lo["decor_density"]) < float(md["decor_density"]) and float(md["decor_density"]) < float(hi["decor_density"]), "densidade cresce com o preset")
	ctx.check(float(lo["view_distance"]) < float(md["view_distance"]) and float(md["view_distance"]) < float(hi["view_distance"]), "distancia de desenho cresce")
	ctx.check(int(lo["max_lights"]) < int(md["max_lights"]) and int(md["max_lights"]) < int(hi["max_lights"]), "luzes ativas crescem")
	ctx.check(not bool(lo["shadows"]) and not bool(lo["ssao"]) and not bool(lo["glow"]) and not bool(lo["volumetric_fog"]), "Baixo desliga sombra, SSAO, glow e nevoa volumetrica")
	ctx.check(QualitySettings.DEFAULT_PRESET == QualitySettings.Preset.MEDIUM, "padrao seguro = Medio")
	ctx.check(not bool(md["ssao"]) and not bool(md["volumetric_fog"]), "Medio sem efeitos exclusivos do Forward+")
	ctx.check(QualitySettings.data(99) == QualitySettings.data(QualitySettings.DEFAULT_PRESET), "preset invalido cai no padrao")


func _args_and_config(ctx: Variant) -> void:
	ctx.check(QualitySettings.preset_from_name("LOW") == QualitySettings.Preset.LOW, "alias low (caixa)")
	ctx.check(QualitySettings.preset_from_name("alto") == QualitySettings.Preset.HIGH, "alias alto")
	ctx.check(QualitySettings.preset_from_name("media") == QualitySettings.Preset.MEDIUM, "alias media")
	ctx.check(QualitySettings.preset_from_name("xyz") == -1, "alias invalido = -1")
	ctx.check(QualitySettings.preset_from_args(PackedStringArray(["--quality", "high"])) == QualitySettings.Preset.HIGH, "--quality high")
	ctx.check(QualitySettings.preset_from_args(PackedStringArray(["--quality=low"])) == QualitySettings.Preset.LOW, "--quality=low")
	ctx.check(QualitySettings.preset_from_args(PackedStringArray(["--quality", "zzz"])) == -1, "--quality invalido ignorado")
	ctx.check(QualitySettings.preset_from_args(PackedStringArray()) == -1, "sem --quality")
	var args: ClientArgs = ClientArgs.parse(PackedStringArray(["--quality", "high"]))
	ctx.check(args != null and str(args.quality) != "", "ClientArgs reconhece --quality")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	ctx.check(QualitySettings.load_saved(TMP) == -1, "sem arquivo: nada salvo")
	ctx.check(QualitySettings.resolve_startup(PackedStringArray(), TMP) == QualitySettings.DEFAULT_PRESET, "sem args nem arquivo: padrao")
	ctx.check(QualitySettings.save(QualitySettings.Preset.HIGH, TMP) == OK, "grava ConfigFile")
	ctx.check(QualitySettings.load_saved(TMP) == QualitySettings.Preset.HIGH, "le o que gravou")
	ctx.check(QualitySettings.resolve_startup(PackedStringArray(), TMP) == QualitySettings.Preset.HIGH, "arquivo vence o padrao")
	ctx.check(QualitySettings.resolve_startup(PackedStringArray(["--quality", "low"]), TMP) == QualitySettings.Preset.LOW, "--quality vence o arquivo")
	ctx.check(QualitySettings.load_saved(TMP) == QualitySettings.Preset.HIGH, "--quality nao regrava o arquivo")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))


func _caps(ctx: Variant) -> void:
	for m: String in ["gl_compatibility", "mobile"]:
		var c: Dictionary = QualitySettings.renderer_caps(m)
		ctx.check(not bool(c["ssao"]) and not bool(c["ssil"]) and not bool(c["volumetric_fog"]), "%s: sem SSAO/SSIL/nevoa volumetrica" % m)
	var fp: Dictionary = QualitySettings.renderer_caps("forward_plus")
	ctx.check(bool(fp["ssao"]) and bool(fp["volumetric_fog"]), "forward_plus: SSAO e nevoa volumetrica disponiveis")
	var env: Environment = Environment.new()
	QualitySettings.apply(QualitySettings.Preset.HIGH, null, env, null)
	var caps: Dictionary = QualitySettings.renderer_caps()
	ctx.check(env.ssao_enabled == bool(caps["ssao"]), "apply(Alto) respeita o renderer atual (SSAO)")
	ctx.check(env.volumetric_fog_enabled == bool(caps["volumetric_fog"]), "apply(Alto) respeita o renderer atual (nevoa)")


func _env(ctx: Variant) -> void:
	var se: SceneryEnv = SceneryEnv.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(se)
	for zid: String in SceneryTheme.zone_ids():
		ctx.check(se.set_zone(zid, true), "SceneryEnv aceita " + zid)
	ctx.check(not se.set_zone("zone_nada", true), "zona sem tema: false (luz de reserva)")
	se.set_zone("zone_ruins", true)
	ctx.check(se.sun.directional_shadow_mode == DirectionalLight3D.SHADOW_ORTHOGONAL, "sol com sombras ortogonais (camera isometrica)")
	ctx.check(se.env.fog_enabled and se.env.glow_enabled, "nevoa e glow ligados")
	var ante: Dictionary = se.mood_for(Vector3(380, 0, 0))
	var hall: Dictionary = se.mood_for(Vector3(432, 0, 0))
	ctx.check(se.region_at(Vector3(380, 0, 0)) == "" and se.region_at(Vector3(432, 0, 0)) == "boss_hall", "regiao do salao do chefe")
	ctx.check(ante["sky_top"] != hall["sky_top"] or ante["sun_color"] != hall["sun_color"], "humor do salao difere da antecamara")
	se.set_zone("zone_hub", true)
	se.update(0.1, Vector3(0, 0, 0))
	var hub_fog: float = se.env.fog_density
	se.set_zone("zone_ruins", false)
	for i: int in 200:
		se.update(0.1, Vector3(380, 0, 0))
	ctx.check(absf(se.env.fog_density - float((SceneryTheme.for_zone("zone_ruins")["mood"] as Dictionary)["fog_density"])) < 0.0002 and hub_fog > 0.0, "humor converge ao da zona")
	# poda de luzes: so as max_lights mais proximas ficam acesas
	var list: Array[OmniLight3D] = []
	for i: int in 30:
		var l: OmniLight3D = OmniLight3D.new()
		l.position = Vector3(float(i) * 3.0, 1.0, 0.0)
		l.set_meta("base_energy", 2.0)
		se.add_child(l)
		list.append(l)
	se.set_lights(list)
	se.quality = QualitySettings.Preset.LOW
	se.update(0.3, Vector3(0, 0, 0))
	var lit: int = 0
	for l: OmniLight3D in list:
		if l.visible:
			lit += 1
	ctx.check(lit == int(QualitySettings.data(QualitySettings.Preset.LOW)["max_lights"]), "Baixo: so %d luzes acesas (%d)" % [int(QualitySettings.data(QualitySettings.Preset.LOW)["max_lights"]), lit])
	ctx.check(list[0].visible and not list[29].visible, "acende as mais proximas do jogador")
	se.free()
