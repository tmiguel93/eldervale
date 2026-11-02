extends RefCounted
## E6.5 - telemetria essencial do servidor (ServerMetrics + ganchos na ServerSession): contadores corretos, sem dados pessoais/segredos,
## memoria limitada, linha periodica e final.

const L = preload("res://tests/e5_loot/loot_helpers.gd")
const B = preload("res://tests/e4/backend_helpers.gd")


func run(ctx: Object) -> void:
	var tree: SceneTree = ctx as SceneTree
	await tree.physics_frame
	ServerLog.capturing = true
	ServerLog.reset_capture()
	_test_unit(ctx)
	_test_hooks(ctx, tree)
	_test_log_and_privacy(ctx, tree)
	ServerLog.capturing = false
	await tree.physics_frame


func _test_unit(ctx: Object) -> void:
	var m: ServerMetrics = ServerMetrics.new(60.0, 1000)
	m.inc("kills", "melee_grunt")
	m.inc("kills", "melee_grunt", 2)
	m.inc("kills", "Bow Scout!!") # nome livre e normalizado: nunca vira chave arbitraria
	m.inc("categoria_inexistente", "x")
	m.inc("kills", "x", 0)
	m.inc("kills", "x", -3)
	ctx.check(m.get_count("kills", "melee_grunt") == 3 and m.total("kills") == 4, "inc soma por (categoria, nome); total por categoria")
	ctx.check(m.get_count("kills", "bow_scout__") == 1 and m.get_count("kills", "x") == 0, "nome normalizado ([a-z0-9_.]); amount <= 0 ignorado")
	ctx.check(m.counters.size() == 2, "categoria desconhecida nao cria chave (%d chaves)" % m.counters.size())
	ctx.check(ServerMetrics.sanitize("") == "unknown" and ServerMetrics.sanitize("A".repeat(200)).length() == ServerMetrics.MAX_NAME_LEN, "sanitize: vazio -> unknown; comprimento limitado")
	for i: int in ServerMetrics.MAX_KEYS + 50:
		m.inc("kills", "k%d" % i)
	ctx.check(m.counters.size() == ServerMetrics.MAX_KEYS and m.dropped_keys > 0, "memoria limitada: %d chaves, %d descartadas" % [m.counters.size(), m.dropped_keys])
	m.inc("kills", "melee_grunt") # chave existente ainda soma com o teto atingido
	ctx.check(m.get_count("kills", "melee_grunt") == 4, "com o teto atingido, chaves existentes continuam somando")
	var m2: ServerMetrics = ServerMetrics.new(10.0, 0)
	m2.inc("skill_use", "warrior.basic_attack")
	ctx.check(not m2.tick(9999) and m2.lines_logged == 0, "antes do intervalo: nada e logado")
	ctx.check(m2.tick(10000) and m2.lines_logged == 1, "no intervalo: loga uma linha")
	ctx.check(not m2.tick(10500) and m2.tick(20000), "o intervalo recomeca a contar a partir do ultimo log")
	var m3: ServerMetrics = ServerMetrics.new(0.0, 0)
	ctx.check(not m3.tick(99999999), "intervalo 0 desliga o log periodico")
	var snap: Dictionary = m2.snapshot(20000)
	ctx.check(float(snap["uptime_s"]) == 20.0 and snap["counters"]["skill_use"]["warrior.basic_attack"] == 1, "snapshot aninhado por categoria")
	var parsed: Variant = JSON.parse_string(m2.line(20000).trim_prefix("[metrics] "))
	ctx.check(typeof(parsed) == TYPE_DICTIONARY and (parsed as Dictionary).has("counters"), "a linha e JSON valido apos o prefixo [metrics]")


func _rig(tree: SceneTree) -> B.BRig:
	var rig: B.BRig = L.make(tree, 1, "greenwood", true, [[{"slot": 0, "item_id": "sword_basic", "qty": 1}]])
	rig.settings.rolled_loot = true
	rig.session.test_now_msec = 1000
	return rig


