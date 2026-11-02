extends RefCounted
## E8.2: em headless (servidor/bots/testes) o cenario nao carrega nada e o fallback primitivo segue intacto; com modelos
## forcados a decoracao e so visual: colisao, camadas e posicoes ficam identicas as do servidor.

const H = preload("res://tests/e8_scenery/e8s_helpers.gd")


func run(ctx: Variant) -> void:
	await tree_frame(ctx)
	await _headless(ctx)
	await _physics_unchanged(ctx)
	await _gate(ctx)


func tree_frame(ctx: Variant) -> void:
	await (ctx as SceneTree).physics_frame


func _headless(ctx: Variant) -> void:
	var tree: SceneTree = ctx as SceneTree
	ModelRig.force_enabled = -1
	ModelRig.clear_cache()
	SceneryBuilder.clear_cache()
	if DisplayServer.get_name() != "headless":
		return
	ctx.check(not SceneryBuilder.enabled(), "headless: cenario desligado")
	var w: ClientWorld = ClientWorld.new()
	tree.root.add_child(w)
	w.show_zone("zone_hub")
	ctx.check(w.scenery_env == null, "headless: sem SceneryEnv")
	var zr: Node = w.get_node_or_null("Zone_zone_hub")
	ctx.check(zr != null and zr.get_node_or_null("Scenery") == null, "headless: sem no Scenery")
	ctx.check(SceneryBuilder.extract_count == 0, "headless: nenhum GLB aberto para extracao")
	ctx.check(ModelRig.load_count == 0, "headless: nenhum GLB carregado")
	var root: Node3D = Node3D.new()
	tree.root.add_child(root)
	var z: ZoneDef = H.zone("zone_hub")
	var zr2: Node3D = WorldBuilder.build_zone(root, z, true)
	ctx.check(SceneryBuilder.decorate(zr2, z, QualitySettings.Preset.HIGH).is_empty(), "headless: decorate devolve vazio")
	ctx.check(zr2.get_node_or_null("Scenery") == null, "headless: decorate nao cria no")
	root.queue_free()
	w.queue_free()
	await tree.physics_frame


func _physics_unchanged(ctx: Variant) -> void:
	var tree: SceneTree = ctx as SceneTree
	ModelRig.force_enabled = 1
	for zid: String in SceneryTheme.zone_ids():
		var z: ZoneDef = H.zone(zid)
		var root: Node3D = Node3D.new()
		tree.root.add_child(root)
		var server_side: Node3D = WorldBuilder.build_zone(root, z, false)
		var before: Array = H.physics_signature(server_side)
		var client_side: Node3D = WorldBuilder.build_zone(root, z, true)
		var info: Dictionary = SceneryBuilder.decorate(client_side, z, QualitySettings.Preset.HIGH)
		ctx.check(not info.is_empty(), "%s: decorate roda com modelos forcados" % zid)
		ctx.check(int((info["stats"] as Dictionary)["missing"]) == 0, "%s: nenhum asset faltando" % zid)
		ctx.check(int((info["stats"] as Dictionary)["instances"]) > 100, "%s: decoracao instanciada" % zid)
		var after: Array = H.physics_signature(client_side)
		ctx.check(before.size() > 4 and before == after, "%s: colisores, camadas e posicoes iguais ao servidor (%d corpos)" % [zid, before.size()])
		ctx.check(H.count_collision_objects(client_side.get_node("Scenery")) == 0, "%s: decoracao nao tem colisao" % zid)
		var layers_ok: bool = true
		for l: Node in client_side.find_children("*", "CollisionObject3D", true, false):
			layers_ok = layers_ok and (l as CollisionObject3D).collision_layer != 0 or l.name == "PuzzleGate"
		ctx.check(layers_ok, "%s: camadas nao zeradas pela decoracao" % zid)
		root.queue_free()
		await tree.physics_frame
	ModelRig.force_enabled = -1
	SceneryBuilder.clear_cache()
	ModelRig.clear_cache()


func _gate(ctx: Variant) -> void:
	var tree: SceneTree = ctx as SceneTree
	ModelRig.force_enabled = 1
	var z: ZoneDef = H.zone("zone_ruins")
	var root: Node3D = Node3D.new()
	tree.root.add_child(root)
	var zr: Node3D = WorldBuilder.build_zone(root, z, true)
	SceneryBuilder.decorate(zr, z, QualitySettings.Preset.MEDIUM)
	var gate: StaticBody3D = WorldBuilder.gate_of(zr)
	ctx.check(gate != null, "ruinas: portao existe")
	if gate != null:
		var mesh: Node3D = gate.get_node_or_null("Mesh") as Node3D
		ctx.check(mesh != null, "portao decorado mantem o no Mesh")
		var layer: int = gate.collision_layer
		WorldBuilder.set_gate_open(zr, true)
		ctx.check(gate.collision_layer == 0 and (mesh == null or not mesh.visible), "portao aberto: sem colisao e sem malha")
		WorldBuilder.set_gate_open(zr, false)
		ctx.check(gate.collision_layer == layer and (mesh == null or mesh.visible), "portao fechado: colisao e malha de volta")
	root.queue_free()
	ModelRig.force_enabled = -1
	SceneryBuilder.clear_cache()
	ModelRig.clear_cache()
	await tree.physics_frame
