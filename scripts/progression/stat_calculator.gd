class_name StatCalculator
extends RefCounted
## Stats finais = base + bonus de nivel (opcional) + modificadores equipados.
## Nunca muta os blocos de entrada (usa StatBlock.combine).


## E6.2: `talent_bonus` (opcional) = bonus de stats dos talentos alocados (SkillMods.collect(...)["stats"]).
static func compute(base: StatBlock, equipment: Equipment = null, progress: CharacterProgress = null, talent_bonus: StatBlock = null) -> StatBlock:
	var mods: Array[StatBlock] = []
	if progress != null:
		mods.append(progress.level_bonus())
	if equipment != null:
		mods.append_array(equipment.get_modifiers())
	if talent_bonus != null:
		mods.append(talent_bonus)
	return StatBlock.combine(base, mods)
