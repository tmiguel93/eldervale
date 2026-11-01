extends RefCounted
## E6.2 - autoridade de talentos no servidor (backend falso): comando valido persiste, comando invalido nao altera nada, replay nao
## duplica, rate limit/payload invalido contam como abuso, respec exige zona segura + itens (custo consumido uma vez), nivel novo
## reenvia o estado, reconexao restaura, o cliente nunca decide.

const L = preload("res://tests/e5_loot/loot_helpers.gd")
const B = preload("res://tests/e4/backend_helpers.gd")
const Fake = preload("res://tests/e4/fake_backend.gd")
const H = preload("res://tests/e3/server_helpers.gd")

const ALLOC: int = 1 # Protocol.TALENT_OP_*
const RESPEC: int = 2
const SPEC: int = 3


func run(ctx: Object) -> void:
	var tree: SceneTree = ctx as SceneTree
	await tree.physics_frame
	ServerLog.capturing = true
	ServerLog.reset_capture()
	_test_happy_path(ctx, tree)
	_test_rejections(ctx, tree)
	_test_invalid_payload_and_rate(ctx, tree)
	_test_replay_and_req_ids(ctx, tree)
	_test_respec(ctx, tree)
	_test_level_up_and_join(ctx, tree)
	await _test_backend_failure(ctx, tree)
	_test_dev_mode(ctx, tree)
	_test_stats_effect(ctx, tree)
	ServerLog.capturing = false
	await tree.physics_frame


func _rig(tree: SceneTree, level: int, inv: Array = [], world_id: String = "greenwood") -> B.BRig:
	var rig: B.BRig = B.make(tree, false, 4, world_id)
	rig.settings.individual_loot = true
	rig.fake.add_character(L.CIDS[0], level, 0 if level <= 1 else CharacterProgress.total_xp_for_level(level), inv, {"weapon": "sword_basic", "armor": "armor_leather"}, 0, "Hero0")
	rig.fake.tickets[L.TICKETS[0]] = L.CIDS[0]
	B.hello(rig, L.PEER0, L.TICKETS[0], "Hero0")
	return rig


func _cmd(rig: B.BRig, req: int, op: int, arg: String = "", i: int = 0) -> void:
	rig.session.test_now_msec += 10000 # reabastece o limitador (rate limit tem teste proprio)
	rig.session.on_talent_cmd(L.PEER0 + i, req, op, arg)


func _errs(rig: B.BRig, i: int = 0) -> Array:
	var out: Array = []
	for d: Dictionary in rig.transport.talent_msgs(L.PEER0 + i, Protocol.TALENTS_ERROR):
		out.append(String(d["code"]))
	return out


func _states(rig: B.BRig, i: int = 0) -> Array[Dictionary]:
	return rig.transport.talent_msgs(L.PEER0 + i, Protocol.TALENTS_STATE)


func _db(rig: B.BRig) -> Dictionary:
	return rig.fake.chars[L.CIDS[0]]["talents"]


func _talent_reqs(rig: B.BRig) -> Array[Dictionary]:
	return rig.fake.find_all("/talents")


func _inv(entries: Array) -> Array:
	var out: Array = []
	for i: int in entries.size():
		out.append({"slot": i, "item_id": entries[i][0], "qty": entries[i][1]})
	return out


