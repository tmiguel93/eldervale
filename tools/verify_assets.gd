extends SceneTree
## Verificacao em runtime de assets (E8.0).
## Uso: godot --headless --path . -s tools/verify_assets.gd   (apos --import)
## Carrega cada modelo do ASSET_MANIFEST.json com GLTFDocument, conta meshes/animacoes e mede o AABB real.

const MANIFEST := "res://assets/ASSET_MANIFEST.json"

func _initialize() -> void:
	var f := FileAccess.open(MANIFEST, FileAccess.READ)
	if f == null:
		printerr("ERRO: manifest ausente")
		quit(1)
		return
	var man: Dictionary = JSON.parse_string(f.get_as_text())
	var ok := 0
	var fail := 0
	var rig_lines: Array[String] = []
	var total_anims := 0
	for id in man["assets"]:
		var a: Dictionary = man["assets"][id]
		var cat := String(a["category"])
		var path := String(a["path"])
		if cat == "model":
			var doc := GLTFDocument.new()
			var st := GLTFState.new()
			var err := doc.append_from_file(ProjectSettings.globalize_path("res://" + path), st)
			if err != OK:
				printerr("ERRO load ", id, " (", err, ")")
				fail += 1
				continue
			var root := doc.generate_scene(st)
			if root == null:
				printerr("ERRO scene ", id)
				fail += 1
				continue
			var aabb := _merged_aabb(root)
			var ap := _find_anim_player(root)
			var n_anim := 0
			if ap != null:
				n_anim = ap.get_animation_list().size()
			total_anims += n_anim
			if a["tags"].has("animated"):
				var sk := _count_skeletons(root)
				rig_lines.append("%s anims=%d skeletons=%d size=(%.2f, %.2f, %.2f)" % [id, n_anim, sk, aabb.size.x, aabb.size.y, aabb.size.z])
				if n_anim == 0:
					printerr("ERRO sem animacoes: ", id)
					fail += 1
					root.free()
					continue
			root.free()
			ok += 1
		else:
			var fp := ProjectSettings.globalize_path("res://" + path)
			if FileAccess.file_exists(fp):
				ok += 1
			else:
				printerr("ERRO arquivo ausente ", id)
				fail += 1
	for l in rig_lines:
		print("RIG ", l)
	print("RESULTADO: ok=%d falhas=%d animacoes_totais=%d" % [ok, fail, total_anims])
	quit(1 if fail > 0 else 0)

func _find_anim_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_anim_player(c)
		if r != null:
			return r
	return null

func _count_skeletons(n: Node) -> int:
	var c := 1 if n is Skeleton3D else 0
	for ch in n.get_children():
		c += _count_skeletons(ch)
	return c

func _merged_aabb(root: Node) -> AABB:
	var out := AABB()
	var first := true
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			var bb := mi.get_aabb()
			var xf := Transform3D.IDENTITY
			var p: Node = mi
			while p != null and p != root.get_parent():
				if p is Node3D:
					xf = (p as Node3D).transform * xf
				p = p.get_parent()
			var tb := xf * bb
			if first:
				out = tb
				first = false
			else:
				out = out.merge(tb)
		for c in n.get_children():
			stack.append(c)
	return out
