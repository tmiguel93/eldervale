extends RefCounted
## E6.4: REPRODUTIBILIDADE do arco de quests e da exploracao via QuestService + ServerSession + backend FALSO (sem rede real).
## O arco inteiro (12 quests, 9 pontos) e percorrido de forma deterministica (sem RNG: eventos do servidor injetados na ordem fixa),
## duas vezes, e os dois resultados tem de ser IGUAIS. Confere progresso, recompensas unicas (chave idempotente), ausencia de
## duplicacao por replay/reconexao/reentrada e a validacao de posicao feita pelo servidor.

const H = preload("res://tests/e3/server_helpers.gd")
const B = preload("res://tests/e4/backend_helpers.gd")

const ARC: Array[Dictionary] = [
	{"q": "gw_welcome", "prep": "talk:npc_hunter_brannoch"},
	{"q": "gw_clear_clearing", "prep": "kill:melee_grunt:5"},
	{"q": "gw_scrap_for_orla", "prep": "item:scrap_material:6"},
	{"q": "gw_bench_lessons", "prep": "craft:potion_minor:2"},
	{"q": "gw_wild_survey", "prep": "poi:poi_wild_fallen_oak,poi_wild_old_milestone"},
	{"q": "gw_whispers", "prep": "talk:npc_warden_lysa,npc_scholar_ilmar"},
	{"q": "gw_thorn_hunt", "prep": "kill:bow_scout:2;kill:thorn_alpha:1"},
	{"q": "gw_shaman_roots", "prep": "kill:grove_shaman:1;kill:burrow_lurker:2"},
	{"q": "gw_ruins_expedition", "prep": "area:area_ruins_gate,area_ruins_hall"},
	{"q": "gw_ruin_secrets", "prep": "poi:poi_ruins_scribe_niche,poi_ruins_altar_inscription,poi_ruins_hidden_vault"},
	{"q": "gw_ruin_guardian", "prep": "kill:ranged_caster:3;kill:blight_treant:1"},
	{"q": "gw_rootsong", "prep": "talk:npc_scholar_ilmar;item:scrap_material:4"},
]


func run(ctx: Object) -> void:
	var tree: SceneTree = ctx as SceneTree
	await tree.physics_frame
	ServerLog.capturing = true
	ServerLog.reset_capture()
	var a: Dictionary = _play_arc(ctx, tree, "A")
	var b: Dictionary = _play_arc(ctx, tree, "B")
	ctx.check(JSON.stringify(a) == JSON.stringify(b), "duas execucoes do arco com a mesma entrada dao o MESMO resultado final no backend")
	_test_gating_and_range(ctx, tree)
	_test_inventory_full_poi(ctx, tree)
	_test_reconnect_and_replay(ctx, tree)
	_test_checkpoint_keeps_discovered(ctx, tree)
	_test_protocol_validation(ctx)
	ServerLog.capturing = false
	await tree.physics_frame


# ------------------------------------------------------------------ helpers

func _brig(tree: SceneTree, level: int = 9, quests: Dictionary = {}) -> B.BRig:
	var rig: B.BRig = B.make(tree)
	rig.fake.add_character(B.CID1, level, 0, [], {"weapon": "sword_basic", "armor": "armor_leather"}, 1, "Sir_Hero")
	if not quests.is_empty():
		rig.fake.chars[B.CID1]["quests"] = quests
	rig.fake.tickets[B.TICKET1] = B.CID1
	B.hello(rig, 1, B.TICKET1)
	rig.session.quests.area_check_interval_ticks = 1
	return rig


func _eid(rig: B.BRig) -> int:
	return rig.session.get_peer_state(1).entity_id


func _goto(rig: B.BRig, eid: int, pos: Vector3) -> void:
	rig.world.get_player_node(eid).global_position = pos


func _goto_npc(rig: B.BRig, eid: int, npc_id: String) -> void:
	_goto(rig, eid, NpcDirectory.shared().get_npc(npc_id)["position"])


func _svc(rig: B.BRig) -> QuestService:
	return rig.session.quests