func _test_happy_path(ctx: Object, tree: SceneTree) -> void:
	var rig: B.BRig = _rig(tree, 5)
	var lo: PlayerLoadout = L.loadout(rig, 0)
	var join: Array[Dictionary] = _states(rig)
	ctx.check(not join.is_empty() and Protocol.validate_talents_update(Protocol.TALENTS_STATE, join[-1]) and int(join[-1]["points_available"]) == 4, "ao entrar: s_talents com 4 pontos (nivel 5) e payload valido")
	_cmd(rig, 1, SPEC, "berserker")
	_cmd(rig, 2, ALLOC, "w_vigor")
	_cmd(rig, 3, ALLOC, "w_vigor")
	ctx.check(_errs(rig).is_empty(), "comandos validos sem erro")
	ctx.check(lo.talents.spec_id == "berserker" and lo.talents.rank_of("w_vigor") == 2, "memoria: spec berserker + w_vigor 2")
	ctx.check(_db(rig) == {"spec": "berserker", "ranks": {"w_vigor": 2}, "respecs": 0}, "BANCO igual a memoria (persistido)")
	var last: Dictionary = _states(rig)[-1]
	ctx.check(int(last["req_id"]) == 3 and int(last["points_spent"]) == 2 and int(last["points_available"]) == 2 and last["spec"] == "berserker", "s_talents responde ao req_id com o estado autoritativo")
	var rq: Array[Dictionary] = _talent_reqs(rig)
	ctx.check(rq.size() == 3 and String(rq[1]["body"]["idempotency_key"]) == "talent:%s:2:%s" % [Fake.SESSION_ID, L.CIDS[0]] and rq[1]["body"]["op"] == "allocate" and rq[1]["body"]["arg"] == "w_vigor", "POST /talents com chave talent:<sessao>:<n>:<personagem>")
	ctx.check(rq[1]["session_header"] == Fake.SESSION_ID, "X-Session-Id enviado (fencing)")
	ctx.check(not rq[1]["body"].has("points") and not rq[1]["body"].has("level") and not rq[1]["body"].has("stats"), "servidor nao envia pontos/nivel/stats - o backend decide")
	rig.free_all()


func _test_rejections(ctx: Object, tree: SceneTree) -> void:
	var rig: B.BRig = _rig(tree, 3) # 2 pontos
	_cmd(rig, 1, ALLOC, "b_bloodlust")
	_cmd(rig, 2, SPEC, "elementalist")
	_cmd(rig, 3, ALLOC, "w_iron_skin")
	_cmd(rig, 4, ALLOC, "inexistente")
	_cmd(rig, 5, ALLOC, "w_vigor")
	_cmd(rig, 6, ALLOC, "w_vigor")
	_cmd(rig, 7, ALLOC, "w_vigor")
	_cmd(rig, 8, RESPEC)
	ctx.check(_errs(rig) == ["spec_not_chosen", "unknown_spec", "prerequisite", "unknown_node", "no_points", "insufficient_items"], "erros de regra na ordem: %s" % str(_errs(rig)))
	ctx.check(_db(rig) == {"spec": "", "ranks": {"w_vigor": 2}, "respecs": 0}, "so os 2 comandos validos persistiram")
	ctx.check(_talent_reqs(rig).size() == 2, "recusas locais NAO chegam ao backend (so 2 chamadas)")
	var st: Array[Dictionary] = _states(rig)
	ctx.check(not st.is_empty(), "estado reenviado")
	rig.free_all()


func _test_invalid_payload_and_rate(ctx: Object, tree: SceneTree) -> void:
	var rig: B.BRig = _rig(tree, 5)
	var ps: ServerSession.PeerState = rig.session.get_peer_state(L.PEER0)
	var before: int = _talent_reqs(rig).size()
	for bad: Array in [["x", 1, "w_vigor"], [1, "x", "w_vigor"], [1, 1, 5], [1, 99, "w_vigor"], [1, 1, "Bad Id"], [1, 2, "algo"], [-4, 1, "w_vigor"], [null, null, null]]:
		rig.session.test_now_msec += 10000
		rig.session.on_talent_cmd(L.PEER0, bad[0], bad[1], bad[2])
	ctx.check(_talent_reqs(rig).size() == before and _db(rig)["ranks"].is_empty(), "payload invalido: nada chega ao backend nem altera estado")
	var invalid_before: int = ps.dropped_invalid
	ctx.check(invalid_before >= 8, "payload invalido conta como abuso (dropped_invalid=%d)" % invalid_before)
	# flood: acima do burst em ~0 s => rate limit
	var rig2: B.BRig = _rig(tree, 40)
	for i: int in 30:
		rig2.session.on_talent_cmd(L.PEER0, i + 1, ALLOC, "w_vigor")
	var applied: int = L.loadout(rig2, 0).talents.rank_of("w_vigor")
	ctx.check(applied <= rig2.settings.talent_burst + 1 and applied >= 1, "flood de comandos limitado pelo rate limit (aplicados %d, burst %d)" % [applied, rig2.settings.talent_burst])
	ctx.check(rig2.session.get_peer_state(L.PEER0).dropped_rate > 0, "descartes por rate limit contabilizados")
	# antes do welcome
	var rig3: B.BRig = B.make(tree)
	rig3.session.on_peer_connected(77)
	rig3.session.on_talent_cmd(77, 1, ALLOC, "w_vigor")
	ctx.check(rig3.transport.talent_updates.is_empty(), "comando antes do welcome nao gera resposta")
	rig3.free_all()
	rig2.free_all()
	rig.free_all()


