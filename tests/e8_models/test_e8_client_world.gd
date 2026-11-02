extends RefCounted
## E8.1: ClientWorld sem display nao carrega GLB (primitivas); com modelos ligados usa ModelRig, escolhe clips pelo `state`
## do snapshot, reage a dano/morte/spawn e troca o modelo do jogador local quando a classe chega. Posicao autoritativa intacta.

const H = preload("res://tests/e8_models/e8_helpers.gd")


func run(ctx: Variant) -> void:
	var tree: SceneTree = ctx as SceneTree
	await tree.physics_frame
	await _headless(ctx, tree)
	await _models(ctx, tree)
	await _npcs(ctx, tree)


func _world(tree: SceneTree, models: int) -> ClientWorld:
	ModelRig.force_enabled = models
	var w: ClientWorld = ClientWorld.new()
	tree.root.add_child(w)
	return w


func _headless(ctx: Variant, tree: SceneTree) -> void:
	ModelRig.force_enabled = -1
	ModelRig.clear_cache()
	if DisplayServer.get_name() == "headless":
		ctx.check(not ModelRig.models_enabled(), "headless: modelos desligados")
		var w: ClientWorld = _world(tree, -1)
		ctx.check(not w.use_models, "ClientWorld headless: use_models = false")
		w.update_frame({1: H.sample(Protocol.KIND_PLAYER, "player", 0), 2: H.sample(Protocol.KIND_ENEMY, "melee_grunt", 1, Vector3(3, 0, 0)), 3: H.sample(Protocol.KIND_PICKUP, "potion_minor", 0, Vector3(1, 0, 1), {"qty": 1})}, 1, null, 0.016)
		for id: int in [1, 2, 3]:
			ctx.check((w.avatars[id] as Node3D).get_node_or_null("Visual/Body") != null, "headless: avatar %d usa primitiva (Visual/Body)" % id)
			ctx.check((w.avatars[id] as Node3D).get_node_or_null("Visual/Rig") == null, "headless: avatar %d sem ModelRig" % id)
		ctx.check(ModelRig.load_count == 0, "headless: nenhum GLB carregado (%d)" % ModelRig.load_count)
		ctx.check(ModelRig.create(VisualSpec.make("class.mage", 1.8)) == null, "headless: ModelRig.create devolve null")
		w.queue_free()
	else:
		ctx.check(true, "com display: checagem headless nao se aplica")
	ModelRig.force_enabled = 0
	var w2: ClientWorld = _world(tree, 0)
	w2.update_frame({5: H.sample(Protocol.KIND_ENEMY, "bark_brute", 0)}, 1, null, 0.016)
	ctx.check((w2.avatars[5] as Node3D).get_node_or_null("Visual/Body") != null and ModelRig.load_count == 0, "modelos desligados a mao: primitiva e zero cargas")
	# asset ausente cai nas primitivas (use_models ligado, mas sem arquivo)
	ModelRig.force_enabled = 1
	w2.use_models = true
	w2.update_frame({6: H.sample(Protocol.KIND_ENEMY, "tipo_sem_dados", 0)}, 1, null, 0.016)
	ctx.check((w2.avatars[6] as Node3D).get_node_or_null("Visual/Body") != null, "inimigo sem EnemyData/visual cai na primitiva")
	w2.queue_free()
	ModelRig.force_enabled = -1


