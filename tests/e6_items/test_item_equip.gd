extends RefCounted
## E6.3 - equipar/desequipar recalcula os stats EXATAMENTE; cada item unico aplica seu efeito; clamps sanitarios (NaN/negativo/overflow);
## crafting ignora itens com affixes; inventario cheio nao perde item; mesmo uid nao entra duas vezes.

const H = preload("res://tests/e2/loop_helpers.gd")
const C = preload("res://tests/e6_classes/class_helpers.gd")

var _rules: ItemRules


func run(ctx: Object) -> void:
	var tree: SceneTree = ctx as SceneTree
	await tree.physics_frame
	_rules = ItemRules.shared()
	var world: Node3D = H.make_world(tree)
	await _test_equip_exact(ctx, world)
	await _test_uniques(ctx, world)
	await _test_clamps(ctx, world)
	await _test_inventory_rules(ctx, world)
	world.queue_free()


func _inst(uid: String, rarity: String, ilvl: int, affixes: Array) -> Dictionary:
	return {"uid": uid, "rarity": rarity, "ilvl": ilvl, "affixes": affixes}


func _aff(id: String, tier: int, at_max: bool = false) -> Dictionary:
	var t: Dictionary = _rules.tier_of(_rules.affixes[id], tier)
	return {"id": id, "tier": tier, "value": float(t["max"]) if at_max else float(t["min"])}


func _hero(world: Node3D) -> PlayerLoadout:
	var p: Player = C.spawn(world, "warrior", Vector3.ZERO)
	return PlayerLoadout.find_for(p)


func _test_equip_exact(ctx: Object, world: Node3D) -> void:
	var lo: PlayerLoadout = _hero(world)
	var before: StatBlock = lo.final_stats.duplicate() as StatBlock
	var inst: Dictionary = _inst("00000000000000a1", "rare", 30, [_aff("pre_brutal", 3), _aff("suf_of_ward", 3), _aff("suf_of_titan", 3)])
	ctx.check(_rules.validate_instance(inst, lo.registry.get_item(&"sword_basic")).is_empty(), "fixture: instancia rara valida")
	ctx.check(lo.inventory.add_instance(&"sword_basic", inst), "instancia entra no inventario")
	var idx: int = lo.inventory.stack_count() - 1
	var sword: ItemData = lo.registry.get_item(&"sword_basic")
	var old_weapon: StringName = lo.equipment.get_equipped(ItemData.Slot.WEAPON)
	ctx.check(lo.equipment.equip_index(idx), "equip_index equipa a instancia")
	var inst_sb: StatBlock = _rules.stat_block(inst)
	var base_mod: StatBlock = sword.stat_modifiers
	var prev_mod: float = 0.0
	if old_weapon != &"":
		prev_mod = lo.registry.get_item(old_weapon).stat_modifiers.max_health
	var expected_hp: float = before.max_health - prev_mod + base_mod.max_health + inst_sb.max_health
	ctx.check(is_equal_approx(lo.final_stats.max_health, expected_hp), "max_health muda exatamente: %.2f -> %.2f (esperado %.2f)" % [before.max_health, lo.final_stats.max_health, expected_hp])
	ctx.check(inst_sb.max_health > 0.0, "o affix de vida contribuiu (+%.1f)" % inst_sb.max_health)
	var prev_atk: float = lo.registry.get_item(old_weapon).stat_modifiers.attack_power if old_weapon != &"" else 0.0
	ctx.check(inst_sb.attack_power > 0.0 and is_equal_approx(lo.final_stats.attack_power, before.attack_power - prev_atk + base_mod.attack_power + inst_sb.attack_power), "attack_power muda exatamente (affix de ataque)")
	ctx.check(inst_sb.resistance > 0.0 and is_equal_approx(lo.final_stats.resistance, before.resistance + inst_sb.resistance), "resistencia muda exatamente (affix de resistencia)")
	ctx.check(lo.equipment.get_equipped_instance(ItemData.Slot.WEAPON) == inst, "a instancia equipada e a mesma (uid/affixes)")
	ctx.check(lo.health.max_health() == lo.final_stats.max_health, "HealthComponent usa os stats novos")
	# desequipar devolve a instancia inteira ao inventario e remove o bonus
	var with_item: float = lo.final_stats.max_health
	ctx.check(lo.equipment.unequip(ItemData.Slot.WEAPON), "desequipa")
	ctx.check(lo.final_stats.max_health < with_item and is_equal_approx(lo.final_stats.max_health, before.max_health - prev_mod), "desequipar remove exatamente o bonus (base+affix)")
	ctx.check(lo.inventory.has_uid("00000000000000a1"), "instancia voltou ao inventario sem perder uid")
	# o SkillData/StatBlock base do item nunca e mutado
	ctx.check(is_equal_approx(sword.stat_modifiers.max_health, base_mod.max_health), "ItemData compartilhado nao foi mutado pelos affixes")
	# affixes de skill_mod: dano das habilidades sobe e some ao desequipar
	var lo2: PlayerLoadout = _hero(world)
	var fury: Dictionary = _inst("00000000000000a2", "uncommon", 30, [_aff("suf_of_fury", 3, true)])
	var heavy: SkillData = ClassCatalog.load_skill(&"heavy_strike")
	var d0: float = lo2.combat.resolve_skill(heavy).skill.damage_multiplier
	lo2.inventory.add_instance(&"sword_basic", fury)
	lo2.equipment.equip_index(lo2.inventory.contents().size() - 1)
	var d1: float = lo2.combat.resolve_skill(heavy).skill.damage_multiplier
	var expected_pct: float = float(_rules.tier_of(_rules.affixes["suf_of_fury"], 3)["max"])
	ctx.check(d1 > d0 and absf(d1 / d0 - (1.0 + expected_pct)) < 0.001, "affix de dano de habilidade: x%.3f (esperado x%.3f)" % [d1 / d0, 1.0 + expected_pct])
	lo2.equipment.unequip(ItemData.Slot.WEAPON)
	ctx.check(is_equal_approx(lo2.combat.resolve_skill(heavy).skill.damage_multiplier, d0), "desequipar remove o modificador de habilidade")


