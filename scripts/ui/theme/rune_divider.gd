class_name RuneDivider
extends Control
## E8.4: divisor ornamental (linha dourada, losango central e pontas) usado sob os titulos dos paineis e nos menus.

var accent: Color = NorseTheme.GOLD
var dim: Color = NorseTheme.GOLD_DIM


func _init(p_accent: Color = NorseTheme.GOLD) -> void:
	accent = p_accent
	custom_minimum_size = Vector2(0, 14)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var c: Vector2 = size * 0.5
	var half: float = size.x * 0.5
	var y: float = c.y
	# linhas que esmaecem para as pontas
	var steps: int = 24
	for i: int in steps:
		var t0: float = float(i) / float(steps)
		var t1: float = float(i + 1) / float(steps)
		var a: float = 0.15 + 0.85 * (1.0 - t0)
		draw_line(Vector2(c.x - 9.0 - (half - 9.0) * t1, y), Vector2(c.x - 9.0 - (half - 9.0) * t0, y), Color(accent, a), 1.0)
		draw_line(Vector2(c.x + 9.0 + (half - 9.0) * t0, y), Vector2(c.x + 9.0 + (half - 9.0) * t1, y), Color(accent, a), 1.0)
	# segunda linha curta (efeito entalhado)
	draw_line(Vector2(c.x - 40.0, y + 3.0), Vector2(c.x - 12.0, y + 3.0), Color(dim, 0.7), 1.0)
	draw_line(Vector2(c.x + 12.0, y + 3.0), Vector2(c.x + 40.0, y + 3.0), Color(dim, 0.7), 1.0)
	# losango central + pontos
	draw_colored_polygon(PackedVector2Array([c + Vector2(-6, 0), c + Vector2(0, -6), c + Vector2(6, 0), c + Vector2(0, 6)]), NorseTheme.GOLD_BRIGHT)
	draw_colored_polygon(PackedVector2Array([c + Vector2(-3, 0), c + Vector2(0, -3), c + Vector2(3, 0), c + Vector2(0, 3)]), Color("#1a130d"))
	for sx: float in [-1.0, 1.0]:
		var p: Vector2 = c + Vector2(sx * 14.0, 0.0)
		draw_colored_polygon(PackedVector2Array([p + Vector2(-2, 0), p + Vector2(0, -2), p + Vector2(2, 0), p + Vector2(0, 2)]), accent)
