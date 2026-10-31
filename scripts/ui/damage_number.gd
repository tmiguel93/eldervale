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
	modulate.a = clampf(1.0 - _age / lifetime, 0.0, 1.0)
	if _age >= lifetime:
		queue_free()
