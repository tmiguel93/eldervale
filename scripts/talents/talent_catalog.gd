class_name TalentCatalog
extends RefCounted
## Catalogo de arvores de talentos (E6.2): data/talents/<class_id>.json (uma arvore por classe; o nome do arquivo = class_id) e
## data/talents/_progression.json (curva de pontos por nivel + respec). Conferencia cruzada com classes/habilidades/itens em
## `validate_refs`. O backend usa shared/content_schemas/talents.json, gerado dos MESMOS arquivos (tools/gen_talents_catalog.mjs).

const TALENTS_DIR: String = "res://data/talents"
const PROGRESSION_FILE: String = "_progression.json"

static var _shared: TalentCatalog = null

var trees: Dictionary = {} ## class_id -> TalentTree
var load_errors: Array[String] = []
## Pontos: pontos(level) = clamp((level - first_point_level + 1) * points_per_level, 0, max_points).
var first_point_level: int = 2
var points_per_level: int = 1
var max_points: int = 60
## Respec: itens consumidos (do INVENTARIO) e se so vale em zona segura (hub). [{item_id, qty}]
var respec_cost_items: Array[Dictionary] = []
var respec_require_safe_zone: bool = true


static func shared() -> TalentCatalog:
	if _shared == null:
		_shared = load_dir(TALENTS_DIR)
	return _shared


static func load_dir(dir_path: String = TALENTS_DIR) -> TalentCatalog:
	var c: TalentCatalog = TalentCatalog.new()
	c._load_progression(dir_path + "/" + PROGRESSION_FILE)
	var classes: ClassCatalog = ClassCatalog.shared()
	for n: String in JsonDir.list_json(dir_path):
		var r: Dictionary = JsonDir.read_json(dir_path + "/" + n)
		if not bool(r["ok"]):
			c.load_errors.append(String(r["error"]))
			continue
		var p: Dictionary = TalentTree.parse(r["data"])
		if p["tree"] == null:
			for e: String in (p["errors"] as Array):
				c.load_errors.append("%s: %s" % [n, e])
			continue
		var tree: TalentTree = p["tree"]
		if n.trim_suffix(".json") != tree.class_id:
			c.load_errors.append("%s: nome do arquivo difere do class_id '%s'" % [n, tree.class_id])
			continue
		if c.trees.has(tree.class_id):
			c.load_errors.append("class_id duplicado: " + tree.class_id)
			continue
		var def: ClassDef = classes.get_def(tree.class_id)
		if def != null:
			for s: Dictionary in def.active_specializations():
				tree.specs.append(String(s["id"]))
		c.trees[tree.class_id] = tree
	return c


func _load_progression(path: String) -> void:
	var r: Dictionary = JsonDir.read_json(path)
	if not bool(r["ok"]):
		load_errors.append(String(r["error"]))
		return
	if typeof(r["data"]) != TYPE_DICTIONARY:
		load_errors.append("_progression.json: raiz deve ser objeto")
		return
	var d: Dictionary = r["data"]
	for k: Variant in d:
		if not ["schema_version", "points", "respec"].has(String(k)):
			load_errors.append("_progression.json: campo desconhecido " + String(k).left(40))
	var pt: Variant = d.get("points", null)
	if typeof(pt) != TYPE_DICTIONARY:
		load_errors.append("_progression.json: points deve ser objeto")
	else:
		var p: Dictionary = pt
		for kv: Array in [["first_point_level", 2, 50], ["points_per_level", 1, 5], ["max_points", 1, 500]]:
			if not TalentTree._is_int(p.get(kv[0], null)) or int(p[kv[0]]) < int(kv[1]) or int(p[kv[0]]) > int(kv[2]):
				load_errors.append("_progression.json: points.%s deve ser inteiro %d..%d" % [kv[0], kv[1], kv[2]])
			else:
				set(String(kv[0]), int(p[kv[0]]))
	var rs: Variant = d.get("respec", null)
	if typeof(rs) != TYPE_DICTIONARY:
		load_errors.append("_progression.json: respec deve ser objeto")
		return
	var rd: Dictionary = rs
	if typeof(rd.get("require_safe_zone", null)) != TYPE_BOOL:
		load_errors.append("_progression.json: respec.require_safe_zone deve ser bool")
	else:
		respec_require_safe_zone = bool(rd["require_safe_zone"])
	var items: Variant = rd.get("cost_items", null)
	if typeof(items) != TYPE_ARRAY or (items as Array).size() > 3:
		load_errors.append("_progression.json: respec.cost_items deve ser lista de ate 3")
		return
	var seen: Dictionary = {}
	for it: Variant in items:
		if typeof(it) != TYPE_DICTIONARY or not ClassDef.is_valid_id((it as Dictionary).get("item_id", null)) or seen.has(String((it as Dictionary)["item_id"])) \
				or not TalentTree._is_int((it as Dictionary).get("qty", null)) or int((it as Dictionary)["qty"]) < 1 or int((it as Dictionary)["qty"]) > 99:
			load_errors.append("_progression.json: respec.cost_items com entrada invalida")
			continue
		seen[String((it as Dictionary)["item_id"])] = true
		respec_cost_items.append({"item_id": String((it as Dictionary)["item_id"]), "qty": int((it as Dictionary)["qty"])})


