extends RefCounted
## E5.6 - INVENTARIO SINCRONIZADO (s_inventory): validador do protocolo, NetRpc, servidor (entrada, mudanca, coalescencia,
## privacidade, craft/desfazer, recompensa de quest), cliente (ClientSession/ClientUi/ClientInventory) e reentrega de
## recompensas apos falha transitoria do backend (BackendSync).

const L = preload("res://tests/e5_loot/loot_helpers.gd")
const B = preload("res://tests/e4/backend_helpers.gd")
const H = preload("res://tests/e3/server_helpers.gd")
const Fake = preload("res://tests/e4/fake_backend.gd")
const U = preload("res://tests/e5_ui/ui_helpers.gd")


func run(ctx: Object) -> void:
	var tree: SceneTree = ctx as SceneTree
	await tree.physics_frame
	ServerLog.capturing = true
	ServerLog.reset_capture()
	_test_protocol_validator(ctx)
	_test_netrpc_surface(ctx, tree)
	_test_join_sends_full_state(ctx, tree)
	_test_change_and_coalesce(ctx, tree)
	_test_privacy_two_players(ctx, tree)
	_test_craft_and_undo(ctx, tree)
	_test_quest_reward(ctx, tree)
	_test_disabled_and_payload_bound(ctx, tree)
	_test_client_session(ctx)
	_test_client_ui(ctx, tree)
	await _test_reward_redelivery(ctx, tree)
	ServerLog.capturing = false
	await tree.physics_frame


static func _inv(entries: Array) -> Array:
	var out: Array = []
	for i: int in entries.size():
		out.append({"slot": i, "item_id": entries[i][0], "qty": entries[i][1]})
	return out


func _ticks(rig: B.BRig, n: int) -> void:
	for i: int in n:
		rig.session.step_tick()


func _msgs(rig: B.BRig, i: int = 0) -> Array[Dictionary]:
	return rig.transport.inventory_msgs(L.PEER0 + i)


func _qty(d: Dictionary, item: String) -> int:
	var n: int = 0
	for s: Variant in d["slots"]:
		if (s as Dictionary)["item_id"] == item:
			n += int((s as Dictionary)["qty"])
	return n


func _test_protocol_validator(ctx: Object) -> void:
	var ok: Dictionary = {"capacity": 24, "slots": [{"item_id": "scrap_material", "qty": 5}], "equipment": {"weapon": "sword_basic"}}
	ctx.check(Protocol.validate_inventory_update(ok), "validador: payload valido")
	ctx.check(Protocol.validate_inventory_update({"capacity": 1, "slots": [], "equipment": {}}), "validador: mochila e equipamento vazios")
	var bad: Array = [
		["nao e dicionario", 5],
		["sem capacity", {"slots": [], "equipment": {}}],
		["capacity 0", {"capacity": 0, "slots": [], "equipment": {}}],
		["capacity acima do limite", {"capacity": Protocol.MAX_INVENTORY_SLOTS + 1, "slots": [], "equipment": {}}],
		["capacity float", {"capacity": 24.0, "slots": [], "equipment": {}}],
		["mais pilhas que capacity", {"capacity": 1, "slots": [{"item_id": "a", "qty": 1}, {"item_id": "b", "qty": 1}], "equipment": {}}],
		["item_id invalido", {"capacity": 4, "slots": [{"item_id": "Item Ruim", "qty": 1}], "equipment": {}}],
		["qty zero", {"capacity": 4, "slots": [{"item_id": "scrap_material", "qty": 0}], "equipment": {}}],
		["qty acima de 999", {"capacity": 4, "slots": [{"item_id": "scrap_material", "qty": 1000}], "equipment": {}}],
		["qty string", {"capacity": 4, "slots": [{"item_id": "scrap_material", "qty": "3"}], "equipment": {}}],
		["slot nao e dicionario", {"capacity": 4, "slots": ["x"], "equipment": {}}],
		["slots nao e array", {"capacity": 4, "slots": {}, "equipment": {}}],
		["equipamento slot desconhecido", {"capacity": 4, "slots": [], "equipment": {"cabeca": "sword_basic"}}],
		["equipamento item invalido", {"capacity": 4, "slots": [], "equipment": {"weapon": "X Y"}}],
		["equipamento com chave nao-string", {"capacity": 4, "slots": [], "equipment": {1: "sword_basic"}}],
		["equipamento nao e dicionario", {"capacity": 4, "slots": [], "equipment": []}],
	]
	for b: Array in bad:
		ctx.check(not Protocol.validate_inventory_update(b[1]), "validador recusa: " + String(b[0]))


