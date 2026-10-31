class_name StatCalculator
extends RefCounted
## Stats finais = base + bonus de nivel (opcional) + modificadores equipados.
## Nunca muta os blocos de entrada (usa StatBlock.combine).


static func compute(base: StatBlock, equipment: Equipment = null, progress: CharacterProgress = null) -> StatBlock:
	var mods: Array[StatBlock] = []
	if progress != null:
		mods.append(progress.level_bonus())
	if equipment != null:
		mods.append_array(equipment.get_modifiers())
	return StatBlock.combine(base, mods)
