class_name Player
extends CharacterBody3D
## Jogador (logica). Movimento WASD relativo a yaw da camera, gravidade, rampas e degraus.
## Apresentacao fica em PlayerVisual (no filho "Visual"), que escuta os sinais abaixo.
##
## Ordem/dependencias (documentado, AGENTS 5):
##  - A camera e obtida por `camera` (export) ou, se nulo, pelo grupo `game_camera`.
##    Ela deve ter `get_yaw() -> float` (radianos). Sem camera valida usa yaw 0 e avisa uma vez.
##  - Input Map: move_forward / move_back / move_left / move_right (WASD).

signal facing_changed(yaw: float)
signal moved(horizontal_speed: float)
signal landed

const CAMERA_GROUP: StringName = &"game_camera"
const SLOPE_EPSILON_DEG: float = 0.5

@export var camera: Node3D
@export var move_speed: float = 6.0
@export var gravity: float = 24.0
@export var turn_speed: float = 14.0
## Maior inclinacao andavel (graus). Rampas <= 30 graus.
@export var max_slope_deg: float = 30.0
## Degrau maximo subido automaticamente (m). Ver _try_step_up.
@export var step_height: float = 0.3
@export var floor_snap: float = 0.45

## Testes/automacao: ignora Input e camera e usa estes valores.
var use_external_input: bool = false
var external_input: Vector2 = Vector2.ZERO
var external_yaw: float = 0.0

## Integracao com PlayerCombat (E2): bloqueia o movimento livre e/ou impoe velocidade horizontal
## (deslocamento da esquiva). Sem PlayerCombat ficam nos valores padrao e nada muda.
var movement_locked: bool = false
var use_forced_velocity: bool = false
var forced_velocity: Vector3 = Vector3.ZERO

var facing_yaw_value: float = 0.0
var _warned_no_camera: bool = false
var _was_on_floor: bool = false


func _ready() -> void:
	floor_max_angle = deg_to_rad(max_slope_deg + SLOPE_EPSILON_DEG)
	floor_snap_length = floor_snap
	floor_stop_on_slope = true
	floor_constant_speed = true
	motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	facing_yaw_value = rotation.y
	if camera == null:
		camera = get_tree().get_first_node_in_group(CAMERA_GROUP) as Node3D


func _physics_process(delta: float) -> void:
	var direction: Vector3 = get_move_direction()
	if movement_locked:
		direction = Vector3.ZERO
	var horizontal: Vector3 = direction * move_speed
	if use_forced_velocity:
		horizontal = Vector3(forced_velocity.x, 0.0, forced_velocity.z)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if is_on_floor():
		velocity.y = minf(velocity.y, 0.0)
		if horizontal.length_squared() > 0.0001:
			_try_step_up(horizontal * delta)
	else:
		velocity.y -= gravity * delta
	move_and_slide()

	var on_floor: bool = is_on_floor()
	if on_floor and not _was_on_floor:
		landed.emit()
	_was_on_floor = on_floor

	_update_facing(direction, delta)
	moved.emit(Vector2(velocity.x, velocity.z).length())


## Direcao de movimento desejada no mundo (plano XZ), pela entrada e pela camera.
func get_move_direction() -> Vector3:
	return PlayerMotion.world_direction(_read_input(), _read_yaw())


## Direcao (unitaria, plano XZ) para onde o personagem olha.
func get_facing_direction() -> Vector3:
	return Vector3(-sin(facing_yaw_value), 0.0, -cos(facing_yaw_value))


func set_facing_yaw(yaw: float) -> void:
	facing_yaw_value = yaw
	facing_changed.emit(yaw)


## Ponto de extensao: mira por mouse (fora do escopo de E1). Sobrescrever/alterar para
## retornar a direcao do cursor no plano do chao; por ora o personagem olha para onde anda.
func _desired_facing_direction(move_direction: Vector3) -> Vector3:
	return move_direction


func _update_facing(move_direction: Vector3, delta: float) -> void:
	var wanted: Vector3 = _desired_facing_direction(move_direction)
	if wanted.length_squared() < 0.0001:
		return
	var target_yaw: float = PlayerMotion.facing_yaw(wanted, facing_yaw_value)
	facing_yaw_value = PlayerMotion.smooth_angle(facing_yaw_value, target_yaw, turn_speed, delta)
	facing_changed.emit(facing_yaw_value)


func _read_input() -> Vector2:
	if use_external_input:
		return external_input
	return Input.get_vector(&"move_left", &"move_right", &"move_back", &"move_forward")


func _read_yaw() -> float:
	if use_external_input:
		return external_yaw
	if camera == null or not is_instance_valid(camera):
		# Busca tardia: a camera pode ser adicionada a arvore depois do jogador.
		camera = get_tree().get_first_node_in_group(CAMERA_GROUP) as Node3D
	if camera != null and camera.has_method(&"get_yaw"):
		return float(camera.call(&"get_yaw"))
	if not _warned_no_camera:
		_warned_no_camera = true
		push_warning("Player: camera ausente ou sem get_yaw(); usando yaw 0.")
	return 0.0


## Degrau simples: se o proximo passo bate numa superficie "parede" (nao andavel) e nao ha
## bloqueio a `step_height` acima nem teto, eleva o corpo em step_height; o floor snap
## traz o corpo de volta ao chao logo apos o avanco. Nao trata degraus > step_height nem
## escadas altas (E1 usa rampa/degraus pequenos).
func _try_step_up(motion: Vector3) -> void:
	var probe: Vector3 = motion.normalized() * maxf(motion.length(), 0.15)
	var hit: PhysicsTestMotionResult3D = PhysicsTestMotionResult3D.new()
	var params: PhysicsTestMotionParameters3D = PhysicsTestMotionParameters3D.new()
	params.from = global_transform
	params.motion = probe
	if not PhysicsServer3D.body_test_motion(get_rid(), params, hit):
		return
	# So considera obstaculos nao andaveis (paredes/quinas), nao rampas.
	if hit.get_collision_normal().angle_to(Vector3.UP) <= floor_max_angle:
		return
	var raised: Transform3D = global_transform.translated(Vector3.UP * step_height)
	params.from = global_transform
	params.motion = Vector3.UP * step_height
	if PhysicsServer3D.body_test_motion(get_rid(), params, null):
		return  # teto
	params.from = raised
	params.motion = probe
	if PhysicsServer3D.body_test_motion(get_rid(), params, null):
		return  # obstaculo alto demais
	global_position.y += step_height