func _step(rig: B.BRig, eid: int, prep: String) -> void:
	for part: String in prep.split(";"):
		var f: PackedStringArray = part.split(":")
		match f[0]:
			"talk":
				for npc: String in f[1].split(","):
					_goto_npc(rig, eid, npc)
					_svc(rig).cmd_dialogue(eid, 1, Protocol.DIALOGUE_OP_OPEN, npc, 0)
					_svc(rig).cmd_dialogue(eid, 2, Protocol.DIALOGUE_OP_CLOSE, "", 0)
			"kill":
				for i: int in int(f[2]):
					rig.world.player_killed_enemy.emit(eid, 1000 + i, f[1])
			"item":
				_svc(rig).on_items_gained(eid, [{"item_id": f[1], "qty": int(f[2])}])
			"craft":
				rig.session.crafting.crafted.emit(eid, [{"item_id": f[1], "qty": int(f[2])}])
			"poi":
				for poi: String in f[1].split(","):
					_goto(rig, eid, ExplorationCatalog.shared().get_point(poi)["center"])
					_svc(rig).tick()
			"area":
				for area: String in f[1].split(","):
					_goto(rig, eid, AreaSet.shared().areas[area]["center"])
					_svc(rig).tick()


## Percorre o arco completo; devolve o resumo final do backend (comparavel entre execucoes).
func _play_arc(ctx: Object, tree: SceneTree, tag: String) -> Dictionary:
	var rig: B.BRig = _brig(tree)
	var eid: int = _eid(rig)
	var svc: QuestService = _svc(rig)
	var t: QuestTracker = svc.tracker_of(eid)
	var cat: QuestCatalog = QuestCatalog.shared()
	var xp_expected: int = 0
	var completed_n: int = 0
	for step: Dictionary in ARC:
		var qid: String = step["q"]
		var def: QuestDef = cat.get_quest(qid)
		_goto_npc(rig, eid, def.giver_npc)
		var acc: Dictionary = svc.cmd_quest(eid, 10 + completed_n, Protocol.QUEST_OP_ACCEPT, qid)
		ctx.check(bool(acc["ok"]), "[%s] %s: aceita (%s)" % [tag, qid, str(acc.get("code", ""))])
		_step(rig, eid, step["prep"])
		ctx.check(t.status_of(qid, 9) == "ready", "[%s] %s: pronta apos os eventos do servidor" % [tag, qid])
		_goto_npc(rig, eid, def.turn_in_npc)
		var res: Dictionary = svc.cmd_quest(eid, 40 + completed_n, Protocol.QUEST_OP_TURN_IN, qid)
		ctx.check(bool(res["ok"]), "[%s] %s: entregue (%s)" % [tag, qid, str(res.get("code", ""))])
		completed_n += 1
	ctx.check(t.state.completed.size() == ARC.size() and t.state.active.is_empty(), "[%s] as %d quests do arco concluidas" % [tag, ARC.size()])
	# backend: uma recompensa por quest + uma por ponto descoberto, todas com chave estavel e sem repeticao
	var rewards: Array[Dictionary] = rig.fake.find_all("/rewards")
	var keys: Dictionary = {}
	var quest_rw: int = 0
	var poi_rw: int = 0
	for r: Dictionary in rewards:
		var body: Dictionary = r["body"]
		keys[String(body["idempotency_key"])] = true
		if body.has("quest_id"):
			quest_rw += 1
			ctx.check(body["idempotency_key"] == "quest:%s:%s" % [body["quest_id"], B.CID1], "[%s] chave de quest estavel" % tag)
		if body.has("poi_id"):
			poi_rw += 1
			ctx.check(body["idempotency_key"] == "explore:%s:%s" % [body["poi_id"], B.CID1], "[%s] chave de exploracao estavel" % tag)
	var n_poi: int = ExplorationCatalog.shared().ids().size()
	ctx.check(quest_rw == ARC.size() and poi_rw == t.state.discovered.size() and keys.size() == rewards.size(), "[%s] %d recompensas de quest + %d de exploracao, sem chave repetida" % [tag, quest_rw, poi_rw])
	for step: Dictionary in ARC:
		xp_expected += cat.get_quest(String(step["q"])).reward_xp
	var ex: ExplorationCatalog = ExplorationCatalog.shared()
	for poi: String in t.state.discovered:
		xp_expected += int(ex.get_point(poi)["xp"])
	var ch: Dictionary = rig.fake.chars[B.CID1]
	ctx.check(int(ch["xp"]) == xp_expected, "[%s] xp no backend = soma exata das quests + pontos (%d)" % [tag, int(ch["xp"])])
	ctx.check((ch["quests"]["completed"] as Array).size() == ARC.size() and ((ch["quests"]["discovered"] as Array).size() == t.state.discovered.size()), "[%s] backend guarda quests concluidas e pontos descobertos" % tag)
	ctx.check(n_poi >= 6 and t.state.discovered.size() >= 5, "[%s] pontos descobertos pelo arco: %d de %d" % [tag, t.state.discovered.size(), n_poi])
	var unique_n: int = 0
	for e: Variant in (ch["inventory"] as Array):
		if String((e as Dictionary)["item_id"]) == "unique_featherknot":
			unique_n += int((e as Dictionary)["qty"])
	ctx.check(unique_n == 1, "[%s] o unico do capstone foi pago exatamente uma vez" % tag)
	# --- replay: nada paga de novo
	var rw0: int = rewards.size()
	var xp0: int = int(ch["xp"])
	for step: Dictionary in ARC:
		var qid2: String = step["q"]
		_goto_npc(rig, eid, cat.get_quest(qid2).turn_in_npc)
		var again: Dictionary = svc.cmd_quest(eid, 90, Protocol.QUEST_OP_TURN_IN, qid2)
		ctx.check(not bool(again["ok"]), "[%s] replay de entrega de %s recusado" % [tag, qid2])
		var reacc: Dictionary = svc.cmd_quest(eid, 91, Protocol.QUEST_OP_ACCEPT, qid2)
		ctx.check(not bool(reacc["ok"]), "[%s] re-aceitar %s recusado" % [tag, qid2])
	for poi: String in t.state.discovered.duplicate():
		_goto(rig, eid, ex.get_point(poi)["center"])
		svc.tick()
		_goto(rig, eid, Vector3(0, 0, 40))
		svc.tick()
		_goto(rig, eid, ex.get_point(poi)["center"])
		svc.tick() # reentrar no raio
	ctx.check(rig.fake.find_all("/rewards").size() == rw0 and int(rig.fake.chars[B.CID1]["xp"]) == xp0, "[%s] reentrar nos pontos ja descobertos e repetir entregas nao gera recompensa" % tag)
	# mesmo reenviando a mesma chave direto ao backend: replayed
	rig.sync.enqueue_reward(B.CID1, "explore:poi_wild_fallen_oak:" + B.CID1, 40, [], "", "poi_wild_fallen_oak")
	ctx.check(int(rig.fake.chars[B.CID1]["xp"]) == xp0, "[%s] mesma chave de exploracao no backend: replay, xp nao dobra" % tag)
	var summary: Dictionary = {
		"xp": int(rig.fake.chars[B.CID1]["xp"]), "completed": (rig.fake.chars[B.CID1]["quests"]["completed"] as Array).duplicate(),
		"discovered": (rig.fake.chars[B.CID1]["quests"]["discovered"] as Array).duplicate(), "n_rewards": rig.fake.find_all("/rewards").size(),
		"inventory": JSON.stringify(rig.fake.chars[B.CID1]["inventory"]),
	}
	rig.free_all()
	return summary


