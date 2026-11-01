class_name TalentPanel
extends UiPanel
## E6.2: painel de talentos (tecla K). Mostra a arvore da classe (nos genericos + especializacao), pontos, pre-requisitos e estado de
## cada no, e emite PEDIDOS (`allocate_requested`, `respec_requested`, `spec_requested`). Apresentacao pura: o estado vem do servidor
## (`s_talents`); os indicadores de disponibilidade usam as MESMAS regras (`TalentState.check_allocate`) so para mostrar, mas quem
## decide e o servidor (e o backend). Nunca e instanciado em bot/headless (so pelo ClientUi).

signal allocate_requested(node_id: String)
signal respec_requested()
signal spec_requested(spec_id: String)

const PENDING_TIMEOUT: float = 6.0
const CONFIRM_WINDOW: float = 3.0

var class_id: String = ""
var tree: TalentTree = null
var state: TalentState = TalentState.new()
var level: int = 1
var points_total: int = 0
var points_spent: int = 0
var points_available: int = 0
var order: Array[String] = []
var selected: int = 0
var pending: bool = false

var header: Label
var list_box: VBoxContainer
var detail_title: Label
var detail_desc: Label
var detail_info: Label
var btn_alloc: Button
var btn_spec: Button
var btn_respec: Button
var _rows: Array[Button] = []
var _pending_left: float = 0.0
var _confirm_left: float = 0.0
var _catalog: TalentCatalog = null


func _init() -> void:
	super._init("Talentos", Vector2(760, 470))
	header = UiStyle.label("", UiStyle.ACCENT, 15)
	header.name = "Header"
	body.add_child(header)
	var split: HBoxContainer = HBoxContainer.new()
	split.add_theme_constant_override("separation", 12)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(split)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(330, 300)
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
	detail_desc = UiStyle.label("", UiStyle.TEXT, 0, true)
	right.add_child(detail_desc)
	detail_info = UiStyle.label("", UiStyle.TEXT_DIM, 0, true)
	right.add_child(detail_info)
	btn_alloc = UiStyle.button("Alocar ponto [Enter]")
	btn_alloc.name = "AllocateButton"
	btn_alloc.pressed.connect(_request_allocate)
	right.add_child(btn_alloc)
	btn_spec = UiStyle.button("Escolher especializacao [S]")
	btn_spec.name = "SpecButton"
	btn_spec.pressed.connect(_request_spec)
	right.add_child(btn_spec)
	btn_respec = UiStyle.button("Resetar talentos [R]")
	btn_respec.name = "RespecButton"
	btn_respec.pressed.connect(_request_respec)
	right.add_child(btn_respec)
	hint_label.text = "Cima/Baixo seleciona | Enter aloca | S especializacao | R reseta (2x) | K ou Esc fecha"


# ------------------------------------------------------------------ funcoes puras (testaveis)

## Ordem de exibicao: nos genericos e depois cada especializacao; dentro do grupo, por profundidade no grafo (ordem do arquivo no empate).
static func display_order(p_tree: TalentTree) -> Array[String]:
	var groups: Array[String] = [""]
	for s: String in p_tree.specs:
		groups.append(s)
	var out: Array[String] = []
	for g: String in groups:
		var items: Array[Array] = []
		for i: int in p_tree.order.size():
			var id: String = p_tree.order[i]
			if String((p_tree.nodes[id] as Dictionary)["spec"]) == g:
				items.append([p_tree.depth(id), i, id])
		items.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] if a[0] != b[0] else a[1] < b[1])
		for it: Array in items:
			out.append(String(it[2]))
	return out


## Estado de um no para exibicao: "maxed", "available" ou o codigo de bloqueio (TalentState.check_allocate).
static func node_status(p_tree: TalentTree, ts: TalentState, p_level: int, p_catalog: TalentCatalog, node_id: String) -> String:
	var code: String = TalentState.check_allocate(p_tree, ts, p_level, node_id, p_catalog)
	if code.is_empty():
		return "available"
	return "maxed" if code == "max_rank" else code


static func status_text(status: String) -> String:
	match status:
		"available": return "disponivel"
		"maxed": return "no maximo"
		"prerequisite": return "requisito pendente"
		"no_points": return "sem pontos"
		"spec_not_chosen": return "escolha a especializacao"
		"wrong_spec": return "outra especializacao"
		"level_too_low": return "nivel insuficiente"
	return status


