class_name TargetSelector
extends RefCounted
## Escolha PURA do alvo de um inimigo entre jogadores VIVOS.
## Regra: 1) quem tem mais ameaca (entre os candidatos a ate `max_distance` do inimigo), com
## histerese (`stickiness`: o alvo atual so e trocado por quem tiver ameaca > atual * stickiness);
## 2) sem ameaca valida: o mais proximo (empate: menor id). Sem candidatos: 0.
## Candidatos: Array de Dictionary {id: int, pos: Vector3} (so vivos).

const DEFAULT_STICKINESS: float = 1.25


static func pick(candidates: Array, enemy_pos: Vector3, threat: ThreatTable, current_id: int = 0,
		max_distance: float = INF, stickiness: float = DEFAULT_STICKINESS) -> int:
	if candidates.is_empty():
		return 0
	var best_threat_id: int = 0
	var best_threat: float = 0.0
	var current_threat: float = 0.0
	var nearest_id: int = 0
	var nearest_d: float = INF
	for c: Dictionary in candidates:
		var cid: int = int(c["id"])
		var d: float = _flat_dist(c["pos"] as Vector3, enemy_pos)
		if d < nearest_d or (is_equal_approx(d, nearest_d) and cid < nearest_id):
			nearest_d = d
			nearest_id = cid
		if threat == null or d > max_distance:
			continue
		var t: float = threat.get_threat(cid)
		if cid == current_id:
			current_threat = t
		if t > best_threat or (is_equal_approx(t, best_threat) and t > 0.0 and cid < best_threat_id):
			best_threat = t
			best_threat_id = cid
	if best_threat_id == 0:
		return nearest_id
	if current_id != 0 and current_id != best_threat_id and current_threat > 0.0 \
			and best_threat <= current_threat * stickiness:
		return current_id
	return best_threat_id


static func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
