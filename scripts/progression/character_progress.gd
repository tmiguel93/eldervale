class_name CharacterProgress
extends RefCounted
## XP e nivel. Curva: XP para sair do nivel L para L+1 = round(XP_BASE * L^XP_EXPONENT)
## (100, 283, 520, 800, ...). Nivel maximo MAX_LEVEL; em MAX_LEVEL o XP total fica
## saturado no minimo necessario para o nivel maximo (nao acumula alem disso).

signal leveled_up(new_level: int, levels_gained: int)

const XP_BASE: float = 100.0
const XP_EXPONENT: float = 1.5
const MAX_LEVEL: int = 50
## Teto por concessao: protege contra overflow de int64 ao somar.
const MAX_GRANT: int = 1_000_000_000

var level: int = 1
var total_xp: int = 0
## Bonus por nivel acima do 1 (partem de zero). Ajustavel por dados no futuro.
var bonus_per_level: StatBlock


func _init() -> void:
	bonus_per_level = StatUtil.zero()
	bonus_per_level.max_health = 10.0
	bonus_per_level.max_resource = 3.0
	bonus_per_level.attack_power = 1.0
	bonus_per_level.defense = 0.25


## XP necessario para ir do nivel `lvl` ao proximo. 0 se lvl >= MAX_LEVEL; lvl<1 trata como 1.
static func xp_to_next(lvl: int) -> int:
	if lvl >= MAX_LEVEL:
		return 0
	return int(roundf(XP_BASE * pow(float(maxi(lvl, 1)), XP_EXPONENT)))


## XP total acumulado necessario para ATINGIR `lvl` (nivel 1 = 0).
static func total_xp_for_level(lvl: int) -> int:
	var t: int = 0
	for l: int in range(1, mini(lvl, MAX_LEVEL)):
		t += xp_to_next(l)
	return t


## XP acumulado dentro do nivel atual.
func xp_in_level() -> int:
	return total_xp - total_xp_for_level(level)


## Soma XP. Valores <= 0 sao ignorados. Retorna quantos niveis subiu (emite leveled_up uma vez).
func add_xp(amount: int) -> int:
	if amount <= 0:
		return 0
	var cap_total: int = total_xp_for_level(MAX_LEVEL)
	total_xp = mini(total_xp + mini(amount, MAX_GRANT), cap_total)
	var old: int = level
	while level < MAX_LEVEL and total_xp >= total_xp_for_level(level + 1):
		level += 1
	var gained: int = level - old
	if gained > 0:
		leveled_up.emit(level, gained)
	return gained


## Bonus acumulado = bonus_per_level * (level - 1), novo bloco a cada chamada.
func level_bonus() -> StatBlock:
	return StatUtil.scaled(bonus_per_level, float(level - 1))
