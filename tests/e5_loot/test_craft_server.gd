extends RefCounted
## E5.4 - CRAFTING no servidor (backend falso): estacao (zona + distancia), validacao, atomicidade/idempotencia,
## rollback/reload em falha, abuso (flood/rate limit), modo dev (sem backend), desconexao em voo e autosave.

const L = preload("res://tests/e5_loot/loot_helpers.gd")
const B = preload("res://tests/e4/backend_helpers.gd")
const H = preload("res://tests/e3/server_helpers.gd")
const Fake = preload("res://tests/e4/fake_backend.gd")


func run(ctx: Object) -> void:
	var tree: SceneTree = ctx as SceneTree
	await tree.physics_frame
	ServerLog.capturing = true
	ServerLog.reset_capture()
	_test_catalog(ctx)
	_test_success(ctx, tree)
	_test_station_rules(ctx, tree)
	_test_rejections(ctx, tree)
	_test_inventory_full(ctx, tree)
	_test_busy_and_autosave(ctx, tree)
	_test_backend_refusal_rollback(ctx, tree)
	await _test_network_failure_reload(ctx, tree)
	_test_replay_idempotent(ctx, tree)
	_test_abuse(ctx, tree)
	_test_disconnect_in_flight(ctx, tree)
	_test_dev_mode(ctx, tree)
	_test_two_players(ctx, tree)
	_test_logs_clean(ctx)
	ServerLog.capturing = false
	await tree.physics_frame


func _registry() -> ContentRegistry:
	var reg: ContentRegistry = ContentRegistry.new()
	reg.load_all()
	return reg


static func _inv(entries: Array) -> Array:
	var out: Array = []
	for i: int in entries.size():
		out.append({"slot": i, "item_id": entries[i][0], "qty": entries[i][1]})
	return out


func _rig(tree: SceneTree, inv: Array, hold: bool = false, world_id: String = "greenwood") -> B.BRig:
	var rig: B.BRig = L.make(tree, 1, world_id, true, [inv], false)
	rig.world.teleport_player(L.eid(rig, 0), L.STATION_POS)
	rig.fake.hold = hold
	return rig


func _craft(rig: B.BRig, req: int, rid: String, i: int = 0) -> void:
	rig.session.on_craft_cmd(L.PEER0 + i, req, rid)


## Os retries do BackendClient avancam por frames: espera ate nao haver craft pendente e a fila drenar.
func _settle(rig: B.BRig, tree: SceneTree) -> void:
	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 4000:
		await tree.process_frame
		if not rig.session.crafting.is_pending(L.eid(rig, 0)) and rig.sync.pending_ops() == 0:
			break
	for i: int in 5:
		await tree.process_frame


func _codes(rig: B.BRig, i: int = 0) -> Array:
	var out: Array = []
	for d: Dictionary in rig.transport.craft_msgs(L.PEER0 + i, Protocol.CRAFT_ERROR):
		out.append(String(d["code"]))
	return out


func _mem(rig: B.BRig, item: String, i: int = 0) -> int:
	return L.loadout(rig, i).inventory.count(StringName(item))


func _db(rig: B.BRig, item: String, i: int = 0) -> int:
	return L.total(rig.fake.chars[L.CIDS[i]], item)


func _crafts(rig: B.BRig) -> Array[Dictionary]:
	return rig.fake.find_all("/craft")


func _test_catalog(ctx: Object) -> void:
	var cat: RecipeCatalog = RecipeCatalog.shared()
	ctx.check(cat.ids().size() >= 3 and cat.ids().size() <= 5, "catalogo: 3-5 receitas (%d)" % cat.ids().size())
	var errs: Array[String] = cat.validate(_registry(), WorldDef.shared("greenwood"))
	ctx.check(errs.is_empty(), "catalogo valida contra itens e estacoes do mundo: %s" % str(errs))
	ctx.check(cat.get_recipe("rcp_potion_minor") != null and cat.get_recipe("nao_existe") == null, "catalogo: busca por id")


