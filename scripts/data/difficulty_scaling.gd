class_name DifficultyScaling
extends Resource
## Escala de dificuldade por numero de jogadores (dados em data/difficulty/*.tres). Funcoes puras:
##   health = min(max_health_mult, 1 + bonus_vida * (n - 1))   (n em 1..max_players)
##   damage = min(max_damage_mult, 1 + bonus_dano * (n - 1))
## Chefes e mini-chefes usam o bonus de vida `boss_health_bonus_per_player`. Os tetos impedem que
## a escala ultrapasse valores controlados mesmo com dados mal editados.

const DEFAULT_PATH: String = "res://data/difficulty/greenwood_coop.tres"
const TIER_NORMAL: StringName = &"normal"
const TIER_MINI_BOSS: StringName = &"mini_boss"
const TIER_BOSS: StringName = &"boss"
## Tetos absolutos do codigo (a validacao rejeita dados acima).
const HARD_MAX_HEALTH_MULT: float = 6.0
const HARD_MAX_DAMAGE_MULT: float = 2.0

@export var id: StringName = &"greenwood_coop"
@export var max_players: int = 4
@export var health_bonus_per_player: float = 0.5
@export var boss_health_bonus_per_player: float = 0.75
@export var damage_bonus_per_player: float = 0.1
@export var max_health_mult: float = 3.5
@export var max_damage_mult: float = 1.35


static func load_default() -> DifficultyScaling:
	var r: DifficultyScaling = load(DEFAULT_PATH) as DifficultyScaling
	return r if r != null else DifficultyScaling.new()


static func is_boss_tier(tier: StringName) -> bool:
	return tier == TIER_BOSS or tier == TIER_MINI_BOSS


func clamp_players(players: int) -> int:
	return clampi(players, 1, maxi(max_players, 1))


func health_mult(players: int, tier: StringName = TIER_NORMAL) -> float:
	var extra: int = clamp_players(players) - 1
	var bonus: float = boss_health_bonus_per_player if is_boss_tier(tier) else health_bonus_per_player
	return clampf(1.0 + bonus * float(extra), 1.0, minf(max_health_mult, HARD_MAX_HEALTH_MULT))


func damage_mult(players: int, _tier: StringName = TIER_NORMAL) -> float:
	var extra: int = clamp_players(players) - 1
	return clampf(1.0 + damage_bonus_per_player * float(extra), 1.0, minf(max_damage_mult, HARD_MAX_DAMAGE_MULT))


func validate() -> Array[String]:
	var errs: Array[String] = []
	if max_players < 1 or max_players > 8:
		errs.append("difficulty: max_players fora de 1..8")
	if health_bonus_per_player < 0.0 or boss_health_bonus_per_player < 0.0 or damage_bonus_per_player < 0.0:
		errs.append("difficulty: bonus negativo")
	if max_health_mult < 1.0 or max_health_mult > HARD_MAX_HEALTH_MULT:
		errs.append("difficulty: max_health_mult fora de 1..%.1f" % HARD_MAX_HEALTH_MULT)
	if max_damage_mult < 1.0 or max_damage_mult > HARD_MAX_DAMAGE_MULT:
		errs.append("difficulty: max_damage_mult fora de 1..%.1f" % HARD_MAX_DAMAGE_MULT)
	return errs