func _test_netrpc_surface(ctx: Object, tree: SceneTree) -> void:
	var n: NetRpc = NetRpc.new()
	ctx.check(n.has_method("s_inventory") and n.has_method("send_inventory") and n.has_signal("inventory_update_received"), "NetRpc: s_inventory / send_inventory / sinal")
	ctx.check(not n.has_method("c_inventory"), "NetRpc: nao existe comando de inventario do cliente (o cliente nao altera inventario)")
	n.free()
	var tp: ServerTransport = ServerTransport.new()
	tp.send_inventory(1, {}) # base e no-op
	ctx.check(true, "ServerTransport.send_inventory existe (no-op na base)")


func _test_join_sends_full_state(ctx: Object, tree: SceneTree) -> void:
	var rig: B.BRig = L.make(tree, 1, "greenwood", true, [_inv([["scrap_material", 7], ["potion_minor", 2]])])
	var m: Array[Dictionary] = _msgs(rig)
	ctx.check(m.size() == 1 and Protocol.validate_inventory_update(m[0]), "entrada: exatamente 1 s_inventory valido logo apos o welcome")
	ctx.check(_qty(m[0], "scrap_material") == 7 and _qty(m[0], "potion_minor") == 2 and int(m[0]["capacity"]) == 24, "entrada: inventario completo do personagem (itens e capacidade)")
	ctx.check(m[0]["equipment"] == {"weapon": "sword_basic", "armor": "armor_leather"}, "entrada: equipamento completo")
	# a ordem: welcome antes do inventario
	ctx.check(rig.transport.welcomes.size() == 1, "welcome enviado")
	_ticks(rig, 30)
	ctx.check(_msgs(rig).size() == 1, "sem mudanca: nenhum reenvio em 30 ticks")
	rig.free_all()
	# modo dev (sem backend): kit inicial
	var dev: H.Rig = H.make_rig(tree, false, 4, false, "")
	dev.session.on_peer_connected(5)
	dev.session.on_hello(5, Protocol.VERSION, "t", "Dev", "")
	var dm: Array[Dictionary] = dev.transport.inventory_msgs(5)
	ctx.check(dm.size() == 1 and Protocol.validate_inventory_update(dm[0]), "modo dev: tambem envia o inventario na entrada")
	dev.free_all()


func _test_change_and_coalesce(ctx: Object, tree: SceneTree) -> void:
	var rig: B.BRig = L.make(tree, 1, "greenwood", true, [_inv([["scrap_material", 1]])])
	var inv: Inventory = L.loadout(rig, 0).inventory
	# varias mudancas dentro da mesma janela => 1 so mensagem com o estado final
	inv.add(&"scrap_material", 2)
	inv.add(&"potion_minor", 1)
	inv.add(&"scrap_material", 3)
	_ticks(rig, 5)
	ctx.check(_msgs(rig).size() == 1, "coalescencia: nada enviado antes da janela fechar (%d)" % _msgs(rig).size())
	_ticks(rig, 1)
	var m: Array[Dictionary] = _msgs(rig)
	ctx.check(m.size() == 2 and _qty(m[1], "scrap_material") == 6 and _qty(m[1], "potion_minor") == 1, "coalescencia: 3 mudancas => 1 mensagem com o estado final")
	# taxa maxima: mudar a cada tick por 60 ticks nao passa de tick_rate/ticks mensagens
	for i: int in 60:
		inv.add(&"scrap_material", 1)
		_ticks(rig, 1)
	ctx.check(_msgs(rig).size() - 2 <= 11, "limite de taxa: <= 1 mensagem a cada %d ticks (%d em 60 ticks)" % [rig.settings.inventory_sync_ticks, _msgs(rig).size() - 2])
	# estado final sempre alcancado
	_ticks(rig, 6)
	ctx.check(_qty(_msgs(rig).back(), "scrap_material") == 66, "estado final sincronizado depois do burst (%d)" % _qty(_msgs(rig).back(), "scrap_material"))
	# remover e esvaziar
	inv.remove(&"scrap_material", 66)
	_ticks(rig, 6)
	ctx.check(_qty(_msgs(rig).back(), "scrap_material") == 0, "remocao sincronizada")
	# equipar muda equipamento (e inventario)
	var lo: PlayerLoadout = L.loadout(rig, 0)
	lo.inventory.add(&"armor_heavy", 1)
	lo.equipment.equip(&"armor_heavy")
	_ticks(rig, 6)
	ctx.check(_msgs(rig).back()["equipment"]["armor"] == "armor_heavy", "troca de equipamento sincronizada")
	rig.free_all()


