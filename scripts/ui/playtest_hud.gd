class_name PlaytestHud
extends CanvasLayer
## UI minima de playtest. SOMENTE le o estado do jogador (vida, recurso, XP, cooldowns, inventario)
## e chama a API publica do PlayerLoadout para equipar/desequipar. Nenhuma logica de combate
## depende dela (pode nem existir). Controles (Input Map): I alterna inventario; 1-9 equipa a pilha
## correspondente (com inventario aberto); X/C/V desequipam arma/armadura/amuleto; R reinicia
## (so apos a morte). Texto/barras sao placeholders sem arte.

signal restart_requested

var player: Player
var loadout: PlayerLoadout
var combat: PlayerCombat
var health: HealthComponent

var hp_bar: ProgressBar
var res_bar: ProgressBar
var info_label: Label
var skills_label: Label
var inventory_panel: PanelContainer
var inventory_label: Label
var death_label: Label
var message_label: Label

var _message_left: float = 0.0


func setup(p_player: Player) -> void:
	player = p_player
	combat = player.get_node_or_null("Combat") as PlayerCombat
	loadout = player.get_node_or_null("Loadout") as PlayerLoadout
	health = player.get_node_or_null("Health") as HealthComponent
	if combat == null or loadout == null or health == null:
		push_error("PlaytestHud: jogador sem Combat/Loadout/Health.")
		return
	loadout.inventory_message.connect(show_message)
	health.died.connect(func(_s: Node) -> void: death_label.visible = true)
	_build()


func _build() -> void:
	var box: VBoxContainer = VBoxContainer.new()
	box.position = Vector2(12, 34)
	box.custom_minimum_size = Vector2(300, 0)
	add_child(box)
	hp_bar = _make_bar(Color(0.8, 0.2, 0.2))
	res_bar = _make_bar(Color(0.25, 0.45, 0.9))
	box.add_child(hp_bar)
	box.add_child(res_bar)
	info_label = Label.new()
	box.add_child(info_label)
	skills_label = Label.new()
	box.add_child(skills_label)

	inventory_panel = PanelContainer.new()
	inventory_panel.visible = false
	inventory_panel.position = Vector2(12, 250)
	inventory_label = Label.new()
	inventory_panel.add_child(inventory_label)
	add_child(inventory_panel)

	death_label = Label.new()
	death_label.visible = false
	death_label.text = "VOCE MORREU\nPressione R para reiniciar"
	death_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	death_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	death_label.add_theme_font_size_override("font_size", 36)
	add_child(death_label)

	message_label = Label.new()
	message_label.position = Vector2(12, 520)
	add_child(message_label)


func _make_bar(color: Color) -> ProgressBar:
	var bar: ProgressBar = ProgressBar.new()
	bar.custom_minimum_size = Vector2(280, 18)
	bar.show_percentage = true
	var fill: StyleBoxFlat = StyleBoxFlat.new()
	fill.bg_color = color
	bar.add_theme_stylebox_override("fill", fill)
	return bar


func show_message(text: String) -> void:
	if message_label != null:
		message_label.text = text
		_message_left = 2.5


func _process(delta: float) -> void:
	if health == null or hp_bar == null:
		return
	hp_bar.max_value = health.max_health()
	hp_bar.value = health.current_health
	res_bar.max_value = maxf(combat.resource_pool.max_value(), 1.0)
	res_bar.value = combat.resource_pool.current
	info_label.text = build_info_text()
	skills_label.text = build_skills_text()
	if inventory_panel.visible:
		inventory_label.text = build_inventory_text()
	if _message_left > 0.0:
		_message_left -= delta
		if _message_left <= 0.0:
			message_label.text = ""


func build_info_text() -> String:
	var p: CharacterProgress = loadout.progress
	var next: int = CharacterProgress.xp_to_next(p.level)
	var xp_part: String = "XP %d/%d" % [p.xp_in_level(), next] if next > 0 else "XP (nivel max.)"
	return "Nivel %d  %s\nVida %d/%d  Recurso %d/%d  ATK %.1f" % [
		p.level, xp_part, int(health.current_health), int(health.max_health()),
		int(combat.resource_pool.current), int(combat.resource_pool.max_value()),
		health.stats.attack_power]


func build_skills_text() -> String:
	var rows: Array[String] = []
	var defs: Array = [["LMB", combat.basic_attack], ["Q", combat.skill_1], ["E", combat.skill_2], ["Espaco", combat.dodge_skill]]
	for d: Array in defs:
		var skill: SkillData = d[1] as SkillData
		if skill == null:
			continue
		var left: float = combat.cooldowns.remaining(skill.id)
		var state: String = "pronto" if left <= 0.0 else "%.1fs" % left
		rows.append("[%s] %s (custo %d): %s" % [d[0], skill.display_name, int(skill.resource_cost), state])
	return "\n".join(rows)


func build_inventory_text() -> String:
	var lines: Array[String] = ["INVENTARIO (I fecha)  [1-9 equipa | X arma, C armadura, V amuleto desequipam]"]
	var contents: Array[Dictionary] = loadout.inventory.contents()
	for i: int in contents.size():
		lines.append("%d. %s x%d" % [i + 1, contents[i]["id"], contents[i]["qty"]])
	if contents.is_empty():
		lines.append("(vazio)")
	lines.append("Pilhas %d/%d" % [loadout.inventory.stack_count(), loadout.inventory.capacity])
	lines.append("Arma: %s" % _equipped_name(ItemData.Slot.WEAPON))
	lines.append("Armadura: %s" % _equipped_name(ItemData.Slot.ARMOR))
	lines.append("Amuleto: %s" % _equipped_name(ItemData.Slot.TRINKET))
	return "\n".join(lines)


func _equipped_name(slot: int) -> String:
	var id: StringName = loadout.equipment.get_equipped(slot)
	return String(id) if id != &"" else "-"


func _unhandled_input(event: InputEvent) -> void:
	if loadout == null:
		return
	if event.is_action_pressed(&"restart") and health.is_dead:
		restart_requested.emit()
		return
	if event.is_action_pressed(&"inventory_toggle"):
		inventory_panel.visible = not inventory_panel.visible
		return
	if not inventory_panel.visible or health.is_dead:
		return
	for i: int in range(1, 10):
		if event.is_action_pressed(StringName("inventory_slot_%d" % i)):
			loadout.equip_from_index(i - 1)
			return
	if event.is_action_pressed(&"unequip_weapon"):
		loadout.unequip_slot(ItemData.Slot.WEAPON)
	elif event.is_action_pressed(&"unequip_armor"):
		loadout.unequip_slot(ItemData.Slot.ARMOR)
	elif event.is_action_pressed(&"unequip_trinket"):
		loadout.unequip_slot(ItemData.Slot.TRINKET)
