class_name RuneSpinner
extends Control
## E8.4: anel de runas girando (loading/conexao/troca de zona). Com reduce_motion (ou headless) o anel fica parado e so pulsa o brilho
## do centro de forma suave (sem rotacao). Nao captura mouse.

const RUNES: String = "ᚠᚢᚦᚨᚱᚲᚷᚹᚺᚾᛁᛃᛇᛈᛉᛊᛏᛒᛖᛗᛚᛜᛞᛟ"

var angle: float = 0.0
var count: int = 12
var tint: Color = NorseTheme.GOLD
var _phase: float = 0.0


func _init(px: float = 96.0) -> void:
	custom_minimum_size = Vector2(px, px)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED or what == NOTIFICATION_ENTER_TREE:
		set_process(is_visible_in_tree() and UiFx.available())


func _process(delta: float) -> void:
	_phase += delta
	if UiFx.motion():
		angle = fposmod(angle + delta * 0.9, TAU)
	queue_redraw()


func _draw() -> void:
	var c: Vector2 = size * 0.5
	var r: float = minf(size.x, size.y) * 0.5 - 8.0
	var pulse: float = 0.75 + 0.25 * sin(_phase * 3.0)
	draw_arc(c, r + 6.0, 0.0, TAU, 48, Color(tint, 0.35), 1.5)
	draw_arc(c, r - 12.0, 0.0, TAU, 48, Color(tint, 0.25), 1.0)
	var font: Font = NorseFonts.font("rune")
	var fs: int = int(maxf(r * 0.34, 12.0))
	for i: int in count:
		var a: float = angle + TAU * float(i) / float(count)
		var p: Vector2 = c + Vector2(cos(a), sin(a)) * r
		draw_set_transform(p, a + PI * 0.5, Vector2.ONE)
		var glyph: String = RUNES[(i * 2) % RUNES.length()]
		var w: float = font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, Vector2(-w * 0.5, fs * 0.35), glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(tint, 0.55 + 0.45 * pulse if i % 3 == 0 else 0.55))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var tex: Texture2D = UiIcons.texture(UiIcons.ref("ui", "loading_rune"))
	if tex != null:
		var s: float = r * 0.9
		draw_texture_rect(tex, Rect2(c - Vector2(s, s) * 0.5, Vector2(s, s)), false, Color(NorseTheme.GOLD_BRIGHT, 0.6 + 0.4 * pulse))