# ------------------------------------------------------------------ regras do servidor

func _test_gating_and_range(ctx: Object, tree: SceneTree) -> void:
	var rig: B.BRig = _brig(tree, 1)
	var eid: int = _eid(rig)
	var t: QuestTracker = _svc(rig).tracker_of(eid)
	var ex: ExplorationCatalog = ExplorationCatalog.shared()
	# posicao fora do raio (a 5 m do centro de um marco com raio 4): nada
	var oak: Vector3 = ex.get_point("poi_wild_fallen_oak")["center"]
	_goto(rig, eid, oak + Vector3(5.0, 0, 0))
	_svc(rig).tick()
	ctx.check(t.state.discovered.is_empty(), "fora do raio: nada e descoberto (posicao validada pelo servidor)")
	_goto(rig, eid, oak + Vector3(0, 10.0, 0))
	_svc(rig).tick()
	ctx.check(t.state.discovered.is_empty(), "acima da altura do cilindro: nada")
	_goto(rig, eid, oak + Vector3(3.0, 0, 0))
	_svc(rig).tick()
	ctx.check(t.state.discovered == ([ "poi_wild_fallen_oak" ] as Array[String]), "dentro do raio: descoberto")
	ctx.check(rig.transport.quest_msgs(1, Protocol.QUEST_DISCOVERED).size() == 1, "evento QUEST_DISCOVERED enviado so ao dono")
	var msg: Dictionary = rig.transport.quest_msgs(1, Protocol.QUEST_DISCOVERED)[0]
	ctx.check(msg["poi_id"] == "poi_wild_fallen_oak" and int(msg["xp"]) == 40, "payload da descoberta (poi, xp)")
	# nivel minimo e quest exigida
	_goto(rig, eid, ex.get_point("poi_wild_thorn_relic")["center"])
	_svc(rig).tick()
	ctx.check(not t.state.is_discovered("poi_wild_thorn_relic"), "nivel 1 < min_level 3: nao descobre")
	_goto(rig, eid, ex.get_point("poi_wild_hunter_cache")["center"])
	_svc(rig).tick()
	ctx.check(not t.state.is_discovered("poi_wild_hunter_cache"), "sem gw_welcome concluida: o esconderijo nao abre")
	t.state.completed.append("gw_welcome")
	_svc(rig).tick()
	ctx.check(t.state.is_discovered("poi_wild_hunter_cache"), "com gw_welcome concluida: abre")
	# nao existe comando de cliente que descubra: o RPC de quest so aceita aceitar/abandonar/entregar
	var bad: Dictionary = Protocol.validate_quest_cmd(1, Protocol.QUEST_DISCOVERED, "poi_wild_fallen_oak")
	ctx.check(not bool(bad["ok"]), "cliente nao tem operacao de 'descobrir' (op invalida)")
	# jogador sem backend (dev) nao envia recompensa
	rig.free_all()


