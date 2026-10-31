extends RefCounted
## Conteudo real carrega e valida; validacao detecta dados sinteticos quebrados.


func _item(id: StringName, slot: int = ItemData.Slot.NONE, stackable: bool = false, max_stack: int = 1) -> ItemData:
	var it: ItemData = ItemData.new()
	it.id = id
	it.display_name = String(id)
	it.slot = slot as ItemData.Slot
	it.stackable = stackable
	it.max_stack = max_stack
	it.stat_modifiers = StatUtil.zero()
	return it


func _has_err(errors: Array[String], needle: String) -> bool:
	for e: String in errors:
		if e.contains(needle):
			return true
	return false


func run(ctx: Object) -> void:
	var reg: ContentRegistry = ContentRegistry.new()
	reg.load_all()
	var errs: Array[String] = reg.validate()
	for e: String in errs:
		print("    erro: ", e)
	ctx.check(errs.is_empty(), "conteudo real: 0 erros de validacao")
	ctx.check(reg.items.size() == 7, "conteudo real: 7 itens (%d)" % reg.items.size())
	ctx.check(reg.enemies.size() == 10, "conteudo real: 10 inimigos (2 do E2 + 8 do E5.2)")
	ctx.check(reg.loot_tables.size() == 10, "conteudo real: 10 tabelas de loot")
	var sw: ItemData = reg.get_item(&"sword_rare")
	ctx.check(sw != null and sw.slot == ItemData.Slot.WEAPON and sw.rarity == ItemData.Rarity.RARE and sw.placeholder, "sword_rare carregou com slot/raridade/placeholder")
	ctx.check(sw != null and is_equal_approx(sw.stat_modifiers.attack_power, 12.0) and is_equal_approx(sw.stat_modifiers.max_health, 0.0), "sword_rare: modificador parte de zero")
	var pot: ItemData = reg.get_item(&"potion_minor")
	ctx.check(pot != null and pot.stackable and pot.max_stack == 20, "potion_minor empilhavel max 20")
	var g: EnemyData = reg.get_enemy(&"melee_grunt")
	var c: EnemyData = reg.get_enemy(&"ranged_caster")
	ctx.check(g != null and g.behavior == &"melee" and g.loot_table != null and g.loot_table.id == &"loot_melee_grunt", "melee_grunt: behavior e loot_table")
	ctx.check(c != null and c.behavior == &"ranged" and c.projectile_speed > 0.0 and c.xp_reward > 0, "ranged_caster: behavior, projetil, xp")

	# Dados quebrados sinteticos
	var bad: ContentRegistry = ContentRegistry.new()
	bad.register_item(_item(&"a"))
	bad.register_item(_item(&"a"))  # duplicado
	bad.register_item(_item(&"zero_stack", ItemData.Slot.NONE, true, 0))
	bad.register_item(_item(&"incons", ItemData.Slot.NONE, false, 5))
	bad.register_item(_item(&"badslot", 99))
	var noeq: ItemData = _item(&"noeq", ItemData.Slot.WEAPON)
	noeq.stat_modifiers = null
	bad.register_item(noeq)
	var lt: LootTable = LootTable.new()
	lt.id = &"lt_bad"
	var le: LootEntry = LootEntry.new()
	le.item_id = &"ghost_item"
	lt.entries = [le] as Array[LootEntry]
	bad.register_loot_table(lt)
	var en: EnemyData = EnemyData.new()
	en.id = &"en_bad"
	en.stats = StatUtil.zero()
	var orphan: LootTable = LootTable.new()
	orphan.id = &"orphan_loot"
	en.loot_table = orphan
	bad.register_enemy(en)
	var berrs: Array[String] = bad.validate()
	ctx.check(_has_err(berrs, "item id duplicado: 'a'"), "detecta id duplicado")
	ctx.check(_has_err(berrs, "'zero_stack': max_stack < 1"), "detecta max_stack < 1")
	ctx.check(_has_err(berrs, "'incons': nao empilhavel mas max_stack > 1"), "detecta stackable inconsistente")
	ctx.check(_has_err(berrs, "'badslot': slot invalido"), "detecta slot invalido")
	ctx.check(_has_err(berrs, "'noeq': equipavel sem stat_modifiers"), "detecta equipavel sem modificadores")
	ctx.check(_has_err(berrs, "item 'ghost_item' inexistente"), "detecta loot -> item quebrado")
	ctx.check(_has_err(berrs, "loot_table 'orphan_loot' nao registrada"), "detecta inimigo -> loot quebrado")
	ctx.check(_has_err(berrs, "max_health <= 0"), "detecta inimigo com vida 0")
