extends SceneTree
## Ferramenta de desenvolvimento (E8.4): bancada da UI SEM servidor. Monta a ClientUi real ligada a uma ClientSession falsa
## (mesmo padrao dos testes e5_ui), usa um print antigo do mundo como pano de fundo e salva um PNG por cena.
## Uso (com display, p.ex. xvfb-run; SHOT_DIR=<pasta>):
##   godot --path . --rendering-driver opengl3 --resolution 1280x720 --script res://tools/shots/ui_lab.gd -- [--scenes a,b,c] [--bg res://...png] [--prefix x_]
## cenas: hud inventory talents quests dialogue map options credits menu login gallery boss craft toasts
const U = preload("res://tests/e5_ui/ui_helpers.gd")

var ui: ClientUi
var ss: ClientSession
var bg: TextureRect
var out_dir: String = ""
var prefix: String = ""

func _initialize() -> void:
	out_dir = OS.get_environment("SHOT_DIR")
	_run.call_deferred()

func _arg(name: String, def: String) -> String:
	var a: PackedStringArray = OS.get_cmdline_user_args()
	for i in a.size():
		if a[i] == name and i + 1 < a.size():
			return a[i + 1]
	return def

func _wait(sec: float) -> void:
	await create_timer(sec).timeout

func _setup(bg_path: String) -> void:
	bg = TextureRect.new()
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	if FileAccess.file_exists(bg_path):
		var img: Image = Image.load_from_file(bg_path)
		if img != null:
			bg.texture = ImageTexture.create_from_image(img)
	var cl: CanvasLayer = CanvasLayer.new()
	cl.layer = 0
	cl.add_child(bg)
	root.add_child(cl)
	var made: Dictionary = U.make_session()
	ss = made["session"]
	ui = U.make_ui(self, ss)
	ui.local_name = "Tester"
	ss.on_class_update({"class_id": "warrior"})
	U.world_event(ss, Protocol.EVENT_ZONE, {"id": ss.player_id, "zone": "zone_hub", "phase": Protocol.ZONE_PHASE_ARRIVED, "pos": U.HUB_ORLA})
	U.snapshot(ss, [U.player(ss.player_id, U.HUB_ORLA, 74.0, 100.0)])

	ui.update_frame(0.016)

func _inventory() -> void:
	var slots: Array = [
		{"item_id": "sword_rare", "qty": 1, "inst": {"uid": 1, "rarity": "rare", "ilvl": 14, "affixes": [{"id": "pre_brutal", "tier": 2, "value": 18}, {"id": "suf_of_fury", "tier": 3, "value": 7}]}},
		{"item_id": "unique_frostbrand", "qty": 1, "inst": {"uid": 2, "rarity": "mythic", "ilvl": 20, "affixes": []}},
		{"item_id": "armor_heavy", "qty": 1, "inst": {"uid": 3, "rarity": "uncommon", "ilvl": 9, "affixes": [{"id": "pre_vital", "tier": 3, "value": 9}]}},
		{"item_id": "armor_leather", "qty": 1, "inst": {"uid": 5, "rarity": "epic", "ilvl": 18, "affixes": [{"id": "pre_bulwark", "tier": 2, "value": 15}]}},
		{"item_id": "amulet_vigor", "qty": 1, "inst": {"uid": 4, "rarity": "legendary", "ilvl": 30, "affixes": [{"id": "pre_vital", "tier": 1, "value": 44}, {"id": "suf_of_titan", "tier": 1, "value": 20}]}},
		{"item_id": "potion_minor", "qty": 5},
		{"item_id": "scrap_material", "qty": 12},
	]
	var eq: Dictionary = {"weapon": "sword_basic", "armor": "armor_leather"}
	ui.inventory.apply_full(slots, eq, {})

func _shot(name: String) -> void:
	await _wait(0.7)
	for _i in 3:
		await process_frame
	for pn: UiPanel in ui._panels():
		if pn.visible:
			print("[ui] panel ", pn.name, " pos=", pn.global_position, " size=", pn.size, " min=", pn.get_combined_minimum_size(), " vp=", root.get_visible_rect().size)
	var img: Image = root.get_texture().get_image()
	img.save_png("%s/%s%s.png" % [out_dir, prefix, name])
	print("[ui] shot ", name, " ", img.get_size())

func _close_all() -> void:
	for p: UiPanel in ui._panels():
		p.close()
	await _wait(0.4)

