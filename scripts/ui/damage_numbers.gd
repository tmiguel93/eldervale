class_name DamageNumbers
extends Node
## Apresentacao: cria um DamageNumber (Label3D) ao receber dano. Fica como irmao da entidade
## (filho do pai da entidade) para sobreviver a ela e nao herdar sua escala/rotacao.

@export var health_path: NodePath = NodePath("../Health")
@export var height: float = 2.2
@export var color: Color = Color(1.0, 0.9, 0.3)

var spawned: int = 0

var _entity: Node3D


func _ready() -> void:
	_entity = get_parent() as Node3D
	var health: HealthComponent = get_node_or_null(health_path) as HealthComponent
	if _entity == null or health == null:
		push_error("DamageNumbers: requer pai Node3D e health_path valido.")
		return
	health.damaged.connect(_on_damaged)


func _on_damaged(info: DamageInfo, final_amount: float) -> void:
	var host: Node = _entity.get_parent()
	if host == null or not host.is_inside_tree():
		return
	var label: DamageNumber = DamageNumber.new()
	label.setup(final_amount, color.lightened(0.4) if info.is_critical else color)
	host.add_child(label)
	label.global_position = _entity.global_position + Vector3(randf_range(-0.3, 0.3), height, 0.0)
	spawned += 1
