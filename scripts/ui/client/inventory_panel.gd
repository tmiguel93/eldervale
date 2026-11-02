class_name InventoryPanel
extends UiPanel
## E5.5: inventario/equipamento (I). Grade de slots (item + quantidade) a partir do ClientInventory.
## Enquanto o servidor nao enviou o inventario completo (`inventory.complete == false`, E5.6) mostra um aviso
## e os dados sao uma ESTIMATIVA da sessao.
## E6.3: itens com raridade/affixes mostram cor por raridade e tooltip com as linhas de affix; Enter pede ao servidor para EQUIPAR a
## pilha sob o cursor (a UI so envia o pedido; quem decide e o servidor) e 1/2/3 pedem para desequipar arma/armadura/amuleto.
## Teclado: setas movem o cursor; mouse: passar o cursor mostra o detalhe.

signal equip_requested(index: int, item_id: String)
signal unequip_requested(slot_index: int)

const COLUMNS: int = 5
const SLOT_SIZE: Vector2 = ItemSlot.SLOT_SIZE

var banner: Label
var grid: GridContainer
var detail: Label
var equip_row: VBoxContainer
var cursor: int = 0
var slot_buttons: Array[Button] = []
var equip_labels: Dictionary = {}
var equip_boxes: Dictionary = {}   ## slot -> {box: PanelContainer, icon: Control (holder)}
var _inv: ClientInventory = null
var _slot_data: Array[Dictionary] = []  ## por slot: {} ou {item_id, qty, inst?}


func _init() -> void:
	super._init("Inventário", Vector2(720, 470), "ᛒ", UiIcons.ref("ui", "inventory"))
	banner = UiStyle.label("", UiStyle.ACCENT, 13, true)
	body.add_child(banner)
	var main: HBoxContainer = HBoxContainer.new()
	main.add_theme_constant_override("separation", 18)
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(main)
	var left: VBoxContainer = VBoxContainer.new()
	left.add_theme_constant_override("separation", 4)
	main.add_child(left)
	var right: VBoxContainer = VBoxContainer.new()
	right.add_theme_constant_override("separation", 4)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.add_child(right)
	right.add_child(UiStyle.heading("Equipamento", UiStyle.INFO, 15))
	equip_row = VBoxContainer.new()
	equip_row.add_theme_constant_override("separation", 5)
	right.add_child(equip_row)
	for slot: String in ClientInventory.EQUIP_SLOTS:
		var pc: PanelContainer = PanelContainer.new()
		pc.add_theme_stylebox_override("panel", UiArt.slot(NorseTheme.GOLD_DIM))
		pc.custom_minimum_size = Vector2(0, 44)
		var hb: HBoxContainer = HBoxContainer.new()
		hb.add_theme_constant_override("separation", 6)
		pc.add_child(hb)
		var holder: Control = Control.new()
		holder.custom_minimum_size = Vector2(30, 30)
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(holder)
		var l: Label = UiStyle.label("", UiStyle.TEXT, 13)
		l.clip_text = true
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hb.add_child(l)
		equip_row.add_child(pc)
		equip_labels[slot] = l
		equip_boxes[slot] = {"box": pc, "icon": holder}
		_set_equip_icon(slot, "", {})
	left.add_child(UiStyle.heading("Mochila", UiStyle.INFO, 15))
	grid = GridContainer.new()
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", 5)
	grid.add_theme_constant_override("v_separation", 5)
	left.add_child(grid)
	for i: int in ClientInventory.SLOT_COUNT:
		var b: ItemSlot = ItemSlot.new()
		b.name = "Slot%d" % i
		b.pressed.connect(_set_cursor.bind(i))
		b.mouse_entered.connect(_set_cursor.bind(i))
		grid.add_child(b)
		slot_buttons.append(b)
	detail = UiStyle.label("", UiStyle.TEXT, 0, true)
	detail.custom_minimum_size = Vector2(230, 0)
	right.add_child(detail)
	hint_label.text = "I abre/fecha | Setas movem | Enter equipa | 1/2/3 desequipa | Esc fecha"
	refresh(null)


static func slot_label(item_id: String, qty: int) -> String:
	var n: String = UiText.item_name(item_id)
	return n if qty <= 1 else "%s\nx%d" % [n, qty]