func _scene(name: String) -> void:
	await _close_all()
	match name:
		"hud":
			ui.boss.visible = false
			U.snapshot(ss, [U.player(ss.player_id, U.HUB_ORLA, 74.0, 100.0), U.enemy(31, "thorn_alpha", U.HUB_ORLA + Vector3(8, 0, 4), 640.0, 900.0, 1)])
			ui.update_frame(0.016)
			ui.on_event(Protocol.EVENT_PICKUP, {"id": 7, "item_id": "potion_minor", "qty": 2})
			ui.toast("Missao aceita: Limpar a clareira", "good")
			ui.toast("Voce foi atingido!", "bad")
			ui.skill_bar.note_actions(Protocol.ACTION_SKILL_1)
		"inventory":
			_inventory()
			ui.open_exclusive(ui.inventory_panel)
		"talents":
			ss.talents_state = {"spec": "berserker", "ranks": {"w_vigor": 2}, "respecs": 0, "level": 7, "points_total": 6, "points_spent": 2, "points_available": 4, "req_id": -1}
			ui.talents.apply_state("warrior", ss.talents_state)
			ui.open_exclusive(ui.talents)
		"quests":
			U.quest_sync(ss.quest_log, {"gw_clear_clearing": {"objectives": {"kill_grunts": 2}}, "gw_scrap_for_orla": {"objectives": {}}}, ["gw_welcome"], {"gw_ruins_expedition": "available"})
			ss.quest_log.ready["gw_scrap_for_orla"] = true
			ui.quests.refresh(ss.quest_log)
			ui.open_exclusive(ui.quests)
		"dialogue":
			ss.on_dialogue(Protocol.DIALOGUE_VIEW, {"npc_id": "npc_elder_orla", "dialogue_id": "dlg_elder_orla", "node_id": "welcome_offer", "speaker": "npc_elder_orla", "text": "Forasteiro... as raizes sussurram sobre a sua chegada. A clareira ao norte esta tomada pelos espinhos; poderia nos ajudar?", "text_key": "k",
				"choices": [{"index": 0, "text": "Eu falarei com ele.", "text_key": "a"}, {"index": 1, "text": "Talvez depois.", "text_key": "b"}], "terminal": false})
		"map":
			ui.open_exclusive(ui.map_panel)
		"options":
			ui.open_exclusive(ui.options)
		"credits":
			ui.open_exclusive(ui.credits)
		"menu":
			ui.open_exclusive(ui.menu)
		"boss":
			U.snapshot(ss, [U.player(ss.player_id, U.HUB_ORLA, 74.0, 100.0), U.enemy(31, "thorn_alpha", U.HUB_ORLA + Vector3(8, 0, 4), 540.0, 900.0, 1)])
			for _i in 4:
				ui.update_frame(0.05)
		"craft":
			U.snapshot(ss, [U.player(ss.player_id, U.HUB_STATION, 74.0, 100.0)])
			ui.update_frame(0.016)
			_inventory()
			ui.close_panel(ui.dialogue)
			ui.craft.open_station("station_greenwood_workbench", "Bancada de Greenwood", RecipeCatalog.shared(), ui.inventory)
		"toasts":
			for t: String in ["Voce encontrou Pocao Menor x2", "Missao concluida: Boas-vindas", "Nivel 5 alcancado!", "Inventario cheio"]:
				ui.toast(t, "good")
		_:
			pass
	for _i in 8:
		ui.update_frame(0.05)

func _login() -> void:
	ui.visible = false
	var ls: LoginScreen = LoginScreen.new()
	var lc: CanvasLayer = CanvasLayer.new()
	lc.layer = 20
	root.add_child(lc)
	ls.set_anchors_preset(Control.PRESET_FULL_RECT)
	lc.add_child(ls)
	await _wait(0.8)
	var img: Image = root.get_texture().get_image()
	img.save_png("%s/%slogin.png" % [out_dir, prefix])
	print("[ui] shot login")
	root.remove_child(lc)
	lc.queue_free()
	ui.visible = true

func _run() -> void:
	prefix = _arg("--prefix", "")
	var scenes: PackedStringArray = _arg("--scenes", "hud,inventory,talents,quests,dialogue,map,options,credits,menu,boss,craft,toasts,login").split(",")
	_setup(_arg("--bg", "res://.tools/scratch/shots/lab_hub_a.png"))
	await _wait(0.5)
	for s in scenes:
		if s == "login":
			await _login()
			continue
		await _scene(s)
		await _shot(s)
	quit(0)
