extends RefCounted
## E6.3 - rolagem: orcamento por raridade, faixas dos affixes, determinismo por seed, distribuicao de raridade, gating por slot/ilvl,
## validacao de payloads invalidos.

var _rules: ItemRules
var _reg: ContentRegistry


func run(ctx: Object) -> void:
	var tree: SceneTree = ctx as SceneTree
	await tree.physics_frame
	_rules = ItemRules.shared()
	_reg = ContentRegistry.new()
	_reg.load_all()
	_test_budget_and_ranges(ctx)
	_test_determinism(ctx)
	_test_distribution(ctx)
	_test_gating(ctx)
	_test_invalid(ctx)
	_test_effects_finite(ctx)


func _rng(seed_value: int) -> RandomNumberGenerator:
	var r: RandomNumberGenerator = RandomNumberGenerator.new()
	r.seed = seed_value
	return r


func _test_budget_and_ranges(ctx: Object) -> void:
	var base: ItemData = _reg.get_item(&"sword_basic")
	for rid: String in ["uncommon", "rare", "epic", "legendary", "mythic"]:
		var r: Dictionary = _rules.rarity(rid)
		var bad_valid: int = 0
		var bad_budget: int = 0
		var bad_count: int = 0
		var bad_range: int = 0
		var made: int = 0
		for s: int in 300:
			var ilvl: int = 1 + (s % _rules.ilvl_max)
			var inst: Dictionary = ItemRoller.roll_instance(_rules, base, rid, ilvl, _rng(s * 7919 + 1), ItemRoller.make_uid("t", s, 0, 0))
			if inst.is_empty():
				continue
			made += 1
			if not _rules.validate_instance(inst, base).is_empty():
				bad_valid += 1
			if _rules.budget_used(inst) > int(r["budget"]):
				bad_budget += 1
			var n: int = (inst["affixes"] as Array).size()
			if n < int(r["affix_min"]) or n > int(r["affix_max"]):
				bad_count += 1
			for a: Dictionary in inst["affixes"]:
				var t: Dictionary = _rules.tier_of(_rules.affixes[String(a["id"])], int(a["tier"]))
				if float(a["value"]) < float(t["min"]) or float(a["value"]) > float(t["max"]) or int(t["ilvl_min"]) > ilvl:
					bad_range += 1
		ctx.check(made >= 290, "%s: rolagem produz instancia (%d/300)" % [rid, made])
		ctx.check(bad_valid == 0 and bad_budget == 0 and bad_count == 0 and bad_range == 0, "%s: orcamento %d, numero de affixes e faixas por tier/ilvl sempre respeitados" % [rid, int(r["budget"])])


func _test_determinism(ctx: Object) -> void:
	var base: ItemData = _reg.get_item(&"armor_heavy")
	var a: Dictionary = ItemRoller.roll_instance(_rules, base, "epic", 30, _rng(4242), "00112233445566ff")
	var b: Dictionary = ItemRoller.roll_instance(_rules, base, "epic", 30, _rng(4242), "00112233445566ff")
	var c: Dictionary = ItemRoller.roll_instance(_rules, base, "epic", 30, _rng(4243), "00112233445566ff")
	ctx.check(not a.is_empty() and JSON.stringify(a) == JSON.stringify(b), "mesma seed => mesma instancia (deterministico)")
	ctx.check(JSON.stringify(a) != JSON.stringify(c), "seed diferente => instancia diferente")
	var d1: Dictionary = ItemRoller.roll_drop(_rules, _reg.get_item(&"sword_rare"), 10, "normal", _rng(99), "aaaaaaaaaaaaaaaa")
	var d2: Dictionary = ItemRoller.roll_drop(_rules, _reg.get_item(&"sword_rare"), 10, "normal", _rng(99), "aaaaaaaaaaaaaaaa")
	ctx.check(JSON.stringify(d1) == JSON.stringify(d2), "roll_drop deterministico por seed")
	ctx.check(ItemRoller.make_uid("s", 1, 2, 3) == ItemRoller.make_uid("s", 1, 2, 3) and ItemRoller.make_uid("s", 1, 2, 3) != ItemRoller.make_uid("s", 1, 2, 4) and ItemRoller.make_uid("s", 1, 2, 3).length() == 16, "uid estavel, distinto por entrada, 16 hex")


