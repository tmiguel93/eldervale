class_name LootDrop
extends RefCounted
## Resultado de um roll de loot: item + quantidade.

var item_id: StringName = &""
var quantity: int = 0


static func make(p_item_id: StringName, p_quantity: int) -> LootDrop:
	var d: LootDrop = LootDrop.new()
	d.item_id = p_item_id
	d.quantity = p_quantity
	return d