func _test_privacy_two_players(ctx: Object, tree: SceneTree) -> void:
	var rig: B.BRig = L.make(tree, 2, "greenwood", true, [_inv([["scrap_material", 4]]), _inv([["potion_minor", 9]])])
	ctx.check(_msgs(rig, 0).size() == 1 and _msgs(rig, 1).size() == 1, "2 jogadores: cada um recebeu a propria mensagem de entrada")
	ctx.check(_qty(_msgs(rig, 0)[0], "potion_minor") == 0 and _qty(_msgs(rig, 1)[0], "scrap_material") == 0, "cada mensagem leva so o inventario do dono")
	L.loadout(rig, 0).inventory.add(&"scrap_material", 5)
	_ticks(rig, 6)
	ctx.check(_msgs(rig, 0).size() == 2 and _msgs(rig, 1).size() == 1, "mudanca do jogador 0 nao gera mensagem para o jogador 1")
	for peer: int in [L.PEER0, L.PEER0 + 1]:
		for m: Dictionary in rig.transport.inventories:
			if int(m["peer"]) == peer:
				pass
	rig.free_all()


func _test_craft_and_undo(ctx: Object, tree: SceneTree) -> void:
	var rig: B.BRig = L.make(tree, 1, "greenwood", true, [_inv([["scrap_material", 9]])])
	rig.world.teleport_player(L.eid(rig, 0), L.STATION_POS)
	rig.session.on_craft_cmd(L.PEER0, 1, "rcp_potion_minor")
	_ticks(rig, 6)
	var last: Dictionary = _msgs(rig).back()
	ctx.check(_qty(last, "potion_minor") == 1 and _qty(last, "scrap_material") == 6, "craft: inventario sincronizado depois do craft")
	# recusa definitiva do backend: o servidor desfaz na memoria => o cliente recebe o estado desfeito
	rig.fake.force("/craft", [Fake.err(409, "insufficient_ingredients")])
	rig.session.on_craft_cmd(L.PEER0, 2, "rcp_potion_minor")
	_ticks(rig, 6)
	last = _msgs(rig).back()
	ctx.check(_qty(last, "potion_minor") == 1 and _qty(last, "scrap_material") == 6, "craft recusado pelo backend: o cliente volta ao estado real (nada de estimativa errada)")
	rig.free_all()


func _test_quest_reward(ctx: Object, tree: SceneTree) -> void:
	var rig: B.BRig = L.make(tree, 1, "greenwood", true, [])
	var eid: int = L.eid(rig, 0)
	rig.world.teleport_player(eid, Vector3(10.0, 0.05, -8.0))
	rig.session.quests.cmd_quest(eid, 1, Protocol.QUEST_OP_ACCEPT, "gw_welcome")
	rig.session.quests.tracker_of(eid).on_npc_talked("npc_hunter_brannoch")
	var r: Dictionary = rig.session.quests.cmd_quest(eid, 2, Protocol.QUEST_OP_TURN_IN, "gw_welcome")
	_ticks(rig, 6)
	ctx.check(bool(r["ok"]) and _qty(_msgs(rig).back(), "potion_minor") == 2, "recompensa de quest: itens chegam ao cliente pelo inventario sincronizado")
	rig.free_all()


func _test_disabled_and_payload_bound(ctx: Object, tree: SceneTree) -> void:
	var rig: B.BRig = L.make(tree, 1, "greenwood", true, [])
	rig.settings.inventory_sync_ticks = 0
	L.loadout(rig, 0).inventory.add(&"scrap_material", 1)
	_ticks(rig, 30)
	ctx.check(_msgs(rig).size() == 1, "inventory_sync_ticks = 0 desliga o reenvio periodico (so a entrada)")
	rig.free_all()
	# tamanho: mochila cheia (24 pilhas) + 3 equipados cabe folgado e valida
	var entries: Array = []
	var ids: Array = ["scrap_material", "potion_minor", "sword_basic", "sword_rare", "armor_leather", "armor_heavy", "amulet_vigor"]
	for i: int in 24:
		entries.append({"slot": i, "item_id": ids[i % ids.size()], "qty": 20 if ids[i % ids.size()] == "scrap_material" else 1})
	var rig2: B.BRig = L.make(tree, 1, "greenwood", true, [entries])
	var m: Dictionary = _msgs(rig2)[0]
	var bytes: int = var_to_bytes(m).size()
	ctx.check(Protocol.validate_inventory_update(m) and bytes < 2600, "mochila cheia: payload valido e pequeno (%d B)" % bytes)
	rig2.free_all()


