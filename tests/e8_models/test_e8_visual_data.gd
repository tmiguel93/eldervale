extends RefCounted
## E8.1: schema visual_* nos dados (inimigos .tres, classes e NPCs .json), validacao e mapeamento do E8_ASSETS secao 4.

const H = preload("res://tests/e8_models/e8_helpers.gd")


func run(ctx: Variant) -> void:
	await (ctx as SceneTree).physics_frame
	var all: Array = H.all_specs()
	ctx.check(all.size() == 19, "19 visuais referenciados (10 inimigos + 3 classes + 6 NPCs): %d" % all.size())
	for e: Array in all:
		var spec: VisualSpec = e[1] as VisualSpec
		ctx.check(spec != null, "%s tem visual_scene" % e[0])
		if spec == null:
			continue
		ctx.check(spec.validate().is_empty(), "%s: valores validos %s" % [e[0], str(spec.validate())])
		ctx.check(not spec.resolved_path().is_empty() and spec.path_exists(), "%s: '%s' resolve para arquivo existente (%s)" % [e[0], spec.scene, spec.resolved_path()])
	_enemies_distinct(ctx)
	_mapping(ctx)
	_negative(ctx)
	_aliases(ctx)


func _enemies_distinct(ctx: Variant) -> void:
	var seen: Dictionary = {}
	for id: StringName in EnemyCatalog.all_ids():
		var sp: VisualSpec = EnemyCatalog.data_for(id).visual_spec()
		var key: String = "%s|%.2f|%s" % [sp.scene, sp.height, sp.tint.to_html()]
		ctx.check(not seen.has(key), "inimigo %s visualmente distinguivel (modelo/escala/tintura)" % id)
		seen[key] = true
	for id: StringName in [&"bark_brute", &"blight_treant"]:
		var bd: EnemyData = EnemyCatalog.data_for(id)
		ctx.check(bd.visual_placeholder and bd.placeholder, "%s marcado PLACEHOLDER no dado" % id)
	ctx.check(EnemyCatalog.data_for(&"blight_treant").visual_height > EnemyCatalog.data_for(&"bark_brute").visual_height * 1.4, "chefe bem maior que o bruto")


func _mapping(ctx: Variant) -> void:
	var cc: ClassCatalog = ClassCatalog.shared()
	ctx.check(cc.get_def("warrior").visual.resolved_path().ends_with("/Barbarian.glb"), "Guerreiro -> Barbarian")
	ctx.check(cc.get_def("mage").visual.resolved_path().ends_with("/Mage.glb"), "Mago -> Mage")
	ctx.check(cc.get_def("ranger").visual.resolved_path().ends_with("/Rogue_Hooded.glb"), "Patrulheiro -> Rogue_Hooded")
	var expect: Dictionary = {
		&"melee_grunt": "Skeleton_Minion", &"ranged_caster": "Skeleton_Mage", &"forest_stalker": "Fox", &"bow_scout": "Skeleton_Rogue",
		&"bark_brute": "Skeleton_Warrior", &"grove_shaman": "Skeleton_Mage", &"thorn_alpha": "Wolf", &"root_sprout": "Spider",
		&"burrow_lurker": "Spider", &"blight_treant": "Skeleton_Warrior",
	}
	for id: StringName in expect:
		var p: String = EnemyCatalog.data_for(id).visual_spec().resolved_path()
		ctx.check(p.ends_with("/%s.glb" % expect[id]), "%s -> %s" % [id, expect[id]])
	var scenes: Dictionary = {}
	for nid: String in NpcDirectory.shared().ids():
		scenes[NpcDirectory.shared().get_npc(nid)["visual"].resolved_path()] = true
	ctx.check(scenes.size() >= 3, "NPCs usam varios personagens KayKit (%d modelos)" % scenes.size())


func _negative(ctx: Variant) -> void:
	var errs: Array[String] = []
	ctx.check(VisualSpec.from_dict({"id": "x"}, errs) == null and errs.is_empty(), "sem visual_scene = sem visual e sem erro")
	errs = []
	VisualSpec.from_dict({"visual_height": 2}, errs)
	ctx.check(not errs.is_empty(), "visual_height sem visual_scene e erro")
	var bad: Array[Dictionary] = [
		{"visual_scene": "../fora.glb"}, {"visual_scene": "res://outro/x.glb"}, {"visual_scene": "class.mage", "visual_height": 0},
		{"visual_scene": "class.mage", "visual_height": 99}, {"visual_scene": "class.mage", "visual_tint": [1, 1]},
		{"visual_scene": "class.mage", "visual_clips": {"voar": "Idle"}}, {"visual_scene": "class.mage", "visual_clips": {"idle": 3}},
		{"visual_scene": "class.mage", "visual_equip": "x"}, {"visual_scene": "class.mage", "visual_yaw_offset": 1000},
		{"visual_scene": 5}, {"visual_scene": "class.mage", "visual_placeholder": "sim"},
	]
	for d: Dictionary in bad:
		var e2: Array[String] = []
		ctx.check(VisualSpec.from_dict(d, e2) == null and not e2.is_empty(), "rejeita %s" % JSON.stringify(d))
	var ok_errs: Array[String] = []
	var good: VisualSpec = VisualSpec.from_dict({"visual_scene": "class.mage", "visual_height": 1.5, "visual_tint": [0.5, 0.5, 1.0], "visual_clips": {"idle": "Idle"}, "visual_equip": ["2H_Staff"], "visual_placeholder": true, "visual_yaw_offset": 90}, ok_errs)
	ctx.check(good != null and ok_errs.is_empty() and good.has_tint() and good.placeholder and is_equal_approx(good.yaw_offset_deg, 90.0), "dicionario valido vira VisualSpec")
	# classe/NPC com visual invalido nao carregam
	var c: Dictionary = (ClassDef.parse(JsonDir.read_json("res://data/classes/warrior.json")["data"]))
	ctx.check(c["def"] != null and (c["def"] as ClassDef).visual != null, "ClassDef.parse le o visual da classe")
	var raw: Dictionary = (JsonDir.read_json("res://data/classes/warrior.json")["data"] as Dictionary).duplicate(true)
	raw["visual_height"] = -1
	ctx.check(ClassDef.parse(raw)["def"] == null, "classe com visual_height invalido e rejeitada")
	var nd: NpcDirectory = NpcDirectory.new()
	var npc_raw: Dictionary = (JsonDir.read_json("res://data/npcs/npc_elder_orla.json")["data"] as Dictionary).duplicate(true)
	npc_raw["visual_clips"] = {"nada": "x"}
	ctx.check(nd.add_dict(npc_raw) != "", "NPC com visual_clips invalido e rejeitado")
	npc_raw.erase("visual_scene")
	for k: String in VisualSpec.KEYS:
		npc_raw.erase(k)
	ctx.check(nd.add_dict(npc_raw) == "" and nd.get_npc("npc_elder_orla")["visual"] == null, "NPC sem visual continua valido (primitiva)")


func _aliases(ctx: Variant) -> void:
	ctx.check(AssetAliases.resolve("class.warrior").ends_with("kaykit_adventurers/Barbarian.glb"), "alias class.warrior")
	ctx.check(AssetAliases.resolve("model.kaykit_adventurers.knight").ends_with("Knight.glb"), "id de asset tambem resolve")
	ctx.check(AssetAliases.resolve("res://assets/third_party/x.glb") == "res://assets/third_party/x.glb", "res:// passa direto")
	ctx.check(AssetAliases.resolve("nao.existe").is_empty(), "alias desconhecido = vazio")
