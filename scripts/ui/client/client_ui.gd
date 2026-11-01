class_name ClientUi
extends CanvasLayer
## E5.5: raiz da UI do cliente (HUD + paineis). SEM logica de jogo: reflete o estado que o servidor envia a
## ClientSession e envia comandos pelas APIs existentes (dialogue_*, quest_*, craft). Nunca e criada em modo
## bot/headless de bots (ClientMain so a instancia em `_build_presentation`).
##
## Ligacao: `bind(session)` (refeita a cada nova sessao), `on_event(kind, data)` (eventos drenados pelo ClientMain),
## `update_frame(delta, view_yaw)` (por frame) e `handle_input(ev)` (teclas; tambem usada por _unhandled_input).
## Teclas (project.godot): interact=F, quest_log_toggle=J, inventory_toggle=I, map_toggle=M, talent_toggle=K (E6.2), Esc fecha.

const PANEL_NAMES: Array[String] = ["dialogue", "quests", "inventory", "craft", "map", "talents"]

var session: ClientSession = null
var inventory: ClientInventory = ClientInventory.new()
var local_name: String = ""
var player_names: Dictionary = {}   ## id -> nome (eventos player_joined)

var root: Control
var dialogue: DialoguePanel
var quests: QuestPanel
var inventory_panel: InventoryPanel
var craft: CraftPanel
var map_panel: MapPanel
var talents: TalentPanel ## E6.2: arvore de talentos (K)
var minimap: MapView
var minimap_box: PanelContainer
var minimap_title: Label
var party: PartyPanel
var boss: BossBar
var toasts: ToastStack
var fade: ScreenFade
var skill_bar: SkillBar ## E6.1: classe + habilidades (reflete o s_class do servidor)
var vitals_box: PanelContainer
var vitals_bar: ProgressBar
var prompt: Label
var interact_target: Dictionary = {}

var _built: bool = false
var _conns: Array[Dictionary] = []  ## {sig: Signal, call: Callable} para desligar ao trocar de sessao
var _view_yaw: float = PI * 0.25


func _init() -> void:
	layer = 10
	name = "ClientUi"


func _ready() -> void:
	ensure_built()


func ensure_built() -> void:
	if _built:
		return
	_built = true
	root = Control.new()
	root.name = "UiRoot"
	root.theme = UiStyle.theme()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	# HUD fixo
	party = PartyPanel.new()
	party.name = "Party"
	_place(party, 0.0, 0.0, 12, 104, 232, 104)
	boss = BossBar.new()
	boss.name = "BossBar"
	_place(boss, 0.5, 0.0, -230, 12, 230, 70)
	minimap_box = PanelContainer.new()
	minimap_box.name = "MinimapBox"
	minimap_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	minimap_box.add_theme_stylebox_override("panel", UiStyle.box(Color(0.07, 0.08, 0.11, 0.7), UiStyle.BORDER, 1, 4))
	var mv: VBoxContainer = VBoxContainer.new()
	mv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	minimap_box.add_child(mv)
	minimap_title = UiStyle.label("", UiStyle.INFO, 12)
	mv.add_child(minimap_title)
	minimap = MapView.new(MapView.Mode.MINI, Vector2(168, 168))
	minimap.name = "Minimap"
	mv.add_child(minimap)
	_place(minimap_box, 1.0, 0.0, -192, 12, -12, 226)
	vitals_box = PanelContainer.new()
	vitals_box.name = "Vitals"
	vitals_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vitals_box.add_theme_stylebox_override("panel", UiStyle.box(Color(0.07, 0.08, 0.11, 0.7), UiStyle.BORDER, 1, 4))
	vitals_bar = UiStyle.bar(230, 20, UiStyle.HP_FILL)
	vitals_box.add_child(vitals_bar)
	vitals_box.visible = false
	_place(vitals_box, 0.0, 1.0, 12, -48, 262, -12)
	skill_bar = SkillBar.new()
	skill_bar.name = "SkillBar"
	_place(skill_bar, 1.0, 1.0, -300, -140, -12, -12)
	prompt = UiStyle.label("", UiStyle.ACCENT, 17)
	prompt.name = "Prompt"
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(prompt, 0.5, 1.0, -220, -96, 220, -66)
	toasts = ToastStack.new()
	toasts.name = "Toasts"
	_place(toasts, 0.5, 1.0, -230, -330, 230, -104)
	# Paineis modais
	dialogue = DialoguePanel.new()
	quests = QuestPanel.new()
	inventory_panel = InventoryPanel.new()
	craft = CraftPanel.new()
	map_panel = MapPanel.new()
	talents = TalentPanel.new()
	for p: UiPanel in [dialogue, quests, inventory_panel, craft, map_panel, talents]:
		var sz: Vector2 = p.custom_minimum_size
		_place(p, 0.5, 0.5, -sz.x * 0.5, -sz.y * 0.5, sz.x * 0.5, sz.y * 0.5)
		p.close_requested.connect(close_panel.bind(p))
	dialogue.choice_picked.connect(_on_choice_picked)
	dialogue.finished.connect(_on_dialogue_finished)
	quests.accept_requested.connect(func(q: String) -> void: _quest_cmd("accept", q))
	quests.abandon_requested.connect(func(q: String) -> void: _quest_cmd("abandon", q))
	quests.turn_in_requested.connect(func(q: String) -> void: _quest_cmd("turn_in", q))
	craft.craft_requested.connect(_on_craft_requested)
	talents.allocate_requested.connect(func(node_id: String) -> void: _talent_cmd(Protocol.TALENT_OP_ALLOCATE, node_id))
	talents.respec_requested.connect(func() -> void: _talent_cmd(Protocol.TALENT_OP_RESPEC, ""))
	talents.spec_requested.connect(func(spec_id: String) -> void: _talent_cmd(Protocol.TALENT_OP_CHOOSE_SPEC, spec_id))
	fade = ScreenFade.new()
	fade.name = "Fade"
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(fade)
	inventory.changed.connect(func() -> void: inventory_panel.refresh(inventory))
	inventory_panel.refresh(inventory)