func _test_replay_and_req_ids(ctx: Object, tree: SceneTree) -> void:
	var rig: B.BRig = _rig(tree, 5)
	_cmd(rig, 10, ALLOC, "w_vigor")
	_cmd(rig, 10, ALLOC, "w_vigor") # mesmo req_id
	_cmd(rig, 9, ALLOC, "w_vigor") # req_id antigo
	ctx.check(L.loadout(rig, 0).talents.rank_of("w_vigor") == 1 and _db(rig)["ranks"]["w_vigor"] == 1, "req_id repetido/antigo (replay do cliente) nao duplica")
	ctx.check(_errs(rig) == ["duplicate_request", "duplicate_request"], "duplicate_request devolvido")
	# replay no BACKEND: mesma chave => mesmo resultado, nada muda
	var key: String = String(_talent_reqs(rig)[0]["body"]["idempotency_key"])
	var rev: int = int(rig.fake.chars[L.CIDS[0]]["revision"])
	var resp: Dictionary = {}
	rig.client.fencing_session_id = Fake.SESSION_ID
	rig.client.talents(L.CIDS[0], key, "allocate", "w_vigor", func(r: Dictionary) -> void: resp.merge(r))
	ctx.check(bool(resp.get("ok", false)) and bool(resp["data"].get("replayed", false)), "backend reconhece a mesma chave como replay")
	ctx.check(_db(rig)["ranks"]["w_vigor"] == 1 and int(rig.fake.chars[L.CIDS[0]]["revision"]) == rev and rig.fake.talent_commands == 1, "replay no backend nao duplica o ponto nem sobe a revision")
	var resp2: Dictionary = {}
	rig.client.talents(L.CIDS[0], key, "allocate", "w_might", func(r: Dictionary) -> void: resp2.merge(r))
	ctx.check(not bool(resp2.get("ok", true)) and String(resp2.get("code", "")) == "idempotency_key_reuse", "mesma chave com outro conteudo: 409 idempotency_key_reuse")
	rig.free_all()


