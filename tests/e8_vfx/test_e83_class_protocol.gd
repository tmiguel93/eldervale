extends RefCounted
## E8.3 / DEC-0036: classe nos jogadores do snapshot (`type = "player:<class_id>"`): helpers do Protocol, validacao,
## round-trip nos dois formatos (legado e compacto), orcamento de MTU, servidor (kill-switch --party-class) e cliente
## escolhendo o modelo da classe do aliado remoto (com fallback para "ally" e compatibilidade com cliente antigo).

const S = preload("res://tests/e5_snapshot/snapshot_helpers.gd")
const W = preload("res://tests/e5_world/world_helpers.gd")
const H8 = preload("res://tests/e8_models/e8_helpers.gd")


func run(ctx: Variant) -> void:
	var tree: SceneTree = ctx as SceneTree
	await tree.physics_frame
	_helpers(ctx)
	_validation(ctx)
	_codec(ctx)
	_mtu(ctx)
	await _server(ctx, tree)
	await _client(ctx, tree)


func _helpers(ctx: Variant) -> void:
	ctx.check(Protocol.player_type_for("mage") == "player:mage", "player_type_for(mage)")
	ctx.check(Protocol.player_type_for("") == "player" and Protocol.player_type_for("Mage X") == "player" and Protocol.player_type_for("../x") == "player", "id invalido -> 'player'")
	ctx.check(Protocol.player_type_for("a".repeat(40)) == "player", "id longo demais -> 'player'")
	ctx.check(Protocol.class_of_player_type("player:ranger") == "ranger", "class_of(player:ranger)")
	for bad: Variant in ["player", "", "player:", "player:Mage", "player:a b", "enemy:mage", 5, null, ["player:mage"]]:
		ctx.check(Protocol.class_of_player_type(bad) == "", "class_of(%s) = ''" % [bad])
	for cid: String in ClassCatalog.shared().ids():
		ctx.check(Protocol.class_of_player_type(Protocol.player_type_for(cid)) == cid, "ida e volta: %s" % cid)
		ctx.check(Protocol.player_type_for(cid).length() <= Protocol.MAX_TYPE_LEN, "%s cabe em MAX_TYPE_LEN" % cid)


func _validation(ctx: Variant) -> void:
	for t: String in ["player", "player:warrior", "player:mage", "player:ranger"]:
		ctx.check(Protocol.validate_entity_dict(S.ent(1, Protocol.KIND_PLAYER, Vector3.ZERO, 10.0, 10.0, t, 0.0)), "validate: jogador type '%s'" % t)
	for t: String in ["player:", "player:Mage", "player:a b", "player:" + "x".repeat(30)]:
		ctx.check(not Protocol.validate_entity_dict(S.ent(1, Protocol.KIND_PLAYER, Vector3.ZERO, 10.0, 10.0, t, 0.0)), "validate: rejeita jogador type '%s'" % t)
	ctx.check(Protocol.validate_entity_dict(S.enemy(2, Vector3.ZERO)), "inimigo continua valido")


func _party() -> Array:
	return [
		S.ent(1, Protocol.KIND_PLAYER, Vector3(1, 0, 1), 90.0, 120.0, "player:warrior", 0.5),
		S.ent(2, Protocol.KIND_PLAYER, Vector3(2, 0, 1), 60.0, 80.0, "player:mage", 1.0),
		S.ent(3, Protocol.KIND_PLAYER, Vector3(3, 0, 1), 70.0, 90.0, "player:ranger", 1.5),
		S.ent(4, Protocol.KIND_PLAYER, Vector3(4, 0, 1), 70.0, 90.0, "player:mage", 2.0),
	]


func _codec(ctx: Variant) -> void:
	var ents: Array = _party()
	var got: Dictionary = S.roundtrip(ents)
	ctx.check(got.size() == 4, "compacto: 4 jogadores de classes diferentes voltam")
	for e: Dictionary in ents:
		var g: Variant = got.get(int(e["id"]))
		ctx.check(g != null and String(g["type"]) == String(e["type"]) and S.diff(e, g) == "", "compacto: type '%s' preservado (%d)" % [e["type"], int(e["id"])])
		ctx.check(g != null and Protocol.validate_entity_dict(g), "compacto: entidade decodificada valida")
	# cliente antigo: trata `type` como texto opaco; "player" puro continua decodificando igual
	var old: Dictionary = S.roundtrip([S.player(9, Vector3(1, 0, 1))])
	ctx.check(old.size() == 1 and String(old[9]["type"]) == "player", "jogador legado (type 'player') segue valido")
	# formato legado (dicionario do contrato): sao os mesmos campos; so o texto muda
	for e: Dictionary in ents:
		ctx.check(Protocol.validate_entity_dict(e), "legado: entidade %d valida" % int(e["id"]))