func _test_hooks(ctx: Object, tree: SceneTree) -> void:
	var rig: B.BRig = _rig(tree)
	var m: ServerMetrics = rig.session.metrics
	ctx.check(m != null and m.get_count("joins", "warrior") == 1, "entrada do jogador conta por classe")
	var node: Player = L.node(rig, 0)
	var combat: PlayerCombat = node.get_node("Combat") as PlayerCombat
	ctx.check(combat.try_use(ClassCatalog.load_skill(&"basic_attack")), "fixture: habilidade usada")
	ctx.check(m.get_count("skill_use", "warrior.basic_attack") == 1, "uso de habilidade contado por classe.habilidade")
	ctx.check(not combat.try_use(ClassCatalog.load_skill(&"fireball")) and m.get_count("skill_use", "mage.fireball") == 0 and m.total("skill_use") == 1, "habilidade recusada (outra classe) NAO conta")
	var enemy: Enemy = L.spawn(rig)
	L.hit(enemy, node, 99999.0)
	ctx.check(m.get_count("kills", "melee_grunt") == 1 and m.get_count("xp_from_kills", "killer") == enemy.data.xp_reward, "abate conta por tipo e soma o XP concedido")
	# coleta: tudo o que o jogador recebeu aparece em drops_*
	var pks: Array[LootManager.LootPickup] = L.pickups_of(rig, 0)
	for p: LootManager.LootPickup in pks:
		rig.world.teleport_player(L.eid(rig, 0), p.pos)
		rig.world.step_loot(0.1)
	var plain: int = m.total("drops_items") + m.total("drops_rarity") + m.total("drops_unique")
	var expected: int = 0
	for p2: LootManager.LootPickup in pks:
		expected += p2.qty if p2.inst.is_empty() else 1
	ctx.check(pks.size() >= 0 and (pks.is_empty() or plain == expected), "coleta: drops contados = unidades recebidas (%d de %d pickups)" % [plain, pks.size()])
	# raridade e unico (via o gancho publico da sessao, como o mundo o chama)
	rig.session._on_pickup_collected(9001, L.eid(rig, 0), "sword_basic", 1, {"uid": "00000000000000a1", "rarity": "epic", "ilvl": 5, "affixes": []})
	rig.session._on_pickup_collected(9002, L.eid(rig, 0), "unique_emberfang", 1, {})
	rig.session._on_pickup_collected(9003, L.eid(rig, 0), "potion_minor", 3, {})
	ctx.check(m.get_count("drops_rarity", "epic") == 1 and m.get_count("drops_unique", "unique_emberfang") == 1 and m.get_count("drops_items", "potion_minor") == 3, "drop: raridade da instancia / unico / item simples (x quantidade)")
	# talentos
	rig.session.on_talent_cmd(L.PEER0, 1, Protocol.TALENT_OP_CHOOSE_SPEC, "berserker")
	rig.session.on_talent_cmd(L.PEER0, 2, Protocol.TALENT_OP_CHOOSE_SPEC, "berserker") # recusado (ja escolhida)
	ctx.check(m.get_count("talents", "choose_spec") == 1, "talento: so comandos APLICADOS contam (a repeticao recusada nao)")
	# equipar: a espada simples entra como `common`; desequipar como `unequip`
	rig.session.on_equip_cmd(L.PEER0, 1, Protocol.EQUIP_OP_EQUIP, 0, "sword_basic")
	rig.session.on_equip_cmd(L.PEER0, 2, Protocol.EQUIP_OP_UNEQUIP, 0, "sword_basic")
	ctx.check(m.get_count("equips", "common") == 1 and m.get_count("equips", "unequip") == 1, "equipar/desequipar contados")
	# quests: o evento do tracker (mesmo caminho da entrega real) chega ao contador
	var pc: QuestService.PlayerCtx = rig.session.quests._players[L.eid(rig, 0)] as QuestService.PlayerCtx
	pc.tracker.quest_completed.emit("gw_welcome")
	rig.session.quests.poi_found.emit(L.eid(rig, 0), "poi_hub_hollow_stump")
	ctx.check(m.get_count("quests_completed", "gw_welcome") == 1 and m.get_count("pois_discovered", "poi_hub_hollow_stump") == 1, "quest concluida e POI descoberto contados")
	# a telemetria nao altera estado de jogo: o inventario/stats seguem coerentes
	ctx.check(L.loadout(rig, 0).final_stats.max_health > 0.0, "ganchos de telemetria nao quebram o jogo")
	rig.free_all()


func _test_log_and_privacy(ctx: Object, tree: SceneTree) -> void:
	var rig: B.BRig = L.make(tree, 1, "greenwood", true)
	rig.settings.metrics_interval_sec = 5.0
	rig.session.test_now_msec = 1000
	rig.session.metrics = ServerMetrics.new(5.0, 1000) # relogio do metrics alinhado ao relogio injetado
	var m: ServerMetrics = rig.session.metrics
	m.inc("joins", "warrior")
	ServerLog.reset_capture()
	rig.session.step_tick()
	var before: int = _metric_lines().size()
	rig.session.test_now_msec = 1000 + 6000
	rig.session.step_tick()
	var lines: Array[String] = _metric_lines()
	ctx.check(lines.size() == before + 1, "step_tick emite a linha [metrics] ao passar o intervalo (%d -> %d)" % [before, lines.size()])
	rig.session.shutdown()
	ctx.check(_metric_lines().size() == lines.size() + 1, "shutdown emite a linha final")
	var blob: String = "\n".join(_metric_lines())
	var leaks: Array[String] = []
	for needle: String in [B.SECRET, B.TICKET1, L.TICKETS[0], L.CIDS[0], "Hero0", "@", "Bearer"]:
		if blob.contains(needle):
			leaks.append(needle.left(8))
	ctx.check(leaks.is_empty() and blob.contains("\"joins\""), "linhas de metricas: sem segredo, ticket, id de personagem, nome de jogador ou e-mail (achados: %s)" % str(leaks))
	rig.free_all()


func _metric_lines() -> Array[String]:
	var out: Array[String] = []
	for l: String in ServerLog.captured:
		if l.begins_with("[metrics] "):
			out.append(l)
	return out