func _test_success(ctx: Object, tree: SceneTree) -> void:
	var rig: B.BRig = _rig(tree, _inv([["scrap_material", 9]]))
	_craft(rig, 1, "rcp_potion_minor")
	var ok: Array[Dictionary] = rig.transport.craft_msgs(L.PEER0, Protocol.CRAFT_OK)
	ctx.check(ok.size() == 1 and int(ok[0]["req_id"]) == 1 and Protocol.validate_craft_update(Protocol.CRAFT_OK, ok[0]), "craft valido: CRAFT_OK correspondente ao req_id e valido no protocolo")
	ctx.check(_mem(rig, "potion_minor") == 1 and _mem(rig, "scrap_material") == 6, "craft: memoria consumiu 3 sucata e ganhou 1 pocao")
	ctx.check(_db(rig, "potion_minor") == 1 and _db(rig, "scrap_material") == 6, "craft: banco igual a memoria")
	var rq: Array[Dictionary] = _crafts(rig)
	ctx.check(rq.size() == 1 and String(rq[0]["body"]["idempotency_key"]) == "craft:%s:1:%s" % [Fake.SESSION_ID, L.CIDS[0]] and rq[0]["body"]["recipe_id"] == "rcp_potion_minor", "craft: POST /craft com chave craft:<sessao>:<n>:<personagem> e recipe_id")
	ctx.check(rq[0]["session_header"] == Fake.SESSION_ID, "craft: cabecalho X-Session-Id (fencing)")
	ctx.check(not rq[0]["body"].has("items") and not rq[0]["body"].has("xp"), "craft: o cliente/servidor nao envia ingredientes nem resultado (so recipe_id)")
	_craft(rig, 2, "rcp_potion_minor")
	ctx.check(_mem(rig, "potion_minor") == 2 and _db(rig, "potion_minor") == 2 and _mem(rig, "scrap_material") == 3, "segundo craft: nova chave, consome de novo")
	ctx.check(String(_crafts(rig)[1]["body"]["idempotency_key"]).ends_with(":2:" + L.CIDS[0]), "chaves distintas por craft")
	# receita com 2 ingredientes
	rig.fake.chars[L.CIDS[0]]["inventory"] = _inv([["armor_leather", 1], ["scrap_material", 9]])
	L.loadout(rig, 0).inventory.restore([ItemStack.make(&"armor_leather", 1), ItemStack.make(&"scrap_material", 9)] as Array[ItemStack])
	_craft(rig, 3, "rcp_armor_heavy")
	ctx.check(_mem(rig, "armor_heavy") == 1 and _mem(rig, "armor_leather") == 0 and _mem(rig, "scrap_material") == 1 and _db(rig, "armor_heavy") == 1, "receita de 2 ingredientes (armor_heavy) consistente memoria x banco")
	rig.free_all()


func _test_station_rules(ctx: Object, tree: SceneTree) -> void:
	var rig: B.BRig = _rig(tree, _inv([["scrap_material", 9]]))
	rig.world.teleport_player(L.eid(rig, 0), L.FAR_POS)
	_craft(rig, 1, "rcp_potion_minor")
	ctx.check(_codes(rig) == ["too_far"] and _mem(rig, "scrap_material") == 9 and _crafts(rig).is_empty(), "estacao distante: too_far, nada consumido, nada enviado ao backend")
	# na borda do raio (3.5) dentro / fora
	rig.world.teleport_player(L.eid(rig, 0), L.STATION_POS + Vector3(3.3, 0, 0))
	_craft(rig, 2, "rcp_potion_minor")
	ctx.check(_mem(rig, "potion_minor") == 1, "dentro do raio da estacao: ok")
	rig.world.teleport_player(L.eid(rig, 0), L.STATION_POS + Vector3(3.7, 0, 0))
	_craft(rig, 3, "rcp_potion_minor")
	ctx.check(_codes(rig) == ["too_far", "too_far"] and _mem(rig, "potion_minor") == 1, "fora do raio da estacao: recusado")
	# zona errada (mesma posicao no plano, mas o jogador esta em outra zona)
	rig.world.teleport_player(L.eid(rig, 0), L.STATION_POS)
	rig.world.get_slot(L.eid(rig, 0)).zone_id = "zone_wild"
	_craft(rig, 4, "rcp_potion_minor")
	ctx.check(_codes(rig)[-1] == "no_station" and _mem(rig, "potion_minor") == 1, "outra zona: no_station")
	rig.free_all()
	# arena de teste (sem mundo): nao existe estacao
	var arena: B.BRig = _rig(tree, _inv([["scrap_material", 9]]), false, "")
	_craft(arena, 1, "rcp_potion_minor")
	ctx.check(_codes(arena) == ["no_station"] and _mem(arena, "scrap_material") == 9, "arena (sem mundo/estacao): no_station")
	arena.free_all()


