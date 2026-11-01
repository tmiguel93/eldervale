extends RefCounted
## E6.1 - modelo de classe como dado: carga, validacao, referencias cruzadas, payload invalido e consistencia com o catalogo
## do backend (shared/content_schemas/classes.json, gerado por tools/gen_classes_catalog.mjs).

const C = preload("res://tests/e6_classes/class_helpers.gd")


func run(ctx: Object) -> void:
	var tree: SceneTree = ctx as SceneTree
	await tree.physics_frame
	_test_catalog_loads(ctx)
	_test_class_contents(ctx)
	_test_skill_data_validation(ctx)
	_test_parse_rejects(ctx)
	_test_cross_refs(ctx)
	_test_backend_catalog_in_sync(ctx)


func _test_catalog_loads(ctx: Object) -> void:
	var cat: ClassCatalog = ClassCatalog.load_dir()
	ctx.check(cat.load_errors.is_empty(), "catalogo carrega sem erros %s" % str(cat.load_errors))
	ctx.check(cat.ids() == ["mage", "ranger", "warrior"], "3 classes jogaveis: %s" % str(cat.ids()))
	ctx.check(cat.validate_refs().is_empty(), "referencias cruzadas ok %s" % str(cat.validate_refs()))
	ctx.check(ClassCatalog.shared().has_class("warrior") and not ClassCatalog.shared().has_class("necromancer"), "has_class conhece o catalogo")
	ctx.check(not ClassCatalog.shared().has_class(5) and not ClassCatalog.shared().has_class(null), "has_class recusa tipos errados")
	ctx.check(ClassCatalog.shared().default_def().id == "warrior", "classe padrao = warrior")


func _test_class_contents(ctx: Object) -> void:
	var cat: ClassCatalog = ClassCatalog.shared()
	var expected_spec: Dictionary = {"warrior": "berserker", "mage": "elementalist", "ranger": "hunter"}
	var gdd_specs: Dictionary = {
		"warrior": ["berserker", "guardian", "arcane_knight"],
		"mage": ["elementalist", "summoner", "arcanist"],
		"ranger": ["hunter", "explorer", "arcane_archer"],
	}
	var kinds: Dictionary = {"warrior": "stamina", "mage": "mana", "ranger": "stamina"}
	for cid: String in C.CLASS_IDS:
		var def: ClassDef = cat.get_def(cid)
		ctx.check(def != null and def.id == cid, "%s: id estavel" % cid)
		ctx.check(def.skill_ids() == C.SKILLS[cid], "%s: habilidades por slot %s" % [cid, str(def.skill_ids())])
		ctx.check(def.skill_ids().size() >= 4 and def.skill_ids().size() <= 6, "%s: 4..6 habilidades" % cid)
		ctx.check(def.resource_kind == kinds[cid], "%s: recurso %s" % [cid, def.resource_kind])
		var ids: Array = []
		for s: Dictionary in def.specializations:
			ids.append(s["id"])
		ctx.check(ids == gdd_specs[cid], "%s: especializacoes do GDD registradas %s" % [cid, str(ids)])
		ctx.check(def.active_specializations().size() == 1 and def.active_specializations()[0]["id"] == expected_spec[cid], "%s: UMA especializacao inicial (%s), as outras planned" % [cid, expected_spec[cid]])
		for s: Dictionary in def.specializations:
			ctx.check((s["tags"] as PackedStringArray).size() >= 1 and not String(s["display_name"]).is_empty(), "%s/%s: nome e tags" % [cid, s["id"]])
		ctx.check(def.base_stats.max_health > 0.0 and def.base_stats.max_resource > 0.0 and def.growth.max_health > 0.0, "%s: stats base e crescimento positivos" % cid)
	ctx.check(cat.get_def("warrior").get_specialization("guardian")["planned"] == true, "guardian: planned sem mecanica")
	ctx.check(cat.get_def("warrior").get_specialization("nope").is_empty(), "especializacao inexistente = vazio")
	ctx.check(cat.get_def("mage").slot_of("fireball") == "skill_1" and cat.get_def("mage").slot_of("heavy_strike") == "", "slot_of por habilidade")


