class_name ItemRules
extends RefCounted
## E6.3: regras de raridade/affixes/unicos (DADOS em data/items/_rarity.json, _affixes.json, _uniques.json) + validacao e conversao de
## INSTANCIAS de item. Uma instancia e um Dictionary JSON-friendly (persistido e enviado ao dono):
##   {uid: "16 hex", rarity: id, ilvl: int, affixes: [{id, tier, value}]}      (a base e o `item_id` da entrada do inventario)
## Item sem instancia = Comum (saves antigos). Instancia so existe para equipavel nao-unico; Comum nunca tem instancia.
## `validate_instance` e espelhada em backend/src/characters/instances.ts (mesmas regras, mesmo catalogo gerado).

const RARITY_PATH: String = "res://data/items/_rarity.json"
const AFFIXES_PATH: String = "res://data/items/_affixes.json"
const UNIQUES_PATH: String = "res://data/items/_uniques.json"
const MAX_INSTANCE_BYTES: int = 512
const SLOT_NAMES: Dictionary = {ItemData.Slot.WEAPON: "weapon", ItemData.Slot.ARMOR: "armor", ItemData.Slot.TRINKET: "trinket"}
const STAT_LABELS: Dictionary = {
	"max_health": "Vida maxima", "max_resource": "Recurso maximo", "resource_regen": "Regeneracao de recurso",
	"attack_power": "Ataque", "defense": "Defesa", "resistance": "Resistencia", "move_speed": "Velocidade de movimento",
}

static var _shared: ItemRules = null

var ilvl_max: int = 1
var max_affixes: int = 6
var rarities: Dictionary = {}      ## id -> Dictionary
var rarity_order: Array[String] = []
var tier_mult: Dictionary = {}
var affixes: Dictionary = {}       ## id -> Dictionary
var affix_order: Array[String] = []
var uniques: Dictionary = {}       ## item_id -> Dictionary
var load_errors: Array[String] = []


static func shared() -> ItemRules:
	if _shared == null:
		_shared = ItemRules.new()
		_shared.load_all()
	return _shared


static func reset_shared() -> void:
	_shared = null


func load_all() -> void:
	var r: Variant = _read(RARITY_PATH)
	if typeof(r) == TYPE_DICTIONARY:
		ilvl_max = int((r as Dictionary).get("ilvl_max", 1))
		max_affixes = int((r as Dictionary).get("max_affixes", 6))
		tier_mult = (r as Dictionary).get("tier_weight_mult", {})
		for x: Variant in (r as Dictionary).get("rarities", []):
			var d: Dictionary = x
			rarities[String(d["id"])] = d
			rarity_order.append(String(d["id"]))
	var a: Variant = _read(AFFIXES_PATH)
	if typeof(a) == TYPE_DICTIONARY:
		for x: Variant in (a as Dictionary).get("affixes", []):
			var d2: Dictionary = x
			affixes[String(d2["id"])] = d2
			affix_order.append(String(d2["id"]))
		affix_order.sort()
	var u: Variant = _read(UNIQUES_PATH)
	if typeof(u) == TYPE_DICTIONARY:
		for x: Variant in (u as Dictionary).get("uniques", []):
			uniques[String((x as Dictionary)["id"])] = x
	if rarities.is_empty() or affixes.is_empty():
		load_errors.append("regras de itens ausentes ou invalidas")


func _read(path: String) -> Variant:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		load_errors.append("nao abriu " + path)
		return null
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed == null:
		load_errors.append("JSON invalido: " + path)
	return parsed


# ------------------------------------------------------------------ consultas

func rarity(id: String) -> Dictionary:
	return rarities.get(id, {}) as Dictionary


func has_rarity(id: String) -> bool:
	return rarities.has(id)


func rarity_name(id: String) -> String:
	return String(rarity(id).get("name", id))


func rarity_color(id: String) -> Color:
	var d: Dictionary = rarity(id)
	return Color.html(String(d["color"])) if d.has("color") else Color.WHITE


## Id de raridade (string) a partir do enum do ItemData.
static func rarity_id_of(r: int) -> String:
	var ids: Array = ["common", "uncommon", "rare", "epic", "legendary", "mythic"]
	return String(ids[clampi(r, 0, ids.size() - 1)])


