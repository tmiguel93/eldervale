class_name OptionsPanel
extends UiPanel
## E8.4: menu de opcoes (tecla O ou Menu > Opcoes): qualidade grafica (Baixa/Media/Alta = QualitySettings), escala da interface, reduzir
## movimento (VfxSettings.reduce_motion, o mesmo do --reduce-motion do E8.3) e volume geral. Tudo persiste em user://settings.cfg
## (`config_path`; os testes usam um arquivo temporario). Quem aplica a qualidade no mundo 3D e o ClientMain, via `quality_changed`.
## Teclado: Cima/Baixo escolhem a linha, Esquerda/Direita ajustam, Enter alterna.

signal quality_changed(preset: int)
signal reduce_motion_changed(on: bool)
signal volume_changed(v: float)
signal scale_changed(s: float)

const ROWS: Array[String] = ["quality", "scale", "reduce", "volume"]

var config_path: String = QualitySettings.CONFIG_PATH
var cursor: int = 0
var quality_buttons: Dictionary = {}   ## preset -> Button
var scale_buttons: Array[Button] = []
var reduce_check: CheckButton
var volume_slider: HSlider
var volume_label: Label
var _row_boxes: Array[PanelContainer] = []
var _syncing: bool = false


func _init() -> void:
	super._init("Opções", Vector2(560, 440), "ᛉ", UiIcons.ref("ui", "options"))
	# Qualidade
	var q_row: HBoxContainer = _row("Qualidade gráfica")
	for preset: int in [QualitySettings.Preset.LOW, QualitySettings.Preset.MEDIUM, QualitySettings.Preset.HIGH]:
		var b: Button = UiStyle.button({0: "Baixa", 1: "Média", 2: "Alta"}[preset])
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.custom_minimum_size = Vector2(84, 34)
		b.toggle_mode = false
		b.pressed.connect(set_quality.bind(preset))
		q_row.add_child(b)
		quality_buttons[preset] = b
	# Escala
	var s_row: HBoxContainer = _row("Escala da interface")
	for sc: float in UiSettings.SCALES:
		var sb: Button = UiStyle.button("%d%%" % int(round(sc * 100.0)))
		sb.alignment = HORIZONTAL_ALIGNMENT_CENTER
		sb.custom_minimum_size = Vector2(62, 34)
		sb.pressed.connect(set_ui_scale.bind(sc))
		s_row.add_child(sb)
		scale_buttons.append(sb)
	# Reduzir movimento
	var r_row: HBoxContainer = _row("Reduzir movimento")
	reduce_check = CheckButton.new()
	reduce_check.text = "Sem tremor, pulsos nem brilho"
	reduce_check.focus_mode = Control.FOCUS_NONE
	reduce_check.toggled.connect(func(on: bool) -> void:
		if not _syncing:
			set_reduce_motion(on))
	r_row.add_child(reduce_check)
	# Volume
	var v_row: HBoxContainer = _row("Volume geral")
	volume_slider = HSlider.new()
	volume_slider.min_value = 0.0
	volume_slider.max_value = 1.0
	volume_slider.step = 0.05
	volume_slider.custom_minimum_size = Vector2(190, 24)
	volume_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	volume_slider.focus_mode = Control.FOCUS_NONE
	volume_slider.value_changed.connect(func(v: float) -> void:
		if not _syncing:
			set_volume(v))
	v_row.add_child(volume_slider)
	volume_label = UiStyle.label("", UiStyle.ACCENT, 15, false, "heading")
	volume_label.custom_minimum_size = Vector2(48, 0)
	v_row.add_child(volume_label)
	hint_label.text = "Cima/Baixo escolhem | Esquerda/Direita ajustam | Enter alterna | O ou Esc fecha | F9 alterna a qualidade"
	sync_from_settings()


