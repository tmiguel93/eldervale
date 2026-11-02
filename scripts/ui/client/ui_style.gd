class_name UiStyle
extends RefCounted
## E5.5: tema unico da UI do cliente (somente codigo, sem assets). Cores/margens centralizadas para
## manter os paineis consistentes. Nada aqui decide jogo.

const BG: Color = Color("#17110d", 0.96)
const BG_SOFT: Color = Color("#241b13", 0.96)
const BG_SELECT: Color = Color("#4a3a26", 1.0)
const BORDER: Color = Color("#8a6f33", 1.0)
const TEXT: Color = Color("#efe4cc", 1.0)
const TEXT_DIM: Color = Color("#b0a48d", 1.0)
const ACCENT: Color = Color("#ecca78", 1.0)
const GOOD: Color = Color("#92d17d", 1.0)
const BAD: Color = Color("#f2705f", 1.0)
const INFO: Color = Color("#8fc7e6", 1.0)
const HP_FILL: Color = Color("#b3261e", 1.0)
const HP_BOSS: Color = Color("#d9531f", 1.0)
const HP_BACK: Color = Color("#1a0a08", 0.9)
const GOLD: Color = Color("#c9a24a", 1.0)
const FONT_SIZE: int = NorseTheme.BODY_SIZE

static var _theme: Theme = null


static func box(bg: Color, border: Color = BORDER, border_w: int = 1, margin: int = 8, radius: int = 4) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	return sb


## E8.4: tema nordico compartilhado (criado uma vez; ver NorseTheme). Aplicado no no raiz da UI; os filhos herdam.
static func theme() -> Theme:
	if _theme == null:
		_theme = NorseTheme.build()
	return _theme


## `font`: "" (corpo do tema), "heading", "title" ou "rune".
static func label(text: String, color: Color = TEXT, size: int = 0, wrap: bool = false, font: String = "") -> Label:
	var l: Label = Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_color_override("font_color", color)
	if size > 0:
		l.add_theme_font_size_override("font_size", size)
	if not font.is_empty():
		l.add_theme_font_override("font", NorseFonts.font(font))
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


## Rotulo de cabecalho (fonte Cinzel).
static func heading(text: String, color: Color = ACCENT, size: int = 17) -> Label:
	return label(text, color, size, false, "heading")


## Botao sem foco (o teclado do jogo e tratado pelos paineis; foco duplicaria Espaco/Enter com a esquiva).
static func button(text: String) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	return b


## Barra estilizada (StatBar e um ProgressBar) com texto centralizado. `fill` escolhe o tipo: HP_BOSS => chefe, GOOD => aliado.
static func bar(width: float, height: float, fill: Color = HP_FILL) -> ProgressBar:
	var kind: int = StatBar.Kind.HEALTH
	if fill == HP_BOSS:
		kind = StatBar.Kind.BOSS
	elif fill == GOOD:
		kind = StatBar.Kind.ALLY
	return StatBar.new(kind, width, height)


static func set_bar(pb: ProgressBar, cur: float, maxv: float, text: String) -> void:
	pb.value = clampf(cur / maxv, 0.0, 1.0) if maxv > 0.0 else 0.0
	var txt: Label = pb.get_node_or_null("Text") as Label
	if txt != null:
		txt.text = text


static func key_pressed(ev: InputEvent, key: Key, allow_echo: bool = true) -> bool:
	if not (ev is InputEventKey):
		return false
	var k: InputEventKey = ev
	if not k.pressed or (k.echo and not allow_echo):
		return false
	return k.keycode == key or k.physical_keycode == key
