extends RefCounted
## E6.3 - dados de raridade/affixes/unicos: carregam, sao coerentes e batem com o catalogo compartilhado (shared/content_schemas/items.json).

const RARITIES: Array[String] = ["common", "uncommon", "rare", "epic", "legendary", "mythic"]


func run(ctx: Object) -> void:
	var tree: SceneTree = ctx as SceneTree
	await tree.physics_frame
	var rules: ItemRules = ItemRules.shared()
	ctx.check(rules.rarity_order == RARITIES, "6 raridades em ordem: Comum, Magico, Raro, Epico, Lendario, Mitico")
	var last_budget: int = -1
	var last_weight: float = INF
	var ok_mono: bool = true
	for id: String in RARITIES:
		var r: Dictionary = rules.rarity(id)
		if int(r["budget"]) < last_budget or float(r["drop_weight"]) > last_weight:
			ok_mono = false
		last_budget = int(r["budget"])
		last_weight = float(r["drop_weight"])
		ctx.check(int(r["affix_max"]) <= rules.max_affixes and int(r["affix_min"]) <= int(r["affix_max"]), "%s: faixa de affixes coerente" % id)
	ctx.check(ok_mono, "orcamento cresce e peso de drop decresce com a raridade")
	ctx.check(rules.rarity_name("uncommon") == "Mágico" and rules.rarity_color("legendary") != rules.rarity_color("common"), "nomes/cores de exibicao")
	ctx.check(int((rules.rarity("common"))["budget"]) == 0 and int((rules.rarity("common"))["affix_max"]) == 0, "Comum nao tem affixes")
	# affixes: tiers bem formados, custo >= 1, faixas validas, efeito em stats existentes
	var sb: StatBlock = StatBlock.new()
	var props: Array[String] = []
	for p: Dictionary in sb.get_property_list():
		props.append(String(p["name"]))
	var bad: int = 0
	for aid: String in rules.affix_order:
		var def: Dictionary = rules.affixes[aid]
		if (def["slots"] as Array).is_empty() or (def["tiers"] as Array).is_empty():
			bad += 1
		for t: Dictionary in def["tiers"]:
			if int(t["cost"]) < 1 or float(t["min"]) > float(t["max"]) or int(t["ilvl_min"]) < 1 or float(t["weight"]) <= 0.0:
				bad += 1
		var fx: Dictionary = def["effect"]
		if String(fx["type"]) == "stat" and not props.has(String(fx["stat"])):
			bad += 1
	ctx.check(rules.affix_order.size() >= 10 and bad == 0, "%d affixes: tiers/custos/faixas/stats validos" % rules.affix_order.size())
	var kinds: Dictionary = {}
	var skill_mod_n: int = 0
	for aid2: String in rules.affix_order:
		kinds[String(rules.affixes[aid2]["kind"])] = true
		if String((rules.affixes[aid2]["effect"] as Dictionary)["type"]) == "skill_mod":
			skill_mod_n += 1
	ctx.check(kinds.has("prefix") and kinds.has("suffix") and skill_mod_n >= 3, "prefixos e sufixos; >=3 affixes de modificador de habilidade (SkillMods)")
	# unicos: ItemData existe, efeito legivel, obtencao em dados, nunca obrigatorio
	var reg: ContentRegistry = ContentRegistry.new()
	reg.load_all()
	var uniques: Array = rules.uniques.keys()
	ctx.check(uniques.size() >= 3 and uniques.size() <= 5, "3-5 itens unicos (%d)" % uniques.size())
	for uid: String in uniques:
		var u: Dictionary = rules.uniques[uid]
		var item: ItemData = reg.get_item(StringName(uid))
		ctx.check(item != null and item.is_equippable() and rules.is_unique(uid), "%s: ItemData equipavel e marcado como unico" % uid)
		ctx.check(not String(u["description"]).is_empty() and not (u["effects"] as Array).is_empty(), "%s: descricao legivel e efeito autorado" % uid)
		var src: Array = (u["obtain"] as Dictionary)["sources"]
		var tables_ok: bool = not src.is_empty()
		for s: Dictionary in src:
			if not ResourceLoader.exists("res://data/loot/%s.tres" % String(s["loot_table"])) or float(s["chance"]) <= 0.0 or float(s["chance"]) >= 1.0:
				tables_ok = false
		ctx.check(tables_ok, "%s: tabela de drop existente e chance em (0,1) - nunca garantido" % uid)
	var slots: Dictionary = {}
	for uid2: String in uniques:
		slots[reg.get_item(StringName(uid2)).slot] = true
	ctx.check(slots.size() >= 2, "unicos cobrem mais de um slot (generico por slot, nao so uma classe)")
	# o catalogo gerado bate com o carregado no Godot
	var f: FileAccess = FileAccess.open("res://shared/content_schemas/items.json", FileAccess.READ)
	var cat: Dictionary = JSON.parse_string(f.get_as_text())
	ctx.check((cat["affixes"] as Array).size() == rules.affix_order.size() and (cat["uniques"] as Array).size() == uniques.size() and (cat["rarities"] as Array).size() == 6, "items.json (backend) tem as mesmas raridades/affixes/unicos")
	ctx.check(int(cat["ilvl_max"]) == rules.ilvl_max and int(cat["max_affixes"]) == rules.max_affixes, "ilvl_max/max_affixes iguais")
