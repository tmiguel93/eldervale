class_name QuestPanel
extends UiPanel
## E5.5: diario de quests (J). Lista prontas/ativas/disponiveis/concluidas a partir do ClientQuestLog (espelho do
## servidor) e dos dados do QuestCatalog. Emite pedidos (aceitar/abandonar/entregar); o servidor decide.
## Teclado: Cima/Baixo seleciona, Enter aceita/entrega, Delete/Backspace abandona (2 toques para confirmar).

signal accept_requested(quest_id: String)
signal abandon_requested(quest_id: String)
signal turn_in_requested(quest_id: String)

const GROUP_ORDER: Array[String] = ["ready", "active", "available", "completed"]
const GROUP_TITLES: Dictionary = {"ready": "Prontas para entregar", "active": "Em andamento", "available": "Disponiveis", "completed": "Concluidas"}
const CONFIRM_WINDOW: float = 3.0
const REQUEST_COOLDOWN: float = 0.4

var list_box: VBoxContainer
var detail_title: Label
var detail_text: Label
var detail_objectives: Label
var detail_extra: Label
var btn_primary: Button
var btn_abandon: Button
var entries: Array[Dictionary] = []   ## {id, title, status}
var selected: int = 0
var _log: ClientQuestLog = null
var _confirm_left: float = 0.0
var _cooldown: float = 0.0
var _rows: Array[Button] = []


func _init() -> void:
	super._init("Diario de Quests", Vector2(760, 440))
	var split: HBoxContainer = HBoxContainer.new()
	split.add_theme_constant_override("separation", 12)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(split)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(250, 300)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(scroll)
	list_box = VBoxContainer.new()
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list_box)
	var right: VBoxContainer = VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 6)
	split.add_child(right)
	detail_title = UiStyle.label("", UiStyle.ACCENT, 17, true)
	right.add_child(detail_title)
	detail_text = UiStyle.label("", UiStyle.TEXT, 0, true)
	right.add_child(detail_text)
	detail_objectives = UiStyle.label("", UiStyle.TEXT, 0, true)
	right.add_child(detail_objectives)
	detail_extra = UiStyle.label("", UiStyle.TEXT_DIM, 0, true)
	right.add_child(detail_extra)
	var btns: HBoxContainer = HBoxContainer.new()
	right.add_child(btns)
	btn_primary = UiStyle.button("")
	btn_primary.name = "PrimaryButton"
	btn_primary.pressed.connect(_on_primary)
	btns.add_child(btn_primary)
	btn_abandon = UiStyle.button("Abandonar")
	btn_abandon.name = "AbandonButton"
	btn_abandon.pressed.connect(_on_abandon)
	btns.add_child(btn_abandon)
	hint_label.text = "J abre/fecha | Cima/Baixo seleciona | Enter aceita/entrega | Del abandona | Esc fecha"
	refresh(null)


## Linhas do diario (ordem: prontas, ativas, disponiveis, concluidas). Funcao pura (testavel).
static func build_entries(log: ClientQuestLog, catalog: QuestCatalog) -> Array[Dictionary]:
	var by_group: Dictionary = {}
	for g: String in GROUP_ORDER:
		by_group[g] = []
	if log != null:
		var seen: Dictionary = {}
		for qid: String in catalog.ids():
			seen[qid] = true
		for qid: Variant in log.active:
			seen[String(qid)] = true
		for qid2: Variant in log.completed:
			seen[String(qid2)] = true
		var ids: Array = seen.keys()
		ids.sort()
		for qv: Variant in ids:
			var qid3: String = String(qv)
			var st: String = log.status_of(qid3)
			if by_group.has(st):
				(by_group[st] as Array).append({"id": qid3, "title": UiText.quest_title(qid3), "status": st})
	var out: Array[Dictionary] = []
	for g2: String in GROUP_ORDER:
		for e: Variant in by_group[g2]:
			out.append(e as Dictionary)
	return out


func refresh(log: ClientQuestLog) -> void:
	if log != null:
		_log = log
	var prev_id: String = selected_id()
	entries = build_entries(_log, QuestCatalog.shared())
	selected = 0
	for i: int in entries.size():
		if String(entries[i]["id"]) == prev_id:
			selected = i
	_rebuild_list()
	_show_detail()


func selected_id() -> String:
	return String(entries[selected]["id"]) if selected >= 0 and selected < entries.size() else ""


func selected_status() -> String:
	return String(entries[selected]["status"]) if selected >= 0 and selected < entries.size() else ""


