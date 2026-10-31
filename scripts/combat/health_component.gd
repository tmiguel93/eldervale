class_name HealthComponent
extends Node
## Vida de uma entidade. Logica pura (sem UI). Usa StatBlock.max_health e defense/resistance.
## `died` dispara UMA vez ate reset(). `invulnerable` faz apply_damage retornar 0.

signal damaged(info: DamageInfo, final_amount: float)
signal healed(amount: float)
signal health_changed(current: float, maximum: float)
signal died(source: Node)

@export var stats: StatBlock

var current_health: float = 0.0
var invulnerable: bool = false
var is_dead: bool = false


func _ready() -> void:
	if stats != null:
		reset()


func max_health() -> float:
	return stats.max_health if stats != null else 1.0


## Aplica dano e devolve o valor final aplicado (0 se morto/invulneravel/info nula).
func apply_damage(info: DamageInfo) -> float:
	if info == null or is_dead or invulnerable:
		return 0.0
	var final_amount: float = DamageCalculator.from_info(info, stats)
	if final_amount <= 0.0:
		return 0.0
	current_health = maxf(0.0, current_health - final_amount)
	damaged.emit(info, final_amount)
	health_changed.emit(current_health, max_health())
	if current_health <= 0.0 and not is_dead:
		is_dead = true
		died.emit(info.source)
	return final_amount


## Cura ate max_health; devolve o quanto realmente curou. Morto nao e curado (use reset()).
func heal(amount: float) -> float:
	if is_dead or amount <= 0.0:
		return 0.0
	var before: float = current_health
	current_health = minf(max_health(), current_health + amount)
	var gained: float = current_health - before
	if gained > 0.0:
		healed.emit(gained)
		health_changed.emit(current_health, max_health())
	return gained


## Vida cheia, revive e remove invulnerabilidade.
func reset() -> void:
	is_dead = false
	invulnerable = false
	current_health = max_health()
	health_changed.emit(current_health, max_health())
