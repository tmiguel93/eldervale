class_name DamageCalculator
extends RefCounted
## Formula de dano pura.
##   bruto  = amount * (CRIT_MULTIPLIER se critico, senao 1)
##   final  = max(0, (bruto - defense) * (1 - resistance))
## Se amount > 0, o resultado nunca fica abaixo de `min_damage` (padrao MIN_DAMAGE = 1.0),
## entao defesa alta nunca zera um golpe valido. amount <= 0 sempre resulta em 0.
## `resistance` e limitado a 0..1 aqui (o StatBlock ja limita a 0.75 ao somar).

const MIN_DAMAGE: float = 1.0
const CRIT_MULTIPLIER: float = 1.5


static func compute(amount: float, defense: float, resistance: float, is_critical: bool = false, min_damage: float = MIN_DAMAGE) -> float:
	if amount <= 0.0:
		return 0.0
	var raw: float = amount * (CRIT_MULTIPLIER if is_critical else 1.0)
	var res: float = clampf(resistance, 0.0, 1.0)
	var result: float = maxf(0.0, (raw - defense) * (1.0 - res))
	return maxf(result, maxf(min_damage, 0.0))


static func from_info(info: DamageInfo, target_stats: StatBlock) -> float:
	var defense: float = 0.0
	var resistance: float = 0.0
	if target_stats != null:
		defense = target_stats.defense
		resistance = target_stats.resistance
	return compute(info.amount, defense, resistance, info.is_critical)