func _test_uniques(ctx: Object, world: Node3D) -> void:
	# emberfang: +25% dano com vida < 40%
	var lo: PlayerLoadout = _hero(world)
	var heavy: SkillData = ClassCatalog.load_skill(&"heavy_strike")
	lo.inventory.add(&"unique_emberfang", 1)
	var d_before: float = lo.combat.resolve_skill(heavy).skill.damage_multiplier
	lo.equipment.equip(&"unique_emberfang")
	var full: float = lo.combat.resolve_skill(heavy).skill.damage_multiplier
	lo.health.current_health = lo.health.max_health() * 0.3
	var low: float = lo.combat.resolve_skill(heavy).skill.damage_multiplier
	ctx.check(is_equal_approx(full, d_before) and absf(low / full - 1.25) < 0.001, "Presa de Brasa: +25%% dano so com vida < 40%% (cheia x%.2f, baixa x%.3f)" % [full / d_before, low / full])
	ctx.check(lo.final_stats.attack_power > 0.0 and lo.equipment.get_equipped(ItemData.Slot.WEAPON) == &"unique_emberfang", "stats fixos do unico aplicados")
	# gravitas: +20% area, -0.3 move_speed
	var lo2: PlayerLoadout = _hero(world)
	var spd0: float = lo2.final_stats.move_speed
	var def0: float = lo2.final_stats.defense
	var arena: SkillData = ClassCatalog.load_skill(&"whirlwind")
	var w0: Vector3 = lo2.combat.resolve_skill(arena).skill.hitbox_size
	lo2.inventory.add(&"unique_gravitas_plate", 1)
	lo2.equipment.equip(&"unique_gravitas_plate")
	var w1: Vector3 = lo2.combat.resolve_skill(arena).skill.hitbox_size
	ctx.check(w1.x > w0.x and absf(w1.x / w0.x - 1.2) < 0.01, "Couraça da Gravitas: area +20%% (x%.3f)" % (w1.x / w0.x))
	ctx.check(lo2.final_stats.move_speed < spd0 and lo2.final_stats.defense > def0, "Gravitas: mais defesa, menos velocidade (trade-off)")
	# featherknot: custo -20%, cooldown -10%, vida -10
	var lo3: PlayerLoadout = PlayerLoadout.find_for(C.spawn(world, "mage", Vector3.ZERO))
	var fb: SkillData = ClassCatalog.load_skill(&"fireball")
	var hp0: float = lo3.final_stats.max_health
	var r0: SkillMods.Resolved = lo3.combat.resolve_skill(fb)
	var cost0: float = r0.skill.resource_cost
	var cd0: float = r0.skill.cooldown
	lo3.inventory.add(&"unique_featherknot", 1)
	lo3.equipment.equip(&"unique_featherknot")
	var r1: SkillMods.Resolved = lo3.combat.resolve_skill(fb)
	ctx.check(absf(r1.skill.resource_cost / cost0 - 0.8) < 0.001 and absf(r1.skill.cooldown / cd0 - 0.9) < 0.001, "Nó de Pena: custo -20%% e cooldown -10%%")
	ctx.check(is_equal_approx(lo3.final_stats.max_health, hp0 - 10.0), "Nó de Pena: -10 vida maxima exato")
	# twin quiver: +1 projetil
	var lo4: PlayerLoadout = PlayerLoadout.find_for(C.spawn(world, "ranger", Vector3.ZERO))
	var pa: SkillData = ClassCatalog.load_skill(&"piercing_arrow")
	var e0: int = lo4.combat.resolve_skill(pa).extra_projectiles
	lo4.inventory.add(&"unique_twin_quiver", 1)
	lo4.equipment.equip(&"unique_twin_quiver")
	var e1: SkillMods.Resolved = lo4.combat.resolve_skill(pa)
	ctx.check(e1.extra_projectiles == e0 + 1, "Aljava Gemea: +1 projetil (%d -> %d)" % [e0, e1.extra_projectiles])
	# frostbrand: converte para gelo, +10% dano
	var lo5: PlayerLoadout = _hero(world)
	var h5: SkillData = ClassCatalog.load_skill(&"heavy_strike")
	var p0: SkillMods.Resolved = lo5.combat.resolve_skill(h5)
	lo5.inventory.add(&"unique_frostbrand", 1)
	lo5.equipment.equip(&"unique_frostbrand")
	var p1: SkillMods.Resolved = lo5.combat.resolve_skill(h5)
	ctx.check(String(p1.damage_type) == "ice" and String(p0.damage_type) != "ice" and p1.skill.damage_multiplier > p0.skill.damage_multiplier, "Gelo-Ferro: converte para gelo e +dano")
	# dodge nao recebe mods curinga
	var dodge: SkillData = ClassCatalog.load_skill(&"dodge")
	ctx.check(lo5.combat.mods_for(dodge).is_empty(), "esquiva nao recebe modificadores curinga de itens")
	# desequipar remove o efeito
	lo5.equipment.unequip(ItemData.Slot.WEAPON)
	ctx.check(String(lo5.combat.resolve_skill(h5).damage_type) != "ice", "desequipar o unico remove o efeito")


