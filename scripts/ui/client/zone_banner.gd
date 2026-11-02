class_name ZoneBanner
extends VBoxContainer
## E8.4: titulo da zona ao chegar (nome grande em Cinzel Decorative + divisor de runas) que entra e sai com fade. O tempo avanca por
## `advance(delta)` (deterministico nos testes); com reduce_motion so faz fade (sem deslizar).

const LIFE: float = 3.4
const FADE_IN: float = 0.6
const FADE_OUT: float = 0.9

var life: float = 0.0
var name_label: Label
var _sub: Label


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override("separation", 2)
	visible = false
	_sub = UiStyle.label("ᚠ  ᚢ  ᚦ  ᚨ  ᚱ  ᚲ", NorseTheme.GOLD_DIM, 15, false, "rune")
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_sub)
	name_label = UiStyle.label("", NorseTheme.GOLD_BRIGHT, 40, false, "title")
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	name_label.add_theme_constant_override("outline_size", 8)
	add_child(name_label)
	var d: RuneDivider = RuneDivider.new()
	d.custom_minimum_size = Vector2(320, 16)
	d.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	add_child(d)


func show_zone(zone_name: String) -> void:
	if zone_name.strip_edges().is_empty():
		return
	name_label.text = zone_name
	life = LIFE
	visible = true
	_apply()


func advance(delta: float) -> void:
	if life <= 0.0:
		return
	life = maxf(life - delta, 0.0)
	if life <= 0.0:
		visible = false
		modulate.a = 1.0
		return
	_apply()


func _apply() -> void:
	var elapsed: float = LIFE - life
	var a: float = clampf(elapsed / FADE_IN, 0.0, 1.0) * clampf(life / FADE_OUT, 0.0, 1.0)
	modulate.a = a if UiFx.available() else 1.0
