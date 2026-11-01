class_name CraftPanel
extends UiPanel
## E5.5: painel de crafting aberto ao interagir com a estacao. Lista as receitas da estacao (data/recipes),
## ingredientes/resultados e o botao Fabricar. Emite `craft_requested(recipe_id)`; o resultado chega por
## `show_result` (craft_finished do servidor). Sem inventario completo no cliente, nao ha como saber se o
## jogador tem os ingredientes: o servidor responde `insufficient_ingredients` (mostrado em texto).

signal craft_requested(recipe_id: String)

const PENDING_TIMEOUT: float = 6.0

var station_id: String = ""
var station_name: String = ""
var recipes: Array[RecipeDef] = []
var selected: int = 0
var pending: bool = false
var list_box: VBoxContainer
var detail_title: Label
var detail_ing: Label
var detail_res: Label
var btn_craft: Button
var _rows: Array[Button] = []
var _pending_left: float = 0.0
var _inv: ClientInventory = null


func _init() -> void:
	super._init("Bancada", Vector2(660, 380))
	var split: HBoxContainer = HBoxContainer.new()
	split.add_theme_constant_override("separation", 12)
	body.add_child(split)
	list_box = VBoxContainer.new()
	list_box.custom_minimum_size = Vector2(250, 0)
	split.add_child(list_box)
	var right: VBoxContainer = VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 6)
	split.add_child(right)
	detail_title = UiStyle.label("", UiStyle.ACCENT, 17, true)
	right.add_child(detail_title)
	detail_ing = UiStyle.label("", UiStyle.TEXT, 0, true)
	right.add_child(detail_ing)
	detail_res = UiStyle.label("", UiStyle.GOOD, 0, true)
	right.add_child(detail_res)
	btn_craft = UiStyle.button("Fabricar [Enter]")
	btn_craft.name = "CraftButton"
	btn_craft.pressed.connect(_request)
	right.add_child(btn_craft)
	hint_label.text = "Cima/Baixo seleciona | Enter fabrica | F ou Esc fecha"


## Receitas de uma estacao (ordenadas por id). Funcao pura.
static func recipes_for(station: String, catalog: RecipeCatalog) -> Array[RecipeDef]:
	var out: Array[RecipeDef] = []
	for id: String in catalog.ids():
		var r: RecipeDef = catalog.get_recipe(id)
		if r.station == station:
			out.append(r)
	return out


func open_station(p_station_id: String, p_name: String, catalog: RecipeCatalog = null, inv: ClientInventory = null) -> void:
	station_id = p_station_id
	station_name = p_name
	title_label.text = p_name if not p_name.is_empty() else "Bancada"
	recipes = recipes_for(p_station_id, catalog if catalog != null else RecipeCatalog.shared())
	_inv = inv
	selected = 0
	pending = false
	_pending_left = 0.0
	set_status("")
	_rebuild()
	open()


func set_inventory(inv: ClientInventory) -> void:
	_inv = inv
	_show_detail()


func selected_recipe() -> RecipeDef:
	return recipes[selected] if selected >= 0 and selected < recipes.size() else null


func _rebuild() -> void:
	clear_children(list_box)
	_rows = []
	if recipes.is_empty():
		list_box.add_child(UiStyle.label("Esta estacao nao tem receitas.", UiStyle.TEXT_DIM, 0, true))
	for i: int in recipes.size():
		var b: Button = UiStyle.button(recipes[i].display_name)
		b.name = "Recipe_" + recipes[i].id
		b.clip_text = true
		b.pressed.connect(_select.bind(i))
		list_box.add_child(b)
		_rows.append(b)
	_paint()
	_show_detail()


func _paint() -> void:
	for i: int in _rows.size():
		_rows[i].add_theme_color_override("font_color", UiStyle.ACCENT if i == selected else UiStyle.TEXT)


func _select(i: int) -> void:
	if i < 0 or i >= recipes.size():
		return
	selected = i
	_paint()
	_show_detail()


func _show_detail() -> void:
	var r: RecipeDef = selected_recipe()
	btn_craft.disabled = r == null or pending
	if r == null:
		detail_title.text = "Sem receitas"
		detail_ing.text = ""
		detail_res.text = ""
		return
	detail_title.text = r.display_name
	var lines: PackedStringArray = PackedStringArray(["Ingredientes:"])
	for i: Dictionary in r.ingredients:
		var line: String = "  " + UiText.stack_text(String(i["item_id"]), int(i["qty"]))
		if _inv != null and _inv.complete:
			line += "  (tem %d)" % _inv.count(String(i["item_id"]))
		lines.append(line)
	detail_ing.text = "\n".join(lines)
	detail_res.text = "Resultado: " + UiText.stacks_text(r.results)


func _request() -> void:
	var r: RecipeDef = selected_recipe()
	if r == null or pending or not is_open():
		return
	pending = true
	_pending_left = PENDING_TIMEOUT
	btn_craft.disabled = true
	set_status("Fabricando...")
	craft_requested.emit(r.id)


## Resposta do servidor (craft_finished). `ok` com results, ou erro com code.
func show_result(ok: bool, data: Dictionary) -> void:
	pending = false
	_pending_left = 0.0
	if ok:
		set_status("Fabricado: " + UiText.stacks_text(data.get("results", [])), "good")
	else:
		set_status(UiText.craft_error(String(data.get("code", ""))), "bad")
	_show_detail()


## Falha local ao enviar (sem conexao).
func show_send_failed() -> void:
	pending = false
	_pending_left = 0.0
	set_status("Sem conexao com o servidor.", "bad")
	_show_detail()


func advance(delta: float) -> void:
	if pending:
		_pending_left -= delta
		if _pending_left <= 0.0:
			pending = false
			set_status("Sem resposta do servidor. Tente de novo.", "bad")
			_show_detail()


func close() -> void:
	super.close()
	pending = false


func handle_key(ev: InputEvent) -> bool:
	if not is_open():
		return false
	var n: int = step_index(ev, selected, recipes.size())
	if n >= 0:
		_select(n)
		return true
	if is_confirm(ev):
		_request()
		return true
	return false