func _test_clamps(ctx: Object, world: Node3D) -> void:
	var nan_b: StatBlock = StatUtil.zero()
	nan_b.max_health = NAN
	nan_b.defense = -5000.0
	nan_b.resistance = 9.0
	nan_b.attack_power = 1.0e30
	nan_b.move_speed = -3.0
	StatCalculator.clamp_final(nan_b)
	ctx.check(is_finite(nan_b.max_health) and nan_b.max_health >= 1.0, "NaN em vida maxima vira piso (>=1)")
	ctx.check(nan_b.defense == 0.0 and nan_b.resistance <= 0.75 and nan_b.attack_power <= 100000.0 and nan_b.move_speed >= 0.5, "negativo/overflow limitados (defesa, resistencia, ataque, velocidade)")
	# empilhar o maximo de affixes nunca ultrapassa os tetos
	var lo: PlayerLoadout = _hero(world)
	var sb: StatBlock = lo.final_stats
	ctx.check(is_finite(sb.max_health) and sb.max_health > 0.0 and sb.resistance >= 0.0 and sb.resistance <= 0.75, "stats finais do heroi sao sanos")
	var guard: int = 0
	for s: int in 40:
		var inst: Dictionary = ItemRoller.roll_instance(_rules, lo.registry.get_item(&"armor_heavy"), "mythic", 50, _seeded(s), ItemRoller.make_uid("cl", s, 0, 0))
		if inst.is_empty():
			continue
		lo.equipment.set_equipped(ItemData.Slot.ARMOR, &"armor_heavy", inst)
		lo.recalculate()
		var f: StatBlock = lo.final_stats
		for key: String in StatCalculator.CAPS:
			var lim: Array = StatCalculator.CAPS[key]
			if not is_finite(float(f.get(key))) or float(f.get(key)) < float(lim[0]) or float(f.get(key)) > float(lim[1]):
				guard += 1
	ctx.check(guard == 0, "40 armaduras miticas equipadas: todos os stats dentro de [piso, teto]")


