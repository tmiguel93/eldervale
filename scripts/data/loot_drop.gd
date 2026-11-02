class_name LootDrop
extends RefCounted
## Resultado de um roll de loot: item + quantidade.

var item_id: StringName = &""
var quantity: int = 0
## E6.3: instancia rolada (raridade/affixes) quando o drop e um equipamento nao Comum; vazio = item simples. Sempre quantity 1.
var inst: Dictionary = {}


static func make(p_item_id: StringName, p_quantity: int, p_inst: Dictionary = {}) -> LootDrop:
	var d: LootDrop = LootDrop.new()
	d.item_id = p_item_id
	d.quantity = p_quantity
	d.inst = p_inst.duplicate(true)
	return d
