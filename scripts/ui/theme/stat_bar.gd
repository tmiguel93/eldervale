class_name StatBar
extends ProgressBar
## E8.4: barra de recurso estilizada (vida/mana/stamina/XP/chefe/aliado). E um ProgressBar (os testes/chamadores continuam usando
## `value`, `set_bar` e o filho "Text"), mas o desenho e proprio: moldura de ferro com fio dourado, gradiente com brilho, marcas, atraso
## de dano ("chip": trecho claro que desce devagar depois de perder vida) e reflexo animado que cruza a barra. Com reduce_motion o
## atraso e o reflexo ficam desligados (a barra mostra o valor direto). Headless nao anima.

enum Kind { HEALTH, MANA, STAMINA, XP, BOSS, ALLY }

## {luz, base, sombra}
const PALETTE: Dictionary = {
	Kind.HEALTH: [Color("#ee6b5f"), Color("#b3261e"), Color("#5c0f0b")],
	Kind.MANA: [Color("#78b8ff"), Color("#2b6fc7"), Color("#12325e")],
	Kind.STAMINA: [Color("#a6d878"), Color("#5b9a3c"), Color("#274a14")],
	Kind.XP: [Color("#c29cf5"), Color("#7a4ac0"), Color("#34195e")],
	Kind.BOSS: [Color("#ff9a58"), Color("#c2411b"), Color("#5b1608")],
	Kind.ALLY: [Color("#86dc98"), Color("#3f9b5a"), Color("#174a2b")],
}
const GHOST_HOLD: float = 0.35
const GHOST_SPEED: float = 0.7
const SHINE_PERIOD: float = 3.6
const SHINE_TIME: float = 0.9

var kind: int = Kind.HEALTH
var ghost: float = 1.0          ## fracao "atrasada" (so para exibir o dano recente)
var shine: float = -1.0         ## progresso do reflexo (0..1) ou -1 (parado)
var _hold: float = 0.0
var _clock: float = 0.0
var _last_ratio: float = 1.0
var text_label: Label = null


func _init(p_kind: int = Kind.HEALTH, w: float = 0.0, h: float = 0.0) -> void:
	kind = p_kind
	if w > 0.0 or h > 0.0:
		custom_minimum_size = Vector2(w, h)
	show_percentage = false
	min_value = 0.0
	max_value = 1.0
	step = 0.0
	value = 1.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("background", StyleBoxEmpty.new())
	add_theme_stylebox_override("fill", StyleBoxEmpty.new())
	text_label = Label.new()
	text_label.name = "Text"
	text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	text_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	text_label.add_theme_font_size_override("font_size", 12)
	text_label.add_theme_color_override("font_color", Color("#f6efe0"))
	text_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	text_label.add_theme_constant_override("outline_size", 3)
	add_child(text_label)
	value_changed.connect(func(_v: float) -> void: _on_value())
	set_process(false)


func ratio() -> float:
	if max_value <= min_value:
		return 0.0
	return clampf((value - min_value) / (max_value - min_value), 0.0, 1.0)


func _on_value() -> void:
	var r: float = ratio()
	if r >= _last_ratio - 0.0001 or not UiFx.motion():
		ghost = r  # cura/sem movimento: sem atraso
	else:
		_hold = GHOST_HOLD
		if ghost < _last_ratio:
			ghost = maxf(ghost, r)
		else:
			ghost = _last_ratio
	_last_ratio = r
	set_process(UiFx.motion() and is_inside_tree())
	queue_redraw()


func _enter_tree() -> void:
	set_process(UiFx.motion())


func _process(delta: float) -> void:
	if not UiFx.motion() or not is_visible_in_tree():
		return
	var r: float = ratio()
	var dirty: bool = false
	if ghost > r + 0.0001:
		if _hold > 0.0:
			_hold -= delta
		else:
			ghost = maxf(r, ghost - GHOST_SPEED * delta)
		dirty = true
	_clock += delta
	if shine >= 0.0:
		shine += delta / SHINE_TIME
		if shine > 1.0:
			shine = -1.0
		dirty = true
	elif _clock >= SHINE_PERIOD and r > 0.05:
		_clock = 0.0
		shine = 0.0
		dirty = true
	if dirty:
		queue_redraw()


func _draw() -> void:
	var pal: Array = PALETTE.get(kind, PALETTE[Kind.HEALTH])
	var light: Color = pal[0]
	var base: Color = pal[1]
	var dark: Color = pal[2]
	var r: Rect2 = Rect2(Vector2.ZERO, size)
	draw_rect(r, Color("#0a0706"))
	var inner: Rect2 = r.grow(-2.0)
	draw_rect(inner, dark.darkened(0.55))
	var frac: float = ratio()
	var fw: float = inner.size.x * frac
	# atraso de dano
	if ghost > frac + 0.001:
		var gw: float = inner.size.x * ghost
		draw_rect(Rect2(inner.position + Vector2(fw, 0.0), Vector2(gw - fw, inner.size.y)), Color("#f0d9a0", 0.85))
	if fw > 0.5:
		var fr: Rect2 = Rect2(inner.position, Vector2(fw, inner.size.y))
		var top: Color = light.lerp(base, 0.35)
		var pts: PackedVector2Array = PackedVector2Array([fr.position, fr.position + Vector2(fr.size.x, 0.0), fr.end, fr.position + Vector2(0.0, fr.size.y)])
		draw_polygon(pts, PackedColorArray([top, top, dark, dark]))
		# faixa clara superior (brilho de vidro)
		draw_rect(Rect2(fr.position, Vector2(fr.size.x, maxf(fr.size.y * 0.38, 1.0))), Color(1, 1, 1, 0.16))
		draw_rect(Rect2(fr.position, Vector2(fr.size.x, 1.0)), Color(light.lightened(0.4), 0.7))
		# marcas a cada 10%
		var tick_col: Color = Color(0, 0, 0, 0.28)
		for i: int in range(1, 10):
			var tx: float = inner.position.x + inner.size.x * float(i) / 10.0
			if tx < fr.end.x - 1.0:
				draw_line(Vector2(tx, inner.position.y + 1.0), Vector2(tx, inner.end.y - 1.0), tick_col, 1.0)
		# reflexo que cruza a barra
		if shine >= 0.0:
			var sx: float = fr.position.x - 24.0 + (fr.size.x + 48.0) * shine
			var band: float = 14.0
			var lean: float = fr.size.y
			var poly: PackedVector2Array = PackedVector2Array([Vector2(sx, fr.end.y), Vector2(sx + band, fr.end.y), Vector2(sx + band + lean * 0.5, fr.position.y), Vector2(sx + lean * 0.5, fr.position.y)])
			var clipped: Array[PackedVector2Array] = Geometry2D.intersect_polygons(poly, PackedVector2Array([fr.position, Vector2(fr.end.x, fr.position.y), fr.end, Vector2(fr.position.x, fr.end.y)]))
			for piece: PackedVector2Array in clipped:
				draw_colored_polygon(piece, Color(1, 1, 1, 0.30))
	# moldura: ferro + fio dourado
	draw_rect(r, Color("#4a4f58"), false, 1.0)
	draw_rect(r.grow(-1.0), Color("#c9a24a", 0.55), false, 1.0)
	# cantos (pequenos losangos dourados)
	for cx: float in [0.0, r.size.x]:
		var c: Vector2 = Vector2(cx, r.size.y * 0.5)
		draw_colored_polygon(PackedVector2Array([c + Vector2(-3, 0), c + Vector2(0, -3), c + Vector2(3, 0), c + Vector2(0, 3)]), Color("#e8c872"))
