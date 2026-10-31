class_name TestArena
extends Node3D
## Arena de teste E1. Geometria placeholder criada em codigo (1 unidade = 1 m).
## Player e camera sao instanciados por caminho; se ausentes, push_error e a arena segue sem eles.

const PLAYER_SCENE_PATH: String = "res://scenes/player/player.tscn"
const CAMERA_SCENE_PATH: String = "res://scenes/camera/iso_camera.tscn"


# --- E2: inimigos e loop de playtest (docs/E2_ENEMIES_LOOP.md) ---
const GRUNT_SCENE_PATH: String = "res://scenes/enemy/melee_grunt.tscn"
const CASTER_SCENE_PATH: String = "res://scenes/enemy/ranged_caster.tscn"
## Pontos de spawn (longe do spawn do jogador em 0,0,0; todos a >= 18 m).
const ENEMY_SPAWNS: Array = [
	[GRUNT_SCENE_PATH, Vector3(-14.0, 0.05, -12.0)],
	[GRUNT_SCENE_PATH, Vector3(14.0, 0.05, -12.0)],
	[GRUNT_SCENE_PATH, Vector3(-20.0, 0.05, 16.0)],
	[CASTER_SCENE_PATH, Vector3(20.0, 0.05, 20.0)],
	[CASTER_SCENE_PATH, Vector3(0.0, 0.05, 24.0)],
]
const STARTING_ITEMS: Array[StringName] = [&"sword_basic", &"armor_leather"]

## Respawn de inimigos desligado por padrao.
var respawn_enabled: bool = false
var respawn_delay: float = 8.0
var hud: PlaytestHud

var _preset: int = QualitySettings.Preset.HIGH
var _environment: Environment
var _light: DirectionalLight3D
var _hud_label: Label
var _player: Node3D
var _camera_rig: Node3D


func _ready() -> void:
	_build_environment()
	ArenaGeometry.build(self, true)
	_build_hud()
	_spawn_player_and_camera()
	_setup_playtest()
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


# --- HUD --------------------------------------------------------------------

func _build_hud() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.name = "Hud"
	_hud_label = Label.new()
	_hud_label.name = "QualityLabel"
	_hud_label.position = Vector2(12, 8)
	layer.add_child(_hud_label)
	add_child(layer)


# --- E2: playtest (inimigos, HUD, reinicio) -----------------------------------

func _setup_playtest() -> void:
	if _player == null:
		return
	var loadout: PlayerLoadout = PlayerLoadout.find_for(_player)
	if loadout != null:
		for id: StringName in STARTING_ITEMS:
			loadout.inventory.add(id, 1)
	hud = PlaytestHud.new()
	hud.name = "PlaytestHud"
	add_child(hud)
	hud.setup(_player as Player)
	hud.restart_requested.connect(func() -> void: get_tree().reload_current_scene())
	for entry: Array in ENEMY_SPAWNS:
		_spawn_enemy(entry[0] as String, entry[1] as Vector3)


func _spawn_enemy(scene_path: String, pos: Vector3) -> void:
	var scene: PackedScene = _load_scene(scene_path)
	if scene == null:
		return
	var enemy: Enemy = scene.instantiate() as Enemy
	if enemy == null:
		push_error("TestArena: raiz de %s nao e Enemy." % scene_path)
		return
	enemy.position = pos
	enemy.target = _player
	add_child(enemy)
	if respawn_enabled:
		enemy.defeated.connect(func(_e: Enemy, _xp: int, _d: Array[LootDrop]) -> void:
			get_tree().create_timer(respawn_delay).timeout.connect(
				func() -> void: _spawn_enemy(scene_path, pos)))
