class_name DeathEffect
extends Node
## Apresentacao: efeito simples de morte. Encolhe o `Visual` da entidade e solta fragmentos
## (cubos pequenos) que se afastam e somem. Sem audio. Fragmentos sao filhos do pai da entidade.

@export var visual_path: NodePath = NodePath("../Visual")
@export var duration: float = 0.5
@export var shard_count: int = 6
@export var shard_color: Color = Color(0.9, 0.3, 0.2)

var playing: bool = false

var _visual: Node3D
var _t: float = 0.0
var _shards: Array[MeshInstance3D] = []
var _velocities: Array[Vector3] = []


func _ready() -> void:
	set_process(false)
	_visual = get_node_or_null(visual_path) as Node3D


func play() -> void:
	if playing or _visual == null:
		return
	playing = true
	var host: Node = get_parent().get_parent()
	var origin: Vector3 = (get_parent() as Node3D).global_position + Vector3(0.0, 0.9, 0.0)
	if host != null:
		for i: int in shard_count:
			var s: MeshInstance3D = MeshInstance3D.new()
			var m: BoxMesh = BoxMesh.new()
			m.size = Vector3(0.15, 0.15, 0.15)
			var mat: StandardMaterial3D = StandardMaterial3D.new()
			mat.albedo_color = shard_color
			m.material = mat
			s.mesh = m
			host.add_child(s)
			s.global_position = origin
			var ang: float = TAU * float(i) / float(maxi(shard_count, 1))
			_shards.append(s)
			_velocities.append(Vector3(cos(ang) * 2.5, 2.5, sin(ang) * 2.5))
	set_process(true)


func _process(delta: float) -> void:
	_t += delta
	var k: float = clampf(_t / duration, 0.0, 1.0)
	_visual.scale = Vector3.ONE * maxf(1.0 - k, 0.01)
	for i: int in _shards.size():
		var s: MeshInstance3D = _shards[i]
		if is_instance_valid(s):
			_velocities[i].y -= 9.0 * delta
			s.global_position += _velocities[i] * delta
			s.scale = Vector3.ONE * maxf(1.0 - k, 0.01)
	if k >= 1.0:
		for s: MeshInstance3D in _shards:
			if is_instance_valid(s):
				s.queue_free()
		_shards.clear()
		set_process(false)
