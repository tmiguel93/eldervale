class_name ClassDef
extends RefCounted
## Definicao de classe jogavel (E6.1), carregada de data/classes/<id>.json (mesma fonte do catalogo do backend:
## tools/gen_classes_catalog.mjs -> shared/content_schemas/classes.json). Dados puros + validacao; sem logica de jogo.
## `class_id` e estavel (nao depende do nome de exibicao). Habilidades por SLOT referenciam ids de data/skills/*.tres.
## Especializacoes: `planned = true` = so registrada como dado (sem mecanica nem selecao nesta etapa).

const SLOTS: Array[String] = ["attack", "skill_1", "skill_2", "dodge"]
const RESOURCE_KINDS: Array[String] = ["stamina", "mana"]
const STAT_KEYS: Array[String] = ["max_health", "max_resource", "resource_regen", "attack_power", "defense", "resistance", "move_speed"]
const GROWTH_KEYS: Array[String] = ["max_health", "max_resource", "resource_regen", "attack_power", "defense", "resistance", "move_speed"]
## Limites iguais aos do backend (characters/model.ts validateState).
const STAT_MAX: Dictionary = {"resistance": 0.75, "move_speed": 100.0}
const STAT_DEFAULT_MAX: float = 100000.0
const MAX_GROWTH: float = 1000.0
const MAX_TAGS: int = 8
const MAX_SPECS: int = 6
const ID_PATTERN: String = "^[a-z][a-z0-9_]{0,47}$"

var id: String = ""
var display_name: String = ""
var description: String = ""
var resource_kind: String = "stamina"
var resource_name: String = ""
var base_stats: StatBlock
var growth: StatBlock ## bonus por nivel acima do 1
var skills: Dictionary = {} ## slot (String) -> skill_id (String)
var specializations: Array[Dictionary] = [] ## {id, display_name, tags: PackedStringArray, description, planned: bool}