func _test_rejections(ctx: Object, tree: SceneTree) -> void:
	var rig: B.BRig = _rig(tree, _inv([["scrap_material", 2]]))
	_craft(rig, 1, "rcp_potion_minor")
	ctx.check(_codes(rig) == ["insufficient_ingredients"] and _mem(rig, "scrap_material") == 2 and _crafts(rig).is_empty(), "ingredientes insuficientes: recusado sem tocar no backend")
	_craft(rig, 2, "rcp_inexistente")
	ctx.check(_codes(rig)[-1] == "unknown_recipe", "receita desconhecida (id valido, nao existe): unknown_recipe")
	rig.fake.chars[L.CIDS[0]]["inventory"] = _inv([["scrap_material", 9]])
	L.loadout(rig, 0).inventory.restore([ItemStack.make(&"scrap_material", 9)] as Array[ItemStack])
	_craft(rig, 3, "rcp_potion_minor")
	_craft(rig, 3, "rcp_potion_minor") # mesmo req_id: duplicado
	ctx.check(_mem(rig, "potion_minor") == 1 and _codes(rig)[-1] == "duplicate_request", "req_id repetido: segunda tentativa recusada, so um craft")
	# ingrediente equipado nao conta: espada equipada nao serve de ingrediente
	var lo: PlayerLoadout = L.loadout(rig, 0)
	ctx.check(lo.inventory.count(&"sword_basic") == 0, "setup: sword_basic so esta equipada")
	# jogador morto nao fabrica
	(L.node(rig, 0).get_node("Health") as HealthComponent).apply_damage(DamageInfo.make(99999.0, null, Hitbox.new_hit_id()))
	rig.session.test_now_msec += 10000 # reabastece o limitador (rajada de 4 ja usada)
	_craft(rig, 4, "rcp_potion_minor")
	ctx.check(_codes(rig)[-1] == "not_available" and _mem(rig, "potion_minor") == 1, "jogador morto: not_available")
	rig.free_all()
	# antes do welcome: rejeitado
	var raw: H.Rig = H.make_rig(tree, false, 4, false, "greenwood")
	raw.session.on_peer_connected(900)
	raw.session.on_craft_cmd(900, 1, "rcp_potion_minor")
	ctx.check(raw.session.get_peer_state(900) == null or raw.session.get_peer_state(900).closing, "craft antes do welcome: conexao recusada")
	raw.session.queue_free()
	raw.world.queue_free()


func _test_inventory_full(ctx: Object, tree: SceneTree) -> void:
	var entries: Array = []
	for i: int in 23:
		entries.append(["sword_rare", 1])
	entries.append(["scrap_material", 6])
	var rig: B.BRig = _rig(tree, _inv(entries))
	var before: int = L.loadout(rig, 0).inventory.stack_count()
	_craft(rig, 1, "rcp_sword_basic") # 5 sucata -> 1 espada: sobra 1 sucata + 23 espadas + a nova = 25 > 24
	ctx.check(_codes(rig) == ["inventory_full"] and L.loadout(rig, 0).inventory.stack_count() == before and _mem(rig, "scrap_material") == 6, "inventario cheio: recusado, memoria intacta")
	ctx.check(_crafts(rig).is_empty() and _db(rig, "scrap_material") == 6, "inventario cheio: backend nem e chamado, banco intacto")
	# ingredientes liberam o slot: 6 sucata, receita de armadura de couro (6) -> pilha some e o resultado ocupa o lugar
	_craft(rig, 2, "rcp_armor_leather")
	ctx.check(_mem(rig, "armor_leather") == 1 and _mem(rig, "scrap_material") == 0 and _db(rig, "armor_leather") == 1, "slot liberado pelos ingredientes e reaproveitado pelo resultado")
	rig.free_all()


