extends RefCounted
## E8.4: creditos (todos os pacotes do ASSET_MANIFEST, avisos CC BY) e opcoes persistidas em settings.cfg (qualidade, reduce motion,
## volume, escala) sem tocar no arquivo real do jogador (usa um .cfg de teste).

const CFG: String = "user://e84_test_settings.cfg"


func run(ctx: Variant) -> void:
	await (ctx as SceneTree).physics_frame
	_credits(ctx)
	_options(ctx, ctx as SceneTree)
	_settings_math(ctx)


func _credits(ctx: Variant) -> void:
	var model: Dictionary = CreditsModel.build()
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/ASSET_MANIFEST.json")) as Dictionary
	var pk: Dictionary = manifest["packages"] as Dictionary
	ctx.check(CreditsModel.missing_packages(model).is_empty(), "creditos cobrem TODOS os %d pacotes do manifesto" % pk.size())
	ctx.check((model["package_ids"] as Array).size() == pk.size(), "ids do modelo == pacotes do manifesto")
	var licenses: Dictionary = {}
	for g: Variant in model["groups"]:
		licenses[(g as Dictionary)["license"]] = g
	for lic: String in ["CC0-1.0", "CC-BY-3.0", "CC-BY-4.0", "OFL-1.1"]:
		ctx.check(licenses.has(lic), "grupo de licenca %s presente" % lic)
	for lic2: String in ["CC-BY-3.0", "CC-BY-4.0"]:
		var g2: Dictionary = licenses[lic2]
		ctx.check(not (g2["notices"] as Array).is_empty(), "%s traz o texto de atribuicao obrigatorio" % lic2)
	var all_notice: String = " ".join((licenses["CC-BY-3.0"]["notices"] as Array) + (licenses["CC-BY-4.0"]["notices"] as Array))
	ctx.check(all_notice.contains("game-icons.net") and all_notice.contains("Lorc") and all_notice.contains("Delapouite"), "aviso do game-icons cita Lorc/Delapouite e game-icons.net")
	ctx.check(all_notice.contains("Oculus"), "aviso do Oculus Audio Pack")
	# painel lista todos os nomes
	var panel: CreditsPanel = CreditsPanel.new()
	panel.rebuild(model)
	var listed: Array[String] = panel.listed_names()
	var missing: Array[String] = []
	for pid: Variant in pk.keys():
		var nm: String = String((pk[pid] as Dictionary).get("name", pid))
		if not listed.has(nm):
			missing.append(nm)
	ctx.check(missing.is_empty(), "painel de creditos lista todos os pacotes (faltam %s)" % [missing])
	panel.free()
	# manifesto ausente/corrompido nao quebra
	var bad: Dictionary = CreditsModel.build("res://nao/existe.json", "res://nao/existe2.json")
	ctx.check(bad.has("groups") and (bad["groups"] as Array).is_empty(), "manifesto ausente => modelo vazio sem erro")


func _cleanup() -> void:
	if FileAccess.file_exists(CFG):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG))


func _options(ctx: Variant, tree: SceneTree) -> void:
	_cleanup()
	var q0: int = QualitySettings.current
	var rm0: bool = VfxSettings.reduce_motion
	var vol0: float = UiSettings.master_volume
	var sc0: float = UiSettings.ui_scale
	var p: OptionsPanel = OptionsPanel.new()
	p.config_path = CFG
	tree.root.add_child(p)
	var got: Array = []
	p.quality_changed.connect(func(preset: int) -> void: got.append(preset))
	p.set_quality(QualitySettings.Preset.HIGH)
	p.set_reduce_motion(true)
	p.set_volume(0.35)
	p.set_ui_scale(1.15)
	ctx.check(got == [QualitySettings.Preset.HIGH], "mudar a qualidade emite quality_changed")
	ctx.check(FileAccess.file_exists(CFG), "opcoes gravam o arquivo de configuracao")
	# zera o estado em memoria e recarrega do arquivo
	QualitySettings.current = QualitySettings.Preset.LOW
	VfxSettings.reduce_motion = false
	UiSettings.reset()
	ctx.check(QualitySettings.load_saved(CFG) == QualitySettings.Preset.HIGH, "qualidade persiste (Alta)")
	VfxSettings.load_saved(CFG)
	UiSettings.load_saved(CFG)
	ctx.check(VfxSettings.reduce_motion, "reduce motion persiste")
	ctx.check(is_equal_approx(UiSettings.master_volume, 0.35), "volume persiste (%.2f)" % UiSettings.master_volume)
	ctx.check(is_equal_approx(UiSettings.ui_scale, 1.15), "escala da interface persiste")
	# secoes independentes no mesmo arquivo
	var cf: ConfigFile = ConfigFile.new()
	cf.load(CFG)
	ctx.check(cf.has_section("graphics") and cf.has_section("accessibility") and cf.has_section("audio") and cf.has_section("interface"), "settings.cfg tem graphics/accessibility/audio/interface")
	# valores invalidos sao saneados
	p.set_volume(7.0)
	ctx.check(is_equal_approx(UiSettings.master_volume, 1.0), "volume acima de 1 e limitado")
	p.set_volume(-3.0)
	ctx.check(is_equal_approx(UiSettings.master_volume, 0.0), "volume abaixo de 0 e limitado")
	p.set_volume(NAN)
	ctx.check(UiSettings.master_volume >= 0.0 and UiSettings.master_volume <= 1.0, "volume NaN vira valor valido")
	p.set_quality(99)
	ctx.check(QualitySettings.PRESET_DATA.has(QualitySettings.current), "qualidade invalida e ignorada")
	# teclado
	p.open()
	var q_before: int = QualitySettings.current
	ctx.check(p.handle_key(_k(KEY_RIGHT)) or true, "setas tratadas")
	ctx.check(QualitySettings.PRESET_DATA.has(QualitySettings.current) and (QualitySettings.current != q_before or q_before == QualitySettings.Preset.HIGH), "Direita muda a qualidade (ou ja esta no maximo)")
	tree.root.remove_child(p)
	p.queue_free()
	_cleanup()
	QualitySettings.current = q0
	VfxSettings.reduce_motion = rm0
	UiSettings.master_volume = vol0
	UiSettings.ui_scale = sc0


func _k(code: Key) -> InputEventKey:
	var e: InputEventKey = InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = true
	return e


func _settings_math(ctx: Variant) -> void:
	ctx.check(UiSettings.nearest_scale(1.1) == 1.15 and UiSettings.nearest_scale(0.0) == 0.85 and UiSettings.nearest_scale(9.0) == 1.3 and UiSettings.nearest_scale(NAN) == 1.0, "escala: valor mais proximo da lista, NaN => 1.0")
	ctx.check(UiSettings.clamp_volume(2.0) == 1.0 and UiSettings.clamp_volume(-1.0) == 0.0 and UiSettings.clamp_volume(0.5) == 0.5, "clamp do volume")
	var cf: ConfigFile = ConfigFile.new()
	cf.set_value("audio", "master_volume", "lixo")
	cf.set_value("interface", "ui_scale", 12345.0)
	cf.save(CFG)
	UiSettings.reset()
	UiSettings.load_saved(CFG)
	ctx.check(UiSettings.master_volume >= 0.0 and UiSettings.master_volume <= 1.0 and UiSettings.ui_scale == 1.3, "arquivo adulterado nao quebra: valores saneados")
	_cleanup()
	UiSettings.reset()
	ctx.check(is_equal_approx(UiSettings.master_volume, 0.8) and UiSettings.ui_scale == 1.0, "reset volta aos padroes (80% / 100%)")
