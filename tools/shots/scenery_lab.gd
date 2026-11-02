extends SceneTree
## Ferramenta de desenvolvimento (E8.2): bancada de cenario SEM servidor. Monta o ClientWorld, mostra uma zona, coloca o modelo do
## guerreiro na posicao pedida, liga a camera isometrica real e salva prints. Muito mais rapido que as tours (sem rede/caminhada).
## Uso (com display, p.ex. xvfb-run; SHOT_DIR=<pasta>):
##   godot --path . --rendering-driver opengl3 --resolution 1280x720 --script res://tools/shots/scenery_lab.gd -- \
##     --shot nome,zona,x,z,zoom[,chave=valor;chave=r:g:b] [--shot ...] [--quality low|medium|high] [--mood chave=valor;...]
## Exemplo: --shot hub_a,zone_hub,0,6,1.0,fog_density=0.002;sun_color=1:0.7:0.4  (cores r:g:b; o 6o campo vale so para aquele print)
var world: ClientWorld
var cam: IsoCamera
var dummy: Node3D
var fader: OcclusionFader
var out_dir: String = ""

func _initialize() -> void:
	out_dir = OS.get_environment("SHOT_DIR")
	_run.call_deferred()

func _parse_overrides(text: String) -> Dictionary:
	var out: Dictionary = {}
	for kv: String in text.split(";", false):
		var p: PackedStringArray = kv.split("=")
		if p.size() != 2:
			continue
		var v: String = p[1]
		if v.contains(":"):
			var c: PackedStringArray = v.split(":")
			out[p[0]] = Color(c[0].to_float(), c[1].to_float(), c[2].to_float())
		else:
			out[p[0]] = v.to_float()
	return out

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var shots: Array = []
	var overrides: Dictionary = {}
	var i: int = 0
	while i < args.size():
		if args[i] == "--shot" and i + 1 < args.size():
			shots.append(args[i + 1].split(","))
			i += 1
		elif args[i] == "--mood" and i + 1 < args.size():
			overrides = _parse_overrides(args[i + 1])
			i += 1
		i += 1
	QualitySettings.current = QualitySettings.resolve_startup(args)
	for zid: String in SceneryTheme.zone_ids():
		var mood: Dictionary = SceneryTheme.for_zone(zid)["mood"]
		for k: Variant in overrides:
			mood[k] = overrides[k]
	world = ClientWorld.new()
	root.add_child(world)
	var cam_scene: PackedScene = load("res://scenes/camera/iso_camera.tscn") as PackedScene
	cam = cam_scene.instantiate() as IsoCamera
	root.add_child(cam)
	dummy = Node3D.new()
	root.add_child(dummy)
	var rig: ModelRig = ModelRig.build(VisualSpec.make("class.warrior", 1.8))
	if rig != null:
		dummy.add_child(rig)
	cam.set_target(dummy)
	fader = OcclusionFader.new()
	fader.camera = cam.get_camera()
	fader.target = dummy
	root.add_child(fader)
	await _frames(3)
	for s: PackedStringArray in shots:
		var zid: String = s[1]
		var mood_ref: Dictionary = SceneryTheme.for_zone(zid)["mood"]
		var saved: Dictionary = mood_ref.duplicate()
		if s.size() > 5:
			for k2: Variant in _parse_overrides(s[5]):
				mood_ref[k2] = _parse_overrides(s[5])[k2]
		world.zone_id = ""
		world.show_zone(zid)
		var pos: Vector3 = Vector3(s[2].to_float(), 0.0, s[3].to_float())
		dummy.position = pos
		var zoom: float = s[4].to_float() if s.size() > 4 else 1.0
		cam.zoom = zoom
		cam._zoom_target = zoom
		cam._apply_projection(true)
		cam.global_position = pos + Vector3.UP * cam.target_height
		for _k: int in 30:
			world.scenery_env.update(0.1, pos)
			await process_frame
		var t0: int = Time.get_ticks_usec()
		await _frames(6)
		var frame_ms: float = float(Time.get_ticks_usec() - t0) / 6000.0
		var img: Image = root.get_texture().get_image()
		img.save_png(out_dir + "/" + s[0] + ".png")
		for k3: Variant in saved:
			mood_ref[k3] = saved[k3]
		var e: Environment = world.scenery_env.env
		print("[lab] env fog=%s dens=%.4f amb=%s ambE=%.2f sunE=%.2f sunC=%s tm=%d exp=%.2f white=%.1f glow=%s gi=%.2f sat=%.2f con=%.2f" % [e.fog_enabled, e.fog_density, e.ambient_light_color, e.ambient_light_energy, world.scenery_env.sun.light_energy, world.scenery_env.sun.light_color, e.tonemap_mode, e.tonemap_exposure, e.tonemap_white, e.glow_enabled, e.glow_intensity, e.adjustment_saturation, e.adjustment_contrast])
		print("[lab] shot ", s[0], " frame_ms=%.0f" % frame_ms, " draws=", int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), " objects=", int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)), " prims=", int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
	quit()

func _frames(n: int) -> void:
	for _i in n:
		await process_frame