func _test_busy_and_autosave(ctx: Object, tree: SceneTree) -> void:
	var rig: B.BRig = _rig(tree, _inv([["scrap_material", 12]]), true)
	var eid: int = L.eid(rig, 0)
	_craft(rig, 1, "rcp_potion_minor")
	ctx.check(rig.session.crafting.is_pending(eid) and _mem(rig, "potion_minor") == 1, "craft em voo: pendente e ja aplicado na memoria (otimista)")
	ctx.check(rig.transport.craft_msgs(L.PEER0, Protocol.CRAFT_OK).is_empty(), "craft em voo: sem resposta ao cliente antes do backend")
	_craft(rig, 2, "rcp_potion_minor")
	ctx.check(_codes(rig) == ["busy"] and _mem(rig, "potion_minor") == 1, "segundo craft com o primeiro em voo: busy (nao empilha otimismo)")
	ctx.check(rig.session.snapshot_character(L.CIDS[0]).is_empty(), "autosave pulado enquanto o craft esta em voo (nao persiste estado a desfazer)")
	rig.fake.hold = false
	rig.fake.flush()
	ctx.check(not rig.session.crafting.is_pending(eid) and rig.transport.craft_msgs(L.PEER0, Protocol.CRAFT_OK).size() == 1, "backend responde: craft concluido e CRAFT_OK enviado")
	ctx.check(not rig.session.snapshot_character(L.CIDS[0]).is_empty() and _db(rig, "potion_minor") == 1, "autosave volta apos o craft; banco == memoria")
	_craft(rig, 3, "rcp_potion_minor")
	ctx.check(_mem(rig, "potion_minor") == 2 and _db(rig, "potion_minor") == 2, "novo craft apos concluir funciona")
	rig.free_all()


func _test_backend_refusal_rollback(ctx: Object, tree: SceneTree) -> void:
	for code: String in ["insufficient_ingredients", "inventory_full"]:
		var rig: B.BRig = _rig(tree, _inv([["scrap_material", 5]]))
		rig.fake.force("/craft", [Fake.err(409, code)])
		_craft(rig, 1, "rcp_potion_minor")
		ctx.check(_codes(rig) == [code], "backend recusa (409 %s): CRAFT_ERROR repassa o codigo" % code)
		ctx.check(_mem(rig, "potion_minor") == 0 and _mem(rig, "scrap_material") == 5, "backend recusa (%s): memoria desfeita, igual ao banco" % code)
		ctx.check(_db(rig, "scrap_material") == 5 and _db(rig, "potion_minor") == 0 and not rig.session.crafting.is_pending(L.eid(rig, 0)), "backend recusa (%s): banco intacto e nada pendente" % code)
		_craft(rig, 2, "rcp_potion_minor")
		ctx.check(_mem(rig, "potion_minor") == 1 and _db(rig, "potion_minor") == 1, "apos a recusa o jogador pode tentar de novo")
		rig.free_all()
	# fencing: 400 session_fenced -> erro, memoria desfeita
	var rig2: B.BRig = _rig(tree, _inv([["scrap_material", 5]]))
	rig2.fake.force("/craft", [Fake.err(409, "session_fenced")])
	_craft(rig2, 1, "rcp_potion_minor")
	ctx.check(_codes(rig2) == ["session_fenced"] and _mem(rig2, "scrap_material") == 5, "fencing recusado pelo backend: desfeito e informado")
	rig2.free_all()


func _test_network_failure_reload(ctx: Object, tree: SceneTree) -> void:
	var rig: B.BRig = _rig(tree, _inv([["scrap_material", 5]]))
	var errs: Array = []
	for i: int in 30:
		errs.append(Fake.NET_ERR)
	rig.fake.force("/craft", errs)
	_craft(rig, 1, "rcp_potion_minor")
	await _settle(rig, tree)
	ctx.check(_codes(rig) == ["backend_error"], "falha de rede esgotada: CRAFT_ERROR backend_error")
	ctx.check(rig.fake.count("GET /internal/characters/" + L.CIDS[0]) >= 1, "resultado desconhecido: personagem recarregado do banco")
	ctx.check(_mem(rig, "potion_minor") == _db(rig, "potion_minor") and _mem(rig, "scrap_material") == _db(rig, "scrap_material") and _db(rig, "scrap_material") == 5, "apos a falha a memoria == banco (5 sucata, 0 pocao)")
	ctx.check(not rig.session.crafting.is_pending(L.eid(rig, 0)) and not rig.session.snapshot_character(L.CIDS[0]).is_empty(), "nada pendente; autosave liberado")
	rig.free_all()
	# a chave e a MESMA em todas as tentativas de rede
	var rig2: B.BRig = _rig(tree, _inv([["scrap_material", 5]]))
	rig2.fake.force("/craft", [Fake.NET_ERR, Fake.NET_ERR])
	_craft(rig2, 1, "rcp_potion_minor")
	await _settle(rig2, tree)
	var keys: Dictionary = {}
	for r: Dictionary in _crafts(rig2):
		keys[String(r["body"]["idempotency_key"])] = true
	ctx.check(_crafts(rig2).size() == 3 and keys.size() == 1 and _mem(rig2, "potion_minor") == 1 and _db(rig2, "potion_minor") == 1, "retry de rede reusa a mesma chave e termina consistente (1 craft)")
	rig2.free_all()