## Descricao de uma linha do no (nome, ranks, custo).
static func node_line(n: Dictionary, rank: int, depth: int) -> String:
	var tag: String = {"small": "", "notable": "* ", "mastery": "** "}.get(String(n["tier"]), "")
	return "%s%s%s  %d/%d  (custo %d)" % ["    ".repeat(mini(depth, 3)), tag, n["name"], rank, int(n["max_rank"]), int(n["cost"])]


# ------------------------------------------------------------------ estado

func reset() -> void:
	class_id = ""
	tree = null
	state = TalentState.new()
	level = 1
	points_total = 0
	points_spent = 0
	points_available = 0
	order = []
	selected = 0
	pending = false
	_pending_left = 0.0
	_confirm_left = 0.0
	set_status("")
	_rebuild()


## Aplica o estado autoritativo do servidor (`s_talents`/STATE) para a classe informada (s_class).
func apply_state(p_class_id: String, data: Dictionary, p_catalog: TalentCatalog = null) -> void:
	_catalog = p_catalog if p_catalog != null else TalentCatalog.shared()
	var new_tree: TalentTree = _catalog.get_tree(p_class_id)
	if new_tree != tree or class_id != p_class_id:
		class_id = p_class_id
		tree = new_tree
		order = display_order(tree) if tree != null else ([] as Array[String])
		selected = clampi(selected, 0, maxi(order.size() - 1, 0))
		_rebuild_rows()
	state = TalentState.new()
	if tree != null:
		state.restore({"spec": data.get("spec", ""), "ranks": data.get("ranks", {}), "respecs": data.get("respecs", 0)}, tree)
	level = int(data.get("level", 1))
	points_total = int(data.get("points_total", 0))
	points_spent = int(data.get("points_spent", 0))
	points_available = int(data.get("points_available", 0))
	pending = false
	_pending_left = 0.0
	_refresh()


func show_error(text: String) -> void:
	pending = false
	_pending_left = 0.0
	set_status(text, "bad")
	_refresh_buttons()


func selected_id() -> String:
	return order[selected] if selected >= 0 and selected < order.size() else ""


func _rebuild() -> void:
	order = display_order(tree) if tree != null else ([] as Array[String])
	_rebuild_rows()
	_refresh()


func _rebuild_rows() -> void:
	clear_children(list_box)
	_rows = []
	if tree == null:
		list_box.add_child(UiStyle.label("Sem arvore de talentos para esta classe.", UiStyle.TEXT_DIM, 0, true))
		return
	var last_group: String = "?"
	for i: int in order.size():
		var n: Dictionary = tree.nodes[order[i]]
		var g: String = String(n["spec"])
		if g != last_group:
			last_group = g
			var title: String = "Geral da classe" if g == "" else "Especializacao: " + _spec_name(g)
			list_box.add_child(UiStyle.label(title, UiStyle.INFO, 14))
		var b: Button = UiStyle.button("")
		b.name = "Node_" + order[i]
		b.clip_text = true
		b.pressed.connect(_select.bind(i))
		list_box.add_child(b)
		_rows.append(b)


func _spec_name(spec_id: String) -> String:
	var def: ClassDef = ClassCatalog.shared().get_def(class_id)
	if def != null:
		var s: Dictionary = def.get_specialization(spec_id)
		if not s.is_empty():
			return String(s["display_name"])
	return spec_id


func _select(i: int) -> void:
	if i < 0 or i >= order.size():
		return
	selected = i
	_refresh()


func _refresh() -> void:
	var spec_txt: String = "nenhuma" if state.spec_id == "" else _spec_name(state.spec_id)
	header.text = "Nivel %d  |  Pontos: %d disponiveis (%d gastos de %d)  |  Especializacao: %s" % [level, points_available, points_spent, points_total, spec_txt]
	for i: int in _rows.size():
		var id: String = order[i]
		var n: Dictionary = tree.nodes[id]
		var rank: int = state.rank_of(id)
		_rows[i].text = node_line(n, rank, tree.depth(id))
		var st: String = node_status(tree, state, level, _catalog, id)
		var col: Color = UiStyle.TEXT_DIM
		if rank >= int(n["max_rank"]):
			col = UiStyle.GOOD
		elif st == "available":
			col = UiStyle.ACCENT
		elif rank > 0:
			col = UiStyle.TEXT
		if i == selected:
			col = col.lightened(0.25)
		_rows[i].add_theme_color_override("font_color", col)
	_show_detail()
	_refresh_buttons()


