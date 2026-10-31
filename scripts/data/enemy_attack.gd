class_name EnemyAttack
extends Resource
## Definicao de UM ataque de inimigo (dados). Usado por EnemyData.attacks / EnemyPhase.attacks.
## O ataque comeca com telegrafo de `windup` s (inimigo parado), libera uma vez e entra em
## `cooldown` (pausa global antes de QUALQUER novo ataque); `own_cooldown` e a recarga so deste ataque.
## Geometria (referencial do inimigo, -Z = frente):
##  MELEE      caixa `width` x `max_range` a frente.
##  AOE        cilindro de `radius` centrado a `aoe_offset` m a frente (0 = em volta do inimigo).
##  PROJECTILE `projectile_count` projeteis, abertos em `spread_degrees` no total.
##  CHARGE     avanca `charge_distance` m a `charge_speed` m/s; a caixa `width` da dano uma vez.
##  SUMMON     invoca `summon_count` de `summon_id` (limites `summon_max_alive` / `summon_max_total`).

enum Kind { MELEE, AOE, PROJECTILE, CHARGE, SUMMON }

@export var id: StringName = &""
@export var kind: Kind = Kind.MELEE
@export var windup: float = 0.45
@export var cooldown: float = 1.5
@export var own_cooldown: float = 0.0
@export var damage_multiplier: float = 1.0
## Distancia ao alvo em que o ataque PODE ser iniciado.
@export var min_range: float = 0.0
@export var max_range: float = 2.0
@export var weight: float = 1.0
@export var width: float = 1.6
@export var radius: float = 2.0
@export var aoe_offset: float = 0.0
@export var projectile_count: int = 1
@export var spread_degrees: float = 0.0
@export var projectile_speed: float = 12.0
@export var charge_distance: float = 0.0
@export var charge_speed: float = 0.0
@export var summon_id: StringName = &""
@export var summon_count: int = 0
@export var summon_max_alive: int = 0 ## 0 = sem limite de vivos
@export var summon_max_total: int = 0 ## 0 = sem limite no encontro
@export var telegraph_color: Color = Color(0.9, 0.15, 0.1, 0.45)

const MAX_PROJECTILES: int = 12
const MAX_SPREAD: float = 180.0


func is_damaging() -> bool:
	return kind != Kind.SUMMON


## Lista de erros legiveis (vazia = valido). `known_enemy_ids` (opcional) valida summon_id.
func validate(known_enemy_ids: Array = []) -> Array[String]:
	var errs: Array[String] = []
	var tag: String = "attack '%s'" % id
	if id == &"":
		errs.append("attack sem id")
	if windup <= 0.0:
		errs.append(tag + ": windup deve ser > 0 (telegrafo obrigatorio)")
	if cooldown < 0.0 or own_cooldown < 0.0:
		errs.append(tag + ": cooldown negativo")
	if weight < 0.0:
		errs.append(tag + ": weight negativo")
	if min_range < 0.0 or max_range < min_range or max_range <= 0.0:
		errs.append(tag + ": faixa de alcance invalida")
	if is_damaging() and damage_multiplier <= 0.0:
		errs.append(tag + ": damage_multiplier deve ser > 0")
	match kind:
		Kind.MELEE:
			if width <= 0.0:
				errs.append(tag + ": MELEE exige width > 0")
		Kind.AOE:
			if radius <= 0.0:
				errs.append(tag + ": AOE exige radius > 0")
		Kind.PROJECTILE:
			if projectile_count < 1 or projectile_count > MAX_PROJECTILES:
				errs.append(tag + ": projectile_count fora de 1..%d" % MAX_PROJECTILES)
			if spread_degrees < 0.0 or spread_degrees > MAX_SPREAD:
				errs.append(tag + ": spread_degrees fora de 0..%d" % int(MAX_SPREAD))
			if projectile_speed <= 0.0:
				errs.append(tag + ": PROJECTILE exige projectile_speed > 0")
		Kind.CHARGE:
			if charge_distance <= 0.0 or charge_speed <= 0.0 or width <= 0.0:
				errs.append(tag + ": CHARGE exige charge_distance, charge_speed e width > 0")
		Kind.SUMMON:
			if summon_id == &"" or summon_count < 1:
				errs.append(tag + ": SUMMON exige summon_id e summon_count >= 1")
			elif not known_enemy_ids.is_empty() and not known_enemy_ids.has(summon_id):
				errs.append("%s: summon_id '%s' inexistente" % [tag, summon_id])
			if summon_max_total > 0 and summon_max_total < summon_count:
				errs.append(tag + ": summon_max_total < summon_count")
		_:
			errs.append(tag + ": kind invalido")
	return errs
