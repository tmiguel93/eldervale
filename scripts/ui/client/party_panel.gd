class_name PartyPanel
extends PanelContainer
## E5.5: lista de jogadores da sessao com vida, usando SO o que o snapshot ja traz (id, hp, max_hp) e os nomes
## dos eventos player_joined. O snapshot so inclui jogadores da MESMA zona (interesse por zona): quem esta em
## outra zona nao aparece. Sem rede nova.

const MAX_ROWS: int = 8

var _rows: Dictionary = {}  ## id -> {label, bar}
var _box: VBoxContainer
var _header: Label


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	add_theme_stylebox_override("panel", UiStyle.box(Color(0.07, 0.08, 0.11, 0.7), UiStyle.BORDER, 1, 6))
	_box = VBoxContainer.new()
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_theme_constant_override("separation", 3)
	add_child(_box)
	_header = UiStyle.label("Grupo", UiStyle.INFO, 13)
	_box.add_child(_header)


## Linhas do grupo a partir das entidades do snapshot: jogador local primeiro, depois por id. Funcao pura.
static func collect(entities: Array, local_id: int, names: Dictionary, local_name: String = "") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e0: Variant in entities:
		if typeof(e0) != TYPE_DICTIONARY:
			continue
		var e: Dictionary = e0
		if int(e.get("kind", 0)) != Protocol.KIND_PLAYER or not (e.has("id") and e.has("hp") and e.has("max_hp")):
			continue
		var id: int = int(e["id"])
		var is_local: bool = id == local_id
		var nm: String = (local_name if not local_name.is_empty() else "Voce") if is_local else String(names.get(id, "Jogador %d" % id))
		out.append({"id": id, "name": nm, "hp": float(e["hp"]), "max_hp": float(e["max_hp"]), "dead": float(e["hp"]) <= 0.0, "local": is_local})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if bool(a["local"]) != bool(b["local"]):
			return bool(a["local"])
		return int(a["id"]) < int(b["id"]))
	if out.size() > MAX_ROWS:
		out.resize(MAX_ROWS)
	return out


func row_count() -> int:
	return _rows.size()


func refresh(entities: Array, local_id: int, names: Dictionary, local_name: String = "") -> void:
	var data: Array[Dictionary] = collect(entities, local_id, names, local_name)
	visible = not data.is_empty()
	var keep: Dictionary = {}
	for d: Dictionary in data:
		var id: int = int(d["id"])
		keep[id] = true
		if not _rows.has(id):
			var l: Label = UiStyle.label("", UiStyle.TEXT, 13)
			var pb: ProgressBar = UiStyle.bar(190, 14, UiStyle.GOOD)
			_box.add_child(l)
			_box.add_child(pb)
			_rows[id] = {"label": l, "bar": pb}
		var row: Dictionary = _rows[id]
		var label: Label = row["label"]
		label.text = String(d["name"]) + (" (morto)" if bool(d["dead"]) else "")
		label.add_theme_color_override("font_color", UiStyle.TEXT_DIM if bool(d["dead"]) else (UiStyle.ACCENT if bool(d["local"]) else UiStyle.TEXT))
		UiStyle.set_bar(row["bar"] as ProgressBar, float(d["hp"]), float(d["max_hp"]), "%d / %d" % [int(ceilf(float(d["hp"]))), int(ceilf(float(d["max_hp"])))])
	for id2: Variant in _rows.keys():
		if not keep.has(id2):
			var r: Dictionary = _rows[id2]
			(r["label"] as Node).queue_free()
			(r["bar"] as Node).queue_free()
			_rows.erase(id2)
