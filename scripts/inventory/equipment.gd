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


func _init(p_registry: ContentRegistry, p_inventory: Inventory) -> void:
	_registry = p_registry
	_inventory = p_inventory


func get_equipped(slot: int) -> StringName:
	return _equipped.get(slot, &"") as StringName


## Equipa 1 unidade de `item_id` vinda do inventario. Se o slot esta ocupado, o item
## anterior volta ao inventario; se nao couber, a operacao falha sem perder nada.
func equip(item_id: StringName) -> bool:
	last_error = ""
	var item: ItemData = _registry.get_item(item_id)
	if item == null:
		return _fail("item desconhecido")
	if not item.is_equippable() or not SLOTS.has(int(item.slot)):
		return _fail("item nao equipavel / slot invalido")
	if not _inventory.has_item(item_id):
		return _fail("item nao esta no inventario")
	var slot: int = int(item.slot)
	var previous: StringName = get_equipped(slot)
	var snap: Array[ItemStack] = _inventory.snapshot()
	_inventory.remove(item_id, 1)
	if previous != &"" and _inventory.add(previous, 1) > 0:
		_inventory.restore(snap)
		return _fail("inventario cheio para devolver o item anterior")
	_equipped[slot] = item_id
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
	if _inventory.add(current, 1) > 0:
		return _fail("inventario cheio")
	_equipped.erase(slot)
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
	return mods


func _fail(msg: String) -> bool:
	last_error = msg
	return false
