class_name SkillSlot
extends Control
## E8.4: slot de habilidade da hotbar: moldura, icone (game-icons), tecla, custo e recarga RADIAL. A recarga e uma ESTIMATIVA
## de apresentacao (inicia quando o jogador aperta a tecla e dura o `cooldown` do SkillData); o servidor continua decidindo se a habilidade
## foi usada. Quando a recarga termina o slot pulsa. Sem reduce_motion o pulso/giro rodam; com ele so ha o varrido escuro (sem pulso).

const SIZE_PX: Vector2 = Vector2(64, 64)

var slot: String = ""
var skill_id: String = ""
var cooldown: float = 0.0
var remaining: float = 0.0
var ready_flash: float = 0.0
var press_flash: float = 0.0
var key_text: String = ""
var cost: int = 0
var _icon_holder: CenterContainer
var _key: Label
var _cost: Label
var _time: Label


func _init() -> void:
	custom_minimum_size = SIZE_PX
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_icon_holder = CenterContainer.new()
	_icon_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon_holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_icon_holder)
	_key = UiStyle.label("", UiStyle.ACCENT, 13, false, "heading")
	_key.position = Vector2(5, 2)
	_key.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	_key.add_theme_constant_override("outline_size", 4)
	add_child(_key)
	_cost = UiStyle.label("", Color("#9cd2f0"), 13, false, "heading")
	_cost.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_cost.offset_left = -30.0
	_cost.offset_right = -5.0
	_cost.offset_top = -20.0
	_cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_cost.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	_cost.add_theme_constant_override("outline_size", 4)
	add_child(_cost)
	_time = UiStyle.label("", Color.WHITE, 18, false, "heading")
	_time.set_anchors_preset(Control.PRESET_FULL_RECT)
	_time.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_time.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_time.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	_time.add_theme_constant_override("outline_size", 5)
	add_child(_time)


func setup(p_slot: String, p_skill_id: String, p_key: String, p_cost: int, p_cooldown: float, tip: String) -> void:
	slot = p_slot
	skill_id = p_skill_id
	key_text = p_key
	cost = p_cost
	cooldown = p_cooldown
	remaining = 0.0
	ready_flash = 0.0
	tooltip_text = tip
	_key.text = p_key
	_cost.text = str(p_cost) if p_cost > 0 else ""
	_time.text = ""
	for ch: Node in _icon_holder.get_children():
		_icon_holder.remove_child(ch)
		ch.queue_free()
	var ic: Control = UiIcons.make(UiIcons.skill_ref(p_skill_id), 40.0, Color("#f1e6cc"), p_skill_id)
	ic.custom_minimum_size = Vector2(42, 42)
	_icon_holder.add_child(ic)
	queue_redraw()


func clear() -> void:
	setup("", "", "", 0, 0.0, "")


func is_cooling() -> bool:
	return remaining > 0.0


## Inicia a recarga estimada (ignorada se ja esta recarregando ou a habilidade tem recarga desprezivel).
func start_cooldown() -> bool:
	if cooldown < 0.45 or remaining > 0.0 or skill_id.is_empty():
		return false
	remaining = cooldown
	if UiFx.motion():
		press_flash = 1.0
	queue_redraw()
	return true


func advance(delta: float) -> void:
	var dirty: bool = false
	if remaining > 0.0:
		remaining = maxf(remaining - delta, 0.0)
		_time.text = "%.1f" % remaining if remaining < 10.0 else str(int(ceilf(remaining)))
		dirty = true
		if remaining <= 0.0:
			_time.text = ""
			if UiFx.motion():
				ready_flash = 1.0
				UiFx.pulse(self, Color(1.5, 1.4, 1.1, 1.0), 0.4)
	if ready_flash > 0.0:
		ready_flash = maxf(ready_flash - delta * 2.2, 0.0)
		dirty = true
	if press_flash > 0.0:
		press_flash = maxf(press_flash - delta * 5.0, 0.0)
		dirty = true
	if dirty:
		queue_redraw()


func _draw() -> void:
	var r: Rect2 = Rect2(Vector2.ZERO, size)
	var gold: Color = NorseTheme.GOLD
	draw_style_box(UiArt.slot(gold, 0.0 if remaining > 0.0 else 0.1, "normal"), r)
	if remaining > 0.0 and cooldown > 0.0:
		var frac: float = clampf(remaining / cooldown, 0.0, 1.0)
		var c: Vector2 = size * 0.5
		var pts: PackedVector2Array = PackedVector2Array([c])
		var n: int = 28
		var a0: float = -PI * 0.5
		for i: int in n + 1:
			var a: float = a0 + TAU * frac * float(i) / float(n)
			pts.append(c + Vector2(cos(a), sin(a)) * size.length())
		var inner: Rect2 = r.grow(-3.0)
		var clip: PackedVector2Array = PackedVector2Array([inner.position, Vector2(inner.end.x, inner.position.y), inner.end, Vector2(inner.position.x, inner.end.y)])
		for piece: PackedVector2Array in Geometry2D.intersect_polygons(pts, clip):
			draw_colored_polygon(piece, Color(0.02, 0.02, 0.05, 0.72))
		# aresta do varrido
		var ea: float = a0 + TAU * frac
		draw_line(c, c + Vector2(cos(ea), sin(ea)) * size.x * 0.6, Color(NorseTheme.GOLD_BRIGHT, 0.55), 1.0)
	if ready_flash > 0.0:
		draw_rect(r.grow(-1.0), Color(NorseTheme.GOLD_BRIGHT, 0.85 * ready_flash), false, 2.0)
		draw_rect(r.grow(-3.0), Color(1, 0.95, 0.75, 0.18 * ready_flash))
	if press_flash > 0.0:
		draw_rect(r.grow(-3.0), Color(1, 1, 1, 0.22 * press_flash))


func _make_custom_tooltip(for_text: String) -> Object:
	if for_text.is_empty():
		return null
	return UiTooltip.build(for_text, UiStyle.ACCENT)
