class_name TestArena
extends Node3D
## Arena de teste E1. Geometria placeholder criada em codigo (1 unidade = 1 m).
## Player e camera sao instanciados por caminho; se ausentes, push_error e a arena segue sem eles.

const PLAYER_SCENE_PATH: String = "res://scenes/player/player.tscn"
const CAMERA_SCENE_PATH: String = "res://scenes/camera/iso_camera.tscn"
const OCCLUDER_GROUP: StringName = &"occluder"

const FLOOR_SIZE: float = 60.0
const RAMP_ANGLE_DEG: float = 20.0  # <= 30
const RAMP_LENGTH: float = 8.0
const RAMP_WIDTH: float = 4.0
const STAIR_STEPS: int = 10
const STAIR_RISE: float = 0.2
const STAIR_DEPTH: float = 0.4
const STAIR_WIDTH: float = 3.0
const CORRIDOR_WIDTH: float = 2.5
const CORRIDOR_LENGTH: float = 14.0
const WALL_HEIGHT: float = 4.0

var _preset: int = QualitySettings.Preset.HIGH
var _environment: Environment
var _light: DirectionalLight3D
var _hud_label: Label
var _player: Node3D
var _camera_rig: Node3D


func _ready() -> void:
	_build_environment()
	_build_geometry()
	_build_hud()
	_spawn_player_and_camera()
	_apply_quality()


func _unhandled_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_F2:
		_preset = QualitySettings.next_preset(_preset)
		_apply_quality()


func _apply_quality() -> void:
	QualitySettings.apply(_preset, get_viewport(), _environment, _light)
	if _hud_label != null:
		_hud_label.text = "Qualidade: %s  (F2 alterna)" % QualitySettings.preset_name(_preset)


func _spawn_player_and_camera() -> void:
	var player_scene: PackedScene = _load_scene(PLAYER_SCENE_PATH)
	var camera_scene: PackedScene = _load_scene(CAMERA_SCENE_PATH)
	if player_scene != null:
		_player = player_scene.instantiate() as Node3D
		if _player == null:
			push_error("TestArena: raiz de player.tscn nao e Node3D.")
		else:
			add_child(_player)
			_player.global_position = Vector3(0.0, 0.0, 0.0)
	if camera_scene != null:
		_camera_rig = camera_scene.instantiate() as Node3D
		if _camera_rig == null:
			push_error("TestArena: raiz de iso_camera.tscn nao e Node3D.")
		else:
			add_child(_camera_rig)
	if _player != null and _camera_rig != null:
		if _camera_rig.has_method("set_target"):
			_camera_rig.call("set_target", _player)
		else:
			push_error("TestArena: iso_camera nao possui set_target(Node3D).")
		_setup_occlusion_fader()


func _setup_occlusion_fader() -> void:
	var camera: Camera3D = null
	if _camera_rig.has_method("get_camera"):
		camera = _camera_rig.call("get_camera") as Camera3D
	if camera == null:
		push_error("TestArena: camera 3D indisponivel para o OcclusionFader.")
		return
	var fader: OcclusionFader = OcclusionFader.new()
	fader.name = "OcclusionFader"
	fader.camera = camera
	fader.target = _player
	add_child(fader)


func _load_scene(path: String) -> PackedScene:
	if not ResourceLoader.exists(path):
		push_error("TestArena: cena ausente: %s" % path)
		return null
	var scene: PackedScene = load(path) as PackedScene
	if scene == null:
		push_error("TestArena: falha ao carregar %s" % path)
	return scene


# --- Ambiente e luz ---------------------------------------------------------

func _build_environment() -> void:
	_environment = Environment.new()
	_environment.background_mode = Environment.BG_COLOR
	_environment.background_color = Color(0.12, 0.14, 0.18)
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_environment.ambient_light_color = Color(0.55, 0.6, 0.7)
	_environment.ambient_light_energy = 0.6
	_environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_environment.ssao_enabled = true
	_environment.ssao_intensity = 1.5
	_environment.ssao_radius = 1.0
	_environment.glow_enabled = true
	_environment.glow_intensity = 0.4
	_environment.glow_bloom = 0.05
	var world_env: WorldEnvironment = WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = _environment
	add_child(world_env)

	_light = DirectionalLight3D.new()
	_light.name = "Sun"
	_light.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
	_light.light_energy = 1.1
	_light.shadow_enabled = true
	_light.directional_shadow_max_distance = 60.0
	add_child(_light)


# --- Geometria --------------------------------------------------------------

