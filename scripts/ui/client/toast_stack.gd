class_name ToastStack
extends VBoxContainer
## E5.5: avisos curtos (loot, quests, zona, morte). Empilha ate MAX_VISIBLE; cada toast some sozinho
## (fade nos ultimos FADE s). Mensagem repetida enquanto visivel apenas renova o tempo. Tempo avancado por
## `advance(delta)` (deterministico nos testes).

const MAX_VISIBLE: int = 5
const DEFAULT_TTL: float = 4.0
const FADE: float = 0.6

var _items: Array[Dictionary] = []  ## {text, node, ttl, life}


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	alignment = BoxContainer.ALIGNMENT_END
	add_theme_constant_override("separation", 4)


static func color_for(kind: String) -> Color:
	match kind:
		"good": return UiStyle.GOOD
		"bad": return UiStyle.BAD
		"loot": return UiStyle.ACCENT
		"quest": return UiStyle.INFO
	return UiStyle.TEXT


func push(text: String, kind: String = "info", ttl: float = DEFAULT_TTL) -> void:
	var t: String = UiText.clamp_text(text, UiText.MAX_TOAST)
	if t.is_empty():
		return
	for it: Dictionary in _items:
		if String(it["text"]) == t:
			it["life"] = ttl
			it["ttl"] = ttl
			(it["node"] as Control).modulate.a = 1.0
			return
	var pc: PanelContainer = PanelContainer.new()
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.add_theme_stylebox_override("panel", UiStyle.box(Color(0.07, 0.08, 0.11, 0.88), color_for(kind), 1, 6))
	var l: Label = UiStyle.label(t, color_for(kind), 15)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pc.add_child(l)
	add_child(pc)
	_items.append({"text": t, "node": pc, "ttl": ttl, "life": ttl})
	while _items.size() > MAX_VISIBLE:
		_drop(0)


func count() -> int:
	return _items.size()


func texts() -> Array[String]:
	var out: Array[String] = []
	for it: Dictionary in _items:
		out.append(String(it["text"]))
	return out


func clear_all() -> void:
	while not _items.is_empty():
		_drop(0)


func _drop(i: int) -> void:
	var node: Node = _items[i]["node"]
	_items.remove_at(i)
	if is_instance_valid(node):
		remove_child(node)
		node.queue_free()


func advance(delta: float) -> void:
	var i: int = 0
	while i < _items.size():
		var it: Dictionary = _items[i]
		it["life"] = float(it["life"]) - delta
		if float(it["life"]) <= 0.0:
			_drop(i)
			continue
		(it["node"] as Control).modulate.a = clampf(float(it["life"]) / FADE, 0.0, 1.0)
		i += 1
