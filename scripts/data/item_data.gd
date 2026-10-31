class_name ItemData
extends Resource
## Definicao estatica de item. `id` e estavel (nunca derivar do nome de exibicao).

enum Slot { NONE, WEAPON, ARMOR, TRINKET }
enum Rarity { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY }

@export var id: StringName = &""
@export var display_name: String = ""
@export var slot: Slot = Slot.NONE
@export var stackable: bool = false
@export var max_stack: int = 1
@export var rarity: Rarity = Rarity.COMMON
## Modificadores somados ao base quando equipado (blocos partem de zero, ver StatUtil.zero).
@export var stat_modifiers: StatBlock
## Marca conteudo de teste (AGENTS.md §8).
@export var placeholder: bool = false


## Tamanho efetivo de pilha: nao empilhaveis valem 1.
func effective_max_stack() -> int:
	return maxi(max_stack, 1) if stackable else 1


func is_equippable() -> bool:
	return slot != Slot.NONE