func _build_geometry() -> void:
	var root: Node3D = Node3D.new()
	root.name = "Geometry"
	add_child(root)

	var grey: Color = Color(0.45, 0.47, 0.5)
	var wall_col: Color = Color(0.55, 0.5, 0.45)
	var accent: Color = Color(0.8, 0.5, 0.2)
	var step_col: Color = Color(0.3, 0.55, 0.7)

	# Piso: topo em y=0.
	_add_box(root, "Floor", Vector3(FLOOR_SIZE, 1.0, FLOOR_SIZE), Vector3(0, -0.5, 0), Color(0.32, 0.36, 0.32), false)

	# Muralha externa (occluder).
	var half: float = FLOOR_SIZE * 0.5
	var wy: float = WALL_HEIGHT * 0.5
	_add_box(root, "WallN", Vector3(FLOOR_SIZE, WALL_HEIGHT, 1.0), Vector3(0, wy, -half + 0.5), wall_col, true)
	_add_box(root, "WallS", Vector3(FLOOR_SIZE, WALL_HEIGHT, 1.0), Vector3(0, wy, half - 0.5), wall_col, true)
	_add_box(root, "WallE", Vector3(1.0, WALL_HEIGHT, FLOOR_SIZE), Vector3(half - 0.5, wy, 0), wall_col, true)
	_add_box(root, "WallW", Vector3(1.0, WALL_HEIGHT, FLOOR_SIZE), Vector3(-half + 0.5, wy, 0), wall_col, true)

	# Area aberta central (x,z em -10..10): caixas baixas e pilares altos (occluder).
	_add_box(root, "Crate1", Vector3(1.5, 1.0, 1.5), Vector3(5, 0.5, 4), grey, false)
	_add_box(root, "Crate2", Vector3(2.0, 1.5, 1.0), Vector3(-5, 0.75, 3), grey, false)
	_add_box(root, "Crate3", Vector3(1.0, 1.0, 1.0), Vector3(3, 0.5, -4), grey, false)
	_add_box(root, "Pillar1", Vector3(1.0, 6.0, 1.0), Vector3(-4, 3.0, -4), wall_col, true)
	_add_box(root, "Pillar2", Vector3(1.0, 6.0, 1.0), Vector3(6, 3.0, -2), wall_col, true)
	_add_box(root, "Pillar3", Vector3(1.0, 6.0, 1.0), Vector3(2, 3.0, 7), wall_col, true)
	_add_box(root, "Pillar4", Vector3(1.2, 6.0, 1.2), Vector3(-7, 3.0, 8), wall_col, true)

	# Corredor estreito ao norte (z de -12 a -26), abre para x=0.
	var cz: float = -12.0 - CORRIDOR_LENGTH * 0.5
	var cx: float = CORRIDOR_WIDTH * 0.5 + 0.25
	_add_box(root, "CorridorWallL", Vector3(0.5, WALL_HEIGHT, CORRIDOR_LENGTH), Vector3(-cx, wy, cz), wall_col, true)
	_add_box(root, "CorridorWallR", Vector3(0.5, WALL_HEIGHT, CORRIDOR_LENGTH), Vector3(cx, wy, cz), wall_col, true)

	# Rampa a leste: sobe em +x, depois plataforma.
	var ang: float = deg_to_rad(RAMP_ANGLE_DEG)
	var rise: float = RAMP_LENGTH * sin(ang)
	var ramp_thick: float = 0.4
	var ramp_cx: float = 14.0
	var ramp_pos: Vector3 = Vector3(
		ramp_cx + (ramp_thick * 0.5) * sin(ang),
		rise * 0.5 - (ramp_thick * 0.5) * cos(ang),
		8.0)
	_add_box(root, "Ramp", Vector3(RAMP_LENGTH, ramp_thick, RAMP_WIDTH), ramp_pos, accent, false, Vector3(0, 0, RAMP_ANGLE_DEG))
	var plat_x0: float = ramp_cx + RAMP_LENGTH * 0.5 * cos(ang)
	_add_box(root, "RampPlatform", Vector3(4.0, rise, RAMP_WIDTH), Vector3(plat_x0 + 2.0, rise * 0.5, 8.0), grey, false)

	# Escada de teste a oeste: degraus de 0.2 m subindo em +z, depois plataforma.
	for i: int in range(STAIR_STEPS):
		var h: float = (i + 1) * STAIR_RISE
		_add_box(root, "Step%d" % i, Vector3(STAIR_WIDTH, h, STAIR_DEPTH),
			Vector3(-16.0, h * 0.5, 4.0 + i * STAIR_DEPTH + STAIR_DEPTH * 0.5), step_col, false)
	var top_h: float = STAIR_STEPS * STAIR_RISE
	_add_box(root, "StairPlatform", Vector3(STAIR_WIDTH, top_h, 4.0),
		Vector3(-16.0, top_h * 0.5, 4.0 + STAIR_STEPS * STAIR_DEPTH + 2.0), grey, false)


func _add_box(parent: Node3D, node_name: String, size: Vector3, pos: Vector3, color: Color,
		occluder: bool, rot_deg: Vector3 = Vector3.ZERO) -> StaticBody3D:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = node_name
	body.position = pos
	body.rotation_degrees = rot_deg
	var mesh_inst: MeshInstance3D = MeshInstance3D.new()
	mesh_inst.name = "Mesh"
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	var mat: StandardMaterial3D = StandardMaterial3D.new()  # placeholder
	mat.albedo_color = color
	mat.roughness = 0.9
	mesh.material = mat
	mesh_inst.mesh = mesh
	body.add_child(mesh_inst)
	var col: CollisionShape3D = CollisionShape3D.new()
	col.name = "Collision"
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	if occluder:
		body.add_to_group(OCCLUDER_GROUP)
	parent.add_child(body)
	return body


# --- HUD --------------------------------------------------------------------

func _build_hud() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.name = "Hud"
	_hud_label = Label.new()
	_hud_label.name = "QualityLabel"
	_hud_label.position = Vector2(12, 8)
	layer.add_child(_hud_label)
	add_child(layer)
