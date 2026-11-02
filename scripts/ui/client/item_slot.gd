class_name ItemSlot
extends Button
## E8.4: slot de item (inventario). E um Button (o texto do botao continua sendo o nome, para testes/leitores de tela; fica invisivel e o
## nome e desenhado pelo rotulo "Caption"), com icone game-icons colorido pela raridade, moldura por raridade (tema Slot<Raridade>),
## badge de quantidade e, para lendario/mitico, brilho pulsante + reflexo (so com movimento; ver UiFx).

const SLOT_SIZE: Vector2 = Vector2(74, 64)

var item_id: String = ""
var rarity_id: String = "common"
var has_item: bool = false
var selected: bool = false
var _icon_holder: CenterContainer
var _caption: Label
var _qty: Label
var _glow: Control
var _clock: float = 0.0


func _init() -> void:
	custom_minimum_size = SLOT_SIZE
	focus_mode = Control.FOCUS_NONE
	clip_text = true
	alignment = HORIZONTAL_ALIGNMENT_CENTER
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	for c: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color", "font_disabled_color"]:
		add_theme_color_override(c, Color(0, 0, 0, 0))
	add_theme_color_override("font_outline_color", Color(0, 0, 0, 0))
	theme_type_variation = NorseTheme.rarity_variation("common")
	_icon_holder = CenterContainer.new()
	_icon_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon_holder.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_icon_holder.offset_top = 3.0
	_icon_holder.offset_bottom = 42.0
	add_child(_icon_holder)
	_caption = UiStyle.label("", UiStyle.TEXT, 11)
	_caption.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_caption.offset_top = -18.0
	_caption.offset_bottom = -2.0
	_caption.offset_left = 3.0
	_caption.offset_right = -3.0
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.clip_text = true
	_caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(_caption)
	_qty = UiStyle.label("", UiStyle.TEXT, 12, false, "heading")
	_qty.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_qty.offset_left = -34.0
	_qty.offset_right = -6.0
	_qty.offset_top = 3.0
	_qty.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_qty.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	_qty.add_theme_constant_override("outline_size", 4)
	add_child(_qty)
	_glow = Control.new()
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	_glow.clip_contents = true
	_glow.draw.connect(_draw_glow)
	add_child(_glow)
	set_process(false)


## Mostra um item (ou esvazia com item_id vazio). `caption` = nome curto; `qty` > 1 mostra o badge.
func show_item(p_item_id: String, qty: int, rarity: String, caption: String) -> void:
	item_id = p_item_id
	has_item = not p_item_id.is_empty()
	rarity_id = rarity if has_item else "common"
	theme_type_variation = NorseTheme.rarity_variation(rarity_id)
	for ch: Node in _icon_holder.get_children():
		_icon_holder.remove_child(ch)
		ch.queue_free()
	if not has_item:
		_caption.text = ""
		_qty.text = ""
		_glow.queue_redraw()
		set_process(false)
		return
	var col: Color = NorseTheme.rarity_color(rarity_id) if rarity_id != "common" else Color("#e6dcc6")
	var icon: Control = UiIcons.make(UiIcons.item_ref(p_item_id), 34.0, col, caption)
	icon.custom_minimum_size = Vector2(34, 34)
	_icon_holder.add_child(icon)
	_caption.text = caption
	_caption.add_theme_color_override("font_color", col if rarity_id != "common" else UiStyle.TEXT)
	_qty.text = "x%d" % qty if qty > 1 else ""
	set_process(rank() >= 4 and UiFx.motion())
	_glow.queue_redraw()


func rank() -> int:
	return NorseTheme.RARITY_IDS.find(rarity_id)


func set_selected(on: bool) -> void:
	selected = on
	if on:
		var col: Color = NorseTheme.rarity_color(rarity_id) if has_item else NorseTheme.GOLD
		add_theme_stylebox_override("normal", UiArt.slot(col.lerp(NorseTheme.GOLD_BRIGHT, 0.55), 0.22, "selected"))
	else:
		remove_theme_stylebox_override("normal")
	_glow.queue_redraw()


func _process(delta: float) -> void:
	_clock += delta
	_glow.queue_redraw()


func _draw_glow() -> void:
	if not has_item or rank() < 4:
		return
	var col: Color = NorseTheme.rarity_color(rarity_id)
	var s: Vector2 = _glow.size
	var pulse: float = 0.5 + 0.5 * sin(_clock * 2.4) if UiFx.motion() else 0.6
	_glow.draw_rect(Rect2(Vector2.ZERO, s).grow(-1.0), Color(col, 0.25 + 0.35 * pulse), false, 2.0)
	if UiFx.motion():
		var x: float = fposmod(_clock * 0.45, 1.6) * (s.x + 40.0) - 40.0
		_glow.draw_colored_polygon(PackedVector2Array([Vector2(x, s.y), Vector2(x + 12.0, s.y), Vector2(x + 12.0 + s.y * 0.5, 0.0), Vector2(x + s.y * 0.5, 0.0)]), Color(1, 1, 1, 0.16))


func _make_custom_tooltip(for_text: String) -> Object:
	if for_text.is_empty():
		return null
	return UiTooltip.build(for_text, NorseTheme.rarity_color(rarity_id) if rarity_id != "common" else UiStyle.TEXT)