func _models(ctx: Variant, tree: SceneTree) -> void:
	ModelRig.clear_cache()
	var w: ClientWorld = _world(tree, 1)
	w.local_class_id = "mage"
	var pos: Vector3 = Vector3(4, 0, -2)
	var snap: Dictionary = {
		1: H.sample(Protocol.KIND_PLAYER, "player", CharacterStateMachine.State.IDLE),
		2: H.sample(Protocol.KIND_ENEMY, "melee_grunt", int(EnemyAI.State.CHASE), pos),
		3: H.sample(Protocol.KIND_ENEMY, "thorn_alpha", int(EnemyAI.State.IDLE), Vector3(9, 0, 9)),
		4: H.sample(Protocol.KIND_PLAYER, "player", CharacterStateMachine.State.MOVE, Vector3(-3, 0, 0)),
		5: H.sample(Protocol.KIND_PICKUP, "potion_minor", 0, Vector3(1, 0, 1), {"qty": 1}),
		6: H.sample(Protocol.KIND_PICKUP, "scrap_material", 0, Vector3(2, 0, 1), {"qty": 3}),
	}
	w.update_frame(snap, 1, Vector3(0, 0, 0), 0.016)
	var g: ModelRig = w.avatars[2].get_node_or_null("Visual/Rig") as ModelRig
	ctx.check(g != null, "inimigo usa ModelRig")
	ctx.check((w.avatars[2] as Node3D).position.is_equal_approx(pos), "posicao autoritativa do snapshot intacta")
	ctx.check(g != null and g.current == &"move", "CHASE -> clip de movimento (%s)" % (str(g.current) if g != null else "-"))
	var me: ModelRig = w.avatars[1].get_node_or_null("Visual/Rig") as ModelRig
	ctx.check(me != null and me.spec.scene == "class.mage", "jogador local usa o modelo da classe (mage)")
	var ally: ModelRig = w.avatars[4].get_node_or_null("Visual/Rig") as ModelRig
	ctx.check(ally != null and ally.spec.scene == ClientWorld.ALLY_SCENE and ally.current == &"move", "aliado remoto usa modelo neutro e anima por MOVE")
	ctx.check(w.avatars[5].get_node_or_null("Visual/Rig") != null and w.avatars[6].get_node_or_null("Visual/Rig") != null, "pickups usam pocao/bau")
	ctx.check(w.avatars[2].get_node_or_null("Visual/Body") == null, "sem primitiva quando ha modelo")
	# classe do local muda depois (s_class chega tarde): troca o modelo
	w.local_class_id = "ranger"
	w.update_frame(snap, 1, Vector3(0, 0, 0), 0.016)
	var me2: ModelRig = w.avatars[1].get_node_or_null("Visual/Rig") as ModelRig
	ctx.check(me2 != null and me2.spec.scene == "class.ranger" and w.avatars[1].get_node("Visual").get_child_count() == 1, "troca de classe troca o modelo (um unico rig)")
	# estados do snapshot
	snap[2]["state"] = int(EnemyAI.State.ATTACK)
	snap[2]["atk"] = "swipe"
	w.update_frame(snap, 1, Vector3(0, 0, 0), 0.016)
	g = w.avatars[2].get_node_or_null("Visual/Rig") as ModelRig
	ctx.check(g.current == &"attack", "ATTACK -> clip de ataque")
	snap[1]["state"] = CharacterStateMachine.State.DODGE
	w.update_frame(snap, 1, Vector3(0, 0, 0), 0.016)
	ctx.check((w.avatars[1].get_node("Visual/Rig") as ModelRig).current == &"dodge", "jogador DODGE -> esquiva")
	snap[1]["state"] = CharacterStateMachine.State.IDLE
	(w.avatars[1].get_node("Visual/Rig") as ModelRig).anim.advance(5.0)
	w.update_frame(snap, 1, Vector3(0, 0, 0), 0.016)
	w.update_frame(snap, 1, Vector3(0.5, 0, 0), 0.016) # predicao andando
	ctx.check((w.avatars[1].get_node("Visual/Rig") as ModelRig).current == &"move", "local andando pela predicao -> move")
	# eventos
	w.apply_event(Protocol.EVENT_DAMAGE, {"target_id": 3, "amount": 5.0, "crit": false})
	var alpha: ModelRig = w.avatars[3].get_node("Visual/Rig") as ModelRig
	ctx.check(alpha.current == &"hit", "EVENT_DAMAGE -> hit react (%s)" % alpha.current)
	ctx.check(alpha.get_node("Pivot").get_child(0).find_child("Wolf", true, false) != null or alpha.model != null, "alfa e um modelo animado")
	w.apply_event(Protocol.EVENT_DEATH, {"id": 2})
	g = w.avatars[2].get_node("Visual/Rig") as ModelRig
	ctx.check(g.current == &"death" and g.dead, "EVENT_DEATH -> clip de morte no proprio corpo")
	snap[2]["state"] = int(EnemyAI.State.DEAD)
	w.update_frame(snap, 1, Vector3(0, 0, 0), 0.016)
	ctx.check(w.avatars.has(2) and g.current == &"death", "corpo morto permanece enquanto o snapshot o lista")
	# spawn antes do avatar existir
	w.apply_event(Protocol.EVENT_ENEMY_SPAWN, {"id": 9, "type": "melee_grunt", "pos": Vector3.ZERO})
	snap[9] = H.sample(Protocol.KIND_ENEMY, "melee_grunt", int(EnemyAI.State.IDLE), Vector3(5, 0, 5))
	w.update_frame(snap, 1, Vector3(0, 0, 0), 0.016)
	var sp: ModelRig = w.avatars[9].get_node("Visual/Rig") as ModelRig
	ctx.check(sp.current == &"spawn", "EVENT_ENEMY_SPAWN -> clip de nascimento (%s)" % sp.current)
	# remover do snapshot libera
	snap.erase(9)
	w.update_frame(snap, 1, Vector3(0, 0, 0), 0.016)
	ctx.check(not w.avatars.has(9) and not w._rigs.has(9), "entidade removida libera o rig")
	# 4 jogadores + 20 entidades: so instancia, sem recarregar
	var crowd: Dictionary = {}
	for i: int in 24:
		crowd[100 + i] = H.sample(Protocol.KIND_PLAYER if i < 4 else Protocol.KIND_ENEMY, "player" if i < 4 else ["melee_grunt", "bow_scout", "forest_stalker", "root_sprout"][i % 4], 0, Vector3(i, 0, 0))
	var t0: int = Time.get_ticks_msec()
	w.update_frame(crowd, 100, null, 0.016)
	var ms: int = Time.get_ticks_msec() - t0
	var first_loads: int = ModelRig.load_count
	ctx.check(w.avatars.size() >= 24, "24 avatares com modelo (%d ms)" % ms)
	var crowd2: Dictionary = {}
	for k: Variant in crowd:
		crowd2[int(k) + 1000] = crowd[k]
	w.update_frame(crowd2, 100, null, 0.016)
	ctx.check(ModelRig.load_count == first_loads, "outras 24 entidades dos mesmos tipos: zero recargas de GLB (cache), cargas=%d" % ModelRig.load_count)
	w.queue_free()
	ModelRig.force_enabled = -1
	await tree.process_frame


func _npcs(ctx: Variant, tree: SceneTree) -> void:
	ModelRig.force_enabled = 1
	var w: ClientWorld = _world(tree, 1)
	ctx.check(w.show_zone("zone_hub"), "zona hub montada")
	var found: int = 0
	for n: Node in w.zone_root.get_children():
		if String(n.name).begins_with("Npc_"):
			if n.get_node_or_null("Rig") != null and n.get_node_or_null("Body") == null:
				found += 1
	var hub_npcs: int = WorldDef.shared().get_zone("zone_hub").npcs.size()
	ctx.check(found == hub_npcs and found >= 3, "NPCs da zona viram modelos animados (%d)" % found)
	w.queue_free()
	ModelRig.force_enabled = 0
	var w2: ClientWorld = _world(tree, 0)
	w2.show_zone("zone_hub")
	var prim: int = 0
	for n: Node in w2.zone_root.get_children():
		if String(n.name).begins_with("Npc_") and n.get_node_or_null("Body") != null:
			prim += 1
	ctx.check(prim == found, "modelos desligados: NPCs voltam para a capsula (%d)" % prim)
	w2.queue_free()
	ModelRig.force_enabled = -1
