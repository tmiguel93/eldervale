class_name BossBar
extends PanelContainer
## E5.5: barra de vida do chefe/mini-chefe quando ha um vivo no snapshot (inimigo com tier boss/mini_boss em
## EnemyData). Usa so campos ja replicados: hp, max_hp, type, phase. Fica restrita ao interesse (raio de 50 m).

var _name: Label
var _bar: ProgressBar
var _phase: Label
var current_id: int = -1


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	add_theme_stylebox_override("panel", UiStyle.box(Color(0.07, 0.05, 0.05, 0.85), UiStyle.HP_BOSS, 1, 6))
	var v: VBoxContainer = VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(v)
	var head: HBoxContainer = HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(head)
	_name = UiStyle.label("", UiStyle.HP_BOSS, 16)
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_name)
	_phase = UiStyle.label("", UiStyle.TEXT_DIM, 12)
	head.add_child(_phase)
	_bar = UiStyle.bar(420, 18, UiStyle.HP_BOSS)
	v.add_child(_bar)


## Escolhe o chefe vivo mais proximo de `from` (ou o primeiro). Devolve a entidade ou {}. Funcao pura.
static func pick_boss(entities: Array, from: Variant = null) -> Dictionary:
	var best: Dictionary = {}
	var best_d: float = INF
	for e0: Variant in entities:
		if typeof(e0) != TYPE_DICTIONARY:
			continue
		var e: Dictionary = e0
		if int(e.get("kind", 0)) != Protocol.KIND_ENEMY or float(e.get("hp", 0.0)) <= 0.0:
			continue
		var data: EnemyData = EnemyCatalog.data_for(StringName(String(e.get("type", ""))))
		if data == null or not data.is_boss():
			continue
		var d: float = 0.0
		if from is Vector3 and e.get("pos") is Vector3:
			d = Vector2((e["pos"] as Vector3).x - (from as Vector3).x, (e["pos"] as Vector3).z - (from as Vector3).z).length()
		if d < best_d:
			best_d = d
			best = e
	return best


func refresh(entities: Array, from: Variant = null) -> void:
	var boss: Dictionary = pick_boss(entities, from)
	visible = not boss.is_empty()
	if boss.is_empty():
		current_id = -1
		return
	current_id = int(boss["id"])
	_name.text = UiText.enemy_name(String(boss["type"]))
	_phase.text = "Fase %d" % (int(boss.get("phase", 0)) + 1) if boss.has("phase") else ""
	UiStyle.set_bar(_bar, float(boss["hp"]), float(boss["max_hp"]), "%d / %d" % [int(ceilf(float(boss["hp"]))), int(ceilf(float(boss["max_hp"])))])