func _test_distribution(ctx: Object) -> void:
	var rng: RandomNumberGenerator = _rng(2026)
	var n: int = 20000
	var counts: Dictionary = {}
	for i: int in n:
		var rid: String = ItemRoller.roll_rarity(_rules, rng, "normal")
		counts[rid] = int(counts.get(rid, 0)) + 1
	var w: Dictionary = ItemRoller.rarity_weights(_rules, "normal")
	var total: float = 0.0
	for id: String in _rules.rarity_order:
		total += float(w[id])
	var ok: bool = true
	var detail: String = ""
	for id2: String in _rules.rarity_order:
		var expected: float = float(w[id2]) / total
		var got: float = float(int(counts.get(id2, 0))) / float(n)
		var tol: float = maxf(0.02, expected * 0.25) if expected > 0.05 else 0.01
		if absf(got - expected) > tol:
			ok = false
		detail += "%s=%.3f(%.3f) " % [id2, got, expected]
	ctx.check(ok, "distribuicao de raridade (20000 rolagens) dentro da tolerancia: " + detail)
	var wb: Dictionary = ItemRoller.rarity_weights(_rules, "boss")
	var tb: float = 0.0
	for id3: String in _rules.rarity_order:
		tb += float(wb[id3])
	ctx.check(float(wb["legendary"]) / tb > float(w["legendary"]) / total and float(wb["common"]) / tb < float(w["common"]) / total, "boss favorece raridades altas")
	ctx.check(ItemRoller.roll_rarity(_rules, _rng(1), "tier_inexistente") in _rules.rarity_order, "tier de inimigo desconhecido cai no padrao")


func _test_gating(ctx: Object) -> void:
	var sword: ItemData = _reg.get_item(&"sword_basic")
	var armor: ItemData = _reg.get_item(&"armor_heavy")
	var trinket: ItemData = _reg.get_item(&"amulet_vigor")
	var bad_slot: int = 0
	var high_at_low: int = 0
	for s: int in 200:
		for base: ItemData in [sword, armor, trinket]:
			var inst: Dictionary = ItemRoller.roll_instance(_rules, base, "rare", 1, _rng(s + 5), "bbbbbbbbbbbbbbbb")
			for a: Dictionary in inst.get("affixes", []):
				if not ((_rules.affixes[String(a["id"])]["slots"] as Array).has(_rules.slot_name_of(base))):
					bad_slot += 1
				if int(_rules.tier_of(_rules.affixes[String(a["id"])], int(a["tier"]))["ilvl_min"]) > 1:
					high_at_low += 1
	ctx.check(bad_slot == 0, "affixes so aparecem nos slots permitidos")
	ctx.check(high_at_low == 0, "ilvl 1 so rola o tier de entrada (tiers melhores exigem ilvl; T3 e o mais fraco, T1 o melhor)")
	var top_seen: bool = false
	for s2: int in 200:
		var inst2: Dictionary = ItemRoller.roll_instance(_rules, sword, "mythic", 50, _rng(s2 + 11), "cccccccccccccccc")
		for a2: Dictionary in inst2.get("affixes", []):
			if int(a2["tier"]) == 1:
				top_seen = true
	ctx.check(top_seen, "ilvl alto libera o melhor tier (T1)")
	ctx.check(ItemRoller.roll_instance(_rules, _reg.get_item(&"potion_minor"), "rare", 10, _rng(1), "dddddddddddddddd").is_empty(), "item nao equipavel nao rola")
	ctx.check(ItemRoller.roll_instance(_rules, _reg.get_item(&"unique_emberfang"), "rare", 10, _rng(1), "dddddddddddddddd").is_empty(), "item unico nao rola affixes")
	ctx.check(ItemRoller.roll_instance(_rules, sword, "common", 10, _rng(1), "dddddddddddddddd").is_empty(), "Comum => sem instancia")
	ctx.check(ItemRoller.roll_instance(_rules, sword, "inexistente", 10, _rng(1), "dddddddddddddddd").is_empty(), "raridade desconhecida => sem instancia")
	var clamped: Dictionary = ItemRoller.roll_instance(_rules, sword, "rare", 9999, _rng(3), "eeeeeeeeeeeeeeee")
	ctx.check(int(clamped.get("ilvl", 0)) == _rules.ilvl_max, "ilvl acima do maximo e limitado a %d" % _rules.ilvl_max)