func _place(c: Control, ax: float, ay: float, l: float, t: float, r: float, b: float) -> void:
	c.anchor_left = ax
	c.anchor_right = ax
	c.anchor_top = ay
	c.anchor_bottom = ay
	c.offset_left = l
	c.offset_top = t
	c.offset_right = r
	c.offset_bottom = b
	root.add_child(c)


# ------------------------------------------------------------------ ligacao com a sessao

func _link(sig: Signal, target: Callable) -> void:
	sig.connect(target)
	_conns.append({"sig": sig, "call": target})


## Liga a UI a uma (nova) ClientSession. Desliga a anterior e zera o estado de apresentacao.
func bind(p_session: ClientSession) -> void:
	ensure_built()
	for c: Dictionary in _conns:
		var s: Signal = c["sig"]
		if s.is_connected(c["call"]):
			s.disconnect(c["call"])
	_conns = []
	session = p_session
	reset_view()
	if session == null:
		return
	_link(session.dialogue_changed, _on_dialogue_changed)
	_link(session.dialogue_error, _on_dialogue_error)
	_link(session.craft_finished, _on_craft_finished)
	_link(session.inventory_synced, _on_inventory_synced)
	_link(session.class_synced, skill_bar.refresh)
	_link(session.talents_changed, _on_talents_changed)
	_link(session.talents_error, _on_talents_error)
	if not session.talents_state.is_empty() and not session.class_id.is_empty():
		talents.apply_state(session.class_id, session.talents_state)
	if not session.class_id.is_empty():
		skill_bar.refresh(session.class_id)
	if not session.inventory_data.is_empty(): # sessao ja sincronizada antes do bind
		_on_inventory_synced(session.inventory_data)
	var log: ClientQuestLog = session.quest_log
	_link(log.changed, _on_quest_log_changed)
	_link(log.quest_accepted, _on_quest_accepted)
	_link(log.objective_progressed, _on_objective_progressed)
	_link(log.quest_ready, _on_quest_ready)
	_link(log.quest_completed, _on_quest_completed)
	_link(log.quest_abandoned, _on_quest_abandoned)
	_link(log.quest_error, _on_quest_error)
	quests.refresh(log)


