class_name ThreatTable
extends RefCounted
## Tabela de ameaca de UM inimigo: entity_id do jogador -> ameaca acumulada (dano causado).
## Pura e deterministica. A ameaca decai com o tempo (`decay`) para o alvo poder mudar.

const MIN_THREAT: float = 0.01

var values: Dictionary = {} ## int -> float


func add(entity_id: int, amount: float) -> void:
	if entity_id <= 0 or amount <= 0.0 or is_nan(amount) or is_inf(amount):
		return
	values[entity_id] = float(values.get(entity_id, 0.0)) + amount


func get_threat(entity_id: int) -> float:
	return float(values.get(entity_id, 0.0))


func remove(entity_id: int) -> void:
	values.erase(entity_id)


func clear() -> void:
	values.clear()


func is_empty() -> bool:
	return values.is_empty()


## Decaimento proporcional: cada valor perde `rate_per_sec * delta` (fracao). Remove o que zerou.
func decay(rate_per_sec: float, delta: float) -> void:
	if rate_per_sec <= 0.0 or delta <= 0.0 or values.is_empty():
		return
	var keep: float = maxf(0.0, 1.0 - rate_per_sec * delta)
	var dead: Array[int] = []
	for id: int in values:
		var v: float = float(values[id]) * keep
		if v < MIN_THREAT:
			dead.append(id)
		else:
			values[id] = v
	for id: int in dead:
		values.erase(id)