func _test_client_session(ctx: Object) -> void:
	var made: Dictionary = U.make_session()
	var ss: ClientSession = made["session"]
	var got: Array = []
	ss.inventory_synced.connect(func(d: Dictionary) -> void: got.append(d))
	var good: Dictionary = {"capacity": 24, "slots": [{"item_id": "scrap_material", "qty": 3}], "equipment": {"weapon": "sword_basic"}}
	ss.on_inventory_update(good)
	ctx.check(got.size() == 1 and ss.inventory_data == good and ss.inventory_updates == 1 and ss.inventory_rejected == 0, "cliente: payload valido aplicado e sinalizado")
	ctx.check(ss.result.inventory == {"scrap_material": 3} and ss.result.equipment == {"weapon": "sword_basic"} and ss.result.inventory_updates == 1, "cliente: relatorio do bot reflete o inventario sincronizado")
	ss.on_inventory_update({"capacity": 0, "slots": [], "equipment": {}})
	ss.on_inventory_update({"slots": "x"})
	ctx.check(got.size() == 1 and ss.inventory_rejected == 2 and ss.inventory_data == good, "cliente: payload malformado descartado e contado, estado anterior mantido")
	var idle: ClientSession = ClientSession.new()
	idle.on_inventory_update(good)
	ctx.check(idle.inventory_data.is_empty() and idle.inventory_updates == 0, "cliente: s_inventory antes do welcome e ignorado")


func _test_client_ui(ctx: Object, tree: SceneTree) -> void:
	var made: Dictionary = U.make_session()
	var ss: ClientSession = made["session"]
	var ui: ClientUi = U.make_ui(tree, ss)
	ui.on_event(Protocol.EVENT_PICKUP, {"id": 1, "item_id": "scrap_material", "qty": 3})
	ctx.check(not ui.inventory.complete and ui.inventory.count("scrap_material") == 3, "antes do s_inventory: estimativa por evento")
	ctx.check(ui.inventory_panel.banner.visible and ui.inventory_panel.banner.text.contains("Estimativa"), "antes do s_inventory: aviso de estimativa visivel")
	ss.on_inventory_update({"capacity": 24, "slots": [{"item_id": "scrap_material", "qty": 10}, {"item_id": "potion_minor", "qty": 2}], "equipment": {"weapon": "sword_basic", "armor": "armor_leather"}})
	ctx.check(ui.inventory.complete and ui.inventory.count("scrap_material") == 10 and ui.inventory.equipment.get("weapon", "") == "sword_basic", "s_inventory aplicado: completo, substitui a estimativa, equipamento visivel")
	ctx.check(not ui.inventory_panel.banner.visible, "aviso de estimativa REMOVIDO quando sincronizado")
	# depois de sincronizado, eventos nao contam em dobro
	ui.on_event(Protocol.EVENT_PICKUP, {"id": 2, "item_id": "scrap_material", "qty": 3})
	ui.inventory.on_quest_reward([{"item_id": "potion_minor", "qty": 5}])
	ui.inventory.on_craft_ok({"recipe_id": "rcp_potion_minor", "results": [{"item_id": "potion_minor", "qty": 1}]})
	ctx.check(ui.inventory.count("scrap_material") == 10 and ui.inventory.count("potion_minor") == 2, "sincronizado: pickup/quest/craft nao contam em dobro (o servidor e a fonte)")
	ss.on_inventory_update({"capacity": 24, "slots": [{"item_id": "scrap_material", "qty": 13}], "equipment": {}})
	ctx.check(ui.inventory.count("scrap_material") == 13 and ui.inventory.count("potion_minor") == 0 and ui.inventory.equipment.is_empty(), "novo s_inventory substitui tudo")
	# nova sessao: bind zera
	ui.bind(ClientSession.new())
	ctx.check(not ui.inventory.complete and ui.inventory.entries().is_empty(), "nova sessao: a UI volta ao estado inicial")
	U.free_ui(tree, ui)


