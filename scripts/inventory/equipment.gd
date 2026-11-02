class_name Equipment
extends RefCounted
## Itens equipados, um por slot (WEAPON/ARMOR/TRINKET). Opera sobre um Inventory.
## equip/unequip sao atomicos: em falha, inventario e equipamento ficam como antes.

signal equipment_changed(slot: int)

const SLOTS: Array[int] = [ItemData.Slot.WEAPON, ItemData.Slot.ARMOR, ItemData.Slot.TRINKET]

var last_error: String = ""
var _inventory: Inventory
var _registry: ContentRegistry
var _equipped: Dictionary = {}  # int slot -> StringName item_id
var _equipped_inst: Dictionary = {}  # E6.3: int slot -> Dictionary (instancia rolada; ausente = item simples)


func _init(p_registry: ContentRegistry, p_inventory: Inventory) -> void:
	_registry = p_registry
	_inventory = p_inventory


func get_equipped(slot: int) -> StringName:
	return _equipped.get(slot, &"") as StringName


## E6.3: instancia equipada no slot ({} = item simples/Comum ou slot vazio).
func get_equipped_instance(slot: int) -> Dictionary:
	return (_equipped_inst.get(slot, {}) as Dictionary).duplicate(true)


## Define o equipado diretamente (carregamento do personagem). `inst` vazio = item simples.
func set_equipped(slot: int, item_id: StringName, inst: Dictionary = {}) -> void:
	_equipped[slot] = item_id
	if inst.is_empty():
		_equipped_inst.erase(slot)
	else:
		_equipped_inst[slot] = inst.duplicate(true)


func clear_slot(slot: int) -> void:
	_equipped.erase(slot)
	_equipped_inst.erase(slot)


## E6.3: equipa a pilha do INDICE `index` do inventario (item simples ou instancia). O anterior volta ao inventario; atomico.
func equip_index(index: int) -> bool:
	last_error = ""
	var st: ItemStack = _inventory.stack_at(index)
	if st == null:
		return _fail("indice invalido")
	var item: ItemData = _registry.get_item(st.item_id)
	if item == null or not item.is_equippable() or not SLOTS.has(int(item.slot)):
		return _fail("item nao equipavel / slot invalido")
	if not st.inst.is_empty():
		var why: String = ItemRules.shared().validate_instance(st.inst, item)
		if not why.is_empty():
			return _fail("instancia invalida")
	var slot: int = int(item.slot)
	var previous: StringName = get_equipped(slot)
	var prev_inst: Dictionary = get_equipped_instance(slot)
	var snap: Array[ItemStack] = _inventory.snapshot()
	var taken: ItemStack = _inventory.take_at(index)
	if previous != &"" and not _return(previous, prev_inst):
		_inventory.restore(snap)
		return _fail("inventario cheio para devolver o item anterior")
	set_equipped(slot, taken.item_id, taken.inst)
	equipment_changed.emit(slot)
	return true


## Devolve ao inventario o item (simples ou instancia). false se nao coube.
func _return(item_id: StringName, inst: Dictionary) -> bool:
	if inst.is_empty():
		return _inventory.add(item_id, 1) == 0
	return _inventory.add_instance(item_id, inst)


## Equipa 1 unidade de `item_id` vinda do inventario. Se o slot esta ocupado, o item
## anterior volta ao inventario; se nao couber, a operacao falha sem perder nada.
func equip(item_id: StringName) -> bool:
	last_error = ""
	var item: ItemData = _registry.get_item(item_id)
	if item == null:
		return _fail("item desconhecido")
	if not item.is_equippable() or not SLOTS.has(int(item.slot)):
		return _fail("item nao equipavel / slot invalido")
	if _inventory.count_plain(item_id) < 1:
		return _fail("item nao esta no inventario")
	var slot: int = int(item.slot)
	var previous: StringName = get_equipped(slot)
	var prev_inst: Dictionary = get_equipped_instance(slot)
	var snap: Array[ItemStack] = _inventory.snapshot()
	_inventory.remove(item_id, 1)
	if previous != &"" and not _return(previous, prev_inst):
		_inventory.restore(snap)
		return _fail("inventario cheio para devolver o item anterior")
	set_equipped(slot, item_id)
	equipment_changed.emit(slot)
	return true


## Desequipa o slot devolvendo o item ao inventario (falha se cheio).
func unequip(slot: int) -> bool:
	last_error = ""
	if not SLOTS.has(slot):
		return _fail("slot invalido")
	var current: StringName = get_equipped(slot)
	if current == &"":
		return _fail("slot vazio")
	if not _return(current, get_equipped_instance(slot)):
		return _fail("inventario cheio")
	clear_slot(slot)
	equipment_changed.emit(slot)
	return true


## Modificadores dos itens equipados (ordem de SLOTS).
func get_modifiers() -> Array[StatBlock]:
	var mods: Array[StatBlock] = []
	for slot: int in SLOTS:
		var id: StringName = get_equipped(slot)
		if id == &"":
			continue
		var item: ItemData = _registry.get_item(id)
		if item != null and item.stat_modifiers != null:
			mods.append(item.stat_modifiers)
		var inst: Dictionary = _equipped_inst.get(slot, {}) as Dictionary
		if not inst.is_empty():
			mods.append(ItemRules.shared().stat_block(inst)) # E6.3: affixes de stat da instancia
	return mods


## E6.3: efeitos de habilidade dos equipados (affixes de skill_mod + efeito do item unico), no formato do SkillMods.
func get_skill_effects() -> Array:
	var out: Array = []
	var rules: ItemRules = ItemRules.shared()
	for slot: int in SLOTS:
		var id: StringName = get_equipped(slot)
		if id == &"":
			continue
		for fx: Variant in rules.unique_effects(String(id)):
			out.append((fx as Dictionary).duplicate(true))
		var inst: Dictionary = _equipped_inst.get(slot, {}) as Dictionary
		if not inst.is_empty():
			out.append_array(rules.skill_effects(inst))
	return out


func _fail(msg: String) -> bool:
	last_error = msg
	return false
