class_name NorseTheme
extends RefCounted
## E8.4: Theme central nordico (construido em codigo; sem .tres para nao depender de editor). Aplicado no no raiz de TODAS as UIs do
## cliente (ClientUi, tela de login); os filhos herdam. Paleta: madeira escura, ferro, ouro velho, azul-gelo, vermelho-sangue.
## Contraste: texto/fundo >= 4.5:1 (teste e8_ui). Tipos auxiliares (theme_type_variation): ModalPanel, HudPanel, PanelTitle, HeadingLabel,
## TitleLabel, DimLabel, RuneLabel, CloseButton, Slot<Raridade>, TooltipPanel.

const WOOD_DARK: Color = Color("#17110d")
const WOOD: Color = Color("#241b13")
const WOOD_LIGHT: Color = Color("#3a2c1e")
const IRON: Color = Color("#3b4048")
const IRON_LIGHT: Color = Color("#5d636e")
const GOLD: Color = Color("#c9a24a")
const GOLD_BRIGHT: Color = Color("#ecca78")
const GOLD_DIM: Color = Color("#8a6f33")
const ICE: Color = Color("#8fc7e6")
const ICE_DEEP: Color = Color("#3c6e8c")
const BLOOD: Color = Color("#b3261e")
const BLOOD_DEEP: Color = Color("#5c0f0b")
const PARCHMENT: Color = Color("#efe4cc")
const PARCHMENT_DIM: Color = Color("#b0a48d")
const GOOD: Color = Color("#92d17d")
const BAD: Color = Color("#f2705f")

const RARITY_IDS: Array[String] = ["common", "uncommon", "rare", "epic", "legendary", "mythic"]
const RARITY_FALLBACK: Dictionary = {"common": "#c8c8c8", "uncommon": "#6fd16f", "rare": "#f1d04b", "epic": "#b46cf2", "legendary": "#ff9a2e", "mythic": "#ff4f6a"}
const RARITY_GLOW: Dictionary = {"common": 0.0, "uncommon": 0.0, "rare": 0.12, "epic": 0.2, "legendary": 0.3, "mythic": 0.34}
const BODY_SIZE: int = 17
const BUTTON_SIZE: int = 15


static func rarity_color(rarity_id: String) -> Color:
	return Color(String(RARITY_FALLBACK.get(rarity_id, "#c8c8c8")))


static func rarity_variation(rarity_id: String) -> StringName:
	return StringName("Slot" + rarity_id.capitalize())


## Luminancia relativa WCAG de uma cor.
static func luminance(c: Color) -> float:
	var f: Callable = func(v: float) -> float: return v / 12.92 if v <= 0.03928 else pow((v + 0.055) / 1.055, 2.4)
	return 0.2126 * float(f.call(c.r)) + 0.7152 * float(f.call(c.g)) + 0.0722 * float(f.call(c.b))


## Razao de contraste WCAG entre duas cores.
static func contrast(a: Color, b: Color) -> float:
	var la: float = luminance(a)
	var lb: float = luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


static func _flat(bg: Color, border: Color, bw: int = 1, margin: int = 6, radius: int = 2) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(float(margin))
	return sb