func _test_invalid(ctx: Object) -> void:
	var sword: ItemData = _reg.get_item(&"sword_basic")
	var good: Dictionary = ItemRoller.roll_instance(_rules, sword, "rare", 20, _rng(77), "0123456789abcdef")
	ctx.check(_rules.validate_instance(good, sword).is_empty(), "instancia rolada valida passa")
	var cases: Dictionary = {}
	var m: Dictionary = good.duplicate(true)
	m["extra"] = 1
	cases["campo extra"] = m
	m = good.duplicate(true)
	m["uid"] = "XYZ"
	cases["uid ruim"] = m
	m = good.duplicate(true)
	m["rarity"] = "common"
	cases["raridade comum com instancia"] = m
	m = good.duplicate(true)
	m["rarity"] = "divine"
	cases["raridade desconhecida"] = m
	m = good.duplicate(true)
	m["ilvl"] = 0
	cases["ilvl 0"] = m
	m = good.duplicate(true)
	m["ilvl"] = 100000
	cases["ilvl enorme"] = m
	m = good.duplicate(true)
	(m["affixes"] as Array)[0]["value"] = 1.0e9
	cases["valor fora da faixa"] = m
	m = good.duplicate(true)
	(m["affixes"] as Array)[0]["value"] = NAN
	cases["valor NaN"] = m
	m = good.duplicate(true)
	(m["affixes"] as Array)[0]["id"] = "affix_fantasma"
	cases["affix desconhecido"] = m
	m = good.duplicate(true)
	(m["affixes"] as Array)[0]["tier"] = 99
	cases["tier inexistente"] = m
	m = good.duplicate(true)
	m["affixes"] = (good["affixes"] as Array) + (good["affixes"] as Array)
	cases["affixes repetidos / acima do limite"] = m
	m = good.duplicate(true)
	m["affixes"] = []
	cases["sem affixes numa raridade que exige"] = m
	m = good.duplicate(true)
	m["affixes"] = "x"
	cases["affixes nao e lista"] = m
	for k: String in cases:
		ctx.check(not _rules.validate_instance(cases[k], sword).is_empty(), "invalida rejeitada: " + k)
	ctx.check(not _rules.validate_instance("texto", sword).is_empty() and not _rules.validate_instance(null, sword).is_empty() and not _rules.validate_instance(good, _reg.get_item(&"potion_minor")).is_empty(), "nao-objeto / base nao equipavel rejeitados")
	ctx.check(not _rules.validate_instance(good, _reg.get_item(&"unique_emberfang")).is_empty(), "instancia em item unico rejeitada")
	# esforco para estourar o orcamento: monta affixes caros demais na raridade Magica
	var over: Dictionary = {"uid": "0123456789abcdef", "rarity": "uncommon", "ilvl": 50, "affixes": [
		{"id": "pre_vital", "tier": 3, "value": float(_rules.tier_of(_rules.affixes["pre_vital"], 3)["max"])},
		{"id": "suf_of_titan", "tier": 3, "value": float(_rules.tier_of(_rules.affixes["suf_of_titan"], 3)["max"])},
	]}
	var cost: int = _rules.budget_used(over)
	ctx.check(cost <= int(_rules.rarity("uncommon")["budget"]) or not _rules.validate_instance(over, sword).is_empty(), "orcamento excedido (custo %d) e rejeitado" % cost)
	# floats vindos de JSON (ilvl 20.0) sao aceitos; fracionarios nao
	var js: Variant = JSON.parse_string(JSON.stringify(good))
	ctx.check(_rules.validate_instance(js, sword).is_empty(), "instancia que passou por JSON (floats) continua valida")
	m = good.duplicate(true)
	m["ilvl"] = 20.5
	ctx.check(not _rules.validate_instance(m, sword).is_empty(), "ilvl fracionario rejeitado")


func _test_effects_finite(ctx: Object) -> void:
	var sword: ItemData = _reg.get_item(&"sword_basic")
	var ok: bool = true
	for s: int in 200:
		var inst: Dictionary = ItemRoller.roll_instance(_rules, sword, "mythic", 50, _rng(s + 31), "ffffffffffffffff")
		var sb: StatBlock = _rules.stat_block(inst)
		for key: String in StatCalculator.CAPS:
			if not is_finite(float(sb.get(key))):
				ok = false
		for fx: Dictionary in _rules.skill_effects(inst):
			for k: String in fx:
				if typeof(fx[k]) == TYPE_FLOAT and not is_finite(float(fx[k])):
					ok = false
	ctx.check(ok, "stats e efeitos dos affixes sempre finitos")
	var evil: Dictionary = {"affixes": [{"id": "pre_vital", "tier": 1, "value": NAN}, {"id": "suf_of_titan", "tier": 1, "value": INF}]}
	var sb2: StatBlock = _rules.stat_block(evil)
	ctx.check(is_zero_approx(sb2.max_health) and _rules.skill_effects(evil).is_empty(), "valores NaN/INF sao ignorados pelo calculo")
	ctx.check(is_finite(sb2.max_health) and is_finite(sb2.attack_power), "bloco de stats com NaN/INF continua finito")