func _test_replay_idempotent(ctx: Object, tree: SceneTree) -> void:
	var rig: B.BRig = _rig(tree, _inv([["scrap_material", 9]]))
	_craft(rig, 1, "rcp_potion_minor")
	var key: String = String(_crafts(rig)[0]["body"]["idempotency_key"])
	var done: Array = []
	rig.sync.enqueue_craft(L.CIDS[0], key, "rcp_potion_minor", func(r: Dictionary) -> void: done.append(r))
	ctx.check(done.size() == 1 and bool(done[0]["ok"]) and bool(done[0].get("replayed", false)), "replay da mesma chave: backend responde replayed=true")
	ctx.check(_db(rig, "potion_minor") == 1 and _db(rig, "scrap_material") == 6, "replay NAO consome nem cria de novo (banco)")
	ctx.check(_mem(rig, "potion_minor") == 1 and _mem(rig, "scrap_material") == 6, "replay nao altera a memoria")
	var bad: Array = []
	rig.sync.enqueue_craft(L.CIDS[0], key, "rcp_sword_basic", func(r: Dictionary) -> void: bad.append(r))
	ctx.check(bad.size() == 1 and not bool(bad[0]["ok"]) and int(bad[0]["status"]) == 409, "mesma chave com outra receita: 409")
	rig.free_all()


func _test_abuse(ctx: Object, tree: SceneTree) -> void:
	# rajada: so `craft_burst` pedidos validos passam; o resto e descartado (sem desconectar)
	var rig: B.BRig = _rig(tree, _inv([["scrap_material", 9]]))
	rig.settings.craft_burst = 4
	var p: ServerSession.PeerState = rig.session.get_peer_state(L.PEER0)
	p.craft_limiter = RateLimiter.new(rig.settings.craft_rate_per_sec, rig.settings.craft_burst)
	for i: int in 12:
		_craft(rig, 100 + i, "rcp_inexistente")
	var answered: int = _codes(rig).size()
	ctx.check(answered <= 4 and p.dropped_rate >= 8, "rate limit de craft: %d respondidos, %d descartados" % [answered, p.dropped_rate])
	rig.free_all()
	# payload invalido em excesso => desconexao
	var rig2: B.BRig = _rig(tree, _inv([["scrap_material", 9]]))
	rig2.settings.max_invalid_inputs = 5
	var bad_payloads: Array = [["x", "rcp_potion_minor"], [1, 7], [1, ""], [-1, "rcp_potion_minor"], [1, "Rcp Mau!"], [1.5, "a"], [null, null], [1, "a".repeat(200)]]
	for k: int in 3:
		for bp: Array in bad_payloads:
			rig2.session.on_craft_cmd(L.PEER0, bp[0], bp[1])
	var st: ServerSession.PeerState = rig2.session.get_peer_state(L.PEER0)
	ctx.check(st == null or st.closing, "payloads de craft invalidos em excesso: peer desconectado")
	ctx.check(_crafts(rig2).is_empty(), "payload invalido nunca chega ao backend")
	rig2.free_all()
	# validadores puros
	ctx.check(bool(Protocol.validate_craft_cmd(1, "rcp_potion_minor")["ok"]), "validate_craft_cmd: valido")
	var all_bad: bool = true
	for bp: Array in bad_payloads:
		all_bad = all_bad and not bool(Protocol.validate_craft_cmd(bp[0], bp[1])["ok"])
	ctx.check(all_bad, "validate_craft_cmd: rejeita tipos errados, vazio, id malformado, longo")
	ctx.check(Protocol.validate_craft_update(Protocol.CRAFT_ERROR, {"req_id": 1, "recipe_id": "a", "code": "too_far"}) and not Protocol.validate_craft_update(Protocol.CRAFT_ERROR, {"req_id": 1, "recipe_id": "a"}) and not Protocol.validate_craft_update(99, {}), "validate_craft_update: erro valido / incompleto / tipo desconhecido")