func _show_detail() -> void:
	var id: String = selected_id()
	if tree == null or id.is_empty():
		detail_title.text = "Sem talentos"
		detail_desc.text = ""
		detail_info.text = ""
		return
	var n: Dictionary = tree.nodes[id]
	var rank: int = state.rank_of(id)
	detail_title.text = "%s  (%d/%d)" % [n["name"], rank, int(n["max_rank"])]
	detail_desc.text = String(n["description"])
	var lines: PackedStringArray = PackedStringArray()
	lines.append("Custo: %d ponto(s) por nivel" % int(n["cost"]))
	if not (n["requires"] as Array).is_empty():
		var names: PackedStringArray = PackedStringArray()
		for r: String in (n["requires"] as Array):
			var rn: Dictionary = tree.get_node_def(r)
			names.append("%s%s" % [rn.get("name", r), "" if state.rank_of(r) >= 1 else " (pendente)"])
		lines.append("Requer: " + ", ".join(names))
	if int(n["min_points_spent"]) > 0:
		lines.append("Requer %d pontos gastos (tem %d)" % [int(n["min_points_spent"]), points_spent])
	if int(n["min_level"]) > 1:
		lines.append("Nivel minimo: %d" % int(n["min_level"]))
	if String(n["spec"]) != "":
		lines.append("Especializacao: " + _spec_name(String(n["spec"])))
	lines.append("Estado: " + status_text(node_status(tree, state, level, _catalog, id)))
	detail_info.text = "\n".join(lines)


func _refresh_buttons() -> void:
	var id: String = selected_id()
	var can: bool = tree != null and not id.is_empty() and not pending \
		and node_status(tree, state, level, _catalog, id) == "available"
	btn_alloc.disabled = not can
	btn_spec.visible = tree != null and state.spec_id == "" and not tree.specs.is_empty()
	btn_spec.disabled = pending
	if btn_spec.visible:
		btn_spec.text = "Escolher: %s [S]" % _spec_name(tree.specs[0])
	btn_respec.disabled = pending or state.is_empty()
	var cost: PackedStringArray = PackedStringArray()
	if _catalog != null:
		for c: Dictionary in _catalog.respec_cost_items:
			cost.append(UiText.stack_text(String(c["item_id"]), int(c["qty"])))
	btn_respec.text = ("Confirmar reset? [R]" if _confirm_left > 0.0 else "Resetar talentos [R]") + ("  (custo: %s)" % ", ".join(cost) if not cost.is_empty() else "")


# ------------------------------------------------------------------ pedidos

func _begin_pending(text: String) -> void:
	pending = true
	_pending_left = PENDING_TIMEOUT
	set_status(text)
	_refresh_buttons()


func _request_allocate() -> void:
	var id: String = selected_id()
	if id.is_empty() or pending or not is_open() or node_status(tree, state, level, _catalog, id) != "available":
		return
	_begin_pending("Alocando...")
	allocate_requested.emit(id)


func _request_spec() -> void:
	if tree == null or pending or not is_open() or state.spec_id != "" or tree.specs.is_empty():
		return
	_begin_pending("Escolhendo especializacao...")
	spec_requested.emit(tree.specs[0])


## Reset total: pede confirmacao com um segundo toque dentro de CONFIRM_WINDOW (custo e zona segura sao decididos pelo servidor).
func _request_respec() -> void:
	if pending or not is_open() or state.is_empty():
		return
	if _confirm_left <= 0.0:
		_confirm_left = CONFIRM_WINDOW
		set_status("Resetar TODOS os talentos? Toque de novo para confirmar.", "bad")
		_refresh_buttons()
		return
	_confirm_left = 0.0
	_begin_pending("Resetando...")
	respec_requested.emit()


func advance(delta: float) -> void:
	if _confirm_left > 0.0:
		_confirm_left -= delta
		if _confirm_left <= 0.0:
			_confirm_left = 0.0
			set_status("")
			_refresh_buttons()
	if pending:
		_pending_left -= delta
		if _pending_left <= 0.0:
			show_error("Sem resposta do servidor.")


func handle_key(ev: InputEvent) -> bool:
	if not is_open():
		return false
	var n: int = step_index(ev, selected, order.size())
	if n >= 0:
		_select(n)
		return true
	if is_confirm(ev):
		_request_allocate()
		return true
	if UiStyle.key_pressed(ev, KEY_S, false):
		_request_spec()
		return true
	if UiStyle.key_pressed(ev, KEY_R, false):
		_request_respec()
		return true
	return false


func _on_open() -> void:
	_confirm_left = 0.0
	set_status("")
	_refresh()
