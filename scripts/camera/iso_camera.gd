class_name IsoCamera
extends Node3D
## Rig de camera isometrica/top-down. Yaw fixo no MVP (get_yaw), inclinacao fixa.
## F3 alterna ortografica <-> perspectiva de baixa distorcao (comparacao do E1).
## Estrutura: este no (yaw + posicao do alvo) > Camera3D (inclinada, recuada).

signal projection_changed(is_orthogonal: bool)

const GROUP: StringName = &"game_camera"

# Parametros por modo (constantes: ponto unico de ajuste).
const ORTHO_SIZE: float = 14.0      # altura visivel em metros
const ORTHO_DISTANCE: float = 30.0
const PERSP_FOV_DEG: float = 28.0   # baixa distorcao
const PERSP_DISTANCE: float = 28.0  # ~mesma area visivel no alvo que ORTHO_SIZE
const NEAR: float = 0.1
const FAR: float = 120.0

@export var target: Node3D
@export var yaw_deg: float = 45.0
@export var pitch_deg: float = 50.0
@export var follow_speed: float = 8.0
@export var start_orthogonal: bool = true
@export var target_height: float = 0.9
## Zoom pelo scroll do mouse: multiplicador de enquadramento (menor = mais perto).
const ZOOM_MIN: float = 0.5
const ZOOM_MAX: float = 1.8
const ZOOM_STEP: float = 0.1
const ZOOM_SMOOTH: float = 12.0
var zoom: float = 1.0
var _zoom_target: float = 1.0


## Passo de zoom puro (testavel): direction -1 = aproxima, +1 = afasta; resultado dentro de [ZOOM_MIN, ZOOM_MAX].
static func step_zoom(current: float, direction: int) -> float:
	return clampf(current * (1.0 + ZOOM_STEP * float(direction)), ZOOM_MIN, ZOOM_MAX)

var is_orthogonal: bool = true

@onready var _camera: Camera3D = get_node_or_null("Camera3D") as Camera3D


func _ready() -> void:
	if _camera == null:
		push_error("IsoCamera: no filho 'Camera3D' nao encontrado.")
		set_process(false)
		set_process_unhandled_key_input(false)
		return
	add_to_group(GROUP)
	rotation = Vector3(0.0, deg_to_rad(yaw_deg), 0.0)
	_apply_projection(start_orthogonal)
	if target != null:
		global_position = _target_point()


func get_yaw() -> float:
	return rotation.y


func get_camera() -> Camera3D:
	return _camera


func set_target(n: Node3D) -> void:
	target = n
	if target != null and is_inside_tree():
		global_position = _target_point()


func toggle_projection() -> void:
	_apply_projection(not is_orthogonal)


func _process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	var weight: float = 1.0 - exp(-follow_speed * delta)
	if not is_equal_approx(zoom, _zoom_target):
		zoom = lerpf(zoom, _zoom_target, 1.0 - exp(-ZOOM_SMOOTH * delta))
		_apply_projection(is_orthogonal)
	global_position = global_position.lerp(_target_point(), weight)


func _unhandled_input(event: InputEvent) -> void:
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb != null and mb.pressed:
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_target = step_zoom(_zoom_target, -1)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_target = step_zoom(_zoom_target, 1)


func _unhandled_key_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_F3:
		toggle_projection()


func _target_point() -> Vector3:
	return target.global_position + Vector3.UP * target_height


func _apply_projection(orthogonal: bool) -> void:
	is_orthogonal = orthogonal
	var pitch: float = deg_to_rad(pitch_deg)
	var distance: float = (ORTHO_DISTANCE if orthogonal else PERSP_DISTANCE * zoom)
	_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	_camera.near = NEAR
	_camera.far = FAR
	if orthogonal:
		_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		_camera.size = ORTHO_SIZE * zoom
	else:
		_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		_camera.fov = PERSP_FOV_DEG
	_camera.position = Vector3(0.0, sin(pitch) * distance, cos(pitch) * distance)
	_camera.rotation = Vector3(-pitch, 0.0, 0.0)
	projection_changed.emit(orthogonal)