func _test_inventory_full_poi(ctx: Object, tree: SceneTree) -> void:
	var rig: B.BRig = _brig(tree, 9)
	var eid: int = _eid(rig)
	var lo: PlayerLoadout = PlayerLoadout.find_for(rig.world.get_player_node(eid))
	var t: QuestTracker = _svc(rig).tracker_of(eid)
	while lo.inventory.add(&"sword_basic", 1) == 0:
		pass
	var stump: Dictionary = ExplorationCatalog.shared().get_point("poi_hub_hollow_stump")
	var xp0: int = lo.progress.total_xp
	_goto(rig, eid, stump["center"])
	_svc(rig).tick()
	_svc(rig).tick()
	_svc(rig).tick()
	ctx.check(not t.state.is_discovered("poi_hub_hollow_stump") and lo.progress.total_xp == xp0, "inventario cheio: nada aplicado, ponto continua disponivel")
	var errs: Array[Dictionary] = rig.transport.quest_msgs(1, Protocol.QUEST_ERROR)
	ctx.check(errs.size() == 1 and errs[0]["code"] == "inventory_full" and errs[0]["quest_id"] == "poi_hub_hollow_stump", "avisa UMA vez (sem spam a cada varredura)")
	ctx.check(rig.fake.find_all("/rewards").is_empty(), "nenhuma recompensa enviada ao backend")
	lo.inventory.remove(&"sword_basic", 5)
	_goto(rig, eid, Vector3(0, 0, 40))
	_svc(rig).tick()
	_goto(rig, eid, stump["center"])
	_svc(rig).tick()
	ctx.check(t.state.is_discovered("poi_hub_hollow_stump") and rig.fake.find_all("/rewards").size() == 1, "com espaco, ao reentrar no raio, descobre e paga uma vez")
	rig.free_all()


