class_name AreaWatcher
extends RefCounted
## Detecta ENTRADA em areas para UM jogador: `update(pos)` devolve as areas em que ele entrou desde
## a ultima chamada (borda fora->dentro). Logica pura; a posicao vem do servidor, nunca do cliente.

var _set: AreaSet
var _inside: Dictionary = {} ## area_id -> true


func _init(p_set: AreaSet) -> void:
	_set = p_set


func update(pos: Vector3) -> Array[String]:
	var entered: Array[String] = []
	for id: String in _set.ids():
		var inside: bool = _set.contains(id, pos)
		if inside and not _inside.has(id):
			entered.append(id)
		if inside:
			_inside[id] = true
		else:
			_inside.erase(id)
	return entered


func is_inside(area_id: String) -> bool:
	return _inside.has(area_id)