func _test_respec(ctx: Object, tree: SceneTree) -> void:
	# fora de zona segura
	var rig: B.BRig = _rig(tree, 5, _inv([["scrap_material", 7]]))
	_cmd(rig, 1, SPEC, "berserker")
	_cmd(rig, 2, ALLOC, "w_vigor")
	rig.world.get_slot(L.eid(rig, 0)).zone_id = "zone_wild"
	_cmd(rig, 3, RESPEC)
	ctx.check(_errs(rig) == ["not_safe_zone"] and L.loadout(rig, 0).talents.rank_of("w_vigor") == 1 and L.loadout(rig, 0).inventory.count(&"scrap_material") == 7, "respec na natureza: not_safe_zone, nada consumido")
	# na vila, com itens
	rig.world.get_slot(L.eid(rig, 0)).zone_id = "zone_hub"
	_cmd(rig, 4, RESPEC)
	var lo: PlayerLoadout = L.loadout(rig, 0)
	ctx.check(lo.talents.is_empty() and lo.talents.respecs == 1, "respec na vila: tudo zerado, contador 1")
	ctx.check(lo.inventory.count(&"scrap_material") == 4 and L.total(rig.fake.chars[L.CIDS[0]], "scrap_material") == 4, "custo (3 sucata) cobrado UMA vez: memoria e banco = 4")
	ctx.check(_db(rig) == {"spec": "", "ranks": {}, "respecs": 1}, "banco zerado")
	ctx.check(lo.talent_points_available() == 4, "pontos devolvidos (4 disponiveis)")
	# refazer a build depois do reset
	_cmd(rig, 5, SPEC, "berserker")
	_cmd(rig, 6, ALLOC, "w_might")
	ctx.check(lo.talents.rank_of("w_might") == 1, "nova build apos o reset")
	rig.free_all()
	# sem itens
	var poor: B.BRig = _rig(tree, 5, _inv([["scrap_material", 2]]))
	_cmd(poor, 1, SPEC, "berserker")
	_cmd(poor, 2, RESPEC)
	ctx.check(_errs(poor) == ["insufficient_items"] and L.loadout(poor, 0).talents.spec_id == "berserker" and L.loadout(poor, 0).inventory.count(&"scrap_material") == 2, "respec sem itens suficientes: recusado, nada muda")
	# nada para resetar
	var empty: B.BRig = _rig(tree, 5, _inv([["scrap_material", 9]]))
	_cmd(empty, 1, RESPEC)
	ctx.check(_errs(empty) == ["nothing_to_reset"] and L.loadout(empty, 0).inventory.count(&"scrap_material") == 9, "respec vazio recusado sem cobrar")
	empty.free_all()
	poor.free_all()
	# arena (sem mundo/diretor): sempre zona segura
	var arena: B.BRig = _rig(tree, 5, _inv([["scrap_material", 5]]), "")
	_cmd(arena, 1, SPEC, "berserker")
	_cmd(arena, 2, RESPEC)
	ctx.check(_errs(arena).is_empty() and L.loadout(arena, 0).talents.respecs == 1, "arena de dev: respec permitido")
	arena.free_all()


func _test_level_up_and_join(ctx: Object, tree: SceneTree) -> void:
	var rig: B.BRig = _rig(tree, 2)
	var lo: PlayerLoadout = L.loadout(rig, 0)
	ctx.check(lo.talent_points_available() == 1, "nivel 2: 1 ponto")
	var n0: int = _states(rig).size()
	rig.session.talents.sync_all()
	ctx.check(_states(rig).size() == n0, "sem mudanca: nao reenvia")
	lo.grant_xp(5000)
	rig.session.talents.sync_all()
	var st: Array[Dictionary] = _states(rig)
	ctx.check(st.size() == n0 + 1 and int(st[-1]["level"]) == lo.progress.level and int(st[-1]["points_available"]) == lo.talent_points_available() and lo.talent_points_available() > 1, "subir de nivel reenvia o estado com mais pontos (nivel %d)" % lo.progress.level)
	rig.free_all()
	# reconexao: talentos persistidos voltam e reaplicam stats/mods
	var rig2: B.BRig = _rig(tree, 5)
	rig2.fake.chars[L.CIDS[0]]["talents"] = {"spec": "berserker", "ranks": {"w_vigor": 3, "b_carnage": 1, "fantasma": 2}, "respecs": 2}
	rig2.session.on_peer_disconnected(L.PEER0)
	B.hello(rig2, L.PEER0 + 10, L.TICKETS[0], "Back")
	var lo2: PlayerLoadout = B.loadout_of(rig2, L.PEER0 + 10)
	ctx.check(lo2 != null and lo2.talents.spec_id == "berserker" and lo2.talents.rank_of("w_vigor") == 3 and lo2.talents.respecs == 2, "reconexao: talentos do banco restaurados")
	ctx.check(lo2.talents.rank_of("fantasma") == 0, "no desconhecido do banco descartado")
	ctx.check(lo2.combat.skill_mods.has("heavy_strike") and lo2.final_stats.max_health > lo2.base_stats.max_health, "mods e stats reaplicados no join")
	rig2.free_all()


