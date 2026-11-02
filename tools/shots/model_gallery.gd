extends SceneTree
## Ferramenta de desenvolvimento (E8.1; nao faz parte do jogo): monta todos os visuais de dados (10 inimigos, 3 classes,
## 6 NPCs) lado a lado com ModelRig e salva um print por estado visual. Sem servidor.
## Uso: SHOT_DIR=<pasta> xvfb-run godot --path . --script res://tools/shots/model_gallery.gd -- [--states idle,move,attack,hit,death,spawn] [--only enemy,class,npc]
const H = preload("res://tests/e8_models/e8_helpers.gd")
const COLS: int = 5
const SPACING: float = 4.4

var out_dir: String = ""
var states: PackedStringArray = PackedStringArray(["idle", "move", "attack", "hit", "death", "spawn"])
var matrix: PackedStringArray = PackedStringArray()
var only: PackedStringArray = PackedStringArray(["enemy", "class", "npc"])
var stage: Node3D
var cam: Camera3D

func _initialize() -> void:
	out_dir = OS.get_environment("SHOT_DIR")
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var i: int = args.find("--states")
	if i >= 0 and i + 1 < args.size():
		states = args[i + 1].split(",")
	i = args.find("--matrix")
	if i >= 0 and i + 1 < args.size():
		matrix = args[i + 1].split(",")
	i = args.find("--only")
	if i >= 0 and i + 1 < args.size():
		only = args[i + 1].split(",")
	_run.call_deferred()

func _wait(sec: float) -> void:
	var t: int = Time.get_ticks_msec() + int(sec * 1000.0)
	while Time.get_ticks_msec() < t:
		await process_frame

func _build_stage(entries: Array) -> void:
	if stage != null:
		stage.queue_free()
	stage = Node3D.new()
	root.add_child(stage)
	var ground: MeshInstance3D = MeshInstance3D.new()
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(60, 40)
	var gm: StandardMaterial3D = StandardMaterial3D.new()
	gm.albedo_color = Color(0.3, 0.36, 0.28)
	plane.material = gm
	ground.mesh = plane
	stage.add_child(ground)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, 30.0, 0.0)
	stage.add_child(sun)
	var rows: int = int(ceil(float(entries.size()) / COLS))
	for n: int in entries.size():
		var e: Array = entries[n]
		var spec: VisualSpec = e[1] as VisualSpec
		var rig: ModelRig = ModelRig.build(spec)
		var holder: Node3D = Node3D.new()
		holder.name = String(e[0]).replace(":", "_")
		var cols: int = mini(COLS, entries.size())
		holder.position = Vector3((n % COLS - (cols - 1) * 0.5) * SPACING, 0.0, (n / COLS - (rows - 1) * 0.5) * SPACING * 1.25)
		holder.rotation.y = PI # frente (-Z local) para +Z = camera
		stage.add_child(holder)
		var tag: Label3D = Label3D.new()
		tag.text = "%s  %.1fm" % [e[0], spec.height]
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.pixel_size = 0.009
		tag.position = Vector3(0, 0.05, 0)
		tag.no_depth_test = true
		tag.font_size = 40
		var tag_holder: Node3D = Node3D.new()
		stage.add_child(tag_holder)
		tag_holder.position = holder.position + Vector3(0, 0, 1.6)
		tag_holder.add_child(tag)
		if rig == null:
			print("[gallery] FALHOU ", e[0])
			continue
		holder.add_child(rig)
		rig.set_meta("label", e[0])
	if cam == null:
		cam = Camera3D.new()
		root.add_child(cam)
	cam.fov = 38.0
	var span: float = maxf(COLS * SPACING, rows * SPACING * 1.5)
	cam.position = Vector3(0, 6.0 + rows * 3.5, 9.0 + rows * 4.5 + span * 0.25)
	cam.look_at(Vector3(0, 1.5, 0.0))
	cam.current = true

func _shot(name: String) -> void:
	await _wait(0.1)
	var img: Image = root.get_texture().get_image()
	img.save_png(out_dir + "/" + name + ".png")
	print("[gallery] shot ", name)

## Matriz: uma linha por visual (ids "enemy:x,class:y"), uma coluna por estado, tudo numa unica imagem.
func _run_matrix(all: Array) -> void:
	var entries: Array = []
	for e: Array in all:
		if matrix.has(String(e[0])):
			entries.append(e)
	var cols: int = states.size()
	_build_stage([])
	var rows: int = entries.size()
	var sp: float = 2.6
	var maxh: float = 0.0
	for r: int in rows:
		maxh = maxf(maxh, (entries[r][1] as VisualSpec).height)
	sp = maxf(sp, maxh * 0.7)
	for r: int in rows:
		for c: int in cols:
			var spec: VisualSpec = entries[r][1] as VisualSpec
			var rig: ModelRig = ModelRig.build(spec)
			var holder: Node3D = Node3D.new()
			holder.position = Vector3((c - (cols - 1) * 0.5) * sp, 0.0, (r - (rows - 1) * 0.5) * sp * 1.5)
			holder.rotation.y = PI * 0.8 # 3/4 para ver o perfil do corpo
			stage.add_child(holder)
			holder.add_child(rig)
			var tag: Label3D = Label3D.new()
			tag.text = "%s / %s" % [String(entries[r][0]).get_slice(":", 1), states[c]]
			tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			tag.pixel_size = 0.007
			tag.font_size = 40
			tag.no_depth_test = true
			stage.add_child(tag)
			tag.position = holder.position + Vector3(0, 0.02, 0.9)
			rig.set_meta("state", states[c])
	cam.fov = 38.0
	var w: float = cols * sp
	cam.position = Vector3(0, 3.5 + rows * 2.2 + maxh, 5.0 + w * 0.7 + rows * 2.2)
	cam.look_at(Vector3(0, maxh * 0.4, 0.0))
	await _wait(0.4)
	for h: Node in stage.get_children():
		var rig: ModelRig = h.get_node_or_null("Rig") as ModelRig
		if rig != null:
			rig.set_state(StringName(String(rig.get_meta("state"))), 0.7)
	await _wait(0.45)
	await _shot("matrix_" + "_".join(matrix).replace(":", "-"))

func _run() -> void:
	await process_frame
	ModelRig.force_enabled = 1
	var all: Array = H.all_specs()
	if not matrix.is_empty():
		await _run_matrix(all)
		print("[gallery] fim")
		quit()
		return
	var groups: Dictionary = {}
	for e: Array in all:
		var kind: String = String(e[0]).get_slice(":", 0)
		if only.has(kind):
			groups.get_or_add(kind, []).append(e)
	for kind: String in groups:
		for st: String in states:
			_build_stage(groups[kind])
			await _wait(0.3)
			for h: Node in stage.get_children():
				var rig: ModelRig = h.get_node_or_null("Rig") as ModelRig
				if rig != null:
					rig.set_state(StringName(st), 0.5)
			await _wait(0.55 if st != "spawn" else 0.5)
			await _shot("gallery_%s_%s" % [kind, st])
	print("[gallery] fim")
	quit()