func reset_view() -> void:
	for p: UiPanel in _panels():
		p.close()
	toasts.clear_all()
	fade.reset()
	inventory.reset()
	player_names = {}
	interact_target = {}
	prompt.text = ""
	party.refresh([], -1, {})
	boss.refresh([])
	vitals_box.visible = false
	skill_bar.refresh("")
	talents.reset()


func _panels() -> Array[UiPanel]:
	return [dialogue, quests, inventory_panel, craft, map_panel, talents]


func is_playing() -> bool:
	return session != null and session.state == ClientSession.State.PLAYING


## Algum painel modal aberto? Com painel aberto o cliente NAO envia acoes de combate (clique nos botoes
## nao pode atacar); o movimento continua.
func blocks_game_actions() -> bool:
	for p: UiPanel in _panels():
		if p.is_open():
			return true
	return false


func open_panel_names() -> Array[String]:
	var out: Array[String] = []
	var ps: Array[UiPanel] = _panels()
	for i: int in ps.size():
		if ps[i].is_open():
			out.append(PANEL_NAMES[i])
	return out


func toast(text: String, kind: String = "info") -> void:
	if toasts != null:
		toasts.push(text, kind)


# ------------------------------------------------------------------ abrir/fechar

func open_exclusive(p: UiPanel) -> void:
	for other: UiPanel in _panels():
		if other != p and other.is_open():
			close_panel(other)
	p.open()


## Fecha um painel; fechar o dialogo avisa o servidor (se a conversa ainda estiver aberta nele).
func close_panel(p: UiPanel) -> void:
	if not p.is_open():
		return
	p.close()
	if p == dialogue and session != null and not dialogue.terminal and not session.dialogue_view.is_empty():
		session.dialogue_close()
		session.dialogue_view = {}
	elif p == craft:
		craft.pending = false


func toggle_panel(p: UiPanel) -> void:
	if p.is_open():
		close_panel(p)
	else:
		open_exclusive(p)
		if p == quests:
			quests.refresh(session.quest_log if session != null else null)
		elif p == inventory_panel:
			inventory_panel.refresh(inventory)
		elif p == talents and session != null and not session.talents_state.is_empty():
			talents.apply_state(session.class_id, session.talents_state)


func close_top() -> bool:
	var ps: Array[UiPanel] = _panels()
	for i: int in ps.size():
		if ps[i].is_open():
			close_panel(ps[i])
			return true
	return false


# ------------------------------------------------------------------ entrada

func _unhandled_input(event: InputEvent) -> void:
	if handle_input(event):
		var vp: Viewport = get_viewport()
		if vp != null:
			vp.set_input_as_handled()


## Trata uma tecla. Devolve true se consumiu. So funciona com a sessao em PLAYING.
func handle_input(ev: InputEvent) -> bool:
	if not is_playing() or not _built:
		return false
	if ev.is_action_pressed("interact"):
		do_interact()
		return true
	if ev.is_action_pressed("quest_log_toggle"):
		toggle_panel(quests)
		return true
	if ev.is_action_pressed("inventory_toggle"):
		toggle_panel(inventory_panel)
		return true
	if ev.is_action_pressed("map_toggle"):
		toggle_panel(map_panel)
		return true
	if ev.is_action_pressed("talent_toggle"):
		toggle_panel(talents)
		return true
	if UiStyle.key_pressed(ev, KEY_ESCAPE, false):
		return close_top()
	for p: UiPanel in _panels():
		if p.is_open():
			return p.handle_key(ev)
	return false


## Tecla `interact`: fecha dialogo terminal/craft, ou abre a conversa/bancada do alvo mais proximo.
func do_interact() -> void:
	if dialogue.is_open():
		dialogue.advance_or_close()
		return
	if craft.is_open():
		close_panel(craft)
		return
	if blocks_game_actions():
		return
	var pos: Variant = _local_pos()
	if not (pos is Vector3):
		return
	var t: Dictionary = InteractTarget.find(pos, _zone(), NpcDirectory.shared())
	if t.is_empty():
		toast("Nada para interagir aqui.")
		return
	if String(t["kind"]) == "npc":
		if session.dialogue_open(String(t["id"])) < 0:
			toast("Nao foi possivel falar agora.", "bad")
	else:
		open_exclusive(craft)
		craft.open_station(String(t["id"]), String(t["name"]), RecipeCatalog.shared(), inventory)


