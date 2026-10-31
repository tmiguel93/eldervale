extends RefCounted
## OcclusionFader: faz fade do occluder no caminho e restaura ao liberar. Sem fisica.


func run(ctx: Object) -> void:
	var tree: SceneTree = ctx as SceneTree
	var root: Node3D = Node3D.new()
	tree.root.add_child(root)

	var cam: Camera3D = Camera3D.new()
	root.add_child(cam)
	cam.global_position = Vector3(0, 3, 6)
	var target: Node3D = Node3D.new()
	root.add_child(target)
	target.global_position = Vector3.ZERO

	var wall: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(2, 2, 0.5)
	wall.mesh = box
	var original: StandardMaterial3D = StandardMaterial3D.new()
	original.albedo_color = Color(0.5, 0.4, 0.3, 1.0)
	wall.set_surface_override_material(0, original)
	wall.add_to_group(&"occluder")
	root.add_child(wall)
	wall.global_position = Vector3(0, 1, 2)

	var fader: OcclusionFader = OcclusionFader.new()
	fader.camera = cam
	fader.target = target
	root.add_child(fader)

	fader.refresh_blocked()
	for i: int in 60:
		fader.tick(1.0 / 60.0)
	var mat: BaseMaterial3D = wall.get_surface_override_material(0) as BaseMaterial3D
	ctx.check(fader.faded_count() == 1, "occluder no caminho entra em fade")
	ctx.check(mat != null and mat != original, "material de override e uma duplicata")
	ctx.check(fader.get_alpha(wall) <= fader.faded_alpha + 0.001, "alpha chegou ao alvo (%.2f)" % fader.get_alpha(wall))
	ctx.check(fader.get_alpha(wall) > 0.0, "jogador/objeto nunca fica com alpha 0")
	ctx.check(original.albedo_color.a == 1.0, "material original nao foi alterado")

	# Libera: jogador sai do caminho.
	target.global_position = Vector3(20, 0, 0)
	fader.refresh_blocked()
	for i: int in 120:
		fader.tick(1.0 / 60.0)
	ctx.check(fader.faded_count() == 0, "fade removido ao liberar")
	ctx.check(wall.get_surface_override_material(0) == original, "override original restaurado")

	# Volta a bloquear e destroi o fader: deve restaurar.
	target.global_position = Vector3.ZERO
	fader.refresh_blocked()
	fader.tick(0.1)
	ctx.check(fader.faded_count() == 1, "volta a fazer fade")
	root.remove_child(fader)
	ctx.check(wall.get_surface_override_material(0) == original, "sair da arvore restaura tudo")
	fader.free()
	root.queue_free()