func is_unique(item_id: String) -> bool:
	return uniques.has(item_id)


## Efeitos do unico `item_id` (mesmo formato dos efeitos de talento: stat / skill_mod).
func unique_effects(item_id: String) -> Array:
	return (uniques.get(item_id, {}) as Dictionary).get("effects", []) as Array


func slot_name_of(item: ItemData) -> String:
	return String(SLOT_NAMES.get(int(item.slot), ""))


static func as_int(v: Variant) -> int:
	## -2147483648 = nao e inteiro (int ou float integral).
	if typeof(v) == TYPE_INT:
		return int(v)
	if typeof(v) == TYPE_FLOAT and is_finite(float(v)) and absf(float(v)) < 2147483000.0 and float(v) == floorf(float(v)):
		return int(v)
	return -2147483648


func tier_of(affix: Dictionary, tier: int) -> Dictionary:
	for t: Variant in affix["tiers"]:
		if int((t as Dictionary)["tier"]) == tier:
			return t as Dictionary
	return {}


# ------------------------------------------------------------------ validacao

## "" se a instancia e valida para a base `base` (ItemData equipavel); senao o motivo. Aceita floats vindos de JSON.
func validate_instance(inst: Variant, base: ItemData) -> String:
	if typeof(inst) != TYPE_DICTIONARY:
		return "instancia nao e objeto"
	var d: Dictionary = inst
	for k: Variant in d.keys():
		if not ["uid", "rarity", "ilvl", "affixes"].has(String(k)):
			return "campo desconhecido na instancia"
	if base == null or not base.is_equippable() or not SLOT_NAMES.has(int(base.slot)):
		return "base nao equipavel"
	if is_unique(String(base.id)):
		return "item unico nao leva instancia"
	var uid: Variant = d.get("uid", null)
	if typeof(uid) != TYPE_STRING or not _is_hex16(String(uid)):
		return "uid invalido"
	var rid: Variant = d.get("rarity", null)
	if typeof(rid) != TYPE_STRING or not rarities.has(String(rid)) or String(rid) == "common":
		return "raridade invalida"
	var ilvl: int = as_int(d.get("ilvl", null))
	if ilvl < 1 or ilvl > ilvl_max:
		return "ilvl fora de faixa"
	var list: Variant = d.get("affixes", null)
	if typeof(list) != TYPE_ARRAY:
		return "affixes nao e lista"
	var r: Dictionary = rarities[String(rid)]
	var n: int = (list as Array).size()
	if n < int(r["affix_min"]) or n > int(r["affix_max"]) or n > max_affixes:
		return "numero de affixes fora da raridade"
	var groups: Dictionary = {}
	var pre: int = 0
	var suf: int = 0
	var cost: int = 0
	var slot_name: String = slot_name_of(base)
	for x: Variant in list:
		if typeof(x) != TYPE_DICTIONARY:
			return "affix invalido"
		var ad: Dictionary = x
		for k2: Variant in ad.keys():
			if not ["id", "tier", "value"].has(String(k2)):
				return "campo desconhecido no affix"
		var aid: Variant = ad.get("id", null)
		if typeof(aid) != TYPE_STRING or not affixes.has(String(aid)):
			return "affix desconhecido"
		var def: Dictionary = affixes[String(aid)]
		if not (def["slots"] as Array).has(slot_name):
			return "affix nao permitido no slot"
		if groups.has(String(def["group"])):
			return "affix repetido (mesmo grupo)"
		groups[String(def["group"])] = true
		var t: Dictionary = tier_of(def, as_int(ad.get("tier", null)))
		if t.is_empty():
			return "tier inexistente"
		if ilvl < int(t["ilvl_min"]):
			return "tier acima do ilvl"
		var v: Variant = ad.get("value", null)
		if (typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT) or not is_finite(float(v)):
			return "valor invalido"
		if float(v) < float(t["min"]) - 0.000001 or float(v) > float(t["max"]) + 0.000001:
			return "valor fora da faixa do tier"
		if String(def["kind"]) == "prefix":
			pre += 1
		else:
			suf += 1
		cost += int(t["cost"])
	if pre > int(r["prefix_max"]) or suf > int(r["suffix_max"]):
		return "prefixos/sufixos acima do limite da raridade"
	if cost > int(r["budget"]):
		return "orcamento da raridade excedido"
	if JSON.stringify(d).length() > MAX_INSTANCE_BYTES:
		return "instancia grande demais"
	return ""