func _test_skill_data_validation(ctx: Object) -> void:
	for cid: String in C.CLASS_IDS:
		for sid: String in C.SKILLS[cid]:
			var sk: SkillData = ClassCatalog.load_skill(StringName(sid))
			ctx.check(sk != null, "carrega skill %s" % sid)
			if sk == null:
				continue
			ctx.check(sk.validate().is_empty(), "%s: valida %s" % [sid, str(sk.validate())])
			ctx.check(sk.id == StringName(sid), "%s: id = nome do arquivo" % sid)
	var bad: SkillData = SkillData.new()
	bad.id = &"x"
	bad.display_name = "X"
	bad.projectile_speed = 10.0
	ctx.check(not bad.validate().is_empty(), "projetil sem esfera/alcance rejeitado")
	bad.hitbox_shape = SkillData.HitboxShape.SPHERE
	bad.projectile_range = 10.0
	ctx.check(bad.validate().is_empty() and bad.is_projectile(), "projetil corrigido valido")
	bad.projectile_pierce = 99
	ctx.check(not bad.validate().is_empty(), "pierce acima do limite rejeitado")
	bad.projectile_pierce = 0
	bad.projectile_speed = 0.0
	ctx.check(not bad.validate().is_empty(), "alcance sem velocidade rejeitado")
	bad.projectile_range = 0.0
	bad.kind = SkillData.Kind.DODGE
	bad.i_frames = 0.1
	bad.dodge_distance = 2.0
	bad.recover = 0.2
	bad.projectile_speed = 5.0
	ctx.check(not bad.validate().is_empty(), "esquiva nao pode disparar projetil")
	ctx.check(ClassCatalog.load_skill(&"../x") == null and ClassCatalog.load_skill(&"no_such_skill") == null, "load_skill recusa id invalido/inexistente")


func _valid_raw() -> Dictionary:
	return (JSON.parse_string(FileAccess.get_file_as_string("res://data/classes/mage.json")) as Dictionary).duplicate(true)


func _parse_errors(raw: Variant) -> Array:
	return ClassDef.parse(raw)["errors"]


func _test_parse_rejects(ctx: Object) -> void:
	var ok: Dictionary = ClassDef.parse(_valid_raw())
	ctx.check(ok["def"] != null and (ok["errors"] as Array).is_empty(), "json valido parseia")
	ctx.check(ClassDef.parse(5)["def"] == null and ClassDef.parse(null)["def"] == null and ClassDef.parse([])["def"] == null, "raiz nao-objeto rejeitada")
	var r: Dictionary = _valid_raw()
	r["extra"] = 1
	ctx.check(not _parse_errors(r).is_empty(), "campo desconhecido rejeitado")
	r = _valid_raw()
	r["id"] = "Mage"
	ctx.check(not _parse_errors(r).is_empty(), "id com maiuscula rejeitado")
	r = _valid_raw()
	r["id"] = "../etc"
	ctx.check(not _parse_errors(r).is_empty(), "id com caminho rejeitado")
	r = _valid_raw()
	r["schema_version"] = 2
	ctx.check(not _parse_errors(r).is_empty(), "schema_version 2 rejeitada")
	r = _valid_raw()
	r["resource"] = {"kind": "rage"}
	ctx.check(not _parse_errors(r).is_empty(), "recurso desconhecido rejeitado")
	r = _valid_raw()
	r["base_stats"]["max_health"] = -1
	ctx.check(not _parse_errors(r).is_empty(), "stat negativo rejeitado")
	r = _valid_raw()
	r["base_stats"]["resistance"] = 0.9
	ctx.check(not _parse_errors(r).is_empty(), "resistencia > 0.75 rejeitada")
	r = _valid_raw()
	r["base_stats"].erase("defense")
	ctx.check(not _parse_errors(r).is_empty(), "stat base ausente rejeitado")
	r = _valid_raw()
	r["base_stats"]["max_health"] = "100"
	ctx.check(not _parse_errors(r).is_empty(), "stat string rejeitado")
	r = _valid_raw()
	r["growth_per_level"]["luck"] = 1
	ctx.check(not _parse_errors(r).is_empty(), "chave de crescimento desconhecida rejeitada")
	r = _valid_raw()
	r["skills"].erase("dodge")
	ctx.check(not _parse_errors(r).is_empty(), "slot sem habilidade rejeitado")
	r = _valid_raw()
	r["skills"]["skill_3"] = "fireball"
	ctx.check(not _parse_errors(r).is_empty(), "slot desconhecido rejeitado")
	r = _valid_raw()
	r["skills"]["skill_2"] = "fireball"
	ctx.check(not _parse_errors(r).is_empty(), "habilidade repetida entre slots rejeitada")
	r = _valid_raw()
	r["specializations"] = []
	ctx.check(not _parse_errors(r).is_empty(), "sem especializacoes rejeitado")
	r = _valid_raw()
	r["specializations"][1]["id"] = "elementalist"
	ctx.check(not _parse_errors(r).is_empty(), "especializacao duplicada rejeitada")
	r = _valid_raw()
	r["specializations"][0]["planned"] = "no"
	ctx.check(not _parse_errors(r).is_empty(), "planned nao-bool rejeitado")
	r = _valid_raw()
	r["specializations"][0]["tags"] = []
	ctx.check(not _parse_errors(r).is_empty(), "especializacao sem tags rejeitada")


