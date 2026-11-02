class_name VfxCatalog
extends RefCounted
## E8.3: catalogo de efeitos visuais data-driven (data/vfx/effects_*.json + bindings.json + _layer_schema.json). So dados e validacao:
## nao carrega textura, shader nem cena (o servidor/testes headless podem ler). O mesmo esquema e validado por tools/vfx_check.mjs.
## bindings.json liga habilidades, ataques de inimigo e eventos cosmeticos aos ids de efeito.

const DIR: String = "res://data/vfx"
const TIER_KEYS: Array[String] = ["normal", "mini_boss", "boss"]

static var _shared: VfxCatalog = null

var effects: Dictionary = {}    ## id -> Dictionary (definicao)
var bindings: Dictionary = {}
var schema: Dictionary = {}
var load_errors: Array[String] = []


static func shared() -> VfxCatalog:
	if _shared == null:
		_shared = load_dir()
	return _shared


static func reset() -> void:
	_shared = null


static func load_dir(dir_path: String = DIR) -> VfxCatalog:
	var c: VfxCatalog = VfxCatalog.new()
	c.schema = _read_json(dir_path + "/_layer_schema.json", c.load_errors)
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		c.load_errors.append("pasta ausente: " + dir_path)
		return c
	var files: PackedStringArray = dir.get_files()
	files.sort()
	for f: String in files:
		if not f.ends_with(".json"):
			continue
		if f.begins_with("effects_"):
			var d: Dictionary = _read_json(dir_path + "/" + f, c.load_errors)
			var fx: Variant = d.get("effects", {})
			if typeof(fx) != TYPE_DICTIONARY:
				c.load_errors.append(f + ": effects deve ser objeto")
				continue
			for id: Variant in (fx as Dictionary):
				if c.effects.has(id):
					c.load_errors.append("%s: efeito duplicado '%s'" % [f, id])
				c.effects[String(id)] = (fx as Dictionary)[id]
		elif f == "bindings.json":
			c.bindings = _read_json(dir_path + "/" + f, c.load_errors)
	return c


