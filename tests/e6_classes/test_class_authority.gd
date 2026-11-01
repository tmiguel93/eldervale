extends RefCounted
## E6.1 - autoridade do servidor sobre classe e habilidades: habilidade de outra classe recusada, slots resolvidos NO servidor a
## partir da classe do personagem (backend falso), s_class so ao dono, class_id desconhecido recusado, payloads invalidos,
## protocolo v2 inalterado para o que ja existia.

const H = preload("res://tests/e2/loop_helpers.gd")
const C = preload("res://tests/e6_classes/class_helpers.gd")
const B = preload("res://tests/e4/backend_helpers.gd")

const SLOT_BITS: Dictionary = {"attack": 1, "skill_1": 2, "skill_2": 4, "dodge": 8}


func run(ctx: Object) -> void:
	var tree: SceneTree = ctx as SceneTree
	await tree.physics_frame
	await _test_cross_class_rejected(ctx, tree)
	_test_apply_class_failures(ctx, tree)
	_test_server_resolves_slots(ctx, tree)
	_test_class_message(ctx, tree)
	_test_unknown_class_rejected(ctx, tree)
	_test_protocol(ctx)
	_test_client_session(ctx, tree)


func _test_cross_class_rejected(ctx: Object, tree: SceneTree) -> void:
	var world: Node3D = H.make_world(tree)
	for cid: String in C.CLASS_IDS:
		var p: Player = C.spawn(world, cid)
		var combat: PlayerCombat = C.combat_of(p)
		var reasons: Array[StringName] = []
		combat.skill_failed.connect(func(_s: SkillData, r: StringName) -> void: reasons.append(r))
		var projectiles: Array[int] = [0]
		combat.projectile_spawned.connect(func(_pr: SkillProjectile) -> void: projectiles[0] += 1)
		for other: String in C.CLASS_IDS:
			if other == cid:
				continue
			for sid: String in C.SKILLS[other]:
				C.reset(combat)
				reasons.clear()
				var skill: SkillData = ClassCatalog.load_skill(StringName(sid))
				var pool: float = combat.resource_pool.current
				ctx.check(not combat.try_use(skill), "%s nao usa %s (de %s)" % [cid, sid, other])
				ctx.check(reasons == [&"not_allowed"], "%s/%s: motivo not_allowed %s" % [cid, sid, str(reasons)])
				ctx.check(combat.resource_pool.current == pool and combat.cooldowns.is_ready(skill.id) and combat.machine.state == CharacterStateMachine.State.IDLE, "%s/%s: sem custo, cooldown nem estado" % [cid, sid])
		ctx.check(projectiles[0] == 0, "%s: nenhum projetil de outra classe" % cid)
		for sid: String in C.SKILLS[cid]:
			ctx.check(combat.is_skill_allowed(ClassCatalog.load_skill(StringName(sid))), "%s: permite a propria %s" % [cid, sid])
		ctx.check(not combat.is_skill_allowed(null), "skill nula nao e permitida")
		p.queue_free()
	# um SkillData com id da classe mas OUTRA instancia/edicao nao burla: a regra e por id estavel
	var w: Player = C.spawn(world, "warrior")
	var forged: SkillData = ClassCatalog.load_skill(&"fireball").duplicate() as SkillData
	ctx.check(not C.combat_of(w).try_use(forged), "copia de habilidade alheia (mesmo id) continua recusada")
	forged.id = &"heavy_strike"
	ctx.check(C.combat_of(w).is_skill_allowed(forged), "(o id e a identidade da habilidade: dados vem so do catalogo do servidor)")
	w.queue_free()
	# jogador legado/offline (sem classe) continua sem restricao
	var legacy: Player = H.spawn_player(world, Vector3.ZERO)
	var lc: PlayerCombat = C.combat_of(legacy)
	ctx.check(lc.allowed_skill_ids.is_empty() and lc.try_use(ClassCatalog.load_skill(&"fireball")), "sem classe aplicada (legado): sem restricao")
	legacy.queue_free()
	world.queue_free()
	await tree.physics_frame


func _test_apply_class_failures(ctx: Object, tree: SceneTree) -> void:
	var world: Node3D = H.make_world(tree)
	var p: Player = C.spawn(world, "mage")
	var combat: PlayerCombat = C.combat_of(p)
	var broken_raw: Dictionary = (JSON.parse_string(FileAccess.get_file_as_string("res://data/classes/mage.json")) as Dictionary).duplicate(true)
	broken_raw["skills"]["skill_1"] = "does_not_exist"
	var broken: ClassDef = ClassDef.parse(broken_raw)["def"]
	ctx.check(not combat.apply_class(broken), "classe com habilidade inexistente: apply_class recusa")
	ctx.check(combat.skill_1.id == &"fireball" and combat.class_id == &"mage", "falha de apply_class nao altera a classe atual")
	ctx.check(not combat.apply_class(null), "apply_class(null) recusado")
	ctx.check(combat.skill_for_slot(&"skill_2").id == &"frost_nova" and combat.skill_for_slot(&"nope") == null, "skill_for_slot")
	p.queue_free()
	world.queue_free()