func get_tree(class_id: String) -> TalentTree:
	return trees.get(class_id) as TalentTree


func has_tree(class_id: Variant) -> bool:
	return typeof(class_id) == TYPE_STRING and trees.has(String(class_id))


func ids() -> Array[String]:
	var out: Array[String] = []
	for k: Variant in trees:
		out.append(String(k))
	out.sort()
	return out


## Pontos de talento totais concedidos pelo nivel (curva de dado).
func points_for_level(level: int) -> int:
	var n: int = maxi(0, level - first_point_level + 1) * points_per_level
	return mini(n, max_points)


## Referencias cruzadas: classe existe e tem arvore, habilidades-alvo pertencem a classe e respeitam o tipo do modificador, item do respec existe.
func validate_refs(classes: ClassCatalog, registry: ContentRegistry = null) -> Array[String]:
	var errors: Array[String] = load_errors.duplicate()
	for cid: String in classes.ids():
		if not trees.has(cid):
			errors.append("classe '%s' sem arvore de talentos" % cid)
	for cid: String in ids():
		var tree: TalentTree = trees[cid]
		var def: ClassDef = classes.get_def(cid)
		if def == null:
			errors.append("arvore '%s': classe inexistente" % cid)
			continue
		for id: String in tree.order:
			var n: Dictionary = tree.nodes[id]
			var spec: String = String(n["spec"])
			if spec != "" and not tree.specs.has(spec):
				errors.append("%s/%s: spec '%s' nao e uma especializacao inicial da classe" % [cid, id, spec])
			for fx: Dictionary in (n["effects"] as Array):
				if String(fx["type"]) != "skill_mod":
					continue
				var sid: String = String(fx["skill"])
				if not def.has_skill(sid):
					errors.append("%s/%s: habilidade '%s' nao pertence a classe" % [cid, id, sid])
					continue
				var skill: SkillData = ClassCatalog.load_skill(StringName(sid))
				if skill == null:
					continue
				var is_dodge: bool = skill.kind == SkillData.Kind.DODGE
				match String(fx["mod"]):
					"extra_projectiles":
						if not skill.is_projectile():
							errors.append("%s/%s: extra_projectiles exige habilidade com projetil (%s)" % [cid, id, sid])
					"duration":
						if not is_dodge:
							errors.append("%s/%s: duration exige habilidade de esquiva (%s)" % [cid, id, sid])
					"area", "convert", "condition", "synergy":
						if is_dodge:
							errors.append("%s/%s: %s nao se aplica a esquiva (%s)" % [cid, id, fx["mod"], sid])
				if String(fx["mod"]) == "synergy":
					if not def.has_skill(String(fx["after_skill"])):
						errors.append("%s/%s: after_skill '%s' nao pertence a classe" % [cid, id, fx["after_skill"]])
					elif String(fx["after_skill"]) == sid:
						errors.append("%s/%s: after_skill deve ser outra habilidade" % [cid, id])
	if registry != null:
		for it: Dictionary in respec_cost_items:
			if registry.get_item(StringName(String(it["item_id"]))) == null:
				errors.append("respec: item '%s' inexistente" % it["item_id"])
	return errors
