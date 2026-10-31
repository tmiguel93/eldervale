class_name OcclusionFader
extends Node
## Fade de objetos que ocluem o jogador. Objetos do grupo `occluder` (MeshInstance3D ou pais
## com MeshInstance3D) cujo AABB global (+ margem) intersecta o segmento camera->jogador
## recebem transparencia via override de material de superficie (duplicata); ao liberar,
## o override original e restaurado. Alpha minimo > 0: nada some por completo.
## Obs: usa teste segmento x AABB (nao exige colisores). Chao fino nao deve ficar no grupo.

signal occluder_faded(mesh: MeshInstance3D)
signal occluder_restored(mesh: MeshInstance3D)

class FadeState:
	extends RefCounted
	var originals: Array[Material] = []
	var fades: Array[Material] = []
	var alpha: float = 1.0
	var blocked: bool = true

@export var camera: Camera3D
@export var target: Node3D
@export var occluder_group: StringName = &"occluder"
@export_range(0.05, 0.9) var faded_alpha: float = 0.25
## Alpha por segundo.
@export var fade_speed: float = 6.0
@export var check_interval: float = 0.05
@export var target_height: float = 0.9
@export var margin: float = 0.2

var _faded: Dictionary = {}  # MeshInstance3D -> FadeState
var _timer: float = 0.0


func _process(delta: float) -> void:
	_timer += delta
	if _timer >= check_interval:
		_timer = 0.0
		refresh_blocked()
	tick(delta)


func _exit_tree() -> void:
	restore_all()


## Recalcula quais malhas bloqueiam a visao agora.
func refresh_blocked() -> void:
	if camera == null or target == null or not is_instance_valid(camera) or not is_instance_valid(target):
		restore_all()
		return
	var segment: PackedVector3Array = _view_segment()
	var blockers: Dictionary = {}
	for node: Node in get_tree().get_nodes_in_group(occluder_group):
		for mesh: MeshInstance3D in _meshes_of(node):
			var box: AABB = mesh.global_transform * mesh.get_aabb()
			if box.grow(margin).intersects_segment(segment[0], segment[1]) != null:
				blockers[mesh] = true
	for mesh: MeshInstance3D in blockers:
		if not _faded.has(mesh):
			_begin_fade(mesh)
		(_faded[mesh] as FadeState).blocked = true
	for mesh: MeshInstance3D in _faded:
		if not blockers.has(mesh):
			(_faded[mesh] as FadeState).blocked = false


## Avanca os alphas; restaura malhas totalmente liberadas.
func tick(delta: float) -> void:
	var done: Array[MeshInstance3D] = []
	for mesh: MeshInstance3D in _faded:
		if not is_instance_valid(mesh):
			done.append(mesh)
			continue
		var st: FadeState = _faded[mesh]
		var goal: float = faded_alpha if st.blocked else 1.0
		st.alpha = move_toward(st.alpha, goal, fade_speed * delta)
		for m: Material in st.fades:
			var bm: BaseMaterial3D = m as BaseMaterial3D
			if bm != null:
				bm.albedo_color.a = st.alpha
		if not st.blocked and st.alpha >= 0.999:
			done.append(mesh)
	for mesh: MeshInstance3D in done:
		_restore(mesh)


func restore_all() -> void:
	for mesh: MeshInstance3D in _faded.keys():
		_restore(mesh)


func faded_count() -> int:
	return _faded.size()


func get_alpha(mesh: MeshInstance3D) -> float:
	if _faded.has(mesh):
		return (_faded[mesh] as FadeState).alpha
	return 1.0


func _view_segment() -> PackedVector3Array:
	var to: Vector3 = target.global_position + Vector3.UP * target_height
	var from: Vector3 = camera.global_position
	if camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
		var fwd: Vector3 = -camera.global_basis.z
		from = to - fwd * (to - camera.global_position).dot(fwd)
	return PackedVector3Array([from, to])


func _meshes_of(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	var self_mesh: MeshInstance3D = node as MeshInstance3D
	if self_mesh != null:
		out.append(self_mesh)
	for child: Node in node.find_children("*", "MeshInstance3D", true, false):
		out.append(child as MeshInstance3D)
	return out


func _begin_fade(mesh: MeshInstance3D) -> void:
	if mesh.mesh == null:
		return
	var st: FadeState = FadeState.new()
	for i: int in mesh.mesh.get_surface_count():
		st.originals.append(mesh.get_surface_override_material(i))
		var active: Material = mesh.get_active_material(i)
		var dup: BaseMaterial3D = null
		if active is BaseMaterial3D:
			dup = (active as BaseMaterial3D).duplicate() as BaseMaterial3D
		else:
			dup = StandardMaterial3D.new()
		dup.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		st.fades.append(dup)
		mesh.set_surface_override_material(i, dup)
	_faded[mesh] = st
	occluder_faded.emit(mesh)


func _restore(mesh: MeshInstance3D) -> void:
	var st: FadeState = _faded.get(mesh)
	_faded.erase(mesh)
	if st == null or not is_instance_valid(mesh):
		return
	for i: int in st.originals.size():
		mesh.set_surface_override_material(i, st.originals[i])
	occluder_restored.emit(mesh)
