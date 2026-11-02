class_name ScreenFade
extends Control
## E5.5: fade preto curto na troca de zona (eventos zone phase 0/1) e aviso de morte. Apenas apresentacao;
## tempo avancado por `advance(delta)`. Trava de seguranca: se ficar preto por mais de MAX_HOLD s sem
## chegada (transicao cancelada), clareia sozinho para nunca deixar a tela presa.

const FADE_OUT_TIME: float = 0.25
const FADE_IN_TIME: float = 0.4
const MAX_HOLD: float = 3.0

var alpha: float = 0.0
var dead: bool = false
var _target: float = 0.0
var _speed: float = 0.0
var _hold: float = 0.0
var _rect: ColorRect
var _death_rect: ColorRect
var _death_label: Label
var _spinner: RuneSpinner
var _loading: Label


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect = ColorRect.new()
	_rect.color = Color.BLACK
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_rect)
	_death_rect = ColorRect.new()
	_death_rect.color = Color(0.45, 0.0, 0.0, 0.35)
	_death_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_death_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_death_rect.visible = false
	add_child(_death_rect)
	_death_label = UiStyle.label("Você morreu. Reaparecendo...", UiStyle.BAD, 34, false, "title")
	_death_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_death_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_death_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_death_label.visible = false
	add_child(_death_label)
	# E8.4: runa girando e texto "Atravessando..." enquanto a tela esta escura (troca de zona)
	_spinner = RuneSpinner.new(110.0)
	_spinner.set_anchors_preset(Control.PRESET_CENTER)
	_spinner.position = -_spinner.custom_minimum_size * 0.5
	_spinner.size = _spinner.custom_minimum_size
	_spinner.visible = false
	add_child(_spinner)
	_loading = UiStyle.label("Atravessando...", UiStyle.ACCENT, 20, false, "heading")
	_loading.set_anchors_preset(Control.PRESET_CENTER)
	_loading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading.position = Vector2(-120, 64)
	_loading.size = Vector2(240, 30)
	_loading.visible = false
	add_child(_loading)
	_apply()


func fade_out() -> void:
	_target = 1.0
	_speed = 1.0 / FADE_OUT_TIME
	_hold = 0.0


func fade_in() -> void:
	_target = 0.0
	_speed = 1.0 / FADE_IN_TIME


func set_dead(p_dead: bool) -> void:
	dead = p_dead
	_death_rect.visible = p_dead
	_death_label.visible = p_dead


func reset() -> void:
	alpha = 0.0
	_target = 0.0
	_hold = 0.0
	set_dead(false)
	_apply()


func is_dark() -> bool:
	return alpha >= 0.999


func advance(delta: float) -> void:
	if _target > 0.5 and alpha >= 0.999:
		_hold += delta
		if _hold >= MAX_HOLD:
			fade_in()
	alpha = move_toward(alpha, _target, _speed * delta)
	_apply()


func _apply() -> void:
	_rect.color = Color(0.02, 0.015, 0.01, alpha)
	_rect.visible = alpha > 0.001
	var show_rune: bool = alpha > 0.45
	if _spinner != null:
		_spinner.visible = show_rune
		_loading.visible = show_rune
		_spinner.modulate.a = clampf((alpha - 0.45) / 0.55, 0.0, 1.0)
		_loading.modulate.a = _spinner.modulate.a
