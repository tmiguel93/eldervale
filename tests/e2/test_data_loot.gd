extends RefCounted
## LootTable: determinismo por seed e distribuicao coerente (tolerancia larga).


func _table() -> LootTable:
	var t: LootTable = LootTable.new()
	t.id = &"t"
	t.rolls = 1
	t.nothing_weight = 50.0
	var a: LootEntry = LootEntry.new()
	a.item_id = &"a"
	a.weight = 30.0
	a.min_qty = 1
	a.max_qty = 3
	var b: LootEntry = LootEntry.new()
	b.item_id = &"b"
	b.weight = 20.0
	t.entries = [a, b] as Array[LootEntry]
	return t


func _sig(drops: Array[LootDrop]) -> String:
	var s: String = ""
	for d: LootDrop in drops:
		s += "%s:%d;" % [d.item_id, d.quantity]
	return s


func run(ctx: Object) -> void:
	var t: LootTable = _table()
	t.rolls = 3
	var r1: RandomNumberGenerator = RandomNumberGenerator.new()
	var r2: RandomNumberGenerator = RandomNumberGenerator.new()
	r1.seed = 12345
	r2.seed = 12345
	var s1: String = ""
	var s2: String = ""
	for i: int in 50:
		s1 += _sig(t.roll(r1)) + "|"
		s2 += _sig(t.roll(r2)) + "|"
	ctx.check(s1 == s2, "mesma seed => mesma sequencia de drops")
	var r3: RandomNumberGenerator = RandomNumberGenerator.new()
	r3.seed = 999
	var s3: String = ""
	for i: int in 50:
		s3 += _sig(t.roll(r3)) + "|"
	ctx.check(s1 != s3, "seeds diferentes => sequencias diferentes")

	# Distribuicao: 1 roll, 20000 amostras. Esperado: nada 50%, a 30%, b 20%.
	t.rolls = 1
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 2024
	var n: int = 20000
	var cnt_a: int = 0
	var cnt_b: int = 0
	var cnt_none: int = 0
	var qty_ok: bool = true
	var seen_max: int = 0
	for i: int in n:
		var drops: Array[LootDrop] = t.roll(rng)
		if drops.is_empty():
			cnt_none += 1
		else:
			var d: LootDrop = drops[0]
			if d.item_id == &"a":
				cnt_a += 1
				qty_ok = qty_ok and d.quantity >= 1 and d.quantity <= 3
				seen_max = maxi(seen_max, d.quantity)
			else:
				cnt_b += 1
				qty_ok = qty_ok and d.quantity == 1
	var fa: float = float(cnt_a) / n
	var fb: float = float(cnt_b) / n
	var fn: float = float(cnt_none) / n
	print("    dist: a=%.3f b=%.3f nada=%.3f" % [fa, fb, fn])
	ctx.check(absf(fa - 0.30) < 0.03, "freq de 'a' ~30%% (%.3f)" % fa)
	ctx.check(absf(fb - 0.20) < 0.03, "freq de 'b' ~20%% (%.3f)" % fb)
	ctx.check(absf(fn - 0.50) < 0.03, "freq de 'nada' ~50%% (%.3f)" % fn)
	ctx.check(qty_ok and seen_max == 3, "quantidades dentro de [min,max] e max atingido")

	# Casos de borda
	var empty: LootTable = LootTable.new()
	ctx.check(empty.roll(rng).is_empty(), "tabela vazia => sem drops")
	t.rolls = 0
	ctx.check(t.roll(rng).is_empty(), "rolls=0 => sem drops")
	t.rolls = 5
	t.nothing_weight = 0.0
	var merged: Array[LootDrop] = t.roll(rng)
	var ids: Dictionary = {}
	var dup: bool = false
	var total: int = 0
	for d: LootDrop in merged:
		dup = dup or ids.has(d.item_id)
		ids[d.item_id] = true
		total += d.quantity
	ctx.check(not dup and total >= 5, "5 rolls sem 'nada': drops fundidos por item, qtd total >= 5")
	# Tabela real
	var reg: ContentRegistry = ContentRegistry.new()
	reg.load_all()
	var real: LootTable = reg.get_enemy(&"melee_grunt").loot_table
	var ok_ids: bool = true
	for i: int in 200:
		for d: LootDrop in real.roll(rng):
			ok_ids = ok_ids and reg.get_item(d.item_id) != null and d.quantity >= 1
	ctx.check(ok_ids, "tabela real: so sorteia itens existentes com qtd >= 1")
