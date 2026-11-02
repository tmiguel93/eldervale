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
	return clamp_final(StatBlock.combine(base, mods))


## E6.3: piso/teto sanitarios dos stats finais (itens/affixes nunca produzem NaN, negativos absurdos nem overflow). Muta e devolve `b`.
const CAPS: Dictionary = {
	"max_health": [1.0, 100000.0], "max_resource": [0.0, 100000.0], "resource_regen": [0.0, 1000.0], "attack_power": [0.0, 100000.0],
	"defense": [0.0, 100000.0], "resistance": [0.0, 0.75], "move_speed": [0.5, 15.0],
}


static func clamp_final(b: StatBlock) -> StatBlock:
	for key: String in CAPS:
		var lim: Array = CAPS[key]
		var v: float = float(b.get(key))
		if is_nan(v):
			v = float(lim[0])
		b.set(key, clampf(v, float(lim[0]), float(lim[1])))
	return b