func _test_backend_failure(ctx: Object, tree: SceneTree) -> void:
	# recusa definitiva do backend (ex.: nivel no banco menor que o da memoria): memoria NAO muda, erro especifico ao cliente
	var rig: B.BRig = _rig(tree, 5)
	rig.fake.chars[L.CIDS[0]]["level"] = 1 # banco discorda da memoria
	_cmd(rig, 1, ALLOC, "w_vigor")
	ctx.check(L.loadout(rig, 0).talents.rank_of("w_vigor") == 0 and _errs(rig) == ["no_points"], "backend recusa (no_points): memoria intacta, codigo repassado")
	rig.free_all()
	# resposta lenta: segundo comando enquanto o primeiro esta em voo => busy
	var held: B.BRig = _rig(tree, 5)
	held.fake.hold = true
	_cmd(held, 1, ALLOC, "w_vigor")
	_cmd(held, 2, ALLOC, "w_might")
	ctx.check(_errs(held) == ["busy"] and held.session.talents.is_pending(L.eid(held, 0)), "comando em voo: o seguinte recebe busy")
	ctx.check(L.loadout(held, 0).talents.rank_of("w_vigor") == 0, "memoria so muda DEPOIS da confirmacao do backend")
	held.fake.flush()
	for i: int in 5:
		await tree.process_frame
	ctx.check(L.loadout(held, 0).talents.rank_of("w_vigor") == 1 and not held.session.talents.is_pending(L.eid(held, 0)), "confirmado: aplicado e liberado")
	held.free_all()
	# erro de rede: reload do banco (verdade) e erro generico
	var net: B.BRig = _rig(tree, 5)
	net.fake.force("/talents", [Fake.err(409, "revision_conflict")])
	_cmd(net, 1, ALLOC, "w_vigor")
	ctx.check(_errs(net) == ["revision_conflict"] and L.loadout(net, 0).talents.rank_of("w_vigor") == 0, "conflito de revision: erro ao cliente, memoria intacta")
	net.free_all()


func _test_dev_mode(ctx: Object, tree: SceneTree) -> void:
	var rig: H.Rig = H.make_rig(tree, false, 4, false, "")
	var eid: int = H.join(rig, 5, "Dev")
	var lo: PlayerLoadout = PlayerLoadout.find_for(rig.world.get_player_node(eid))
	if lo != null:
		lo.progress.total_xp = 0
		lo.grant_xp(3000)
		rig.session.test_now_msec += 10000
		rig.session.on_talent_cmd(5, 1, SPEC, "berserker")
		rig.session.test_now_msec += 10000
		rig.session.on_talent_cmd(5, 2, ALLOC, "w_vigor")
		ctx.check(lo.talents.rank_of("w_vigor") == 1, "modo dev (sem backend): aplica na memoria")
	else:
		ctx.check(false, "modo dev: jogador criado")
	rig.free_all()


func _test_stats_effect(ctx: Object, tree: SceneTree) -> void:
	var rig: B.BRig = _rig(tree, 5)
	var lo: PlayerLoadout = L.loadout(rig, 0)
	var hp0: float = lo.final_stats.max_health
	_cmd(rig, 1, ALLOC, "w_vigor")
	_cmd(rig, 2, ALLOC, "w_vigor")
	ctx.check(lo.final_stats.max_health == hp0 + 20.0, "w_vigor x2 = +20 vida maxima no servidor (%.0f -> %.0f)" % [hp0, lo.final_stats.max_health])
	var slot: ServerWorld.PlayerSlot = rig.world.get_slot(L.eid(rig, 0))
	ctx.check(slot != null and slot.health.max_health() == lo.final_stats.max_health, "a vida maxima do jogador na simulacao usa o bonus")
	rig.free_all()
