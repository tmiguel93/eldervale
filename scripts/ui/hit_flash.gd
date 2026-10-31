class_name HitFlash
extends Node
## Apresentacao: pisca o material de um MeshInstance3D quando o HealthComponent recebe dano.
## Nao altera gameplay. Usa material_override temporario e restaura o anterior. Sem audio
## (nenhum som nesta entrega; ver docs/E2_ENEMIES_LOOP.md).

@export var health_path: NodePath = NodePath("../Health")
@export var mesh_path: NodePath = NodePath("../Visual/Body")
@export var duration: float = 0.12
@export var flash_color: Color = Color(1.0, 1.0, 1.0)

var flashing: bool = false
var flash_count: int = 0

var _mesh: MeshInstance3D
var _saved: Material
var _left: float = 0.0
var _material: StandardMaterial3D


func _ready() -> void:
	_mesh = get_node_or_null(mesh_path) as MeshInstance3D
	var health: HealthComponent = get_node_or_null(health_path) as HealthComponent
	if _mesh == null or health == null:
		push_error("HitFlash: requer health_path e mesh_path validos.")
		set_process(false)
		return
	_material = StandardMaterial3D.new()
	_material.albedo_color = flash_color
	_material.emission_enabled = true
	_material.emission = flash_color
	health.damaged.connect(func(_i: DamageInfo, _f: float) -> void: flash())


func flash() -> void:
	if _mesh == null:
		return
	if not flashing:
		_saved = _mesh.material_override
	flashing = true
	flash_count += 1
	_left = duration
	_mesh.material_override = _material


func _process(delta: float) -> void:
	if not flashing:
		return
	_left -= delta
	if _left <= 0.0:
		flashing = false
		_mesh.material_override = _saved
