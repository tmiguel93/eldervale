class_name UiStyle
extends RefCounted
## E5.5: tema unico da UI do cliente (somente codigo, sem assets). Cores/margens centralizadas para
## manter os paineis consistentes. Nada aqui decide jogo.

const BG: Color = Color(0.07, 0.08, 0.11, 0.94)
const BG_SOFT: Color = Color(0.13, 0.15, 0.2, 0.96)
const BG_SELECT: Color = Color(0.32, 0.26, 0.12, 1.0)
const BORDER: Color = Color(0.58, 0.47, 0.26, 1.0)
const TEXT: Color = Color(0.93, 0.91, 0.85, 1.0)
const TEXT_DIM: Color = Color(0.64, 0.64, 0.68, 1.0)
const ACCENT: Color = Color(0.96, 0.8, 0.32, 1.0)
const GOOD: Color = Color(0.5, 0.88, 0.55, 1.0)
const BAD: Color = Color(0.96, 0.42, 0.36, 1.0)
const INFO: Color = Color(0.55, 0.78, 1.0, 1.0)
const HP_FILL: Color = Color(0.78, 0.2, 0.2, 1.0)
const HP_BOSS: Color = Color(0.86, 0.45, 0.12, 1.0)
const HP_BACK: Color = Color(0.12, 0.05, 0.05, 0.9)
const FONT_SIZE: int = 15

static var _theme: Theme = null


static func box(bg: Color, border: Color = BORDER, border_w: int = 1, margin: int = 8, radius: int = 4) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	return sb


## Tema compartilhado (criado uma vez). Aplicado no no raiz da UI; os filhos herdam.
static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t: Theme = Theme.new()
	t.default_font_size = FONT_SIZE
	t.set_color("font_color", "Label", TEXT)
	t.set_stylebox("panel", "PanelContainer", box(BG))
	t.set_stylebox("normal", "Button", box(BG_SOFT, BORDER, 1, 6))
	t.set_stylebox("hover", "Button", box(BG_SELECT, ACCENT, 1, 6))
	t.set_stylebox("pressed", "Button", box(BG_SELECT, ACCENT, 2, 6))
	t.set_stylebox("disabled", "Button", box(Color(0.1, 0.1, 0.12, 0.8), Color(0.3, 0.3, 0.3), 1, 6))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	for c: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		t.set_color(c, "Button", TEXT)
	t.set_color("font_disabled_color", "Button", TEXT_DIM)
	t.set_stylebox("background", "ProgressBar", box(HP_BACK, Color(0, 0, 0, 0.6), 1, 0, 2))
	t.set_stylebox("fill", "ProgressBar", box(HP_FILL, HP_FILL, 0, 0, 2))
	_theme = t
	return t


static func label(text: String, color: Color = TEXT, size: int = 0, wrap: bool = false) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_color_override("font_color", color)
	if size > 0:
		l.add_theme_font_size_override("font_size", size)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


## Botao sem foco (o teclado do jogo e tratado pelos paineis; foco duplicaria Espaco/Enter com a esquiva).
static func button(text: String) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	return b


## Barra (vida) com texto centralizado.
static func bar(width: float, height: float, fill: Color = HP_FILL) -> ProgressBar:
	var pb: ProgressBar = ProgressBar.new()
	pb.custom_minimum_size = Vector2(width, height)
	pb.show_percentage = false
	pb.min_value = 0.0
	pb.max_value = 1.0
	pb.step = 0.0
	pb.value = 1.0
	pb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pb.add_theme_stylebox_override("fill", box(fill, fill, 0, 0, 2))
	var txt: Label = label("", TEXT, 12)
	txt.name = "Text"
	txt.set_anchors_preset(Control.PRESET_FULL_RECT)
	txt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	txt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pb.add_child(txt)
	return pb


static func set_bar(pb: ProgressBar, cur: float, maxv: float, text: String) -> void:
	pb.value = clampf(cur / maxv, 0.0, 1.0) if maxv > 0.0 else 0.0
	var txt: Label = pb.get_node_or_null("Text") as Label
	if txt != null:
		txt.text = text


## True se `ev` e um KeyEvent pressionado com a tecla `key` (keycode ou fisica; aceita eco para navegacao).
static func key_pressed(ev: InputEvent, key: Key, allow_echo: bool = true) -> bool:
	if not (ev is InputEventKey):
		return false
	var k: InputEventKey = ev
	if not k.pressed or (k.echo and not allow_echo):
		return false
	return k.keycode == key or k.physical_keycode == key
