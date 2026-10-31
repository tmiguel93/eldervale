extends SceneTree
## Gera o conteudo PLACEHOLDER em data/. Rodar uma vez (apos --import):
##   $G --headless --path . --script res://scripts/data/content_generator.gd
## Edite aqui e regenere, ou edite os .tres direto. Tudo e PLACEHOLDER de teste.


func _initialize() -> void:
	var ok: bool = true
	var mods: Dictionary = {
		&"sword_basic": _mod({"attack_power": 5.0}),
		&"sword_rare": _mod({"attack_power": 12.0, "move_speed": 0.3}),
		&"armor_leather": _mod({"defense": 3.0, "max_health": 15.0}),
		&"armor_heavy": _mod({"defense": 8.0, "max_health": 30.0, "move_speed": -0.5}),
		&"amulet_vigor": _mod({"max_health": 20.0, "resource_regen": 1.0, "resistance": 0.05}),
	}
	ok = _item(&"sword_basic", "Espada Simples [PLACEHOLDER]", ItemData.Slot.WEAPON, false, 1, ItemData.Rarity.COMMON, mods[&"sword_basic"]) and ok
	ok = _item(&"sword_rare", "Espada Rara [PLACEHOLDER]", ItemData.Slot.WEAPON, false, 1, ItemData.Rarity.RARE, mods[&"sword_rare"]) and ok
	ok = _item(&"armor_leather", "Armadura de Couro [PLACEHOLDER]", ItemData.Slot.ARMOR, false, 1, ItemData.Rarity.COMMON, mods[&"armor_leather"]) and ok
	ok = _item(&"armor_heavy", "Armadura Pesada [PLACEHOLDER]", ItemData.Slot.ARMOR, false, 1, ItemData.Rarity.UNCOMMON, mods[&"armor_heavy"]) and ok
	ok = _item(&"amulet_vigor", "Amuleto do Vigor [PLACEHOLDER]", ItemData.Slot.TRINKET, false, 1, ItemData.Rarity.UNCOMMON, mods[&"amulet_vigor"]) and ok
	ok = _item(&"potion_minor", "Pocao Menor [PLACEHOLDER]", ItemData.Slot.NONE, true, 20, ItemData.Rarity.COMMON, null) and ok
	ok = _item(&"scrap_material", "Sucata [PLACEHOLDER]", ItemData.Slot.NONE, true, 50, ItemData.Rarity.COMMON, null) and ok

	var grunt_loot: LootTable = _loot(&"loot_melee_grunt", 1, 40.0, [
		_entry(&"scrap_material", 40.0, 1, 3), _entry(&"potion_minor", 20.0, 1, 1),
		_entry(&"sword_basic", 5.0, 1, 1), _entry(&"armor_leather", 5.0, 1, 1)])
	var caster_loot: LootTable = _loot(&"loot_ranged_caster", 2, 30.0, [
		_entry(&"potion_minor", 30.0, 1, 2), _entry(&"amulet_vigor", 6.0, 1, 1),
		_entry(&"sword_rare", 1.5, 1, 1), _entry(&"armor_heavy", 3.0, 1, 1)])
	ok = _save(grunt_loot, "res://data/loot/loot_melee_grunt.tres") and ok
	ok = _save(caster_loot, "res://data/loot/loot_ranged_caster.tres") and ok

	# Recarrega do disco para os inimigos referenciarem o .tres externo (nao sub-recurso embutido).
	grunt_loot = load("res://data/loot/loot_melee_grunt.tres") as LootTable
	caster_loot = load("res://data/loot/loot_ranged_caster.tres") as LootTable

	var g: EnemyData = EnemyData.new()
	g.id = &"melee_grunt"
	g.display_name = "Bruto [PLACEHOLDER]"
	g.stats = _stats(60.0, 0.0, 0.0, 8.0, 1.0, 0.0, 3.5)
	g.xp_reward = 40
	g.loot_table = grunt_loot
	g.behavior = EnemyData.BEHAVIOR_MELEE
	g.aggro_range = 10.0
	g.attack_range = 1.8
	g.attack_cooldown = 1.4
	g.attack_damage_multiplier = 1.0
	g.projectile_speed = 0.0
	g.placeholder = true
	ok = _save(g, "res://data/enemies/melee_grunt.tres") and ok

	var c: EnemyData = EnemyData.new()
	c.id = &"ranged_caster"
	c.display_name = "Conjurador [PLACEHOLDER]"
	c.stats = _stats(40.0, 0.0, 0.0, 10.0, 0.0, 0.0, 3.0)
	c.xp_reward = 60
	c.loot_table = caster_loot
	c.behavior = EnemyData.BEHAVIOR_RANGED
	c.aggro_range = 14.0
	c.attack_range = 9.0
	c.attack_cooldown = 2.2
	c.attack_damage_multiplier = 1.2
	c.projectile_speed = 12.0
	c.placeholder = true
	ok = _save(c, "res://data/enemies/ranged_caster.tres") and ok

	print("GERADO: ", "OK" if ok else "COM ERROS")
	quit(0 if ok else 1)


func _mod(values: Dictionary) -> StatBlock:
	var b: StatBlock = StatUtil.zero()
	for k: String in values:
		b.set(k, values[k])
	return b


func _stats(hp: float, res: float, regen: float, atk: float, def: float, resist: float, spd: float) -> StatBlock:
	var b: StatBlock = StatUtil.zero()
	b.max_health = hp
	b.max_resource = res
	b.resource_regen = regen
	b.attack_power = atk
	b.defense = def
	b.resistance = resist
	b.move_speed = spd
	return b


func _entry(item_id: StringName, weight: float, mn: int, mx: int) -> LootEntry:
	var e: LootEntry = LootEntry.new()
	e.item_id = item_id
	e.weight = weight
	e.min_qty = mn
	e.max_qty = mx
	return e


func _loot(id: StringName, rolls: int, nothing: float, entries: Array[LootEntry]) -> LootTable:
	var t: LootTable = LootTable.new()
	t.id = id
	t.rolls = rolls
	t.nothing_weight = nothing
	t.entries = entries
	t.placeholder = true
	return t


func _item(id: StringName, name: String, slot: ItemData.Slot, stackable: bool, max_stack: int, rarity: ItemData.Rarity, mod: StatBlock) -> bool:
	var it: ItemData = ItemData.new()
	it.id = id
	it.display_name = name
	it.slot = slot
	it.stackable = stackable
	it.max_stack = max_stack
	it.rarity = rarity
	it.stat_modifiers = mod
	it.placeholder = true
	return _save(it, "res://data/items/%s.tres" % id)


func _save(res: Resource, path: String) -> bool:
	var err: int = ResourceSaver.save(res, path)
	if err != OK:
		printerr("falha ao salvar ", path, " erro ", err)
	return err == OK
