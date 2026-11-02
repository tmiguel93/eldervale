class_name ItemStack
extends RefCounted
## Pilha de um item num slot do inventario. Invariante: quantity >= 1.
## E6.3: `inst` (Dictionary, ver ItemRules) vazio = item simples/Comum (empilha normalmente); nao vazio = instancia rolada com
## raridade/affixes (sempre quantity 1, nunca empilha, identidade por `inst.uid`).

var item_id: StringName = &""
var quantity: int = 0
var inst: Dictionary = {}


static func make(p_item_id: StringName, p_quantity: int, p_inst: Dictionary = {}) -> ItemStack:
	var s: ItemStack = ItemStack.new()
	s.item_id = p_item_id
	s.quantity = p_quantity
	s.inst = p_inst.duplicate(true)
	return s