func _mtu(ctx: Variant) -> void:
	# pior caso razoavel: 4 jogadores com classe + 26 inimigos com fase/atk, todos em partes <= MTU
	var ents: Array = _party()
	for i: int in 26:
		ents.append(S.enemy(100 + i, Vector3(i * 3.0, 0, i * 2.0), 50.0, 60.0, ["melee_grunt", "bow_scout", "blight_treant", "bark_brute"][i % 4], i % 3, ["", "slam", "arrow"][i % 3], 2))
	var enc: Dictionary = SnapshotCodec.encode(ents)
	ctx.check(int(enc["skipped"]) == 0 and int(enc["encoded"]) == ents.size(), "30 entidades codificadas sem perdas")
	var worst: int = 0
	for blob: PackedByteArray in enc["parts"]:
		worst = maxi(worst, blob.size())
	ctx.check(worst <= Protocol.MTU_PAYLOAD, "maior parte compacta %d B <= MTU %d" % [worst, Protocol.MTU_PAYLOAD])
	# sobrecusto do type com classe: <= 1 string nova por classe (tabela deduplica)
	var base_party: Array = [S.player(1, Vector3(1, 0, 1)), S.player(2, Vector3(2, 0, 1)), S.player(3, Vector3(3, 0, 1)), S.player(4, Vector3(4, 0, 1))]
	var a: int = (SnapshotCodec.encode(base_party)["parts"][0] as PackedByteArray).size()
	var b: int = (SnapshotCodec.encode(_party())["parts"][0] as PackedByteArray).size()
	ctx.check(b - a <= 3 * 14, "sobrecusto de 3 classes <= 42 B (%d B)" % (b - a))


func _server(ctx: Variant, tree: SceneTree) -> void:
	for on: bool in [true, false]:
		var rig: Object = W.rig(tree, false)
		rig.world.settings.default_class_id = "mage"
		rig.world.settings.party_class = on
		var id: int = W.H.join(rig, 1, "A")
		var found: String = ""
		for e: Variant in rig.world.build_entities():
			if int((e as Dictionary)["id"]) == id:
				found = String((e as Dictionary)["type"])
		ctx.check(found == ("player:mage" if on else "player"), "servidor party_class=%s: type '%s'" % [on, found])
		for e: Variant in rig.world.build_entities():
			ctx.check(Protocol.validate_entity_dict(e), "servidor: entidade valida (party_class=%s)" % on)
		rig.free_all()
	ctx.check(ServerSettings.new().party_class, "party_class ligado por padrao")
	await tree.physics_frame


func _client(ctx: Variant, tree: SceneTree) -> void:
	ModelRig.force_enabled = 1
	var w: ClientWorld = ClientWorld.new()
	tree.root.add_child(w)
	w.local_class_id = "warrior"
	var snap: Dictionary = {
		1: H8.sample(Protocol.KIND_PLAYER, "player:warrior", 0),
		2: H8.sample(Protocol.KIND_PLAYER, "player:mage", 0, Vector3(3, 0, 0)),
		3: H8.sample(Protocol.KIND_PLAYER, "player:ranger", 0, Vector3(-3, 0, 0)),
		4: H8.sample(Protocol.KIND_PLAYER, "player", 0, Vector3(0, 0, 3)),
		5: H8.sample(Protocol.KIND_PLAYER, "player:classe_desconhecida", 0, Vector3(0, 0, -3)),
	}
	w.update_frame(snap, 1, null, 0.016)
	var scenes: Dictionary = {}
	for id: int in [2, 3, 4, 5]:
		var rig: ModelRig = w.avatars[id].get_node_or_null("Visual/Rig") as ModelRig
		scenes[id] = rig.spec.scene if rig != null else ""
	ctx.check(scenes[2] == "class.mage", "aliado remoto 'player:mage' usa o modelo do mago (%s)" % scenes[2])
	ctx.check(scenes[3] == "class.ranger", "aliado remoto 'player:ranger' usa o modelo do arqueiro (%s)" % scenes[3])
	ctx.check(scenes[4] == ClientWorld.ALLY_SCENE, "type 'player' (servidor antigo/kill-switch) cai no aliado neutro")
	ctx.check(scenes[5] == ClientWorld.ALLY_SCENE, "classe desconhecida cai no aliado neutro")
	# a classe de um aliado nunca altera o local; mudar o type troca o modelo (um unico rig)
	snap[4]["type"] = "player:ranger"
	w.update_frame(snap, 1, null, 0.016)
	var r4: ModelRig = w.avatars[4].get_node("Visual/Rig") as ModelRig
	ctx.check(r4.spec.scene == "class.ranger" and w.avatars[4].get_node("Visual").get_child_count() == 1, "type muda de player -> player:ranger: troca de modelo, um unico rig")
	ctx.check((w.avatars[2] as Node3D).position.is_equal_approx(Vector3(3, 0, 0)), "posicao autoritativa intacta")
	w.queue_free()
	ModelRig.force_enabled = -1
	await tree.physics_frame
