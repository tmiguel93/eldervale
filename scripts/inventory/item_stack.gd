class_name ItemStack
extends RefCounted
## Pilha de um item num slot do inventario. Invariante: quantity >= 1.

var item_id: StringName = &""
var quantity: int = 0


static func make(p_item_id: StringName, p_quantity: int) -> ItemStack:
	var s: ItemStack = ItemStack.new()
	s.item_id = p_item_id
	s.quantity = p_quantity
	return s
