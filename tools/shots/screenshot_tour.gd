extends SceneTree
## Ferramenta de desenvolvimento (nao faz parte do jogo): abre o cliente real, injeta entradas e salva
## prints do viewport. Uso: godot --path . --script res://tools/shots/screenshot_tour.gd -- --tour hub|wild|ruins
## (com display, p. ex. xvfb-run) e SHOT_DIR=<pasta>. O cliente deve receber --host/--port apos "--".
var main: Node
var out_dir: String = ""
var tour: String = "hub"
var fwd: Vector2 = Vector2(0, 1)
var rgt: Vector2 = Vector2(1, 0)

func _initialize() -> void:
	out_dir = OS.get_environment("SHOT_DIR")
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var i: int = args.find("--tour")
	if i >= 0 and i + 1 < args.size():
		tour = args[i + 1]
	_run.call_deferred()

func _frames(n: int) -> void:
	for _i in n:
		await process_frame

func _wait(sec: float) -> void:
	var t: int = Time.get_ticks_msec() + int(sec * 1000.0)
	while Time.get_ticks_msec() < t:
		await process_frame

func _shot(name: String) -> void:
	await _frames(3)
	var img: Image = root.get_texture().get_image()
	img.save_png(out_dir + "/" + name + ".png")
	print("[tour] shot ", name)

func _pos() -> Vector2:
	var p: Vector3 = main.session.prediction.pos
	return Vector2(p.x, p.z)

func _press(action: String, sec: float = 0.15) -> void:
	var e: InputEventAction = InputEventAction.new()
	e.action = action
	e.pressed = true
	Input.parse_input_event(e)
	await _wait(sec)
	var r: InputEventAction = InputEventAction.new()
	r.action = action
	r.pressed = false
	Input.parse_input_event(r)
	await _wait(0.1)

func _hold_move(a: String, sec: float) -> void:
	Input.action_press(a)
	await _wait(sec)
	Input.action_release(a)

func _calibrate() -> void:
	var p0: Vector2 = _pos()
	await _hold_move("move_forward", 0.7)
	var p1: Vector2 = _pos()
	await _hold_move("move_right", 0.7)
	var p2: Vector2 = _pos()
	fwd = (p1 - p0).normalized() if (p1 - p0).length() > 0.1 else fwd
	rgt = (p2 - p1).normalized() if (p2 - p1).length() > 0.1 else rgt
	print("[tour] calib fwd=", fwd, " rgt=", rgt)

func _goto(target: Vector2, tol: float = 2.0, timeout: float = 60.0) -> void:
	var t_end: int = Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < t_end:
		var d: Vector2 = target - _pos()
		if d.length() <= tol:
			break
		d = d.normalized()
		var a: float = d.dot(fwd)
		var b: float = d.dot(rgt)
		_set_move(a, b)
		await process_frame
	_set_move(0.0, 0.0)

func _set_move(a: float, b: float) -> void:
	for pair in [["move_forward", maxf(a, 0.0)], ["move_back", maxf(-a, 0.0)], ["move_right", maxf(b, 0.0)], ["move_left", maxf(-b, 0.0)]]:
		if pair[1] > 0.01:
			Input.action_press(pair[0], pair[1])
		else:
			Input.action_release(pair[0])

func _toggle(action: String, name: String) -> void:
	await _press(action)
	await _wait(0.6)
	await _shot(name)
	await _press(action)
	await _wait(0.3)

func _fight(sec: float, name: String) -> void:
	var t_end: int = Time.get_ticks_msec() + int(sec * 1000.0)
	var shots: int = 0
	while Time.get_ticks_msec() < t_end:
		Input.action_press("attack")
		await _wait(0.25)
		Input.action_release("attack")
		if shots < 2 and Time.get_ticks_msec() > t_end - int(sec * 1000.0 * (0.6 - 0.3 * shots)):
			await _shot(name + str(shots))
			shots += 1
		await _wait(0.15)

func _run() -> void:
	var packed: PackedScene = load("res://scenes/client/client_boot.tscn")
	main = packed.instantiate()
	root.add_child(main)
	await _wait(8.0)
	await _calibrate()
	match tour:
		"hub": await _tour_hub()
		"wild": await _tour_wild()
		"ruins": await _tour_ruins()
	print("[tour] fim")
	quit()

func _tour_hub() -> void:
	await _shot("hub_01_inicio")
	var ev: InputEventMouseButton = InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_WHEEL_DOWN
	ev.pressed = true
	for _i in 4:
		Input.parse_input_event(ev)
		await _wait(0.1)
	await _wait(1.0)
	await _shot("hub_02_camera_afastada")
	await _goto(Vector2(8, -6), 2.5)
	await _shot("hub_03_perto_da_bancada_e_npc")
	await _goto(Vector2(10, -6), 3.0)
	await _press("interact")
	await _wait(1.0)
	await _shot("hub_04_dialogo")
	await _press("interact")
	await _wait(0.5)
	await _toggle("quest_log_toggle", "hub_05_quests")
	await _toggle("inventory_toggle", "hub_06_inventario")
	await _toggle("talent_toggle", "hub_07_talentos")
	await _toggle("map_toggle", "hub_08_mapa")

func _tour_wild() -> void:
	await _goto(Vector2(30, 0), 3.0)
	await _wait(2.0)
	await _goto(Vector2(170, 0), 4.0, 90.0)
	await _shot("wild_01_entrada")
	await _goto(Vector2(190, -18), 3.0, 40.0)
	await _shot("wild_02_inimigos")
	await _fight(12.0, "wild_03_combate")
	await _toggle("inventory_toggle", "wild_04_inventario_pos_combate")

func _tour_ruins() -> void:
	await _goto(Vector2(30, 0), 3.0, 25.0)
	await _wait(1.0)
	await _goto(Vector2(246, 0), 5.0, 40.0)
	await _wait(1.0)
	await _goto(Vector2(372, 0), 5.0, 30.0)
	await _shot("ruins_01_antecamara")
	await _goto(Vector2(395, 0), 4.0, 15.0)
	await _fight(6.0, "ruins_02_combate")
	await _goto(Vector2(425, 0), 5.0, 15.0)
	await _shot("ruins_03_salao")
	await _fight(6.0, "ruins_04_salao_combate")