func _rebuild_list() -> void:
	clear_children(list_box)
	_rows = []
	if entries.is_empty():
		list_box.add_child(UiStyle.label("Nenhuma quest disponivel.\nConverse com os moradores de Greenwood.", UiStyle.TEXT_DIM, 0, true))
		return
	var last: String = ""
	for i: int in entries.size():
		var st: String = String(entries[i]["status"])
		if st != last:
			last = st
			list_box.add_child(UiStyle.label(String(GROUP_TITLES.get(st, st)), UiStyle.INFO, 13))
		var b: Button = UiStyle.button(String(entries[i]["title"]))
		b.name = "Quest_" + String(entries[i]["id"])
		b.clip_text = true
		b.pressed.connect(_select.bind(i))
		list_box.add_child(b)
		_rows.append(b)
	_paint()


func _paint() -> void:
	for i: int in _rows.size():
		_rows[i].add_theme_color_override("font_color", UiStyle.ACCENT if i == selected else UiStyle.TEXT)


func _select(i: int) -> void:
	if i < 0 or i >= entries.size():
		return
	selected = i
	_confirm_left = 0.0
	_paint()
	_show_detail()


func _show_detail() -> void:
	btn_primary.visible = false
	btn_abandon.visible = false
	detail_objectives.text = ""
	detail_extra.text = ""
	if entries.is_empty():
		detail_title.text = "Sem quests"
		detail_text.text = "Quando houver quests disponiveis ou ativas elas aparecem aqui."
		return
	var qid: String = selected_id()
	var st: String = selected_status()
	var def: QuestDef = QuestCatalog.shared().get_quest(qid)
	detail_title.text = "%s  (%s)" % [UiText.quest_title(qid), UiText.status_label(st)]
	if def == null:
		detail_text.text = "Quest desconhecida deste cliente."
		return
	detail_text.text = def.description
	var lines: PackedStringArray = PackedStringArray()
	var progress: Dictionary = _log.active.get(qid, {}) if _log != null else {}
	for o: QuestDef.Objective in def.objectives:
		var v: int = int(progress.get(o.id, 0))
		if st == "completed":
			v = o.required
		lines.append(UiText.objective_line(o.text, v, o.required))
	detail_objectives.text = "\n".join(lines)
	var extra: String = "Recompensa: " + UiText.rewards_text(def.reward_xp, def.reward_items)
	if st == "ready" or st == "active":
		extra += "\nEntregar a: " + UiText.npc_name(def.turn_in_npc)
	elif st == "available":
		extra += "\nFalar com: " + UiText.npc_name(def.giver_npc)
	detail_extra.text = extra
	match st:
		"available":
			btn_primary.text = "Aceitar [Enter]"
			btn_primary.visible = true
		"ready":
			btn_primary.text = "Entregar [Enter]"
			btn_primary.visible = true
	if (st == "active" or st == "ready") and def.abandonable:
		btn_abandon.text = "Abandonar [Del]"
		btn_abandon.visible = true
	elif st == "active" or st == "ready":
		detail_extra.text += "\nEsta quest nao pode ser abandonada."


func _on_primary() -> void:
	if _cooldown > 0.0:
		return
	var qid: String = selected_id()
	match selected_status():
		"available":
			_cooldown = REQUEST_COOLDOWN
			accept_requested.emit(qid)
		"ready":
			_cooldown = REQUEST_COOLDOWN
			turn_in_requested.emit(qid)


func _on_abandon() -> void:
	var st: String = selected_status()
	if st != "active" and st != "ready":
		return
	if _confirm_left <= 0.0:
		_confirm_left = CONFIRM_WINDOW
		btn_abandon.text = "Confirmar abandono?"
		set_status("Abandonar zera o progresso. Pressione de novo para confirmar.", "bad")
		return
	_confirm_left = 0.0
	btn_abandon.text = "Abandonar [Del]"
	set_status("")
	abandon_requested.emit(selected_id())


func advance(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	if _confirm_left > 0.0:
		_confirm_left -= delta
		if _confirm_left <= 0.0:
			_confirm_left = 0.0
			btn_abandon.text = "Abandonar [Del]"
			set_status("")


func handle_key(ev: InputEvent) -> bool:
	if not is_open():
		return false
	var n: int = step_index(ev, selected, entries.size())
	if n >= 0:
		_select(n)
		return true
	if is_confirm(ev):
		_on_primary()
		return true
	if UiStyle.key_pressed(ev, KEY_DELETE, false) or UiStyle.key_pressed(ev, KEY_BACKSPACE, false):
		_on_abandon()
		return true
	return false
