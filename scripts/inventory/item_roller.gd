class_name ItemRoller
extends RefCounted
## E6.3: rolagem de raridade e affixes. SO o servidor rola (o cliente nunca informa valores). Determinismo: o resultado depende apenas
## do estado do `rng` recebido (e do uid, que e dado). Ordem das chamadas ao rng: 1 randf (raridade) e, se nao Comum, por tentativa:
## randi_range (n de affixes) e, por affix, randi_range (candidato), randf (tier) e randf (valor).

const MAX_ATTEMPTS: int = 16


## Pesos de raridade para o tier do inimigo ("normal"|"mini_boss"|"boss"): drop_weight x multiplicador.
static func rarity_weights(rules: ItemRules, enemy_tier: String) -> Dictionary:
	var mult: Dictionary = rules.tier_mult.get(enemy_tier, rules.tier_mult.get("normal", {})) as Dictionary
	var out: Dictionary = {}
	for id: String in rules.rarity_order:
		out[id] = float((rules.rarities[id] as Dictionary)["drop_weight"]) * float(mult.get(id, 1.0))
	return out


static func roll_rarity(rules: ItemRules, rng: RandomNumberGenerator, enemy_tier: String = "normal") -> String:
	var w: Dictionary = rarity_weights(rules, enemy_tier)
	var total: float = 0.0
	for id: String in rules.rarity_order:
		total += maxf(float(w[id]), 0.0)
	if total <= 0.0:
		return "common"
	var pick: float = rng.randf() * total
	var acc: float = 0.0
	var last: String = "common"
	for id: String in rules.rarity_order:
		var x: float = maxf(float(w[id]), 0.0)
		if x <= 0.0:
			continue
		acc += x
		last = id
		if pick < acc:
			break
	return last


## uid deterministico: 16 hex de sha256("salt:a:b:c").
static func make_uid(salt: String, a: int, b: int, c: int) -> String:
	return ("%s:%d:%d:%d" % [salt, a, b, c]).sha256_text().substr(0, 16)


## Rola uma instancia da raridade `rarity_id` para `base` e `ilvl`. {} se nao deu (raridade Comum, base invalida ou sem candidatos).
static func roll_instance(rules: ItemRules, base: ItemData, rarity_id: String, ilvl: int, rng: RandomNumberGenerator, uid: String) -> Dictionary:
	if base == null or not base.is_equippable() or rules.is_unique(String(base.id)) or not rules.has_rarity(rarity_id) or rarity_id == "common":
		return {}
	var r: Dictionary = rules.rarity(rarity_id)
	var lv: int = clampi(ilvl, 1, rules.ilvl_max)
	var slot_name: String = rules.slot_name_of(base)
	for _attempt: int in MAX_ATTEMPTS:
		var picked: Array = _try_roll(rules, r, slot_name, lv, rng)
		if picked.size() >= int(r["affix_min"]):
			return {"uid": uid, "rarity": rarity_id, "ilvl": lv, "affixes": picked}
	return {}


static func _try_roll(rules: ItemRules, r: Dictionary, slot_name: String, ilvl: int, rng: RandomNumberGenerator) -> Array:
	var n: int = rng.randi_range(int(r["affix_min"]), int(r["affix_max"]))
	var out: Array = []
	var groups: Dictionary = {}
	var pre: int = 0
	var suf: int = 0
	var left: int = int(r["budget"])
	for i: int in n:
		var reserve: int = n - i - 1 # cada affix restante custa no minimo 1
		var cands: Array = []
		for aid: String in rules.affix_order:
			var def: Dictionary = rules.affixes[aid]
			if not (def["slots"] as Array).has(slot_name) or groups.has(String(def["group"])):
				continue
			if String(def["kind"]) == "prefix" and pre >= int(r["prefix_max"]):
				continue
			if String(def["kind"]) == "suffix" and suf >= int(r["suffix_max"]):
				continue
			if not _eligible_tiers(def, ilvl, left - reserve).is_empty():
				cands.append(def)
		if cands.is_empty():
			break
		var def2: Dictionary = cands[rng.randi_range(0, cands.size() - 1)]
		var tiers: Array = _eligible_tiers(def2, ilvl, left - reserve)
		var total: float = 0.0
		for t: Dictionary in tiers:
			total += float(t["weight"])
		var pick: float = rng.randf() * total
		var chosen: Dictionary = tiers[tiers.size() - 1]
		var acc: float = 0.0
		for t2: Dictionary in tiers:
			acc += float(t2["weight"])
			if pick < acc:
				chosen = t2
				break
		var value: float = snappedf(lerpf(float(chosen["min"]), float(chosen["max"]), rng.randf()), 0.01)
		value = clampf(value, float(chosen["min"]), float(chosen["max"]))
		out.append({"id": String(def2["id"]), "tier": int(chosen["tier"]), "value": value})
		groups[String(def2["group"])] = true
		if String(def2["kind"]) == "prefix":
			pre += 1
		else:
			suf += 1
		left -= int(chosen["cost"])
	return out


static func _eligible_tiers(def: Dictionary, ilvl: int, max_cost: int) -> Array:
	var out: Array = []
	for t: Variant in def["tiers"]:
		if int((t as Dictionary)["ilvl_min"]) <= ilvl and int((t as Dictionary)["cost"]) <= max_cost:
			out.append(t)
	return out


## Item de drop: sorteia a raridade; Comum => {} (item simples, sem instancia); senao rola a instancia.
static func roll_drop(rules: ItemRules, base: ItemData, ilvl: int, enemy_tier: String, rng: RandomNumberGenerator, uid: String) -> Dictionary:
	if base == null or not base.is_equippable() or rules.is_unique(String(base.id)):
		return {}
	var rid: String = roll_rarity(rules, rng, enemy_tier)
	if rid == "common":
		return {}
	return roll_instance(rules, base, rid, ilvl, rng, uid)
