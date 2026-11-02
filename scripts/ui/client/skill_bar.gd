class_name SkillBar
extends PanelContainer
## E6.1/E8.4: hotbar de habilidades da classe (so apresentacao). Mostra classe, recurso e os 4 slots (SkillSlot) com icone, tecla, custo e
## recarga radial, lidos do catalogo LOCAL (data/classes + data/skills) para o `class_id` que o SERVIDOR informou (s_class). O cliente nao
## decide habilidades: a barra so reflete. A recarga e uma estimativa visual (ver SkillSlot). Nunca instanciada em bot/headless.

const KEYS: Dictionary = {"attack": "LMB", "skill_1": "Q", "skill_2": "E", "dodge": "Espaco"}
const ACTION_BITS: Dictionary = {"attack": 1, "skill_1": 2, "skill_2": 4, "dodge": 8}

var class_id: String = ""
var slots: Array[SkillSlot] = []
var _title: Label
var _class_icon: Control
var _head: HBoxContainer
var _row: HBoxContainer
var _prev_bits: int = 0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	theme_type_variation = &"HudPanel"
	var v: VBoxContainer = VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 4)
	add_child(v)
	_head = HBoxContainer.new()
	_head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_head.alignment = BoxContainer.ALIGNMENT_CENTER
	_head.add_theme_constant_override("separation", 6)
	v.add_child(_head)
	_title = UiStyle.label("", UiStyle.ACCENT, 14, false, "heading")
	_head.add_child(_title)
	_row = HBoxContainer.new()
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_theme_constant_override("separation", 8)
	v.add_child(_row)
	for _i: int in ClassDef.SLOTS.size():
		var s: SkillSlot = SkillSlot.new()
		_row.add_child(s)
		slots.append(s)


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
	if _class_icon != null:
		_head.remove_child(_class_icon)
		_class_icon.queue_free()
		_class_icon = null
	if not rows.is_empty():
		_class_icon = UiIcons.make(UiIcons.class_ref(p_class_id), 22.0, UiStyle.ACCENT, p_class_id)
		_head.add_child(_class_icon)
		_head.move_child(_class_icon, 0)
	for i: int in slots.size():
		if i < rows.size():
			var r: Dictionary = rows[i]
			var tip: String = "%s\nCusto %d - recarga %.1f s\nTecla: %s" % [r["name"], r["cost"], r["cooldown"], r["key"]]
			slots[i].setup(String(r["slot"]), String(r["skill_id"]), String(r["key"]), int(r["cost"]), float(r["cooldown"]), tip)
			slots[i].visible = true
		else:
			slots[i].clear()
			slots[i].visible = false


## Textos das teclas/habilidades (para testes).
func slot_summary() -> Array[String]:
	var out: Array[String] = []
	for s: SkillSlot in slots:
		if s.visible and not s.skill_id.is_empty():
			out.append("%s:%s" % [s.key_text, s.skill_id])
	return out


## Acoes locais enviadas (bits do c_input): a borda de subida de cada tecla inicia a recarga estimada do slot.
func note_actions(bits: int) -> void:
	var rising: int = bits & ~_prev_bits
	_prev_bits = bits
	if rising == 0:
		return
	for s: SkillSlot in slots:
		if s.slot.is_empty():
			continue
		if (rising & int(ACTION_BITS.get(s.slot, 0))) != 0:
			s.start_cooldown()


func advance(delta: float) -> void:
	for s: SkillSlot in slots:
		s.advance(delta)
