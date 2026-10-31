class_name ResourcePool
extends RefCounted
## Mana/stamina. Maximo e regen vem do StatBlock (max_resource / resource_regen por segundo).
## Chame tick(delta) a cada frame de fisica.

signal changed(current: float, maximum: float)
signal spent(amount: float)

var stats: StatBlock
var current: float = 0.0


func setup(p_stats: StatBlock, start_full: bool = true) -> void:
	stats = p_stats
	current = max_value() if start_full else 0.0
	changed.emit(current, max_value())


## Troca o StatBlock (ex.: equipamento mudou) mantendo o valor atual, limitado ao novo maximo.
func set_stats(p_stats: StatBlock) -> void:
	stats = p_stats
	var clamped: float = minf(current, max_value())
	if clamped != current:
		current = clamped
		changed.emit(current, max_value())


func max_value() -> float:
	return stats.max_resource if stats != null else 0.0


func can_afford(cost: float) -> bool:
	return cost >= 0.0 and cost <= current


## Gasta `cost`. Se insuficiente (ou custo negativo), retorna false SEM consumir nada.
func spend(cost: float) -> bool:
	if not can_afford(cost):
		return false
	if cost > 0.0:
		current -= cost
		spent.emit(cost)
		changed.emit(current, max_value())
	return true


func restore(amount: float) -> void:
	if amount <= 0.0:
		return
	var before: float = current
	current = minf(max_value(), current + amount)
	if current != before:
		changed.emit(current, max_value())


func tick(delta: float) -> void:
	if stats == null or delta <= 0.0 or current >= max_value():
		return
	restore(stats.resource_regen * delta)