# ------------------------------------------------------------------ callbacks de sessao

func _on_dialogue_changed(view: Dictionary) -> void:
	if view.is_empty():
		if dialogue.is_open():
			dialogue.close()
		return
	for other: UiPanel in _panels():
		if other != dialogue and other.is_open():
			close_panel(other)
	dialogue.show_view(view)


func _on_dialogue_error(_req: int, _op: int, code: String) -> void:
	var msg: String = UiText.dialogue_error(code)
	if dialogue.is_open():
		dialogue.set_status(msg, "bad")
	toast(msg, "bad")


func _on_choice_picked(index: int) -> void:
	if session == null or session.dialogue_choose(index) < 0:
		dialogue.set_status("Sem conexao com o servidor.", "bad")


func _on_dialogue_finished() -> void:
	# No terminal o servidor ja encerrou a conversa: so fecha localmente.
	dialogue.close()
	if session != null:
		session.dialogue_view = {}


func _quest_cmd(op: String, quest_id: String) -> void:
	if session == null:
		return
	var r: int = -1
	match op:
		"accept": r = session.quest_accept(quest_id)
		"abandon": r = session.quest_abandon(quest_id)
		"turn_in": r = session.quest_turn_in(quest_id)
	if r < 0:
		quests.set_status("Sem conexao com o servidor.", "bad")
	else:
		quests.set_status("")


func _on_quest_log_changed() -> void:
	quests.refresh(session.quest_log)


func _on_quest_accepted(qid: String) -> void:
	toast("Quest aceita: " + UiText.quest_title(qid), "quest")


func _on_objective_progressed(qid: String, oid: String, value: int, required: int) -> void:
	var def: QuestDef = QuestCatalog.shared().get_quest(qid)
	var o: QuestDef.Objective = def.objective(oid) if def != null else null
	toast("%s: %s (%d/%d)" % [UiText.quest_title(qid), o.text if o != null else oid, mini(value, required), required], "quest")


func _on_quest_ready(qid: String) -> void:
	toast("Quest pronta para entregar: " + UiText.quest_title(qid), "good")


func _on_quest_completed(qid: String, xp: int, items: Array) -> void:
	inventory.on_quest_reward(items)
	toast("Quest concluida: %s (%s)" % [UiText.quest_title(qid), UiText.rewards_text(xp, items)], "good")


func _on_quest_abandoned(qid: String) -> void:
	toast("Quest abandonada: " + UiText.quest_title(qid))


func _on_quest_error(_req: int, _op: int, qid: String, code: String) -> void:
	var msg: String = UiText.quest_error(code)
	if quests.is_open():
		quests.set_status(msg, "bad")
	toast("%s%s" % [UiText.quest_title(qid) + ": " if not qid.is_empty() else "", msg], "bad")


func _on_inventory_synced(data: Dictionary) -> void:
	inventory.apply_full(data.get("slots", []), data.get("equipment", {}))


func _talent_cmd(op: int, arg: String) -> void:
	if session == null or session.talent_cmd(op, arg) < 0:
		talents.show_error("Sem conexao com o servidor.")


func _on_talents_changed(data: Dictionary) -> void:
	if session != null:
		talents.apply_state(session.class_id, data)
		if talents.is_open():
			talents.set_status("")


func _on_talents_error(_req: int, _op: int, code: String) -> void:
	var msg: String = UiText.talent_error(code)
	talents.show_error(msg)
	toast(msg, "bad")


func _on_craft_requested(recipe_id: String) -> void:
	if session == null or session.craft(recipe_id) < 0:
		craft.show_send_failed()


func _on_craft_finished(ok: bool, data: Dictionary) -> void:
	if ok:
		inventory.on_craft_ok(data)
		toast("Fabricado: " + UiText.stacks_text(data.get("results", [])), "good")
	else:
		toast(UiText.craft_error(String(data.get("code", ""))), "bad")
	if craft.is_open():
		craft.show_result(ok, data)


# ------------------------------------------------------------------ eventos do mundo

