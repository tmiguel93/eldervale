extends RefCounted
## E8.4: tema nordico central (carrega, variacoes de tipo, contraste de leitura, fontes com acentos do portugues e fallback) e
## arte procedural (molduras por raridade com brilho). Sem GPU.

const VARIATIONS: Array[String] = ["ModalPanel", "HudPanel", "PanelTitle", "HeadingLabel", "TitleLabel", "DimLabel", "RuneLabel", "CloseButton", "SlotSelected", "TooltipPanel", "TooltipLabel"]


func run(ctx: Variant) -> void:
	await (ctx as SceneTree).physics_frame
	_theme(ctx)
	_contrast(ctx)
	_fonts(ctx)
	_art(ctx)


func _theme(ctx: Variant) -> void:
	var th: Theme = NorseTheme.build()
	ctx.check(th != null and th.default_font != null, "tema constroi e tem fonte padrao")
	ctx.check(th.default_font_size == NorseTheme.BODY_SIZE, "fonte padrao no tamanho do corpo (%d)" % th.default_font_size)
	var types: PackedStringArray = th.get_type_list()
	for v: String in VARIATIONS:
		ctx.check(types.has(v), "variacao de tipo '%s' existe no tema" % v)
	for r: String in NorseTheme.RARITY_IDS:
		ctx.check(types.has(String(NorseTheme.rarity_variation(r))), "variacao de slot da raridade '%s'" % r)
	ctx.check(th.has_stylebox("panel", "ModalPanel") and th.has_stylebox("normal", "Button") and th.has_stylebox("hover", "Button") and th.has_stylebox("pressed", "Button") and th.has_stylebox("focus", "Button"), "botao: normal/hover/pressed/focus + painel modal")
	ctx.check(th.has_stylebox("panel", "TooltipPanel") or th.has_stylebox("panel", "PanelContainer"), "tooltip/painel tematicos")
	ctx.check(th.has_stylebox("scroll", "VScrollBar") and th.has_stylebox("grabber", "VScrollBar"), "barra de rolagem tematica")
	ctx.check(th.has_stylebox("separator", "HSeparator") or th.has_constant("separation", "HSeparator"), "separador tematico")
	ctx.check(UiStyle.theme() == UiStyle.theme(), "UiStyle.theme() e compartilhado (cache)")
	ctx.check(UiStyle.FONT_SIZE == NorseTheme.BODY_SIZE, "UiStyle usa o tamanho do corpo do tema")


func _contrast(ctx: Variant) -> void:
	var base: Color = NorseTheme.WOOD_DARK
	ctx.check(is_equal_approx(NorseTheme.contrast(Color.WHITE, Color.BLACK), 21.0), "contraste branco/preto = 21")
	for pair: Array in [["TEXT", UiStyle.TEXT], ["TEXT_DIM", UiStyle.TEXT_DIM], ["ACCENT", UiStyle.ACCENT], ["GOOD", UiStyle.GOOD], ["BAD", UiStyle.BAD], ["INFO", UiStyle.INFO]]:
		var c: float = NorseTheme.contrast(pair[1] as Color, base)
		ctx.check(c >= 4.5, "contraste %s sobre o painel >= 4.5 (%.1f)" % [pair[0], c])
	for r: String in NorseTheme.RARITY_IDS:
		var c2: float = NorseTheme.contrast(NorseTheme.rarity_color(r), base)
		ctx.check(c2 >= 4.5, "cor da raridade '%s' legivel sobre o painel (%.1f)" % [r, c2])


func _fonts(ctx: Variant) -> void:
	var kinds: Array[String] = NorseFonts.available_kinds()
	for k: String in NorseFonts.KINDS:
		ctx.check(NorseFonts.font(k) != null, "fonte '%s' resolve (arquivo ou fallback)" % k)
	ctx.check(NorseFonts.font("inexistente") != null, "tipo de fonte desconhecido cai no fallback")
	ctx.check(kinds.has("title") and kinds.has("heading") and kinds.has("body") and kinds.has("rune"), "as 4 familias (Cinzel Decorative, Cinzel, IM Fell, Noto Sans Runic) disponiveis")
	for k2: String in ["title", "heading", "body"]:
		ctx.check(NorseFonts.missing_glyphs(k2, NorseFonts.PT_GLYPHS).is_empty(), "fonte '%s' cobre os acentos do portugues (faltam: '%s')" % [k2, NorseFonts.missing_glyphs(k2, NorseFonts.PT_GLYPHS)])
	ctx.check(NorseFonts.missing_glyphs("rune", "ᚠᚢᚦᚨᚱᚲ").is_empty(), "fonte de runas cobre o Futhark antigo")


func _art(ctx: Variant) -> void:
	var seen: Dictionary = {}
	for r: String in NorseTheme.RARITY_IDS:
		var sb: StyleBox = UiArt.slot(NorseTheme.rarity_color(r), float(NorseTheme.RARITY_GLOW.get(r, 0.0)), "normal")
		ctx.check(sb != null, "moldura de slot '%s' gerada" % r)
		seen[(sb as StyleBoxTexture).texture.get_rid().get_id() if sb is StyleBoxTexture else sb.get_instance_id()] = true
	ctx.check(seen.size() == NorseTheme.RARITY_IDS.size(), "uma moldura distinta por raridade")
	var t1: Texture2D = (UiArt.panel() as StyleBoxTexture).texture
	var t2: Texture2D = (UiArt.panel() as StyleBoxTexture).texture
	ctx.check(t1 == t2 and t1 != null, "a textura da moldura do painel e gerada uma vez (cache)")
	ctx.check(UiArt.boss() is StyleBoxTexture and UiArt.hud(0.8) is StyleBoxTexture and UiArt.minimap() is StyleBoxTexture and UiArt.tooltip() is StyleBoxTexture, "molduras procedurais: chefe, HUD, minimapa, tooltip")
	ctx.check((UiArt.boss() as StyleBoxTexture).texture != t1, "a moldura do chefe e diferente da do painel")
	ctx.check(NorseTheme.RARITY_GLOW["legendary"] > NorseTheme.RARITY_GLOW["common"], "raridade alta tem brilho")
