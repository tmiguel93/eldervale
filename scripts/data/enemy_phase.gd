class_name EnemyPhase
extends Resource
## Fase de um inimigo (chefe/mini-chefe). A fase `i` fica ativa quando vida/vida_maxima <=
## `health_threshold` (a fase 0 usa 1.0). Fases so avancam (monotonico) ate o reset do encontro.
## Ao ENTRAR (indice > 0): fica `transition_time` s parado e invulneravel (rugido), aplica os
## multiplicadores e invoca `summon_count` de `summon_id` (adds opcionais).

@export var id: StringName = &""
@export var health_threshold: float = 1.0
@export var attacks: Array[EnemyAttack] = []
@export var speed_mult: float = 1.0
@export var damage_mult: float = 1.0
## < 1 = ataca com mais frequencia (multiplica as pausas entre ataques).
@export var cooldown_mult: float = 1.0
@export var transition_time: float = 0.0
@export var summon_id: StringName = &""
@export var summon_count: int = 0

const MAX_TRANSITION: float = 3.0


func validate(known_enemy_ids: Array = []) -> Array[String]:
	var errs: Array[String] = []
	var tag: String = "phase '%s'" % id
	if id == &"":
		errs.append("phase sem id")
	if health_threshold <= 0.0 or health_threshold > 1.0:
		errs.append(tag + ": health_threshold fora de (0, 1]")
	if attacks.is_empty():
		errs.append(tag + ": sem ataques")
	if speed_mult <= 0.0 or damage_mult <= 0.0 or cooldown_mult <= 0.0:
		errs.append(tag + ": multiplicadores devem ser > 0")
	if transition_time < 0.0 or transition_time > MAX_TRANSITION:
		errs.append(tag + ": transition_time fora de 0..%.0f s" % MAX_TRANSITION)
	if summon_count < 0 or (summon_count > 0 and summon_id == &""):
		errs.append(tag + ": summon_count/summon_id inconsistentes")
	if summon_count > 0 and not known_enemy_ids.is_empty() and not known_enemy_ids.has(summon_id):
		errs.append("%s: summon_id '%s' inexistente" % [tag, summon_id])
	for a: EnemyAttack in attacks:
		if a == null:
			errs.append(tag + ": ataque nulo")
		else:
			errs.append_array(a.validate(known_enemy_ids))
	return errs
