class_name ContentRegistry
extends RefCounted
## Registro de conteudo estatico. Carrega .tres de data/items, data/enemies, data/loot.
## `validate()` devolve lista de erros legiveis (vazia = conteudo consistente).

const ITEMS_DIR: String = "res://data/items"
const ENEMIES_DIR: String = "res://data/enemies"
const LOOT_DIR: String = "res://data/loot"

var items: Dictionary = {}    # StringName -> ItemData
var enemies: Dictionary = {}  # StringName -> EnemyData
var loot_tables: Dictionary = {}  # StringName -> LootTable
var _load_errors: Array[String] = []
var _dups: Array[String] = []


func load_all() -> void:
	for r: Resource in _load_dir(ITEMS_DIR):
		if r is ItemData:
			register_item(r)
		else:
			_load_errors.append("%s: nao e ItemData" % r.resource_path)
	for r: Resource in _load_dir(LOOT_DIR):
		if r is LootTable:
			register_loot_table(r)
		else:
			_load_errors.append("%s: nao e LootTable" % r.resource_path)
	for r: Resource in _load_dir(ENEMIES_DIR):
		if r is EnemyData:
			register_enemy(r)
		else:
			_load_errors.append("%s: nao e EnemyData" % r.resource_path)


func register_item(item: ItemData) -> void:
	if items.has(item.id):
		_dups.append("item id duplicado: '%s'" % item.id)
		return
	items[item.id] = item


func register_enemy(enemy: EnemyData) -> void:
	if enemies.has(enemy.id):
		_dups.append("enemy id duplicado: '%s'" % enemy.id)
		return
	enemies[enemy.id] = enemy


func register_loot_table(table: LootTable) -> void:
	if loot_tables.has(table.id):
		_dups.append("loot id duplicado: '%s'" % table.id)
		return
	loot_tables[table.id] = table


func get_item(id: StringName) -> ItemData:
	return items.get(id) as ItemData


func get_enemy(id: StringName) -> EnemyData:
	return enemies.get(id) as EnemyData


func get_loot_table(id: StringName) -> LootTable:
	return loot_tables.get(id) as LootTable


func validate() -> Array[String]:
	var errors: Array[String] = []
	errors.append_array(_load_errors)
	errors.append_array(_dups)
	for id: StringName in items:
		_validate_item(items[id] as ItemData, id, errors)
	for id: StringName in loot_tables:
		_validate_loot(loot_tables[id] as LootTable, id, errors)
	for id: StringName in enemies:
		_validate_enemy(enemies[id] as EnemyData, id, errors)
	return errors


func _validate_item(it: ItemData, key: StringName, errors: Array[String]) -> void:
	var tag: String = "item '%s'" % key
	if it.id == &"":
		errors.append(tag + ": id vazio")
	if it.max_stack < 1:
		errors.append(tag + ": max_stack < 1")
	if not it.stackable and it.max_stack > 1:
		errors.append(tag + ": nao empilhavel mas max_stack > 1")
	if it.stackable and it.max_stack < 2:
		errors.append(tag + ": empilhavel mas max_stack < 2")
	if not ItemData.Slot.values().has(int(it.slot)):
		errors.append(tag + ": slot invalido (%d)" % int(it.slot))
	if not ItemData.Rarity.values().has(int(it.rarity)):
		errors.append(tag + ": rarity invalida (%d)" % int(it.rarity))
	if it.stackable and it.slot != ItemData.Slot.NONE:
		errors.append(tag + ": empilhavel nao pode ter slot de equipamento")
	if it.slot != ItemData.Slot.NONE and it.stat_modifiers == null:
		errors.append(tag + ": equipavel sem stat_modifiers")
	if it.display_name.strip_edges() == "":
		errors.append(tag + ": display_name vazio")


func _validate_loot(t: LootTable, key: StringName, errors: Array[String]) -> void:
	var tag: String = "loot '%s'" % key
	if t.id == &"":
		errors.append(tag + ": id vazio")
	if t.rolls < 1:
		errors.append(tag + ": rolls < 1")
	if t.entries.is_empty():
		errors.append(tag + ": sem entradas")
	if t.nothing_weight < 0.0:
		errors.append(tag + ": nothing_weight negativo")
	if t.total_weight() <= 0.0 and not t.entries.is_empty():
		errors.append(tag + ": peso total <= 0")
	for e: LootEntry in t.entries:
		if e == null:
			errors.append(tag + ": entrada nula")
			continue
		if not items.has(e.item_id):
			errors.append("%s: item '%s' inexistente" % [tag, e.item_id])
		if e.weight < 0.0:
			errors.append("%s: peso negativo em '%s'" % [tag, e.item_id])
		if e.min_qty < 1 or e.max_qty < e.min_qty:
			errors.append("%s: faixa de quantidade invalida em '%s'" % [tag, e.item_id])


func _validate_enemy(en: EnemyData, key: StringName, errors: Array[String]) -> void:
	var tag: String = "enemy '%s'" % key
	if en.id == &"":
		errors.append(tag + ": id vazio")
	if en.stats == null:
		errors.append(tag + ": sem stats")
	elif en.stats.max_health <= 0.0:
		errors.append(tag + ": max_health <= 0")
	if en.xp_reward < 0:
		errors.append(tag + ": xp_reward negativo")
	if en.behavior != EnemyData.BEHAVIOR_MELEE and en.behavior != EnemyData.BEHAVIOR_RANGED:
		errors.append("%s: behavior invalido '%s'" % [tag, en.behavior])
	if en.behavior == EnemyData.BEHAVIOR_RANGED and en.projectile_speed <= 0.0:
		errors.append(tag + ": ranged exige projectile_speed > 0")
	if en.aggro_range <= 0.0 or en.attack_range <= 0.0 or en.attack_cooldown <= 0.0:
		errors.append(tag + ": aggro_range/attack_range/attack_cooldown devem ser > 0")
	if en.loot_table != null:
		if not loot_tables.has(en.loot_table.id):
			errors.append("%s: loot_table '%s' nao registrada" % [tag, en.loot_table.id])


static func _load_dir(path: String) -> Array[Resource]:
	var out: Array[Resource] = []
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return out
	var names: PackedStringArray = dir.get_files()
	var sorted: Array[String] = []
	for n: String in names:
		sorted.append(n.trim_suffix(".remap"))
	sorted.sort()
	for n: String in sorted:
		if n.ends_with(".tres"):
			var r: Resource = load(path + "/" + n)
			if r != null:
				out.append(r)
	return out