func _test_disconnect_in_flight(ctx: Object, tree: SceneTree) -> void:
	var rig: B.BRig = _rig(tree, _inv([["scrap_material", 9]]), true)
	_craft(rig, 1, "rcp_potion_minor")
	rig.session.on_peer_disconnected(L.PEER0)
	rig.fake.hold = false
	rig.fake.flush()
	ctx.check(rig.world.player_count() == 0 and rig.session.crafting.is_pending_character(L.CIDS[0]) == false, "desconectou com craft em voo: sem jogador e sem pendencia")
	var cps: Array[Dictionary] = rig.fake.find_all("/checkpoint")
	var cp_has_potion: bool = not cps.is_empty() and L.total(cps[-1]["body"]["state"] if cps[-1]["body"].has("state") else cps[-1]["body"], "potion_minor") == 1
	ctx.check(_db(rig, "potion_minor") == 1 and _db(rig, "scrap_material") == 6, "banco consistente (craft concluiu uma vez): 1 pocao, 6 sucata")
	ctx.check(not cps.is_empty() and rig.fake.count("/disconnect") == 1 and cp_has_potion, "checkpoint final (ja com a pocao) e disconnect enviados, nessa ordem de fila")
	rig.free_all()


func _test_dev_mode(ctx: Object, tree: SceneTree) -> void:
	var raw: H.Rig = H.make_rig(tree, false, 4, false, "greenwood")
	var eid: int = H.join(raw, 301, "Dev")
	var lo: PlayerLoadout = PlayerLoadout.find_for(raw.world.get_player_node(eid))
	lo.inventory.add(&"scrap_material", 9)
	raw.world.teleport_player(eid, L.STATION_POS)
	raw.session.on_craft_cmd(301, 1, "rcp_potion_minor")
	ctx.check(raw.transport.craft_msgs(301, Protocol.CRAFT_OK).size() == 1 and lo.inventory.count(&"potion_minor") == 1 and lo.inventory.count(&"scrap_material") == 6, "modo dev (sem backend): aplica na hora e responde")
	raw.world.teleport_player(eid, L.FAR_POS)
	raw.session.on_craft_cmd(301, 2, "rcp_potion_minor")
	ctx.check(raw.transport.craft_msgs(301, Protocol.CRAFT_ERROR).size() == 1 and lo.inventory.count(&"potion_minor") == 1, "modo dev: estacao distante tambem recusa")
	raw.session.queue_free()
	raw.world.queue_free()


func _test_two_players(ctx: Object, tree: SceneTree) -> void:
	var rig: B.BRig = L.make(tree, 3, "greenwood", true, [_inv([["scrap_material", 3]]), _inv([["scrap_material", 20]]), _inv([["scrap_material", 20]])])
	rig.world.teleport_player(L.eid(rig, 0), L.STATION_POS)
	rig.world.teleport_player(L.eid(rig, 1), L.STATION_POS + Vector3(1, 0, 1))
	rig.world.teleport_player(L.eid(rig, 2), L.FAR_POS)
	_craft(rig, 1, "rcp_potion_minor", 0)
	_craft(rig, 1, "rcp_sword_basic", 1)
	_craft(rig, 1, "rcp_potion_minor", 2)
	ctx.check(_mem(rig, "potion_minor", 0) == 1 and _db(rig, "potion_minor", 0) == 1, "jogador 0 fabrica (perto)")
	ctx.check(_mem(rig, "sword_basic", 1) == 1 and _db(rig, "sword_basic", 1) == 1 and _mem(rig, "scrap_material", 1) == 15, "jogador 1 fabrica a propria receita (perto)")
	ctx.check(_codes(rig, 2) == ["too_far"] and _mem(rig, "potion_minor", 2) == 0 and _db(rig, "scrap_material", 2) == 20, "jogador 2 (longe) recusado sem afetar os outros")
	ctx.check(_codes(rig, 0).is_empty() and _codes(rig, 1).is_empty(), "respostas de erro so ao proprio jogador")
	var keys: Dictionary = {}
	for r: Dictionary in _crafts(rig):
		keys[String(r["body"]["idempotency_key"])] = true
	ctx.check(keys.size() == 2, "chaves de craft distintas entre jogadores")
	rig.free_all()


func _test_logs_clean(ctx: Object) -> void:
	var dump: String = ServerLog.joined()
	ctx.check(not dump.contains("eyJhbGci") and not dump.contains(B.SECRET) and not dump.contains("Bearer"), "logs do crafting sem ticket nem segredo")
