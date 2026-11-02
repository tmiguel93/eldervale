extends RefCounted
## E8.4: mapeamento data-driven de icones game-icons.net (data/ui/icons.json): arquivos existem, cobertura de habilidades/itens/
## classes/tipos/slots/atributos e fallback (letra/primitiva) quando nao ha icone.


func run(ctx: Variant) -> void:
	await (ctx as SceneTree).physics_frame
	UiIcons.reload()
	var errs: Array[String] = UiIcons.validate()
	ctx.check(errs.is_empty(), "icons.json valido e todos os arquivos existem %s" % [errs.slice(0, 4)])
	var refs: Array[String] = UiIcons.all_refs()
	ctx.check(refs.size() >= 40, "ao menos 40 icones referenciados (%d)" % refs.size())
	for r: String in refs:
		if not UiIcons.exists(r):
			ctx.check(false, "icone inexistente: " + r)
	# cobertura
	for f: String in DirAccess.get_files_at("res://data/skills"):
		if f.ends_with(".tres"):
			var id: String = f.get_basename()
			ctx.check(not UiIcons.skill_ref(id).is_empty(), "habilidade '%s' tem icone" % id)
	for f2: String in DirAccess.get_files_at("res://data/items"):
		if f2.ends_with(".tres"):
			var iid: String = f2.get_basename()
			ctx.check(not UiIcons.item_ref(iid).is_empty(), "item '%s' tem icone" % iid)
	for cid: String in ClassCatalog.shared().ids():
		ctx.check(not UiIcons.class_ref(cid).is_empty(), "classe '%s' tem icone" % cid)
		for sk: String in ["attack", "skill_1", "skill_2", "dodge"]:
			var sid: String = String(ClassCatalog.shared().get_def(cid).skills.get(sk, ""))
			if not sid.is_empty():
				ctx.check(not UiIcons.skill_ref(sid).is_empty(), "habilidade %s/%s tem icone" % [cid, sid])
	for t: String in ["weapon", "armor", "trinket", "consumable", "material", "misc"]:
		ctx.check(not UiIcons.ref("item_types", t).is_empty(), "tipo de item '%s' tem icone de fallback" % t)
	for s: String in ["weapon", "armor", "trinket"]:
		ctx.check(not UiIcons.ref("equip_slots", s).is_empty(), "slot '%s' tem icone" % s)
	for a: String in ["max_health", "max_resource", "resource_regen", "attack_power", "defense", "resistance", "move_speed"]:
		ctx.check(not UiIcons.attribute_ref(a).is_empty(), "atributo '%s' tem icone" % a)
	# fallbacks
	ctx.check(UiIcons.skill_ref("habilidade_inexistente").is_empty(), "habilidade desconhecida => referencia vazia")
	ctx.check(UiIcons.texture("lorc/nao-existe") == null and UiIcons.texture("") == null, "referencia ruim => sem textura (sem erro)")
	var fb: Control = UiIcons.make("lorc/nao-existe", 32.0, Color.WHITE, "espada")
	ctx.check(fb is Label and (fb as Label).text == "E" and fb.has_meta("icon_fallback"), "icone ausente vira letra (fallback de texto)")
	fb.free()
	var ok: Control = UiIcons.make(UiIcons.skill_ref("fireball"), 32.0, Color.WHITE, "x")
	ctx.check(ok is TextureRect and (ok as TextureRect).texture != null, "icone existente vira TextureRect com textura")
	ok.free()
	# luma->alfa: o fundo preto do SVG nao pode ficar opaco fora do headless; em headless e a textura crua (sem erro)
	var tex: Texture2D = UiIcons.texture(UiIcons.skill_ref("fireball"))
	ctx.check(tex != null and tex.get_width() > 0, "textura carregada (%dx%d)" % [tex.get_width() if tex else 0, tex.get_height() if tex else 0])
	# item desconhecido cai no icone do tipo/miscelanea; nunca vazio
	ctx.check(not UiIcons.item_ref("item_inexistente").is_empty(), "item desconhecido usa icone generico")
