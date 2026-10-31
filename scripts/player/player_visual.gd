class_name PlayerVisual
extends Node3D
## Apresentacao do jogador: aplica o yaw de facing emitido pela logica (Player).
## Nenhuma regra de gameplay aqui.


func _ready() -> void:
	var player: Player = get_parent() as Player
	if player == null:
		push_error("PlayerVisual: o pai deve ser um Player.")
		return
	player.facing_changed.connect(_on_facing_changed)


func _on_facing_changed(yaw: float) -> void:
	rotation.y = yaw