static func _read_json(path: String, errors: Array[String]) -> Dictionary:
	if not FileAccess.file_exists(path):
		errors.append("arquivo ausente: " + path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		errors.append("JSON invalido: " + path)
		return {}
	return parsed as Dictionary


func has_effect(id: String) -> bool:
	return effects.has(id)


func get_effect(id: String) -> Dictionary:
	return effects.get(id, {}) as Dictionary


func effect_ids() -> Array[String]:
	var out: Array[String] = []
	for id: Variant in effects:
		out.append(String(id))
	out.sort()
	return out


## Ligacao de uma habilidade: {cast?, delay?, projectile?, muzzle?, impact?, shake?...} ({} se nao ha).
func skill_binding(skill_id: String) -> Dictionary:
	return (bindings.get("skills", {}) as Dictionary).get(skill_id, {}) as Dictionary


## Ligacao de um ataque de inimigo: override por id do ataque, senao o padrao do kind (melee/aoe/projectile/charge/summon).
func enemy_binding(kind_name: String, attack_id: String) -> Dictionary:
	var eb: Dictionary = bindings.get("enemy_attacks", {}) as Dictionary
	var ov: Dictionary = (eb.get("overrides", {}) as Dictionary).get(attack_id, {}) as Dictionary
	var base: Dictionary = ((eb.get("kinds", {}) as Dictionary).get(kind_name, {}) as Dictionary).duplicate()
	base.merge(ov, true)
	return base


func event_effect(key: String) -> String:
	return String((bindings.get("events", {}) as Dictionary).get(key, ""))


## Efeito de loot por raridade (cai em "common" se a raridade nao tem entrada).
func drop_effect(rarity: String) -> String:
	var d: Dictionary = (bindings.get("drops", {}) as Dictionary)
	return String(d.get(rarity, d.get("common", "")))


func rarity_color(rarity: String) -> Color:
	var c: Variant = (bindings.get("rarity_colors", {}) as Dictionary).get(rarity, null)
	return color_of(c, Color(0.8, 0.8, 0.8))


func telegraph_color(kind_name: String) -> Color:
	return color_of((bindings.get("telegraph_colors", {}) as Dictionary).get(kind_name, null), Color(0.9, 0.2, 0.1))


func tier_scale(tier: String) -> float:
	return float((bindings.get("tier_scale", {}) as Dictionary).get(tier, 1.0))


static func color_of(v: Variant, fallback: Color = Color.WHITE) -> Color:
	if typeof(v) == TYPE_ARRAY and (v as Array).size() >= 3:
		var a: Array = v
		return Color(float(a[0]), float(a[1]), float(a[2]), float(a[3]) if a.size() > 3 else 1.0)
	return fallback


static func vec3_of(v: Variant, fallback: Vector3 = Vector3.ZERO) -> Vector3:
	if typeof(v) == TYPE_ARRAY and (v as Array).size() == 3:
		var a: Array = v
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return fallback


## Ids de efeito citados em bindings (habilidades, ataques, eventos, drops).
func referenced_effect_ids() -> Array[String]:
	var out: Array[String] = []
	var add: Callable = func(v: Variant) -> void:
		if typeof(v) == TYPE_STRING and not String(v).is_empty() and not out.has(String(v)):
			out.append(String(v))
	for k: Variant in (bindings.get("skills", {}) as Dictionary):
		for f: String in ["cast", "muzzle", "projectile", "impact", "end", "extra"]:
			add.call(((bindings["skills"] as Dictionary)[k] as Dictionary).get(f, ""))
	var eb: Dictionary = bindings.get("enemy_attacks", {}) as Dictionary
	for grp: String in ["kinds", "overrides"]:
		for k: Variant in (eb.get(grp, {}) as Dictionary):
			for f: String in ["windup", "strike", "projectile", "impact", "end"]:
				add.call(((eb[grp] as Dictionary)[k] as Dictionary).get(f, ""))
	for k: Variant in (bindings.get("events", {}) as Dictionary):
		add.call((bindings["events"] as Dictionary)[k])
	for k: Variant in (bindings.get("drops", {}) as Dictionary):
		add.call((bindings["drops"] as Dictionary)[k])
	out.sort()
	return out


## Erros de esquema/referencias (vazia = valido). `known_skills` (opcional) valida os ids de habilidade de `bindings.skills`.
func validate(known_skills: Array = []) -> Array[String]:
	var errs: Array[String] = load_errors.duplicate()
	var types: Dictionary = schema.get("layer_types", {}) as Dictionary
	var common: Dictionary = schema.get("common", {}) as Dictionary
	var eff_keys: Dictionary = schema.get("effect_keys", {}) as Dictionary
	if effects.is_empty():
		errs.append("nenhum efeito carregado")
	for id: String in effect_ids():
		if not Protocol.is_content_id(id):
			errs.append("efeito '%s': id invalido" % id)
		var def: Variant = effects[id]
		if typeof(def) != TYPE_DICTIONARY:
			errs.append("efeito '%s': deve ser objeto" % id)
			continue
		var d: Dictionary = def
		for k: Variant in d:
			if not eff_keys.has(k):
				errs.append("efeito '%s': chave desconhecida '%s'" % [id, k])
		for k2: String in ["priority", "fade_out"]:
			if d.has(k2) and not _check_field(eff_keys[k2] as Dictionary, d[k2]):
				errs.append("efeito '%s': %s invalido" % [id, k2])
		var layers: Variant = d.get("layers", null)
		if typeof(layers) != TYPE_ARRAY or (layers as Array).is_empty():
			errs.append("efeito '%s': layers deve ser lista nao vazia" % id)
			continue
		if (layers as Array).size() > 12:
			errs.append("efeito '%s': camadas demais (> 12)" % id)
		for i: int in (layers as Array).size():
			var L: Variant = (layers as Array)[i]
			var tag: String = "efeito '%s' camada %d" % [id, i]
			if typeof(L) != TYPE_DICTIONARY:
				errs.append(tag + ": deve ser objeto")
				continue
			var ty: String = String((L as Dictionary).get("type", ""))
			if not types.has(ty):
				errs.append("%s: type '%s' desconhecido" % [tag, ty])
				continue
			var spec: Dictionary = (types[ty] as Dictionary)
			for k3: Variant in (L as Dictionary):
				var fs: Variant = common.get(k3, spec.get(k3, null))
				if fs == null:
					errs.append("%s (%s): campo desconhecido '%s'" % [tag, ty, k3])
				elif not _check_field(fs as Dictionary, (L as Dictionary)[k3]):
					errs.append("%s (%s): valor invalido em '%s'" % [tag, ty, k3])
			for k4: Variant in common:
				if bool((common[k4] as Dictionary).get("req", false)) and not (L as Dictionary).has(k4):
					errs.append("%s (%s): falta '%s'" % [tag, ty, k4])
			for k5: Variant in spec:
				if bool((spec[k5] as Dictionary).get("req", false)) and not (L as Dictionary).has(k5):
					errs.append("%s (%s): falta '%s'" % [tag, ty, k5])
	for rid: String in referenced_effect_ids():
		if not effects.has(rid):
			errs.append("bindings referencia efeito inexistente '%s'" % rid)
	if not known_skills.is_empty():
		for sid: Variant in (bindings.get("skills", {}) as Dictionary):
			if not known_skills.has(String(sid)):
				errs.append("bindings.skills: habilidade inexistente '%s'" % sid)
	return errs


func _check_field(fs: Dictionary, v: Variant) -> bool:
	var t: String = String(fs.get("t", ""))
	match t:
		"num":
			return Protocol.is_finite_number(v) and float(v) >= float(fs.get("min", -1.0e9)) and float(v) <= float(fs.get("max", 1.0e9))
		"int":
			return typeof(v) in [TYPE_INT, TYPE_FLOAT] and float(v) == floorf(float(v)) and float(v) >= float(fs.get("min", -1.0e9)) and float(v) <= float(fs.get("max", 1.0e9))
		"bool":
			return typeof(v) == TYPE_BOOL
		"str":
			return typeof(v) == TYPE_STRING
		"enum":
			return typeof(v) == TYPE_STRING and (fs.get("values", []) as Array).has(v)
		"sprite":
			return typeof(v) == TYPE_STRING and (schema.get("sprites", []) as Array).has(v)
		"color":
			if typeof(v) != TYPE_ARRAY or (v as Array).size() < 3 or (v as Array).size() > 4:
				return false
			for x: Variant in v:
				if not Protocol.is_finite_number(x) or float(x) < 0.0 or float(x) > 8.0:
					return false
			return true
		"vec3":
			if typeof(v) != TYPE_ARRAY or (v as Array).size() != 3:
				return false
			for x2: Variant in v:
				if not Protocol.is_finite_number(x2) or absf(float(x2)) > 30.0:
					return false
			return true
		"range":
			if typeof(v) != TYPE_ARRAY or (v as Array).size() != 2:
				return false
			var a: Variant = (v as Array)[0]
			var b: Variant = (v as Array)[1]
			return Protocol.is_finite_number(a) and Protocol.is_finite_number(b) and float(a) <= float(b) and float(a) >= float(fs.get("min", -1.0e9)) and float(b) <= float(fs.get("max", 1.0e9))
	return false