func refresh(inv: ClientInventory) -> void:
	if inv != null:
		_inv = inv
	_slot_data = []
	var ents: Array[Dictionary] = _inv.slot_entries() if _inv != null else ([] as Array[Dictionary])
	for i: int in ClientInventory.SLOT_COUNT:
		if i < ents.size():
			_slot_data.append(ents[i])
			var inst: Dictionary = ents[i].get("inst", {}) as Dictionary
			slot_buttons[i].text = slot_label(String(ents[i]["item_id"]), int(ents[i]["qty"])) if inst.is_empty() else UiText.item_display(String(ents[i]["item_id"]), inst)
			slot_buttons[i].tooltip_text = UiText.item_tooltip(String(ents[i]["item_id"]), int(ents[i]["qty"]), inst)
			(slot_buttons[i] as ItemSlot).show_item(String(ents[i]["item_id"]), int(ents[i]["qty"]), UiText.rarity_of(String(ents[i]["item_id"]), inst), UiText.item_display(String(ents[i]["item_id"]), inst))
		else:
			_slot_data.append({})
			slot_buttons[i].text = ""
			slot_buttons[i].tooltip_text = ""
			(slot_buttons[i] as ItemSlot).show_item("", 0, "common", "")
	var complete: bool = _inv != null and _inv.complete
	banner.text = "" if complete else "Estimativa desta sessao: aguardando o inventario do servidor."
	banner.visible = not complete
	for slot: String in ClientInventory.EQUIP_SLOTS:
		var l: Label = equip_labels[slot]
		var eq: String = String(_inv.equipment.get(slot, "")) if _inv != null else ""
		var einst: Dictionary = (_inv.equipment_inst.get(slot, {}) as Dictionary) if _inv != null else {}
		var slot_name: String = {"weapon": "Arma", "armor": "Armadura", "trinket": "Amuleto"}[slot]
		l.text = "%s: %s" % [slot_name, UiText.item_display(eq, einst) if not eq.is_empty() else ("-" if complete else "?")]
		l.add_theme_color_override("font_color", UiText.rarity_color(eq, einst) if not eq.is_empty() else UiStyle.TEXT)
		l.tooltip_text = UiText.item_tooltip(eq, 1, einst) if not eq.is_empty() else ""
		_set_equip_icon(slot, eq, einst)
	if ents.is_empty():
		set_status("Mochila vazia." if complete else "Nenhum item obtido nesta sessao ainda.")
	else:
		set_status("")
	_set_cursor(clampi(cursor, 0, ClientInventory.SLOT_COUNT - 1))


func _set_cursor(i: int) -> void:
	cursor = clampi(i, 0, ClientInventory.SLOT_COUNT - 1)
	for k: int in slot_buttons.size():
		(slot_buttons[k] as ItemSlot).set_selected(k == cursor)
	var d: Dictionary = _slot_data[cursor] if cursor < _slot_data.size() else {}
	if d.is_empty():
		detail.text = "Slot %d: vazio" % (cursor + 1)
		detail.add_theme_color_override("font_color", UiStyle.TEXT)
		return
	var dinst: Dictionary = d.get("inst", {}) as Dictionary
	var tip: PackedStringArray = UiText.item_tooltip(String(d["item_id"]), int(d["qty"]), dinst).split("\n")
	detail.add_theme_color_override("font_color", UiText.rarity_color(String(d["item_id"]), dinst))
	var rest: PackedStringArray = tip.slice(1)
	rest.insert(0, "Slot %d: %s" % [cursor + 1, tip[0]])
	var base: ItemData = load(UiText.ITEMS_DIR + String(d["item_id"]) + ".tres") as ItemData if Protocol.is_content_id(d["item_id"]) and ResourceLoader.exists(UiText.ITEMS_DIR + String(d["item_id"]) + ".tres") else null
	if base != null and base.is_equippable() and _inv != null:
		var sn: String = String(ItemRules.SLOT_NAMES.get(int(base.slot), ""))
		var cur: String = String(_inv.equipment.get(sn, ""))
		rest.append("Equipado: %s" % (UiText.item_display(cur, _inv.equipment_inst.get(sn, {}) as Dictionary) if not cur.is_empty() else "nada"))
	detail.text = "\n".join(rest)


## E8.4: icone/borda do slot de equipamento (item equipado = icone na cor da raridade; vazio = icone do tipo, apagado).
func _set_equip_icon(slot: String, item_id: String, inst: Dictionary) -> void:
	var rec: Dictionary = equip_boxes.get(slot, {}) as Dictionary
	if rec.is_empty():
		return
	var holder: Control = rec["icon"]
	for ch: Node in holder.get_children():
		holder.remove_child(ch)
		ch.queue_free()
	var box: PanelContainer = rec["box"]
	if item_id.is_empty():
		holder.add_child(UiIcons.make(UiIcons.ref("equip_slots", slot), 28.0, Color(1, 1, 1, 0.28), slot))
		box.add_theme_stylebox_override("panel", UiArt.slot(NorseTheme.GOLD_DIM))
	else:
		var rid: String = UiText.rarity_of(item_id, inst)
		var col: Color = NorseTheme.rarity_color(rid)
		holder.add_child(UiIcons.make(UiIcons.item_ref(item_id), 28.0, col if rid != "common" else Color("#e6dcc6"), UiText.item_name(item_id)))
		box.add_theme_stylebox_override("panel", UiArt.slot(col, float(NorseTheme.RARITY_GLOW.get(rid, 0.0))))


## Texto exibido em um slot (para testes).
func slot_text(i: int) -> String:
	return slot_buttons[i].text if i >= 0 and i < slot_buttons.size() else ""


func handle_key(ev: InputEvent) -> bool:
	if not is_open():
		return false
	var c: int = cursor
	if UiStyle.key_pressed(ev, KEY_ENTER, false) or UiStyle.key_pressed(ev, KEY_KP_ENTER, false):
		var d: Dictionary = _slot_data[cursor] if cursor < _slot_data.size() else {}
		if not d.is_empty() and _inv != null and _inv.complete:
			equip_requested.emit(cursor, String(d["item_id"]))
		return true
	for n: int in 3:
		if UiStyle.key_pressed(ev, (KEY_1 + n) as Key, false):
			unequip_requested.emit(n)
			return true
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