static func _is_hex16(s: String) -> bool:
	if s.length() != 16:
		return false
	for i: int in s.length():
		var c: int = s.unicode_at(i)
		if not ((c >= 48 and c <= 57) or (c >= 97 and c <= 102)):
			return false
	return true


## Custo total de orcamento da instancia (assume valida).
func budget_used(inst: Dictionary) -> int:
	var c: int = 0
	for x: Variant in inst.get("affixes", []):
		var def: Dictionary = affixes.get(String((x as Dictionary)["id"]), {})
		if not def.is_empty():
			c += int(tier_of(def, as_int((x as Dictionary)["tier"])).get("cost", 0))
	return c


# ------------------------------------------------------------------ efeitos

## Bloco de stats (a SOMAR) dos affixes de stat da instancia. Valores nao finitos sao ignorados.
func stat_block(inst: Dictionary) -> StatBlock:
	var b: StatBlock = StatUtil.zero()
	for x: Variant in inst.get("affixes", []):
		var ad: Dictionary = x
		var def: Dictionary = affixes.get(String(ad.get("id", "")), {})
		if def.is_empty() or String((def["effect"] as Dictionary)["type"]) != "stat":
			continue
		var v: float = float(ad.get("value", 0.0))
		if not is_finite(v):
			continue
		var key: String = String((def["effect"] as Dictionary)["stat"])
		b.set(key, float(b.get(key)) + v)
	return b


## Efeitos de habilidade (mods no formato do SkillMods) dos affixes de skill_mod da instancia.
func skill_effects(inst: Dictionary) -> Array:
	var out: Array = []
	for x: Variant in inst.get("affixes", []):
		var ad: Dictionary = x
		var def: Dictionary = affixes.get(String(ad.get("id", "")), {})
		if def.is_empty():
			continue
		var fx: Dictionary = def["effect"]
		if String(fx["type"]) != "skill_mod":
			continue
		var v: float = float(ad.get("value", 0.0))
		if not is_finite(v):
			continue
		out.append({"type": "skill_mod", "skill": String(fx["skill"]), "mod": String(fx["mod"]), String(fx["param"]): v * float(fx["sign"])})
	return out


# ------------------------------------------------------------------ apresentacao

## Linhas legiveis dos affixes ("+12 Vida maxima", "+5% dano das habilidades").
func lines(inst: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for x: Variant in inst.get("affixes", []):
		var ad: Dictionary = x
		var def: Dictionary = affixes.get(String(ad.get("id", "")), {})
		if def.is_empty():
			continue
		out.append(affix_line(def, float(ad.get("value", 0.0))))
	return out


func affix_line(def: Dictionary, v: float) -> String:
	var fx: Dictionary = def["effect"]
	if String(fx["type"]) == "stat":
		var key: String = String(fx["stat"])
		var label: String = String(STAT_LABELS.get(key, key))
		if key == "resistance":
			return "+%d%% %s" % [roundi(v * 100.0), label]
		if key == "move_speed" or key == "resource_regen":
			return "+%.2f %s" % [v, label]
		return "+%d %s" % [roundi(v), label]
	var pct: int = roundi(v * 100.0)
	match String(fx["mod"]):
		"damage": return "+%d%% dano das habilidades" % pct
		"cost": return "-%d%% custo das habilidades" % pct
		"area": return "+%d%% area das habilidades" % pct
	return String(def.get("name", ""))


## Nome composto: "Brutal Espada Basica da Furia" (prefixo + base + sufixo; primeiro de cada tipo).
func display_name(base_name: String, inst: Dictionary) -> String:
	var pre: String = ""
	var suf: String = ""
	for x: Variant in inst.get("affixes", []):
		var def: Dictionary = affixes.get(String((x as Dictionary).get("id", "")), {})
		if def.is_empty():
			continue
		if String(def["kind"]) == "prefix" and pre.is_empty():
			pre = String(def["name"])
		elif String(def["kind"]) == "suffix" and suf.is_empty():
			suf = String(def["name"])
	return ("%s %s %s" % [pre, base_name, suf]).strip_edges().replace("  ", " ")
