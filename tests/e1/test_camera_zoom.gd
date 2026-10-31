extends RefCounted
## Zoom por scroll: passo puro, limites e efeito no enquadramento.


func run(ctx: Object) -> void:
	print("== test_camera_zoom")
	var closer: float = IsoCamera.step_zoom(1.0, -1)
	var farther: float = IsoCamera.step_zoom(1.0, 1)
	ctx.check(closer < 1.0 and farther > 1.0, "scroll para cima aproxima e para baixo afasta")
	var z: float = 1.0
	for i in 100:
		z = IsoCamera.step_zoom(z, -1)
	ctx.check(is_equal_approx(z, IsoCamera.ZOOM_MIN), "aproximar respeita o limite minimo")
	for i in 200:
		z = IsoCamera.step_zoom(z, 1)
	ctx.check(is_equal_approx(z, IsoCamera.ZOOM_MAX), "afastar respeita o limite maximo")
	var rig: IsoCamera = (load("res://scenes/camera/iso_camera.tscn") as PackedScene).instantiate() as IsoCamera
	ctx.check(rig != null, "rig instanciado")
	if rig == null:
		return
	ctx.root.add_child(rig)
	await ctx.process_frame
	var base_size: float = rig.get_camera().size
	rig.zoom = 0.5
	rig._apply_projection(true)
	ctx.check(rig.get_camera().size < base_size, "zoom menor reduz o tamanho ortografico (mais perto)")
	rig.queue_free()
