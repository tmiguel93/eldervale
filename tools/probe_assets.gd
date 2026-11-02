extends SceneTree
## Ferramenta de desenvolvimento (E8.2): lista malhas, AABB e materiais de GLB/GLTF. Uso: godot --headless --script res://tools/probe_assets.gd -- res://a.glb res://b.gltf
func _initialize() -> void:
	for p: String in OS.get_cmdline_user_args():
		var ps: PackedScene = load(p) as PackedScene
		if ps == null:
			print(p, " NAO CARREGA")
			continue
		var n: Node = ps.instantiate()
		var parts: Array[String] = []
		_walk(n, Transform3D.IDENTITY, parts)
		print(p.get_file(), " :: ", " | ".join(parts))
		n.free()
	quit()

func _walk(n: Node, xf: Transform3D, out: Array[String]) -> void:
	var cur: Transform3D = xf
	var n3: Node3D = n as Node3D
	if n3 != null:
		cur = xf * n3.transform
	var mi: MeshInstance3D = n as MeshInstance3D
	if mi != null and mi.mesh != null:
		var bb: AABB = cur * mi.mesh.get_aabb()
		var mats: Array[String] = []
		for i in mi.mesh.get_surface_count():
			var m: Material = mi.mesh.surface_get_material(i)
			var d: String = m.get_class()
			var bm: BaseMaterial3D = m as BaseMaterial3D
			if bm != null:
				d += "[tex=%s vc=%s tr=%d cull=%d]" % [bm.albedo_texture != null, bm.vertex_color_use_as_albedo, bm.transparency, bm.cull_mode]
			mats.append(d)
		out.append("%s size=(%.2f,%.2f,%.2f) min=(%.2f,%.2f,%.2f) skin=%s %s" % [mi.name, bb.size.x, bb.size.y, bb.size.z, bb.position.x, bb.position.y, bb.position.z, mi.skin != null, ",".join(mats)])
	for c in n.get_children():
		_walk(c, cur, out)