## Linha "rotulo + controles" dentro de uma moldura; devolve o HBox dos controles.
func _row(title: String) -> HBoxContainer:
	var pc: PanelContainer = PanelContainer.new()
	pc.theme_type_variation = &"HudPanel"
	var hb: HBoxContainer = HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	pc.add_child(hb)
	var l: Label = UiStyle.label(title, UiStyle.TEXT, 16, false, "heading")
	l.custom_minimum_size = Vector2(170, 0)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(l)
	body.add_child(pc)
	_row_boxes.append(pc)
	return hb


## Le o estado atual (QualitySettings/VfxSettings/UiSettings) para os controles.
func sync_from_settings() -> void:
	_syncing = true
	for preset: Variant in quality_buttons.keys():
		mark_row(quality_buttons[preset] as Button, int(preset) == QualitySettings.current, UiStyle.ACCENT if int(preset) == QualitySettings.current else UiStyle.TEXT)
	for i: int in scale_buttons.size():
		var on: bool = is_equal_approx(UiSettings.SCALES[i], UiSettings.ui_scale)
		mark_row(scale_buttons[i], on, UiStyle.ACCENT if on else UiStyle.TEXT)
	reduce_check.button_pressed = VfxSettings.reduce_motion
	volume_slider.value = UiSettings.master_volume
	volume_label.text = "%d%%" % int(round(UiSettings.master_volume * 100.0))
	_syncing = false
	_paint_cursor()


func _paint_cursor() -> void:
	for i: int in _row_boxes.size():
		_row_boxes[i].add_theme_stylebox_override("panel", UiArt.slot(NorseTheme.GOLD_BRIGHT, 0.12, "selected") if i == cursor else UiArt.hud(0.72))


func _on_open() -> void:
	sync_from_settings()


# ------------------------------------------------------------------ mudancas (aplicam e gravam)

func set_quality(preset: int) -> void:
	if not QualitySettings.PRESET_DATA.has(preset):
		return
	QualitySettings.current = preset
	QualitySettings.save(preset, config_path)
	sync_from_settings()
	quality_changed.emit(preset)


func set_ui_scale(s: float) -> void:
	UiSettings.ui_scale = UiSettings.nearest_scale(s)
	UiSettings.save(config_path)
	UiSettings.apply_scale(get_window())
	sync_from_settings()
	scale_changed.emit(UiSettings.ui_scale)


func set_reduce_motion(on: bool) -> void:
	VfxSettings.reduce_motion = on
	VfxSettings.save(config_path)
	if not _syncing:
		sync_from_settings()
	reduce_motion_changed.emit(on)


func set_volume(v: float) -> void:
	UiSettings.master_volume = UiSettings.clamp_volume(v)
	UiSettings.save(config_path)
	UiSettings.apply_volume()
	if not _syncing:
		sync_from_settings()
	volume_changed.emit(UiSettings.master_volume)


func handle_key(ev: InputEvent) -> bool:
	var step: int = UiPanel.step_index(ev, cursor, ROWS.size())
	if step >= 0:
		cursor = step
		_paint_cursor()
		return true
	var dir: int = 0
	if UiStyle.key_pressed(ev, KEY_LEFT):
		dir = -1
	elif UiStyle.key_pressed(ev, KEY_RIGHT):
		dir = 1
	var confirm: bool = UiPanel.is_confirm(ev)
	if dir == 0 and not confirm:
		return false
	match ROWS[cursor]:
		"quality":
			if dir == 0:
				set_quality(QualitySettings.next_preset(QualitySettings.current))
			else:
				set_quality(posmod(QualitySettings.current + dir, QualitySettings.PRESET_DATA.size()))
		"scale":
			var idx: int = UiSettings.SCALES.find(UiSettings.nearest_scale(UiSettings.ui_scale))
			set_ui_scale(UiSettings.SCALES[posmod(idx + (dir if dir != 0 else 1), UiSettings.SCALES.size())])
		"reduce":
			set_reduce_motion(not VfxSettings.reduce_motion if dir == 0 else dir > 0)
		"volume":
			set_volume(UiSettings.master_volume + 0.05 * float(dir if dir != 0 else 1))
	return true
