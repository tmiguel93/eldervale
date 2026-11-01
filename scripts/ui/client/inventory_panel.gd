class_name InventoryPanel
extends UiPanel
## E5.5: inventario/equipamento (I). Grade de slots (item + quantidade) a partir do ClientInventory.
## Enquanto o servidor nao envia o inventario completo (`inventory.complete == false`) mostra um aviso
## e os dados sao uma ESTIMATIVA da sessao. Sem comandos de equipar/usar (o protocolo ainda nao tem).
## Teclado: setas movem o cursor; mouse: passar o cursor mostra o detalhe.

const COLUMNS: int = 5
const SLOT_SIZE: Vector2 = Vector2(86, 58)

var banner: Label
var grid: GridContainer
var detail: Label
var equip_row: HBoxContainer
var cursor: int = 0
var slot_buttons: Array[Button] = []
var equip_labels: Dictionary = {}
var _inv: ClientInventory = null
var _slot_data: Array[Dictionary] = []  ## por slot: {} ou {item_id, qty}


func _init() -> void:
	super._init("Inventario", Vector2(520, 470))
	banner = UiStyle.label("", UiStyle.ACCENT, 13, true)
	body.add_child(banner)
	body.add_child(UiStyle.label("Equipamento", UiStyle.INFO, 13))
	equip_row = HBoxContainer.new()
	equip_row.add_theme_constant_override("separation", 6)
	body.add_child(equip_row)
	for slot: String in ClientInventory.EQUIP_SLOTS:
		var pc: PanelContainer = PanelContainer.new()
		pc.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.BG_SOFT, UiStyle.BORDER, 1, 4))
		pc.custom_minimum_size = Vector2(150, 34)
		var l: Label = UiStyle.label("", UiStyle.TEXT, 13)
		l.clip_text = true
		pc.add_child(l)
		equip_row.add_child(pc)
		equip_labels[slot] = l
	body.add_child(UiStyle.label("Mochila", UiStyle.INFO, 13))
	grid = GridContainer.new()
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	body.add_child(grid)
	for i: int in ClientInventory.SLOT_COUNT:
		var b: Button = UiStyle.button("")
		b.name = "Slot%d" % i
		b.custom_minimum_size = SLOT_SIZE
		b.clip_text = true
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.pressed.connect(_set_cursor.bind(i))
		b.mouse_entered.connect(_set_cursor.bind(i))
		grid.add_child(b)
		slot_buttons.append(b)
	detail = UiStyle.label("", UiStyle.TEXT, 0, true)
	body.add_child(detail)
	hint_label.text = "I abre/fecha | Setas movem o cursor | Esc fecha"
	refresh(null)


static func slot_label(item_id: String, qty: int) -> String:
	var n: String = UiText.item_name(item_id)
	return n if qty <= 1 else "%s\nx%d" % [n, qty]


func refresh(inv: ClientInventory) -> void:
	if inv != null:
		_inv = inv
	_slot_data = []
	var ents: Array[Dictionary] = _inv.entries() if _inv != null else ([] as Array[Dictionary])
	for i: int in ClientInventory.SLOT_COUNT:
		if i < ents.size():
			_slot_data.append(ents[i])
			slot_buttons[i].text = slot_label(String(ents[i]["item_id"]), int(ents[i]["qty"]))
			slot_buttons[i].tooltip_text = UiText.stack_text(String(ents[i]["item_id"]), int(ents[i]["qty"]))
		else:
			_slot_data.append({})
			slot_buttons[i].text = ""
			slot_buttons[i].tooltip_text = ""
	var complete: bool = _inv != null and _inv.complete
	banner.text = "" if complete else "Estimativa desta sessao: o inventario completo ainda nao e sincronizado pelo servidor (itens de antes do login nao aparecem)."
	banner.visible = not complete
	for slot: String in ClientInventory.EQUIP_SLOTS:
		var l: Label = equip_labels[slot]
		var eq: String = String(_inv.equipment.get(slot, "")) if _inv != null else ""
		var slot_name: String = {"weapon": "Arma", "armor": "Armadura", "trinket": "Amuleto"}[slot]
		l.text = "%s: %s" % [slot_name, UiText.item_name(eq) if not eq.is_empty() else ("-" if complete else "?")]
	if ents.is_empty():
		set_status("Mochila vazia." if complete else "Nenhum item obtido nesta sessao ainda.")
	else:
		set_status("")
	_set_cursor(clampi(cursor, 0, ClientInventory.SLOT_COUNT - 1))


func _set_cursor(i: int) -> void:
	cursor = clampi(i, 0, ClientInventory.SLOT_COUNT - 1)
	for k: int in slot_buttons.size():
		slot_buttons[k].add_theme_color_override("font_color", UiStyle.ACCENT if k == cursor else UiStyle.TEXT)
	var d: Dictionary = _slot_data[cursor] if cursor < _slot_data.size() else {}
	detail.text = "Slot %d: vazio" % (cursor + 1) if d.is_empty() else "Slot %d: %s" % [cursor + 1, UiText.stack_text(String(d["item_id"]), int(d["qty"]))]


## Texto exibido em um slot (para testes).
func slot_text(i: int) -> String:
	return slot_buttons[i].text if i >= 0 and i < slot_buttons.size() else ""


func handle_key(ev: InputEvent) -> bool:
	if not is_open():
		return false
	var c: int = cursor
	if UiStyle.key_pressed(ev, KEY_LEFT):
		c = maxi(c - 1, 0)
	elif UiStyle.key_pressed(ev, KEY_RIGHT):
		c = mini(c + 1, ClientInventory.SLOT_COUNT - 1)
	elif UiStyle.key_pressed(ev, KEY_UP):
		c = c - COLUMNS if c - COLUMNS >= 0 else c
	elif UiStyle.key_pressed(ev, KEY_DOWN):
		c = c + COLUMNS if c + COLUMNS < ClientInventory.SLOT_COUNT else c
	else:
		return false
	_set_cursor(c)
	return true
