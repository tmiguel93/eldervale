class_name DamageNumber
extends Label3D
## Numero de dano flutuante: sobe e some em `lifetime` s e se libera. Apresentacao pura.

var lifetime: float = 0.9
var rise_speed: float = 1.6
var _age: float = 0.0


func setup(amount: float, color: Color) -> void:
	text = str(int(roundf(amount)))
	modulate = color
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	no_depth_test = true
	fixed_size = false
	pixel_size = 0.012
	font_size = 48
	outline_size = 10


func _process(delta: float) -> void:
	_age += delta
	global_position.y += rise_speed * delta
	if not _style.is_empty():
		global_position.x += _drift * delta
		if _pop_left > 0.0:
			_pop_left -= delta
			pixel_size = _base_pixel * lerpf(1.0, float(_style["pop"]), clampf(_pop_left / 0.14, 0.0, 1.0))
	modulate.a = clampf(1.0 - _age / lifetime, 0.0, 1.0)
	if _age >= lifetime:
		queue_free()


## E8.3: numero estilizado. style: "hit" (amarelo), "crit" (dourado, maior, com "!"), "taken" (vermelho, dano no jogador), "heal" (verde, "+").
## Anima: surge grande (pop), sobe com leve deriva lateral e some. `lifetime` maior para critico/cura.
const STYLES: Dictionary = {
	"hit": {"color": Color(1.0, 0.92, 0.35), "size": 48, "outline": Color(0.25, 0.12, 0.0, 0.95), "life": 0.9, "prefix": "", "suffix": "", "pop": 1.35},
	"crit": {"color": Color(1.0, 0.68, 0.12), "size": 72, "outline": Color(0.45, 0.1, 0.0, 1.0), "life": 1.15, "prefix": "", "suffix": "!", "pop": 1.9},
	"taken": {"color": Color(1.0, 0.38, 0.32), "size": 52, "outline": Color(0.25, 0.0, 0.0, 0.95), "life": 1.0, "prefix": "-", "suffix": "", "pop": 1.3},
	"heal": {"color": Color(0.55, 1.0, 0.55), "size": 56, "outline": Color(0.0, 0.25, 0.05, 0.95), "life": 1.2, "prefix": "+", "suffix": "", "pop": 1.4},
}
var _style: Dictionary = {}
var _drift: float = 0.0
var _pop_left: float = 0.0
var _base_pixel: float = 0.012


func setup_styled(amount: float, style: String) -> void:
	_style = STYLES.get(style, STYLES["hit"]) as Dictionary
	text = "%s%d%s" % [_style["prefix"], int(roundf(amount)), _style["suffix"]]
	modulate = _style["color"] as Color
	outline_modulate = _style["outline"] as Color
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	no_depth_test = true
	fixed_size = false
	pixel_size = _base_pixel
	font_size = int(_style["size"])
	outline_size = 14
	lifetime = float(_style["life"])
	rise_speed = 1.3 if style == "crit" else 1.6
	_drift = randf_range(-0.5, 0.5)
	_pop_left = 0.14
	pixel_size = _base_pixel * float(_style["pop"])