func _test_reconnect_and_replay(ctx: Object, tree: SceneTree) -> void:
	var rig: B.BRig = _brig(tree, 9)
	var eid: int = _eid(rig)
	var ex: ExplorationCatalog = ExplorationCatalog.shared()
	_goto(rig, eid, ex.get_point("poi_hub_hollow_stump")["center"])
	_svc(rig).tick()
	var xp_b: int = int(rig.fake.chars[B.CID1]["xp"])
	ctx.check(xp_b == 25 and (rig.fake.chars[B.CID1]["quests"]["discovered"] as Array) == ["poi_hub_hollow_stump"], "backend: xp e descoberta persistidos")
	rig.session.on_peer_disconnected(1)
	rig.fake.tickets[B.TICKET2] = B.CID1
	B.hello(rig, 2, B.TICKET2)
	var e2: int = rig.session.get_peer_state(2).entity_id
	rig.session.quests.area_check_interval_ticks = 1
	var t2: QuestTracker = rig.session.quests.tracker_of(e2)
	ctx.check(t2.state.is_discovered("poi_hub_hollow_stump"), "reconexao: descoberta restaurada do backend")
	var sync_msgs: Array[Dictionary] = rig.transport.quest_msgs(2, Protocol.QUEST_SYNC)
	ctx.check(not sync_msgs.is_empty() and (sync_msgs.back()["quests"]["discovered"] as Array) == ["poi_hub_hollow_stump"], "QUEST_SYNC leva as descobertas ao cliente")
	var n0: int = rig.fake.find_all("/rewards").size()
	rig.world.get_player_node(e2).global_position = ex.get_point("poi_hub_hollow_stump")["center"]
	rig.session.quests.tick()
	ctx.check(rig.fake.find_all("/rewards").size() == n0 and int(rig.fake.chars[B.CID1]["xp"]) == xp_b, "reconexao: reentrar no ponto nao paga de novo")
	# o cliente espelha descobertas
	var log: ClientQuestLog = ClientQuestLog.new()
	log.apply(Protocol.QUEST_SYNC, sync_msgs.back())
	ctx.check(log.discovered == ([ "poi_hub_hollow_stump" ] as Array[String]), "ClientQuestLog espelha o sync")
	var seen: Array[String] = []
	log.poi_discovered.connect(func(p: String, _x: int, _i: Array) -> void: seen.append(p))
	ctx.check(log.apply(Protocol.QUEST_DISCOVERED, {"poi_id": "poi_wild_fallen_oak", "xp": 40, "items": []}) and seen == (["poi_wild_fallen_oak"] as Array[String]), "ClientQuestLog aplica QUEST_DISCOVERED")
	ctx.check(not log.apply(Protocol.QUEST_DISCOVERED, {"poi_id": "Bad Id"}) and log.updates_ignored == 1, "QUEST_DISCOVERED malformado ignorado e contado")
	rig.free_all()


func _test_checkpoint_keeps_discovered(ctx: Object, tree: SceneTree) -> void:
	var rig: B.BRig = _brig(tree, 9)
	var eid: int = _eid(rig)
	_goto(rig, eid, ExplorationCatalog.shared().get_point("poi_hub_hollow_stump")["center"])
	_svc(rig).tick()
	rig.sync.tick(30.0) # autosave
	var cp: Dictionary = rig.fake.find_all("/checkpoint").back()["body"]["state"]
	ctx.check((cp["quests"]["discovered"] as Array) == ["poi_hub_hollow_stump"], "o checkpoint leva as descobertas (o backend as trata como somente-servidor)")
	ctx.check((rig.fake.chars[B.CID1]["quests"]["discovered"] as Array) == ["poi_hub_hollow_stump"], "descoberta continua no backend apos o checkpoint")
	rig.free_all()


func _test_protocol_validation(ctx: Object) -> void:
	ctx.check(Protocol.validate_poi_discovered({"poi_id": "poi_x", "xp": 10, "items": [{"item_id": "potion_minor", "qty": 1}]}), "QUEST_DISCOVERED valido")
	for bad: Variant in [null, "x", {}, {"poi_id": "Bad Id", "xp": 1}, {"poi_id": "poi_x", "xp": -1}, {"poi_id": "poi_x", "xp": NAN}, {"poi_id": "poi_x", "xp": 1, "items": "x"},
			{"poi_id": "poi_x", "xp": 1, "items": [{"item_id": "Bad", "qty": 1}]}, {"poi_id": "poi_x", "xp": 1e9}]:
		ctx.check(not Protocol.validate_poi_discovered(bad), "QUEST_DISCOVERED invalido rejeitado: " + str(bad).substr(0, 40))