func _backend_rig(tree: SceneTree, class_id: String, cid: String = B.CID1, ticket: String = B.TICKET1) -> B.BRig:
	var rig: B.BRig = B.make(tree)
	var def: ClassDef = ClassCatalog.shared().get_def(class_id)
	rig.fake.add_character(cid, 3, CharacterProgress.total_xp_for_level(3), [], {}, 0, "Hero_" + class_id)
	var ch: Dictionary = rig.fake.chars[cid]
	ch["class_id"] = class_id
	if def != null:
		var st: StatBlock = def.base_stats
		ch["stats"] = {"max_health": st.max_health, "max_resource": st.max_resource, "resource_regen": st.resource_regen, "attack_power": st.attack_power,
			"defense": st.defense, "resistance": st.resistance, "move_speed": st.move_speed}
	rig.fake.tickets[ticket] = cid
	return rig


func _test_server_resolves_slots(ctx: Object, tree: SceneTree) -> void:
	var peer: int = 200
	for cid: String in C.CLASS_IDS:
		var rig: B.BRig = _backend_rig(tree, cid)
		B.hello(rig, peer, B.TICKET1)
		var st: ServerSession.PeerState = rig.session.get_peer_state(peer)
		ctx.check(st != null and st.welcomed and st.entity_id > 0, "%s: personagem entra" % cid)
		if st == null or not st.welcomed:
			rig.free_all()
			continue
		var slot: ServerWorld.PlayerSlot = rig.world.get_slot(st.entity_id)
		var combat: PlayerCombat = slot.combat
		ctx.check(combat.class_id == StringName(cid) and slot.loadout.class_id() == cid, "%s: servidor aplicou a classe do personagem" % cid)
		ctx.check(StatUtil.equals(slot.loadout.final_stats, ClassCatalog.shared().get_def(cid).stats_at_level(3)), "%s: stats nivel 3 da classe" % cid)
		var slots: Array = ["attack", "skill_1", "skill_2", "dodge"]
		for i: int in slots.size():
			var expected_id: StringName = StringName(C.SKILLS[cid][i])
			C.reset(combat)
			slot.node.set_physics_process(false)
			rig.session.on_input(peer, 1000 + i + 10 * cid.length(), Vector2.ZERO, 0.0, int(SLOT_BITS[slots[i]]), 0)
			rig.world.apply_inputs()
			var used: Array[StringName] = []
			for sid: String in C.SKILLS[cid]:
				if not combat.cooldowns.is_ready(StringName(sid)):
					used.append(StringName(sid))
			ctx.check(used == [expected_id], "%s: bit do slot %s aciona SO %s (acionou %s)" % [cid, slots[i], expected_id, str(used)])
			for other: String in C.CLASS_IDS:
				if other == cid:
					continue
				for sid: String in C.SKILLS[other]:
					ctx.check(combat.cooldowns.is_ready(StringName(sid)), "%s: habilidade %s de outra classe nunca acionada" % [cid, sid])
		rig.free_all()
	# stats/habilidades sobrevivem a um conflito de revision (reaplicacao do estado recarregado)
	var rig2: B.BRig = _backend_rig(tree, "ranger")
	B.hello(rig2, peer, B.TICKET1)
	var lo: PlayerLoadout = B.loadout_of(rig2, peer)
	rig2.session._on_state_conflict(B.CID1, rig2.fake.chars[B.CID1].duplicate(true))
	ctx.check(lo.class_id() == "ranger" and lo.combat.basic_attack.id == &"quick_shot", "reaplicar estado do backend preserva a classe")
	var cap: Dictionary = rig2.session.snapshot_character(B.CID1)
	ctx.check(not cap.has("class_id"), "checkpoint do servidor nao envia class_id")
	rig2.free_all()


