class_name SkillBar
extends PanelContainer
## E6.1: barra de habilidades da classe (so apresentacao). Mostra classe, recurso e as 4 habilidades dos slots com a tecla,
## o custo e o cooldown, lidos do catalogo LOCAL (data/classes + data/skills) para o `class_id` que o SERVIDOR informou (s_class).
## O cliente nao decide habilidades: a barra so reflete. Nunca instanciada em bot/headless (so pelo ClientUi).

const KEYS: Dictionary = {"attack": "LMB", "skill_1": "Q", "skill_2": "E", "dodge": "Espaco"}

var class_id: String = ""
var _title: Label
var _rows: Array[Label] = []


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	add_theme_stylebox_override("panel", UiStyle.box(Color(0.07, 0.08, 0.11, 0.7), UiStyle.BORDER, 1, 6))
	var v: VBoxContainer = VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(v)
	_title = UiStyle.label("", UiStyle.ACCENT, 14)
	v.add_child(_title)
	for _i: int in ClassDef.SLOTS.size():
		var l: Label = UiStyle.label("", UiStyle.TEXT, 13)
		v.add_child(l)
		_rows.append(l)


## Linhas {slot, key, skill_id, name, cost, cooldown} da classe. Funcao pura (vazia se a classe e desconhecida).
static func rows_for(p_class_id: String, catalog: ClassCatalog = null) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var cat: ClassCatalog = catalog if catalog != null else ClassCatalog.shared()
	var def: ClassDef = cat.get_def(p_class_id)
	if def == null:
		return out
	for slot: String in ClassDef.SLOTS:
		var skill: SkillData = ClassCatalog.load_skill(StringName(def.skills.get(slot, "")))
		if skill == null:
			continue
		out.append({"slot": slot, "key": String(KEYS.get(slot, "?")), "skill_id": String(skill.id), "name": skill.display_name,
			"cost": int(skill.resource_cost), "cooldown": skill.cooldown})
	return out


static func title_for(p_class_id: String, catalog: ClassCatalog = null) -> String:
	var cat: ClassCatalog = catalog if catalog != null else ClassCatalog.shared()
	var def: ClassDef = cat.get_def(p_class_id)
	return "" if def == null else "%s  (%s)" % [def.display_name, def.resource_label()]


func refresh(p_class_id: String) -> void:
	class_id = p_class_id
	var rows: Array[Dictionary] = rows_for(p_class_id)
	visible = not rows.is_empty()
	_title.text = title_for(p_class_id)
	for i: int in _rows.size():
		if i < rows.size():
			var r: Dictionary = rows[i]
			_rows[i].text = "[%s] %s  custo %d  rec. %.1fs" % [r["key"], r["name"], r["cost"], r["cooldown"]]
		else:
			_rows[i].text = ""