func _test_cross_refs(ctx: Object) -> void:
	# classe valida em memoria + variacoes que quebram as referencias
	var base: Dictionary = _valid_raw()
	var cat: ClassCatalog = ClassCatalog.new()
	cat.add(ClassCatalog.shared().get_def("warrior"))
	var m: ClassDef = ClassDef.parse(base)["def"]
	cat.add(m)
	ctx.check(cat.validate_refs().is_empty(), "catalogo parcial valido (warrior + mage)")

	var broken: Dictionary = _valid_raw()
	broken["skills"]["skill_1"] = "meteor_swarm"
	var d1: ClassDef = ClassDef.parse(broken)["def"]
	var c1: ClassCatalog = ClassCatalog.new()
	c1.add(ClassCatalog.shared().get_def("warrior"))
	c1.add(d1)
	ctx.check(not c1.validate_refs().is_empty(), "habilidade inexistente detectada")

	broken = _valid_raw()
	broken["skills"]["dodge"] = "fireball"
	broken["skills"]["skill_1"] = "blink"
	var c2: ClassCatalog = ClassCatalog.new()
	c2.add(ClassCatalog.shared().get_def("warrior"))
	c2.add(ClassDef.parse(broken)["def"])
	ctx.check(not c2.validate_refs().is_empty(), "slot dodge com ataque / slot de ataque com esquiva detectado")

	broken = _valid_raw()
	broken["skills"]["skill_1"] = "heavy_strike" # pertence ao guerreiro
	var c3: ClassCatalog = ClassCatalog.new()
	c3.add(ClassCatalog.shared().get_def("warrior"))
	c3.add(ClassDef.parse(broken)["def"])
	ctx.check(not c3.validate_refs().is_empty(), "habilidade compartilhada entre classes detectada")

	broken = _valid_raw()
	broken["skills"]["attack"] = "fireball" # ataque basico nao pode custar recurso
	broken["skills"]["skill_1"] = "arcane_bolt"
	var c4: ClassCatalog = ClassCatalog.new()
	c4.add(ClassCatalog.shared().get_def("warrior"))
	c4.add(ClassDef.parse(broken)["def"])
	ctx.check(not c4.validate_refs().is_empty(), "ataque basico com custo detectado")

	broken = _valid_raw()
	broken["specializations"][0]["id"] = "berserker" # ja existe no guerreiro
	var c5: ClassCatalog = ClassCatalog.new()
	c5.add(ClassCatalog.shared().get_def("warrior"))
	c5.add(ClassDef.parse(broken)["def"])
	ctx.check(not c5.validate_refs().is_empty(), "especializacao duplicada entre classes detectada")

	broken = _valid_raw()
	for s: Dictionary in broken["specializations"]:
		s["planned"] = true
	var c6: ClassCatalog = ClassCatalog.new()
	c6.add(ClassCatalog.shared().get_def("warrior"))
	c6.add(ClassDef.parse(broken)["def"])
	ctx.check(not c6.validate_refs().is_empty(), "classe sem especializacao inicial detectada")

	var c7: ClassCatalog = ClassCatalog.new()
	c7.add(m)
	ctx.check(not c7.validate_refs().is_empty(), "catalogo sem a classe padrao detectado")
	var c8: ClassCatalog = ClassCatalog.new()
	c8.add(m)
	c8.add(m)
	ctx.check(not c8.load_errors.is_empty(), "id de classe duplicado registrado como erro")


func _test_backend_catalog_in_sync(ctx: Object) -> void:
	var text: String = FileAccess.get_file_as_string("res://shared/content_schemas/classes.json")
	var raw: Variant = JSON.parse_string(text)
	ctx.check(typeof(raw) == TYPE_DICTIONARY and int((raw as Dictionary).get("schema_version", 0)) == 1, "classes.json do backend existe (schema 1)")
	if typeof(raw) != TYPE_DICTIONARY:
		return
	var by_id: Dictionary = {}
	for e: Variant in (raw as Dictionary)["classes"]:
		by_id[String((e as Dictionary)["id"])] = e
	var be_ids: Array[String] = []
	for k: Variant in by_id:
		be_ids.append(String(k))
	be_ids.sort()
	ctx.check(be_ids.size() == 3 and ClassCatalog.shared().ids() == be_ids, "mesmos ids no backend e no jogo")
	for cid: String in C.CLASS_IDS:
		var def: ClassDef = ClassCatalog.shared().get_def(cid)
		var b: Dictionary = by_id[cid]
		var same: bool = true
		for k: String in ClassDef.STAT_KEYS:
			same = same and is_equal_approx(float((b["base_stats"] as Dictionary)[k]), float(def.base_stats.get(k)))
		ctx.check(same, "%s: base_stats iguais no backend" % cid)
		ctx.check((b["skills"] as Dictionary) == def.skills, "%s: habilidades iguais no backend" % cid)
		ctx.check(String(b["resource_kind"]) == def.resource_kind, "%s: recurso igual no backend" % cid)
		var planned_ok: bool = (b["specializations"] as Array).size() == def.specializations.size()
		for i: int in def.specializations.size():
			var be: Dictionary = (b["specializations"] as Array)[i]
			planned_ok = planned_ok and String(be["id"]) == String(def.specializations[i]["id"]) and bool(be["planned"]) == bool(def.specializations[i]["planned"])
		ctx.check(planned_ok, "%s: especializacoes iguais no backend" % cid)
