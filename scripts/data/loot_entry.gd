class_name LootEntry
extends Resource
## Entrada de uma LootTable: item, peso relativo e faixa de quantidade.

@export var item_id: StringName = &""
@export var weight: float = 1.0
@export var min_qty: int = 1
@export var max_qty: int = 1
