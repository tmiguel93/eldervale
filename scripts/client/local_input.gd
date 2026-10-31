class_name LocalInput
extends RefCounted
## Captura do Input Map e montagem do payload de c_input. Contem o contador de seq.
## Convencao (ver docs/E3_CLIENT.md): `move` = entrada local (x direita, y frente) e `yaw` = base
## de rotacao do movimento (yaw da camera isometrica), de modo que o servidor aplique
## PlayerMotion.world_direction(move, yaw). Normalizado para [-PI, PI].

const ACTION_ATTACK: int = 1
const ACTION_SKILL_1: int = 2
const ACTION_SKILL_2: int = 4
const ACTION_DODGE: int = 8
const SEND_HZ: float = 30.0

var seq: int = 0
var yaw: float = 0.0


func next_seq() -> int:
	seq += 1
	return seq


static func normalize_yaw(y: float) -> float:
	if not is_finite(y):
		return 0.0
	return wrapf(y, -PI, PI)


## Le o Input Map. Funciona sem display (retorna zeros).
static func read_move() -> Vector2:
	var m: Vector2 = Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_forward") - Input.get_action_strength("move_back"))
	return m.limit_length(1.0)


static func read_actions() -> int:
	var a: int = 0
	if Input.is_action_pressed("attack"):
		a |= ACTION_ATTACK
	if Input.is_action_pressed("skill_1"):
		a |= ACTION_SKILL_1
	if Input.is_action_pressed("skill_2"):
		a |= ACTION_SKILL_2
	if Input.is_action_pressed("dodge"):
		a |= ACTION_DODGE
	return a
