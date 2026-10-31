class_name CooldownTracker
extends RefCounted
## Cooldown por id de habilidade (StringName). tick(delta) a cada frame de fisica.

signal cooldown_finished(id: StringName)

var _remaining: Dictionary = {} ## StringName -> float


func start(id: StringName, seconds: float) -> void:
	if seconds > 0.0:
		_remaining[id] = seconds
	else:
		_remaining.erase(id)


func is_ready(id: StringName) -> bool:
	return not _remaining.has(id)


func remaining(id: StringName) -> float:
	return float(_remaining.get(id, 0.0))


func clear() -> void:
	_remaining.clear()


func tick(delta: float) -> void:
	if delta <= 0.0 or _remaining.is_empty():
		return
	var finished: Array[StringName] = []
	for id: StringName in _remaining.keys():
		var left: float = float(_remaining[id]) - delta
		if left <= 0.0:
			finished.append(id)
		else:
			_remaining[id] = left
	for id: StringName in finished:
		_remaining.erase(id)
		cooldown_finished.emit(id)