static func build() -> Theme:
	var t: Theme = Theme.new()
	var body: Font = NorseFonts.font("body")
	var head: Font = NorseFonts.font("heading")
	t.default_font = body
	t.default_font_size = BODY_SIZE
	# ---- Label
	t.set_color("font_color", "Label", PARCHMENT)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.55))
	t.set_constant("shadow_offset_x", "Label", 1)
	t.set_constant("shadow_offset_y", "Label", 1)
	t.set_font("font", "Label", body)
	t.set_type_variation("HeadingLabel", "Label")
	t.set_font("font", "HeadingLabel", head)
	t.set_font_size("font_size", "HeadingLabel", 17)
	t.set_color("font_color", "HeadingLabel", GOLD)
	t.set_type_variation("PanelTitle", "Label")
	t.set_font("font", "PanelTitle", head)
	t.set_font_size("font_size", "PanelTitle", 22)
	t.set_color("font_color", "PanelTitle", GOLD_BRIGHT)
	t.set_color("font_outline_color", "PanelTitle", Color(0, 0, 0, 0.85))
	t.set_constant("outline_size", "PanelTitle", 3)
	t.set_type_variation("TitleLabel", "Label")
	t.set_font("font", "TitleLabel", NorseFonts.font("title"))
	t.set_font_size("font_size", "TitleLabel", 34)
	t.set_color("font_color", "TitleLabel", GOLD_BRIGHT)
	t.set_color("font_outline_color", "TitleLabel", Color(0, 0, 0, 0.9))
	t.set_constant("outline_size", "TitleLabel", 4)
	t.set_type_variation("DimLabel", "Label")
	t.set_color("font_color", "DimLabel", PARCHMENT_DIM)
	t.set_type_variation("RuneLabel", "Label")
	t.set_font("font", "RuneLabel", NorseFonts.font("rune"))
	t.set_color("font_color", "RuneLabel", GOLD_DIM)
	# ---- Paineis
	t.set_stylebox("panel", "PanelContainer", UiArt.hud(0.82))
	t.set_type_variation("ModalPanel", "PanelContainer")
	t.set_stylebox("panel", "ModalPanel", UiArt.panel())
	t.set_type_variation("HudPanel", "PanelContainer")
	t.set_stylebox("panel", "HudPanel", UiArt.hud(0.72))
	t.set_stylebox("panel", "TooltipPanel", UiArt.tooltip())
	t.set_color("font_color", "TooltipLabel", PARCHMENT)
	t.set_font("font", "TooltipLabel", body)
	t.set_font_size("font_size", "TooltipLabel", 16)
	# ---- Botoes
	t.set_font("font", "Button", head)
	t.set_font_size("font_size", "Button", BUTTON_SIZE)
	t.set_stylebox("normal", "Button", UiArt.button("normal"))
	t.set_stylebox("hover", "Button", UiArt.button("hover"))
	t.set_stylebox("pressed", "Button", UiArt.button("pressed"))
	t.set_stylebox("disabled", "Button", UiArt.button("disabled"))
	t.set_stylebox("hover_pressed", "Button", UiArt.button("pressed"))
	t.set_stylebox("focus", "Button", _focus_box())
	t.set_color("font_color", "Button", PARCHMENT)
	t.set_color("font_hover_color", "Button", GOLD_BRIGHT)
	t.set_color("font_pressed_color", "Button", GOLD)
	t.set_color("font_hover_pressed_color", "Button", GOLD_BRIGHT)
	t.set_color("font_focus_color", "Button", PARCHMENT)
	t.set_color("font_disabled_color", "Button", Color("#7d7566"))
	t.set_color("font_outline_color", "Button", Color(0, 0, 0, 0.7))
	t.set_constant("outline_size", "Button", 2)
	t.set_color("icon_normal_color", "Button", Color.WHITE)
	t.set_color("icon_hover_color", "Button", Color(1.2, 1.1, 0.9))
	t.set_constant("h_separation", "Button", 8)
	t.set_type_variation("CloseButton", "Button")
	t.set_stylebox("normal", "CloseButton", _close_box(false))
	t.set_stylebox("hover", "CloseButton", _close_box(true))
	t.set_stylebox("pressed", "CloseButton", _close_box(true))
	# slots por raridade (itens): borda e brilho na cor da raridade
	for rid: String in RARITY_IDS:
		var col: Color = rarity_color(rid)
		var glow: float = float(RARITY_GLOW.get(rid, 0.0))
		var v: StringName = rarity_variation(rid)
		t.set_type_variation(v, "Button")
		t.set_stylebox("normal", v, UiArt.slot(col, glow))
		t.set_stylebox("hover", v, UiArt.slot(col, glow, "hover"))
		t.set_stylebox("pressed", v, UiArt.slot(col, glow, "selected"))
		t.set_stylebox("disabled", v, UiArt.slot(col, glow))
	t.set_type_variation("SlotSelected", "Button")
	for st: String in ["normal", "hover", "pressed"]:
		t.set_stylebox(st, "SlotSelected", UiArt.slot(GOLD_BRIGHT, 0.2, "selected"))
	# ---- CheckBox / CheckButton
	for tn: String in ["CheckBox", "CheckButton"]:
		t.set_icon("checked", tn, UiArt.check_icon(true))
		t.set_icon("unchecked", tn, UiArt.check_icon(false))
		t.set_icon("checked_disabled", tn, UiArt.check_icon(true))
		t.set_icon("unchecked_disabled", tn, UiArt.check_icon(false))
		t.set_font("font", tn, head)
		t.set_font_size("font_size", tn, BUTTON_SIZE)
		t.set_color("font_color", tn, PARCHMENT)
		t.set_color("font_hover_color", tn, GOLD_BRIGHT)
		t.set_color("font_pressed_color", tn, GOLD_BRIGHT)
		t.set_color("font_hover_pressed_color", tn, GOLD_BRIGHT)
		t.set_stylebox("normal", tn, StyleBoxEmpty.new())
		t.set_stylebox("hover", tn, StyleBoxEmpty.new())
		t.set_stylebox("pressed", tn, StyleBoxEmpty.new())
		t.set_stylebox("hover_pressed", tn, StyleBoxEmpty.new())
		t.set_stylebox("focus", tn, _focus_box())
		t.set_constant("h_separation", tn, 10)
	# ---- Sliders
	t.set_stylebox("slider", "HSlider", _flat(Color("#0f0b08"), IRON, 1, 0, 1))
	(t.get_stylebox("slider", "HSlider") as StyleBoxFlat).content_margin_top = 3.0
	(t.get_stylebox("slider", "HSlider") as StyleBoxFlat).content_margin_bottom = 3.0
	t.set_stylebox("grabber_area", "HSlider", _flat(GOLD_DIM, GOLD_DIM, 0, 0, 1))
	t.set_stylebox("grabber_area_highlight", "HSlider", _flat(GOLD, GOLD, 0, 0, 1))
	t.set_icon("grabber", "HSlider", UiArt.grabber_icon(false))
	t.set_icon("grabber_highlight", "HSlider", UiArt.grabber_icon(true))
	t.set_icon("grabber_disabled", "HSlider", UiArt.grabber_icon(false))
	# ---- Scroll
	for sb_name: String in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", sb_name, _flat(Color("#0f0b08", 0.85), Color("#2a2e35"), 1, 0, 2))
		t.set_stylebox("scroll_focus", sb_name, _flat(Color("#0f0b08", 0.85), IRON, 1, 0, 2))
		t.set_stylebox("grabber", sb_name, _flat(IRON, GOLD_DIM, 1, 0, 2))
		t.set_stylebox("grabber_highlight", sb_name, _flat(IRON_LIGHT, GOLD, 1, 0, 2))
		t.set_stylebox("grabber_pressed", sb_name, _flat(GOLD_DIM, GOLD_BRIGHT, 1, 0, 2))
	# ---- Separadores
	var sep: StyleBoxLine = StyleBoxLine.new()
	sep.color = GOLD_DIM
	sep.thickness = 1
	t.set_stylebox("separator", "HSeparator", sep)
	t.set_constant("separation", "HSeparator", 10)
	var vsep: StyleBoxLine = StyleBoxLine.new()
	vsep.color = GOLD_DIM
	vsep.thickness = 1
	vsep.vertical = true
	t.set_stylebox("separator", "VSeparator", vsep)
	# ---- Campos de texto / lista (tela de login)
	t.set_stylebox("normal", "LineEdit", _flat(Color("#0f0b08"), IRON, 1, 8, 2))
	t.set_stylebox("focus", "LineEdit", _flat(Color("#16100b"), GOLD, 1, 8, 2))
	t.set_stylebox("read_only", "LineEdit", _flat(Color("#16120e"), IRON, 1, 8, 2))
	t.set_color("font_color", "LineEdit", PARCHMENT)
	t.set_color("font_placeholder_color", "LineEdit", Color("#8d826f"))
	t.set_color("caret_color", "LineEdit", GOLD_BRIGHT)
	t.set_color("selection_color", "LineEdit", Color(ICE_DEEP, 0.7))
	t.set_stylebox("panel", "ItemList", _flat(Color("#0f0b08", 0.9), IRON, 1, 6, 2))
	t.set_stylebox("focus", "ItemList", _flat(Color(0, 0, 0, 0), GOLD, 1, 0, 2))
	t.set_stylebox("selected", "ItemList", _flat(Color("#3a2c1e"), GOLD, 1, 4, 2))
	t.set_stylebox("selected_focus", "ItemList", _flat(Color("#3a2c1e"), GOLD_BRIGHT, 1, 4, 2))
	t.set_stylebox("hovered", "ItemList", _flat(Color("#2a2018"), GOLD_DIM, 1, 4, 2))
	t.set_color("font_color", "ItemList", PARCHMENT)
	t.set_color("font_selected_color", "ItemList", GOLD_BRIGHT)
	t.set_font("font", "ItemList", head)
	t.set_font_size("font_size", "ItemList", BUTTON_SIZE)
	# ---- Menus suspensos (OptionButton usa Button; popup abaixo)
	t.set_stylebox("panel", "PopupMenu", UiArt.tooltip())
	t.set_stylebox("hover", "PopupMenu", _flat(Color("#3a2c1e"), GOLD, 1, 4, 2))
	t.set_color("font_color", "PopupMenu", PARCHMENT)
	t.set_color("font_hover_color", "PopupMenu", GOLD_BRIGHT)
	t.set_font("font", "PopupMenu", head)
	t.set_font_size("font_size", "PopupMenu", BUTTON_SIZE)
	# ---- Barras nativas (o jogo usa StatBar; estes valores so evitam o visual padrao em ProgressBar avulso)
	t.set_stylebox("background", "ProgressBar", _flat(Color("#0f0b08"), IRON, 1, 0, 2))
	t.set_stylebox("fill", "ProgressBar", _flat(BLOOD, BLOOD, 0, 0, 2))
	# ---- RichTextLabel
	t.set_font("normal_font", "RichTextLabel", body)
	t.set_font("bold_font", "RichTextLabel", head)
	t.set_color("default_color", "RichTextLabel", PARCHMENT)
	return t


static func _focus_box() -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.draw_center = false
	sb.border_color = ICE
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(3)
	sb.set_expand_margin_all(1.0)
	return sb


static func _close_box(hot: bool) -> StyleBoxFlat:
	var sb: StyleBoxFlat = _flat(Color("#4a1a16") if hot else Color("#2a1512"), Color("#d2563f") if hot else Color("#8a3a2a"), 1, 4, 3)
	sb.content_margin_left = 9.0
	sb.content_margin_right = 9.0
	return sb
