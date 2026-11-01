class_name ClassCatalog
extends RefCounted
## Catalogo de classes carregado de data/classes/*.json (arquivos que comecam com "_" sao ignorados; o nome do arquivo
## = id da classe). `validate_refs()` confere as referencias cruzadas (habilidades existem, tipo certo por slot, especializacoes
## unicas no catalogo). O backend valida o `class_id` contra shared/content_schemas/classes.json, gerado dos MESMOS arquivos.

const CLASSES_DIR: String = "res://data/classes"
const SKILLS_DIR: String = "res://data/skills"
const DEFAULT_CLASS_ID: String = "warrior"

static var _shared: ClassCatalog = null
static var _skill_cache: Dictionary = {} ## StringName -> SkillData

var classes: Dictionary = {} ## id -> ClassDef
var load_errors: Array[String] = []


static func shared() -> ClassCatalog:
	if _shared == null:
		_shared = load_dir(CLASSES_DIR)
	return _shared


static func load_dir(dir_path: String = CLASSES_DIR) -> ClassCatalog:
	var c: ClassCatalog = ClassCatalog.new()
	for n: String in JsonDir.list_json(dir_path):
		var r: Dictionary = JsonDir.read_json(dir_path + "/" + n)
		if not bool(r["ok"]):
			c.load_errors.append(String(r["error"]))
			continue
		var p: Dictionary = ClassDef.parse(r["data"])
		if p["def"] == null:
			for e: String in (p["errors"] as Array):
				c.load_errors.append("%s: %s" % [n, e])
			continue
		var def: ClassDef = p["def"]
		if n.trim_suffix(".json") != def.id:
			c.load_errors.append("%s: nome do arquivo difere do id '%s'" % [n, def.id])
			continue
		c.add(def)
	return c


func add(def: ClassDef) -> void:
	if classes.has(def.id):
		load_errors.append("class id duplicado: " + def.id)
		return
	classes[def.id] = def


func get_def(class_id: String) -> ClassDef:
	return classes.get(class_id) as ClassDef


func has_class(class_id: Variant) -> bool:
	return typeof(class_id) == TYPE_STRING and classes.has(String(class_id))


func default_def() -> ClassDef:
	return get_def(DEFAULT_CLASS_ID)


func ids() -> Array[String]:
	var out: Array[String] = []
	for k: Variant in classes:
		out.append(String(k))
	out.sort()
	return out


## SkillData de data/skills/<id>.tres (cache de processo); null se ausente ou invalido.
static func load_skill(skill_id: StringName) -> SkillData:
	if _skill_cache.has(skill_id):
		return _skill_cache[skill_id] as SkillData
	var path: String = "%s/%s.tres" % [SKILLS_DIR, skill_id]
	if not ClassDef.is_valid_id(String(skill_id)) or not ResourceLoader.exists(path):
		return null
	var skill: SkillData = load(path) as SkillData
	if skill == null or skill.id != skill_id:
		return null
	_skill_cache[skill_id] = skill
	return skill


## Referencias cruzadas e consistencia. Lista de erros (vazia = ok). Inclui os erros de carga.
func validate_refs() -> Array[String]:
	var errors: Array[String] = load_errors.duplicate()
	if not classes.has(DEFAULT_CLASS_ID):
		errors.append("classe padrao ausente: " + DEFAULT_CLASS_ID)
	var spec_ids: Dictionary = {}
	var skill_owner: Dictionary = {}
	for cid: String in ids():
		var def: ClassDef = classes[cid]
		for slot: String in ClassDef.SLOTS:
			var sid: String = String(def.skills.get(slot, ""))
			var skill: SkillData = load_skill(StringName(sid))
			if skill == null:
				errors.append("%s: habilidade '%s' (slot %s) inexistente em data/skills" % [cid, sid, slot])
				continue
			for e: String in skill.validate():
				errors.append("%s: habilidade %s invalida: %s" % [cid, sid, e])
			var wants_dodge: bool = slot == "dodge"
			if (skill.kind == SkillData.Kind.DODGE) != wants_dodge:
				errors.append("%s: slot %s exige habilidade %s" % [cid, slot, "de esquiva" if wants_dodge else "de ataque"])
			if slot == "attack" and skill.resource_cost > 0.0:
				errors.append("%s: o ataque basico nao pode custar recurso" % cid)
			# Habilidades exclusivas por classe, exceto o conjunto compartilhado explicito (nenhum hoje).
			if skill_owner.has(sid) and skill_owner[sid] != cid:
				errors.append("habilidade '%s' usada pelas classes %s e %s" % [sid, skill_owner[sid], cid])
			skill_owner[sid] = cid
		if def.active_specializations().size() < 1:
			errors.append("%s: precisa de ao menos 1 especializacao inicial (planned = false)" % cid)
		for s: Dictionary in def.specializations:
			if spec_ids.has(s["id"]):
				errors.append("especializacao '%s' duplicada entre classes" % s["id"])
			spec_ids[s["id"]] = cid
	return errors