func _seeded(s: int) -> RandomNumberGenerator:
	var r: RandomNumberGenerator = RandomNumberGenerator.new()
	r.seed = s + 1000
	return r


func _test_inventory_rules(ctx: Object, world: Node3D) -> void:
	var lo: PlayerLoadout = _hero(world)
	var inv: Inventory = lo.inventory
	# mesmo uid duas vezes: recusado
	var i1: Dictionary = _inst("00000000000000b1", "rare", 20, [_aff("pre_brutal", 3), _aff("suf_of_ward", 3), _aff("suf_of_insight", 3)])
	ctx.check(inv.add_instance(&"sword_basic", i1) and not inv.add_instance(&"sword_basic", i1), "mesmo uid nao entra duas vezes")
	# remove()/count() enxergam so itens simples: crafting nunca consome item com affixes
	var plain_before: int = inv.count_plain(&"sword_basic")
	ctx.check(inv.count(&"sword_basic") >= plain_before + 1 and inv.count_plain(&"sword_basic") == plain_before, "count_plain ignora instancias")
	var all_n: int = inv.count(&"sword_basic")
	ctx.check(not inv.remove(&"sword_basic", all_n) or inv.has_uid("00000000000000b1"), "remove() simples nunca consome a instancia")
	ctx.check(inv.has_uid("00000000000000b1"), "instancia sobrevive a remove() de itens simples")
	# inventario cheio: add_instance falha sem alterar nada
	var full: Inventory = Inventory.new(lo.registry, 2)
	full.add(&"sword_basic", 2)
	var snap: Array[Dictionary] = full.contents()
	ctx.check(not full.add_instance(&"sword_basic", _inst("00000000000000b2", "rare", 20, [_aff("pre_brutal", 3), _aff("suf_of_ward", 3), _aff("suf_of_insight", 3)])) and full.contents() == snap, "inventario cheio: instancia recusada sem alterar nada")
	# equip_index com instancia invalida e rejeitado e nada muda
	var bad: Dictionary = _inst("00000000000000b3", "rare", 20, [{"id": "pre_brutal", "tier": 3, "value": 1.0e9}])
	var inv2: Inventory = Inventory.new(lo.registry, 5)
	inv2.add_instance(&"sword_basic", bad)
	var eq2: Equipment = Equipment.new(lo.registry, inv2)
	ctx.check(not eq2.equip_index(0) and eq2.get_equipped(ItemData.Slot.WEAPON) == &"" and inv2.stack_count() == 1, "equipar instancia invalida: recusado, nada muda")
	ctx.check(not eq2.equip_index(7) and not eq2.equip_index(-1), "indice fora da faixa recusado")
	# equipar com inventario cheio troca sem perder (o anterior ocupa o slot liberado)
	var inv3: Inventory = Inventory.new(lo.registry, 2)
	var eq3: Equipment = Equipment.new(lo.registry, inv3)
	eq3.set_equipped(ItemData.Slot.WEAPON, &"sword_basic", i1)
	inv3.add_instance(&"sword_basic", _inst("00000000000000b4", "rare", 20, [_aff("pre_brutal", 3), _aff("suf_of_ward", 3), _aff("suf_of_insight", 3)]))
	inv3.add(&"potion_minor", 1)
	ctx.check(eq3.equip_index(0), "troca com inventario cheio funciona (o anterior volta ao slot liberado)")
	ctx.check(inv3.has_uid("00000000000000b1") and not inv3.has_uid("00000000000000b4") and eq3.get_equipped_instance(ItemData.Slot.WEAPON).get("uid") == "00000000000000b4", "nenhum item perdido nem duplicado na troca")
	# snapshot/restore preservam as instancias
	var s: Array[ItemStack] = inv3.snapshot()
	inv3.take_at(0)
	inv3.restore(s)
	ctx.check(inv3.has_uid("00000000000000b1"), "snapshot/restore preservam a instancia")
