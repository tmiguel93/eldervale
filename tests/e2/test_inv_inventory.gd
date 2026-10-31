extends RefCounted
## Inventory (stack/limite/capacidade) e Equipment (atomicidade).


func _reg() -> ContentRegistry:
	var r: ContentRegistry = ContentRegistry.new()
	r.load_all()
	return r


func run(ctx: Object) -> void:
	var reg: ContentRegistry = _reg()
	_stack_tests(ctx, reg)
	_equip_tests(ctx, reg)


func _stack_tests(ctx: Object, reg: ContentRegistry) -> void:
	var inv: Inventory = Inventory.new(reg, 3)
	var changes: Array[int] = [0]
	inv.changed.connect(func() -> void: changes[0] += 1)
	ctx.check(inv.add(&"potion_minor", 15) == 0 and inv.count(&"potion_minor") == 15, "add 15 pocoes cabe")
	ctx.check(inv.add(&"potion_minor", 10) == 0 and inv.stack_count() == 2, "add 10: completa pilha (20) + nova (5)")
	var slots: Array[Dictionary] = inv.contents()
	ctx.check(slots[0]["qty"] == 20 and slots[1]["qty"] == 5, "pilhas 20 + 5")
	ctx.check(changes[0] == 2, "changed emitido uma vez por add efetivo (%d)" % changes[0])
	ctx.check(inv.add(&"sword_basic", 1) == 0 and inv.stack_count() == 3, "nao empilhavel ocupa slot proprio")
	ctx.check(inv.add(&"sword_basic", 1) == 1, "inventario cheio devolve o que nao coube")
	ctx.check(inv.add(&"potion_minor", 15) == 0 and inv.count(&"potion_minor") == 40, "completa pilha existente mesmo cheio")
	ctx.check(inv.add(&"potion_minor", 1) == 1, "pilhas cheias + slots cheios => 1 sobra")
	var before: int = changes[0]
	inv.add(&"potion_minor", 1)
	ctx.check(changes[0] == before, "add sem efeito nao emite changed")
	ctx.check(inv.add(&"ghost", 3) == 3 and inv.count(&"ghost") == 0, "item desconhecido rejeitado")
	ctx.check(inv.add(&"potion_minor", 0) == 0 and inv.add(&"potion_minor", -4) == 0, "qty <= 0 e no-op")

	# remove
	ctx.check(not inv.remove(&"potion_minor", 41) and inv.count(&"potion_minor") == 40, "remove acima do disponivel falha sem mudar nada")
	ctx.check(not inv.remove(&"potion_minor", 0) and not inv.remove(&"potion_minor", -1), "remove qty <= 0 falha")
	ctx.check(inv.remove(&"potion_minor", 25), "remove 25 de 40")
	ctx.check(inv.count(&"potion_minor") == 15 and inv.stack_count() == 2, "sem pilhas vazias residuais (pocao 15 + espada)")
	var consistent: bool = true
	for d: Dictionary in inv.contents():
		consistent = consistent and int(d["qty"]) >= 1
	ctx.check(consistent, "nenhuma pilha com qtd <= 0")
	ctx.check(inv.remove(&"potion_minor", 15) and not inv.has_item(&"potion_minor") and inv.stack_count() == 1, "remover tudo libera o slot")
	ctx.check(inv.room_for(&"potion_minor", 100) == 40, "room_for: 2 slots livres x 20")
	var zero: Inventory = Inventory.new(reg, 0)
	ctx.check(zero.add(&"potion_minor", 1) == 1, "capacidade 0 nao aceita nada")


func _equip_tests(ctx: Object, reg: ContentRegistry) -> void:
	var inv: Inventory = Inventory.new(reg, 3)
	var eq: Equipment = Equipment.new(reg, inv)
	var events: Array[int] = []
	eq.equipment_changed.connect(func(slot: int) -> void: events.append(slot))
	inv.add(&"sword_basic", 1)
	inv.add(&"sword_rare", 1)
	ctx.check(eq.equip(&"sword_basic"), "equipa espada basica")
	ctx.check(eq.get_equipped(ItemData.Slot.WEAPON) == &"sword_basic" and not inv.has_item(&"sword_basic"), "slot WEAPON ocupado, item saiu do inventario")
	ctx.check(eq.equip(&"sword_rare"), "troca por espada rara")
	ctx.check(inv.has_item(&"sword_basic") and not inv.has_item(&"sword_rare"), "troca devolveu a basica ao inventario")
	ctx.check(events == [ItemData.Slot.WEAPON, ItemData.Slot.WEAPON], "sinal equipment_changed por equip")
	ctx.check(not eq.equip(&"potion_minor") and eq.last_error != "", "pocao nao e equipavel")
	ctx.check(not eq.equip(&"armor_heavy") and eq.get_equipped(ItemData.Slot.ARMOR) == &"", "item fora do inventario nao equipa")
	ctx.check(not eq.equip(&"ghost"), "item desconhecido nao equipa")

	# Atomicidade: inventario cheio com troca impossivel? Troca libera o proprio slot, entao
	# monta caso real: 1 slot, equipado X; inventario tem Y. Troca ok (slot de Y reaproveitado).
	var inv2: Inventory = Inventory.new(reg, 1)
	var eq2: Equipment = Equipment.new(reg, inv2)
	inv2.add(&"armor_leather", 1)
	eq2.equip(&"armor_leather")
	inv2.add(&"armor_heavy", 1)
	ctx.check(eq2.equip(&"armor_heavy") and inv2.has_item(&"armor_leather") and eq2.get_equipped(ItemData.Slot.ARMOR) == &"armor_heavy", "troca com 1 slot reaproveita o slot liberado")
	# unequip com inventario cheio falha e nao perde item
	var inv3: Inventory = Inventory.new(reg, 1)
	var eq3: Equipment = Equipment.new(reg, inv3)
	inv3.add(&"amulet_vigor", 1)
	eq3.equip(&"amulet_vigor")
	inv3.add(&"scrap_material", 5)  # enche o unico slot
	var snap_before: Array[Dictionary] = inv3.contents()
	ctx.check(not eq3.unequip(ItemData.Slot.TRINKET), "unequip com inventario cheio falha")
	ctx.check(eq3.get_equipped(ItemData.Slot.TRINKET) == &"amulet_vigor" and inv3.contents() == snap_before, "falha atomica: item continua equipado, inventario intacto")
	inv3.remove(&"scrap_material", 5)
	ctx.check(eq3.unequip(ItemData.Slot.TRINKET) and inv3.has_item(&"amulet_vigor") and eq3.get_equipped(ItemData.Slot.TRINKET) == &"", "unequip devolve ao inventario")
	ctx.check(not eq3.unequip(ItemData.Slot.TRINKET), "unequip de slot vazio falha")
	ctx.check(not eq3.unequip(ItemData.Slot.NONE) and not eq3.unequip(77), "unequip de slot invalido falha")
	# conservacao total de itens
	var total_amulets: int = inv3.count(&"amulet_vigor") + (1 if eq3.get_equipped(ItemData.Slot.TRINKET) == &"amulet_vigor" else 0)
	ctx.check(total_amulets == 1, "nenhum item perdido/duplicado")
