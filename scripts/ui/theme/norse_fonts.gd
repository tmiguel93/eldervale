class_name NorseFonts
extends RefCounted
## E8.4: fontes do tema (Google Fonts, OFL; docs/E8_ASSETS.md). Titulo = Cinzel Decorative Bold, cabecalho = Cinzel, corpo = IM Fell Double Pica,
## runas = Noto Sans Runic. Cada fonte e uma FontVariation com cadeia de fallback (runas -> fonte padrao do motor) para que acentos do
## portugues e simbolos que faltem na fonte principal nunca virem quadrados. Arquivo ausente => cai na fonte padrao do motor.

const DIR: String = "res://assets/third_party/google_fonts/"
const PATHS: Dictionary = {
	"title": DIR + "cinzeldecorative/CinzelDecorative-Bold.ttf",
	"heading": DIR + "cinzel/Cinzel-Variable.ttf",
	"body": DIR + "imfelldoublepica/IMFELLDoublePica-Regular.ttf",
	"rune": DIR + "notosansrunic/NotoSansRunic-Regular.ttf",
}
const KINDS: Array[String] = ["title", "heading", "body", "rune"]
## Texto de teste do portugues (cobertura de glifos).
const PT_GLYPHS: String = "áàâãäéêíóôõúüçÁÀÂÃÉÊÍÓÔÕÚÇ«»–—…"

static var _cache: Dictionary = {}


static func _load(path: String) -> FontFile:
	if not ResourceLoader.exists(path):
		return null
	return load(path) as FontFile


static func fallback_font() -> Font:
	return ThemeDB.fallback_font


## Fonte do tipo ("title", "heading", "body", "rune"); nunca nula.
static func font(kind: String) -> Font:
	if _cache.has(kind):
		return _cache[kind] as Font
	var base: FontFile = _load(String(PATHS.get(kind, PATHS["body"])))
	var fv: FontVariation = FontVariation.new()
	if base != null:
		fv.base_font = base
	else:
		fv.base_font = fallback_font()
	var fbs: Array[Font] = []
	if kind != "rune":
		var rune: FontFile = _load(String(PATHS["rune"]))
		if rune != null:
			fbs.append(rune)
	if fallback_font() != null:
		fbs.append(fallback_font())
	fv.fallbacks = fbs
	if kind == "heading" and base != null:
		var tag: int = TextServerManager.get_primary_interface().name_to_tag("weight") if TextServerManager.get_primary_interface() != null else 0
		if tag != 0:
			fv.variation_opentype = {tag: 600}
	_cache[kind] = fv
	return fv


## Fontes de arquivo presentes (para testes/diagnostico).
static func available_kinds() -> Array[String]:
	var out: Array[String] = []
	for k: String in KINDS:
		if ResourceLoader.exists(String(PATHS[k])):
			out.append(k)
	return out


## Glifos de `text` que NEM a fonte principal NEM a cadeia de fallback cobrem.
static func missing_glyphs(kind: String, text: String) -> String:
	var f: Font = font(kind)
	var missing: String = ""
	for i: int in text.length():
		var cp: int = text.unicode_at(i)
		if cp <= 32:
			continue
		if not f.has_char(cp):
			var covered: bool = false
			for fb: Font in (f as FontVariation).fallbacks:
				if fb.has_char(cp):
					covered = true
					break
			if not covered:
				missing += text[i]
	return missing


static func clear_cache() -> void:
	_cache.clear()
