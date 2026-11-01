extends RefCounted
## E6.1 - UI de classe no cliente: barra de habilidades (reflete o s_class do servidor), seletor de classe na tela de login e
## criacao de personagem com a classe escolhida (backend falso). A UI nunca existe em modo bot.

const U = preload("res://tests/e5_ui/ui_helpers.gd")
const C = preload("res://tests/e6_classes/class_helpers.gd")


func run(ctx: Object) -> void:
	var tree: SceneTree = ctx as SceneTree
	await tree.physics_frame
	_test_rows(ctx)
	_test_bar_follows_server(ctx, tree)
	_test_login_class_selection(ctx)
	_test_bot_safety(ctx)


func _test_rows(ctx: Object) -> void:
	for cid: String in C.CLASS_IDS:
		var rows: Array[Dictionary] = SkillBar.rows_for(cid)
		ctx.check(rows.size() == 4, "%s: 4 linhas na barra" % cid)
		var ids: Array = []
		for r: Dictionary in rows:
			ids.append(r["skill_id"])
		ctx.check(ids == C.SKILLS[cid], "%s: linhas na ordem dos slots %s" % [cid, str(ids)])
		ctx.check(rows[0]["key"] == "LMB" and rows[1]["key"] == "Q" and rows[2]["key"] == "E" and rows[3]["key"] == "Espaco", "%s: teclas dos slots" % cid)
		var fireball_cost: int = int(ClassCatalog.load_skill(&"fireball").resource_cost)
		if cid == "mage":
			ctx.check(int(rows[1]["cost"]) == fireball_cost and String(rows[1]["name"]) == "Bola de Fogo", "mage: custo e nome vem dos dados")
	ctx.check(SkillBar.rows_for("necromancer").is_empty() and SkillBar.rows_for("").is_empty(), "classe desconhecida: sem linhas")
	ctx.check(SkillBar.title_for("mage").begins_with("Mago") and SkillBar.title_for("mage").contains("Mana"), "titulo mostra classe e recurso (mana)")
	ctx.check(SkillBar.title_for("ranger").contains("Stamina") and SkillBar.title_for("zzz").is_empty(), "titulo do patrulheiro / desconhecido")


func _test_bar_follows_server(ctx: Object, tree: SceneTree) -> void:
	var made: Dictionary = U.make_session()
	var ss: ClientSession = made["session"]
	var ui: ClientUi = U.make_ui(tree, ss)
	ctx.check(ui.skill_bar != null and not ui.skill_bar.visible, "barra existe e fica oculta ate o servidor informar a classe")
	ss.on_class_update({"class_id": "mage"})
	ctx.check(ui.skill_bar.visible and ui.skill_bar.class_id == "mage", "s_class mostra a barra do mago")
	ss.on_class_update({"class_id": "ranger"})
	ctx.check(ui.skill_bar.class_id == "ranger", "barra segue a classe informada pelo servidor")
	ss.on_class_update({"class_id": "necromancer"})
	ctx.check(ui.skill_bar.class_id == "ranger", "classe invalida nao altera a barra")
	# rebind a uma sessao que ja tem classe
	var made2: Dictionary = U.make_session(9)
	var ss2: ClientSession = made2["session"]
	ss2.on_class_update({"class_id": "warrior"})
	ui.bind(ss2)
	ctx.check(ui.skill_bar.visible and ui.skill_bar.class_id == "warrior", "bind a sessao ja classificada mostra a classe")
	ui.bind(ClientSession.new())
	ctx.check(not ui.skill_bar.visible and ui.skill_bar.class_id == "", "sessao nova/IDLE: barra oculta")
	U.free_ui(tree, ui)


func _test_login_class_selection(ctx: Object) -> void:
	var screen: LoginScreen = LoginScreen.new()
	ctx.check(screen.selected_class == "warrior", "padrao do seletor = warrior")
	ctx.check(screen.select_class("mage") and screen.selected_class == "mage", "seleciona mage")
	ctx.check(not screen.select_class("necromancer") and screen.selected_class == "mage", "classe fora do catalogo ignorada")
	ctx.check(not screen.select_class("") and not screen.select_class("Mage") and screen.selected_class == "mage", "ids invalidos ignorados")
	screen.free()


func _test_bot_safety(ctx: Object) -> void:
	var src: String = FileAccess.get_file_as_string("res://scripts/client/client_main.gd")
	ctx.check(src.contains("class_update_received.connect"), "ClientMain liga s_class a sessao")
	var ui_idx: int = src.find("ClientUi.new()")
	var bot_idx: int = src.find("is_bot")
	ctx.check(ui_idx > 0 and bot_idx >= 0, "ClientMain so cria a UI no caminho de apresentacao")
	var sess_src: String = FileAccess.get_file_as_string("res://scripts/client/client_session.gd")
	ctx.check(not sess_src.contains("SkillBar") and not sess_src.contains("Control"), "ClientSession (usada por bots) nao referencia UI")