static func is_valid_id(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	var re: RegEx = RegEx.new()
	re.compile(ID_PATTERN)
	return re.search(String(value)) != null


## Stats finais SO por classe+nivel (sem equipamento): base + growth * (level - 1). Mesma conta do StatCalculator.
func stats_at_level(level: int) -> StatBlock:
	return StatBlock.combine(base_stats, [StatUtil.scaled(growth, float(maxi(level, 1) - 1))] as Array[StatBlock])


func skill_ids() -> Array[String]:
	var out: Array[String] = []
	for slot: String in SLOTS:
		out.append(String(skills.get(slot, "")))
	return out


func has_skill(skill_id: String) -> bool:
	return skill_ids().has(skill_id)


func slot_of(skill_id: String) -> String:
	for slot: String in SLOTS:
		if String(skills.get(slot, "")) == skill_id:
			return slot
	return ""


func get_specialization(spec_id: String) -> Dictionary:
	for s: Dictionary in specializations:
		if String(s["id"]) == spec_id:
			return s
	return {}


## Especializacoes com mecanica prevista nesta etapa (planned = false).
func active_specializations() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s: Dictionary in specializations:
		if not bool(s["planned"]):
			out.append(s)
	return out


func resource_label() -> String:
	return resource_name if not resource_name.is_empty() else resource_kind.capitalize()


## Converte o JSON (Variant) em ClassDef. Devolve {"def": ClassDef|null, "errors": Array[String]}; def so existe sem erros.
static func parse(data: Variant) -> Dictionary:
	var errors: Array[String] = []
	if typeof(data) != TYPE_DICTIONARY:
		return {"def": null, "errors": ["raiz deve ser objeto"] as Array[String]}
	var d: Dictionary = data
	var allowed: Array[String] = ["schema_version", "id", "display_name", "description", "resource", "base_stats", "growth_per_level", "skills", "specializations"]
	for k: Variant in d:
		if not allowed.has(String(k)):
			errors.append("campo desconhecido: " + String(k).left(40))
	if typeof(d.get("schema_version", null)) not in [TYPE_INT, TYPE_FLOAT] or int(d.get("schema_version", 0)) != 1:
		errors.append("schema_version deve ser 1")
	var def: ClassDef = ClassDef.new()
	if not is_valid_id(d.get("id", null)):
		errors.append("id invalido")
	else:
		def.id = String(d["id"])
	for k: String in ["display_name", "description"]:
		var v: Variant = d.get(k, "")
		if typeof(v) != TYPE_STRING or (k == "display_name" and String(v).strip_edges().is_empty()) or String(v).length() > 400:
			errors.append(k + " invalido")
		else:
			def.set(k, String(v))
	var res: Variant = d.get("resource", null)
	if typeof(res) != TYPE_DICTIONARY or not RESOURCE_KINDS.has(str((res as Dictionary).get("kind", ""))):
		errors.append("resource.kind deve ser um de " + ", ".join(RESOURCE_KINDS))
	else:
		def.resource_kind = str((res as Dictionary)["kind"])
		def.resource_name = str((res as Dictionary).get("display_name", ""))
	def.base_stats = _parse_block(d.get("base_stats", null), "base_stats", true, errors)
	def.growth = _parse_block(d.get("growth_per_level", null), "growth_per_level", false, errors)
	var sk: Variant = d.get("skills", null)
	if typeof(sk) != TYPE_DICTIONARY:
		errors.append("skills deve ser objeto")
	else:
		for k: Variant in (sk as Dictionary):
			if not SLOTS.has(String(k)):
				errors.append("slot de habilidade desconhecido: " + String(k).left(40))
		var seen: Dictionary = {}
		for slot: String in SLOTS:
			var sid: Variant = (sk as Dictionary).get(slot, null)
			if not is_valid_id(sid):
				errors.append("skills.%s ausente/invalido" % slot)
				continue
			if seen.has(String(sid)):
				errors.append("habilidade repetida em slots: " + String(sid))
			seen[String(sid)] = true
			def.skills[slot] = String(sid)
	_parse_specs(d.get("specializations", null), def, errors)
	return {"def": def if errors.is_empty() else null, "errors": errors}


static func _parse_block(v: Variant, label: String, is_base: bool, errors: Array[String]) -> StatBlock:
	var b: StatBlock = StatUtil.zero()
	if typeof(v) != TYPE_DICTIONARY:
		errors.append(label + " deve ser objeto")
		return b
	var d: Dictionary = v
	for k: Variant in d:
		if not STAT_KEYS.has(String(k)):
			errors.append("%s: chave desconhecida %s" % [label, String(k).left(40)])
	for key: String in STAT_KEYS:
		if not d.has(key):
			if is_base:
				errors.append("%s.%s ausente" % [label, key])
			continue
		var val: Variant = d[key]
		if typeof(val) not in [TYPE_INT, TYPE_FLOAT] or not Protocol.is_finite_number(val):
			errors.append("%s.%s deve ser numero finito" % [label, key])
			continue
		var f: float = float(val)
		var max_v: float = float(STAT_MAX.get(key, STAT_DEFAULT_MAX if is_base else MAX_GROWTH))
		if f < 0.0 or f > max_v:
			errors.append("%s.%s fora de 0..%s" % [label, key, str(max_v)])
			continue
		b.set(key, f)
	if is_base:
		if b.max_health <= 0.0 or b.max_resource <= 0.0 or b.attack_power <= 0.0 or b.move_speed <= 0.0:
			errors.append("base_stats: max_health/max_resource/attack_power/move_speed devem ser > 0")
	return b


static func _parse_specs(v: Variant, def: ClassDef, errors: Array[String]) -> void:
	if typeof(v) != TYPE_ARRAY or (v as Array).is_empty() or (v as Array).size() > MAX_SPECS:
		errors.append("specializations deve ser lista de 1..%d" % MAX_SPECS)
		return
	var seen: Dictionary = {}
	for e: Variant in v:
		if typeof(e) != TYPE_DICTIONARY:
			errors.append("especializacao invalida")
			continue
		var s: Dictionary = e
		for k: Variant in s:
			if not ["id", "display_name", "tags", "description", "planned"].has(String(k)):
				errors.append("especializacao: campo desconhecido " + String(k).left(40))
		var sid: Variant = s.get("id", null)
		if not is_valid_id(sid) or seen.has(String(sid)):
			errors.append("especializacao: id invalido/duplicado")
			continue
		seen[String(sid)] = true
		if typeof(s.get("display_name", null)) != TYPE_STRING or String(s["display_name"]).strip_edges().is_empty():
			errors.append("especializacao %s: display_name invalido" % sid)
		if typeof(s.get("planned", null)) != TYPE_BOOL:
			errors.append("especializacao %s: planned deve ser bool" % sid)
		var tags: PackedStringArray = PackedStringArray()
		var tv: Variant = s.get("tags", null)
		if typeof(tv) != TYPE_ARRAY or (tv as Array).is_empty() or (tv as Array).size() > MAX_TAGS:
			errors.append("especializacao %s: tags deve ser lista de 1..%d" % [sid, MAX_TAGS])
		else:
			for t: Variant in tv:
				if not is_valid_id(t):
					errors.append("especializacao %s: tag invalida" % sid)
				else:
					tags.append(String(t))
		def.specializations.append({
			"id": String(sid), "display_name": str(s.get("display_name", "")), "tags": tags,
			"description": str(s.get("description", "")), "planned": bool(s["planned"]) if typeof(s.get("planned", null)) == TYPE_BOOL else true,
		})