func on_event(kind: int, data: Dictionary) -> void:
	if session == null:
		return
	match kind:
		Protocol.EVENT_PICKUP:
			inventory.on_pickup(data)
			toast("+ " + UiText.stack_text(String(data.get("item_id", "")), int(data.get("qty", 1))), "loot")
		Protocol.EVENT_PLAYER_JOINED:
			if data.get("id") is int:
				player_names[int(data["id"])] = UiText.clamp_text(String(data.get("name", "")), 24)
		Protocol.EVENT_PLAYER_LEFT:
			player_names.erase(int(data.get("id", -1)))
		Protocol.EVENT_ZONE:
			if int(data.get("id", -1)) == session.player_id:
				if int(data.get("phase", -1)) == Protocol.ZONE_PHASE_LEAVING:
					fade.fade_out()
				else:
					fade.fade_in()
					toast("Zona: " + UiText.zone_name(String(data.get("zone", ""))), "info")
		Protocol.EVENT_DEATH:
			if int(data.get("id", -1)) == session.player_id:
				fade.set_dead(true)
				toast("Voce morreu.", "bad")
				if dialogue.is_open() or craft.is_open():
					close_top()
		Protocol.EVENT_RESPAWN:
			if int(data.get("id", -1)) == session.player_id:
				fade.set_dead(false)
				fade.fade_in()  # morrer durante a transicao cancela o fade preto
		_:
			pass


# ------------------------------------------------------------------ por frame

func _local_pos() -> Variant:
	if session == null:
		return null
	if session.prediction.initialized:
		return session.prediction.pos
	if not session.local_entity.is_empty() and session.local_entity.get("pos") is Vector3:
		return session.local_entity["pos"]
	return null


func _zone() -> ZoneDef:
	if session == null or session.zone_id.is_empty():
		return null
	return WorldDef.shared().get_zone(session.zone_id)


func update_frame(delta: float, view_yaw: float = NAN) -> void:
	if not _built:
		return
	if is_finite(view_yaw):
		_view_yaw = view_yaw
	toasts.advance(delta)
	fade.advance(delta)
	for p: UiPanel in _panels():
		if p.is_open():
			p.advance(delta)
	if not is_playing():
		return
	var pos: Variant = _local_pos()
	var ents: Array = session.last_entities
	var zone: ZoneDef = _zone()
	party.refresh(ents, session.player_id, player_names, local_name)
	boss.refresh(ents, pos)
	minimap.set_state(zone, session.player_id, pos, ents, _view_yaw)
	minimap_title.text = zone.display_name if zone != null else ""
	if map_panel.is_open():
		map_panel.view.set_state(zone, session.player_id, pos, ents, _view_yaw)
		map_panel.set_zone_title(zone.display_name if zone != null else "Arena")
	var le: Dictionary = session.local_entity
	vitals_box.visible = not le.is_empty()
	if not le.is_empty():
		UiStyle.set_bar(vitals_bar, float(le["hp"]), float(le["max_hp"]), "Vida %d / %d" % [int(ceilf(float(le["hp"]))), int(ceilf(float(le["max_hp"])))])
		if float(le["hp"]) > 0.0 and fade.dead:
			fade.set_dead(false)  # reanimado (o evento respawn pode ter sido perdido)
	# prompt de interacao
	interact_target = {}
	if pos is Vector3 and not blocks_game_actions() and (le.is_empty() or float(le["hp"]) > 0.0):
		interact_target = InteractTarget.find(pos, zone, NpcDirectory.shared())
	prompt.text = InteractTarget.prompt_text(interact_target)
	# fecha o que depende de proximidade se o jogador se afastou (o servidor tambem valida)
	if pos is Vector3:
		if craft.is_open() and not craft.station_id.is_empty() and zone != null:
			var near: bool = false
			for st: Dictionary in zone.stations:
				if String(st["id"]) == craft.station_id:
					var sp: Vector3 = st["pos"]
					near = Vector2(pos.x - sp.x, pos.z - sp.z).length() <= float(st["radius"]) + 1.5
			if not near:
				close_panel(craft)
				toast("Voce se afastou da bancada.")
		if dialogue.is_open() and not dialogue.npc_id.is_empty():
			var n: Dictionary = NpcDirectory.shared().get_npc(dialogue.npc_id)
			if not n.is_empty():
				var np: Vector3 = n["position"]
				if Vector2(pos.x - np.x, pos.z - np.z).length() > float(n["radius"]) + 2.0:
					close_panel(dialogue)