func _test_class_message(ctx: Object, tree: SceneTree) -> void:
	var peer: int = 210
	var rig: B.BRig = _backend_rig(tree, "mage")
	B.hello(rig, peer, B.TICKET1)
	var msgs: Array[Dictionary] = rig.transport.class_msgs(peer)
	ctx.check(msgs.size() == 1 and msgs[0] == {"class_id": "mage"}, "s_class {class_id: mage} enviado uma vez ao dono")
	ctx.check(Protocol.validate_class_update(msgs[0]), "payload enviado passa no validador do protocolo")
	ctx.check(rig.transport.class_msgs(999).is_empty(), "outros peers nao recebem a classe alheia")
	# 2o jogador em dev (sem ticket): recebe a classe padrao e o 1o nao recebe a dele
	B.hello(rig, 211, "")
	var st2: ServerSession.PeerState = rig.session.get_peer_state(211)
	if st2 != null and st2.welcomed:
		ctx.check(rig.transport.class_msgs(211) == [{"class_id": "warrior"}] and rig.transport.class_msgs(peer).size() == 1, "dev sem backend: warrior ao proprio peer, sem vazar para outros")
	else:
		ctx.check(true, "(dev sem ticket recusado com backend ativo - esperado)")
	rig.free_all()
	var drig: Variant = preload("res://tests/e3/server_helpers.gd").make_rig(tree)
	var eid: int = preload("res://tests/e3/server_helpers.gd").join(drig, 1, "Bot")
	ctx.check(eid > 0 and drig.transport.class_msgs(1) == [{"class_id": "warrior"}], "bots/dev usam a classe padrao (warrior) e recebem s_class")
	var lo: PlayerLoadout = PlayerLoadout.find_for(drig.world.get_player_node(eid))
	ctx.check(lo.combat.basic_attack.id == &"basic_attack" and lo.combat.skill_1.id == &"heavy_strike", "bots mantem as habilidades do guerreiro")
	drig.free_all()


func _test_unknown_class_rejected(ctx: Object, tree: SceneTree) -> void:
	var rig: B.BRig = B.make(tree)
	rig.fake.add_character(B.CID1, 2, 100, [], {}, 0, "Estranho")
	rig.fake.chars[B.CID1]["class_id"] = "necromancer"
	rig.fake.tickets[B.TICKET1] = B.CID1
	B.hello(rig, 220, B.TICKET1)
	var st: ServerSession.PeerState = rig.session.get_peer_state(220)
	ctx.check(rig.transport.welcomes.is_empty() and rig.world.player_count() == 0 and (st == null or not st.welcomed), "class_id desconhecido do backend: entrada recusada, nenhum jogador criado")
	ctx.check(rig.transport.reject_codes(220).has(Protocol.REJECT_NOT_AUTHENTICATED), "recusa com NOT_AUTHENTICATED (sem detalhar o motivo)")
	ctx.check(rig.transport.class_msgs(220).is_empty(), "nenhum s_class enviado")
	rig.free_all()


func _test_protocol(ctx: Object) -> void:
	ctx.check(Protocol.VERSION == 2 and Protocol.ACTION_MASK == 15, "protocolo continua v2 e a mascara de acoes nao mudou")
	ctx.check(not bool(Protocol.validate_input(1, Vector2.ZERO, 0.0, 16, 0)["ok"]), "bit de acao desconhecido (16) continua rejeitado: o cliente nao pode pedir 'habilidade 5'")
	ctx.check(not bool(Protocol.validate_input(1, Vector2.ZERO, 0.0, 1 << 20, 0)["ok"]), "bit alto rejeitado")
	for good: Variant in [{"class_id": "mage"}, {"class_id": "warrior"}, {"class_id": "arcane_x1"}]:
		ctx.check(Protocol.validate_class_update(good), "s_class valido %s" % str(good))
	var long_id: String = "a".repeat(Protocol.MAX_CLASS_ID_LEN + 1)
	for bad: Variant in [null, 5, "mage", [], {}, {"class_id": 5}, {"class_id": ""}, {"class_id": "Mage"}, {"class_id": "ma ge"}, {"class_id": long_id},
			{"class_id": "mage", "extra": 1}, {"id": "mage"}, {"class_id": null}, {"class_id": ["mage"]}, {"class_id": "../x"}]:
		ctx.check(not Protocol.validate_class_update(bad), "s_class invalido rejeitado: %s" % str(bad).left(30))


func _test_client_session(ctx: Object, _tree: SceneTree) -> void:
	var ss: ClientSession = ClientSession.new()
	var seen: Array[String] = []
	ss.class_synced.connect(func(c: String) -> void: seen.append(c))
	ss.on_class_update({"class_id": "mage"})
	ctx.check(ss.class_id == "" and ss.class_updates == 0 and seen.is_empty(), "fora de PLAYING a classe e ignorada")
	ss.begin(Protocol.VERSION, "test", "T")
	ss.on_welcome(5, 30, 1)
	ss.on_class_update({"class_id": "necromancer"})
	ctx.check(ss.class_id == "" and ss.class_rejected == 1, "classe desconhecida localmente: descartada e contada")
	ss.on_class_update({"class_id": 7})
	ss.on_class_update({})
	ss.on_class_update({"class_id": "mage", "x": 1})
	ctx.check(ss.class_rejected == 4 and ss.class_id == "" and ss.class_updates == 0, "payloads malformados descartados e contados (%d)" % ss.class_rejected)
	ss.on_class_update({"class_id": "ranger"})
	ctx.check(ss.class_id == "ranger" and ss.class_updates == 1 and seen == ["ranger"], "classe valida aceita e sinalizada")
	ss.on_class_update({"class_id": "mage"})
	ctx.check(ss.class_id == "mage" and seen == ["ranger", "mage"], "o servidor pode corrigir a classe (ultimo valido vence)")