func _test_reward_redelivery(ctx: Object, tree: SceneTree) -> void:
	# Quest: o backend fica indisponivel (rede) por TODAS as tentativas do BackendClient; a recompensa e reentregue com a
	# mesma chave e aplicada exatamente uma vez quando ele volta.
	var rig: B.BRig = L.make(tree, 1, "greenwood", true, [])
	rig.sync.reward_redeliver_delay_sec = 0.2
	var errs: Array = []
	for i: int in 3:
		errs.append(Fake.NET_ERR)
	rig.fake.force("/rewards", errs) # 3 tentativas do BackendClient falham; a reentrega funciona
	var eid: int = L.eid(rig, 0)
	rig.world.teleport_player(eid, Vector3(10.0, 0.05, -8.0))
	rig.session.quests.cmd_quest(eid, 1, Protocol.QUEST_OP_ACCEPT, "gw_welcome")
	rig.session.quests.tracker_of(eid).on_npc_talked("npc_hunter_brannoch")
	rig.session.quests.cmd_quest(eid, 2, Protocol.QUEST_OP_TURN_IN, "gw_welcome")
	var t0: int = Time.get_ticks_msec()
	while rig.fake.find_all("/rewards").size() < 4 and Time.get_ticks_msec() - t0 < 4000:
		await tree.process_frame
		rig.sync.tick(0.05)
	for i: int in 5:
		await tree.process_frame
	var rw: Array[Dictionary] = rig.fake.find_all("/rewards")
	var keys: Dictionary = {}
	for x: Dictionary in rw:
		keys[x["body"]["idempotency_key"]] = true
	ctx.check(rw.size() == 4 and keys.size() == 1, "backend fora do ar: 3 tentativas + 1 reentrega, sempre a MESMA chave (%d pedidos)" % rw.size())
	ctx.check(rig.fake.chars[L.CIDS[0]]["quests"]["completed"] == ["gw_welcome"] and int(rig.fake.chars[L.CIDS[0]]["xp"]) == 60, "recompensa da quest aplicada exatamente uma vez no banco")
	ctx.check(int(rig.sync.stats["reward_redeliveries"]) == 1, "contador de reentregas = 1")
	# a fila nao ficou presa
	ctx.check(rig.sync.pending_ops() == 0, "fila do personagem drenada depois da reentrega")
	rig.free_all()
	# Erro definitivo (4xx) NAO e reentregue
	var rig2: B.BRig = L.make(tree, 1, "greenwood", true, [])
	rig2.sync.reward_redeliver_delay_sec = 0.05
	rig2.fake.force("/rewards", [Fake.err(409, "inventory_full")])
	rig2.sync.enqueue_reward(L.CIDS[0], "kill:x:1:" + L.CIDS[0], 10, [])
	for i: int in 10:
		await tree.process_frame
		rig2.sync.tick(0.1)
	ctx.check(rig2.fake.count("/rewards") == 1 and rig2.sync.pending_ops() == 0, "erro definitivo (409): sem reentrega, fila liberada")
	rig2.free_all()
	# Limite de reentregas: depois de max, desiste (nao fica preso para sempre) e libera a fila
	var rig3: B.BRig = L.make(tree, 1, "greenwood", true, [])
	rig3.sync.reward_redeliver_delay_sec = 0.01
	rig3.sync.reward_redeliver_max = 2
	var many: Array = []
	for i: int in 40:
		many.append(Fake.NET_ERR)
	rig3.fake.force("/rewards", many)
	rig3.sync.enqueue_reward(L.CIDS[0], "kill:x:2:" + L.CIDS[0], 10, [])
	var t1: int = Time.get_ticks_msec()
	while rig3.sync.pending_ops() > 0 and Time.get_ticks_msec() - t1 < 4000:
		await tree.process_frame
		rig3.sync.tick(0.05)
	ctx.check(rig3.sync.pending_ops() == 0 and rig3.fake.count("/rewards") == 9, "limite de reentregas: desiste apos %d (pedidos=%d) e libera a fila" % [2, rig3.fake.count("/rewards")])
	ctx.check(ServerLog.joined().contains("reentrega 1/2") and ServerLog.joined().contains("falhou de forma permanente"), "reentregas e desistencia registradas no log")
	rig3.free_all()
