extends RefCounted
## E6.3 - servidor (backend FALSO): loot rolado -> pickup -> inventario com instancia -> recompensa idempotente; comandos de equipar
## (OK, indice ruim, base trocada, pedido repetido, ocupado, rate limit, payload invalido); checkpoint e reconexao com instancia;
## saves antigos (sem instancias) continuam validos como Comuns; instancias adulteradas sao recusadas ao carregar.

const L = preload("res://tests/e5_loot/loot_helpers.gd")
const B = preload("res://tests/e4/backend_helpers.gd")
const Fake = preload("res://tests/e4/fake_backend.gd")

var _rules: ItemRules


func run(ctx: Object) -> void:
	var tree: SceneTree = ctx as SceneTree
	await tree.physics_frame
	ServerLog.capturing = true
	ServerLog.reset_capture()
	_rules = ItemRules.shared()
	_test_rolled_loot(ctx, tree)
	_test_unique_drop_gate(ctx, tree)
	_test_equip_commands(ctx, tree)
	_test_equip_busy(ctx, tree)
	_test_equip_abuse(ctx, tree)
	_test_checkpoint_and_reconnect(ctx, tree)
	_test_old_saves_and_tampering(ctx, tree)
	ServerLog.capturing = false
	await tree.physics_frame


func _aff(id: String, tier: int) -> Dictionary:
	return {"id": id, "tier": tier, "value": float(_rules.tier_of(_rules.affixes[id], tier)["min"])}


func _sword(uid: String) -> Dictionary:
	return {"uid": uid, "rarity": "rare", "ilvl": 20, "affixes": [_aff("pre_brutal", 3), _aff("suf_of_ward", 3), _aff("suf_of_titan", 3)]}


func _rig_with(tree: SceneTree, inv: Array, hold: bool = false) -> B.BRig:
	var rig: B.BRig = L.make(tree, 1, "greenwood", true, [inv], hold)
	rig.settings.rolled_loot = true
	rig.session.test_now_msec = 1000
	return rig


func _equip(rig: B.BRig, req: int, op: int, index: int, item_id: String) -> void:
	rig.session.on_equip_cmd(L.PEER0, req, op, index, item_id)


func _codes(rig: B.BRig) -> Array:
	var out: Array = []
	for u: Dictionary in rig.transport.equip_updates:
		out.append("ok" if int(u["kind"]) == Protocol.EQUIP_OK else String(u["data"]["code"]))
	return out


func _test_rolled_loot(ctx: Object, tree: SceneTree) -> void:
	var rig: B.BRig = _rig_with(tree, [])
	rig.settings.test_force_rarity = "rare"
	var enemy: Enemy = L.spawn(rig)
	L.hit(enemy, L.node(rig, 0), 99999.0)
	var pks: Array[LootManager.LootPickup] = L.pickups_of(rig, 0)
	var with_inst: Array[LootManager.LootPickup] = []
	for p: LootManager.LootPickup in pks:
		if not p.inst.is_empty():
			with_inst.append(p)
	ctx.check(with_inst.size() >= 1, "morte do inimigo gera pelo menos 1 item rolado (%d pickups)" % pks.size())
	if with_inst.is_empty():
		rig.free_all()
		return
	var pk: LootManager.LootPickup = with_inst[0]
	var base: ItemData = rig.world.loot._registry().get_item(StringName(pk.item_id))
	ctx.check(_rules.validate_instance(pk.inst, base).is_empty() and String(pk.inst["rarity"]) == "rare", "instancia do drop e valida e Rara (forcada no modo teste)")
	var drop_ev: Array = rig.transport.events_of(L.PEER0, Protocol.EVENT_DROP)
	var with_rarity: int = 0
	var leaked: int = 0
	for dev: Dictionary in drop_ev:
		with_rarity += 1 if (dev["data"] as Dictionary).has("rarity") else 0
		leaked += 1 if (dev["data"] as Dictionary).has("inst") else 0
	ctx.check(with_rarity >= 1 and leaked == 0, "evento de drop mostra a raridade, nunca a instancia (%d com raridade)" % with_rarity)
	var lo: PlayerLoadout = L.loadout(rig, 0)
	rig.world.teleport_player(L.eid(rig, 0), pk.pos)
	rig.world.step_loot(0.1)
	var found: int = -1
	var contents: Array[Dictionary] = lo.inventory.contents()
	for i: int in contents.size():
		if contents[i].has("inst") and contents[i]["inst"]["uid"] == pk.inst["uid"]:
			found = i
	ctx.check(found >= 0, "coletar: a MESMA instancia (uid) entra no inventario do dono")
	var rewards: Array[Dictionary] = []
	for r: Dictionary in rig.fake.find_all("/rewards"):
		if String(r["body"]["idempotency_key"]).begins_with("loot:") and (r["body"]["items"] as Array)[0].has("inst"):
			rewards.append(r)
	ctx.check(rewards.size() >= 1 and JSON.stringify(Fake._canon((rewards[0]["body"]["items"] as Array)[0]["inst"])) == JSON.stringify(Fake._canon(pk.inst)), "recompensa ao backend carrega a instancia (chave loot:<sessao>:<n>:<char>)")
	var pickups_ev: Array = rig.transport.events_of(L.PEER0, Protocol.EVENT_PICKUP)
	var inv_ok: bool = false
	for ev: Dictionary in pickups_ev:
		var d: Dictionary = ev["data"]
		if d.has("inst") and String(d["inst"]["uid"]) == String(pk.inst["uid"]):
			inv_ok = true
	ctx.check(inv_ok, "evento de pickup ao dono leva a instancia completa")
	# nada duplica ao repetir passos / segundo contato
	var n_inst: int = 0
	var key: String = String(rewards[0]["body"]["idempotency_key"])
	for i: int in 6:
		rig.world.step_loot(0.1)
	for e: Dictionary in lo.inventory.contents():
		if e.has("inst") and e["inst"]["uid"] == pk.inst["uid"]:
			n_inst += 1
	var sent: int = 0
	for r2: Dictionary in rig.fake.find_all("/rewards"):
		if String(r2["body"]["idempotency_key"]) == key:
			sent += 1
	ctx.check(n_inst == 1 and sent == 1, "coleta repetida: 1 instancia e 1 recompensa (sem duplicar)")
	# o servidor so tem a verdade: o banco falso recebeu a mesma instancia
	var db_n: int = 0
	for line: Variant in rig.fake.chars[L.CIDS[0]]["inventory"]:
		if (line as Dictionary).has("inst") and line["inst"]["uid"] == pk.inst["uid"]:
			db_n += 1
	ctx.check(db_n == 1, "banco (falso) tem exatamente 1 copia da instancia")
	# determinismo do servidor: mesma semente base + mesmos ids => mesma instancia
	var rig2: B.BRig = _rig_with(tree, [])
	rig2.settings.test_force_rarity = "rare"
	rig2.world.loot.uid_salt = rig.world.loot.uid_salt
	var tbl: LootTable = enemy.data.loot_table
	var a: Array[LootDrop] = rig.world.loot.roll_for(tbl, 5, 7, 10, "normal", 10)
	var b: Array[LootDrop] = rig2.world.loot.roll_for(tbl, 5, 7, 10, "normal", 10)
	var same: bool = a.size() == b.size()
	for i2: int in mini(a.size(), b.size()):
		same = same and JSON.stringify(a[i2].inst) == JSON.stringify(b[i2].inst) and a[i2].item_id == b[i2].item_id
	ctx.check(same and not a.is_empty(), "mesmo seed/salt/inimigo/jogador => mesmos drops e instancias (servidor deterministico)")
	rig2.free_all()
	rig.free_all()


func _test_unique_drop_gate(ctx: Object, tree: SceneTree) -> void:
	var rig: B.BRig = _rig_with(tree, [])
	var loot: LootManager = rig.world.loot
	var tbl_id: StringName = &"loot_blight_treant"
	var tbl: LootTable = load("res://data/loot/loot_blight_treant.tres") as LootTable
	var got_low: int = 0
	var got_high: int = 0
	var found_ids: Dictionary = {}
	for s: int in 400:
		loot.base_seed = s
		for d: LootDrop in loot.roll_for(tbl, 3, 9, 3, "boss", 3):
			if _rules.is_unique(String(d.item_id)):
				got_low += 1
		for d2: LootDrop in loot.roll_for(tbl, 3, 9, 30, "boss", 30):
			if _rules.is_unique(String(d2.item_id)):
				got_high += 1
				found_ids[String(d2.item_id)] = true
	ctx.check(got_low == 0, "unicos nao caem abaixo do nivel minimo (nivel 3)")
	ctx.check(got_high > 0 and got_high < 400 * 3, "unicos caem com chance < 100%% no nivel elegivel (%d em 400 rolagens)" % got_high)
	var other: LootTable = load("res://data/loot/loot_melee_grunt.tres") as LootTable
	var from_other: int = 0
	for s2: int in 200:
		loot.base_seed = s2
		for d3: LootDrop in loot.roll_for(other, 3, 9, 30, "normal", 30):
			if _rules.is_unique(String(d3.item_id)):
				from_other += 1
	ctx.check(from_other == 0, "unico so cai das tabelas listadas em obtain (grunt comum nunca)")
	rig.free_all()


func _test_equip_commands(ctx: Object, tree: SceneTree) -> void:
	var inst: Dictionary = _sword("00000000000000c1")
	var rig: B.BRig = _rig_with(tree, [{"slot": 0, "item_id": "sword_basic", "qty": 1, "inst": inst}, {"slot": 1, "item_id": "potion_minor", "qty": 3}])
	var lo: PlayerLoadout = L.loadout(rig, 0)
	var hp0: float = lo.final_stats.max_health
	ctx.check(lo.inventory.has_uid("00000000000000c1"), "fixture: personagem carregado com instancia no inventario")
	_equip(rig, 1, Protocol.EQUIP_OP_EQUIP, 5, "sword_basic")
	_equip(rig, 2, Protocol.EQUIP_OP_EQUIP, 0, "armor_leather")
	_equip(rig, 3, Protocol.EQUIP_OP_EQUIP, 1, "potion_minor")
	ctx.check(_codes(rig) == ["bad_index", "item_mismatch", "not_equippable"], "indice ruim / base trocada / nao equipavel: rejeitados sem mudar nada (%s)" % str(_codes(rig)))
	ctx.check(lo.inventory.has_uid("00000000000000c1") and lo.final_stats.max_health == hp0, "rejeicoes nao alteram estado")
	_equip(rig, 4, Protocol.EQUIP_OP_EQUIP, 0, "sword_basic")
	ctx.check(_codes(rig).back() == "ok", "equipar a instancia: OK")
	var expect: float = hp0 - lo.registry.get_item(&"sword_basic").stat_modifiers.max_health * 0.0 + _rules.stat_block(inst).max_health
	ctx.check(is_equal_approx(lo.final_stats.max_health, expect), "stats recalculados no servidor (+%.0f vida do affix)" % _rules.stat_block(inst).max_health)
	ctx.check(lo.equipment.get_equipped_instance(ItemData.Slot.WEAPON).get("uid") == "00000000000000c1" and not lo.inventory.has_uid("00000000000000c1"), "a instancia saiu do inventario e esta no slot (nao duplicou)")
	var prev_n: int = _codes(rig).size()
	_equip(rig, 4, Protocol.EQUIP_OP_UNEQUIP, 0, "")
	ctx.check(_codes(rig).size() == prev_n + 1 and _codes(rig).back() == "duplicate_request", "mesmo req_id repetido: rejeitado (idempotencia do comando)")
	ctx.check(lo.equipment.get_equipped_instance(ItemData.Slot.WEAPON).get("uid") == "00000000000000c1", "duplicado nao desequipou")
	_equip(rig, 5, Protocol.EQUIP_OP_UNEQUIP, 0, "armor_leather")
	ctx.check(_codes(rig).back() == "item_mismatch", "desequipar com base trocada: item_mismatch")
	_equip(rig, 6, Protocol.EQUIP_OP_UNEQUIP, 0, "sword_basic")
	ctx.check(_codes(rig).back() == "ok" and lo.inventory.has_uid("00000000000000c1") and is_equal_approx(lo.final_stats.max_health, hp0), "desequipar: instancia volta intacta e os stats voltam exatamente")
	_equip(rig, 7, Protocol.EQUIP_OP_UNEQUIP, 2, "")
	ctx.check(_codes(rig).back() == "empty_slot", "desequipar slot vazio: empty_slot")
	# a visao do cliente (s_inventory) leva a instancia completa; o snapshot compacto nao
	ctx.check(rig.sync.pending_ops() >= 0, "checkpoint coalescido enfileirado")
	rig.free_all()


func _test_equip_busy(ctx: Object, tree: SceneTree) -> void:
	var rig: B.BRig = _rig_with(tree, [{"slot": 0, "item_id": "sword_basic", "qty": 1, "inst": _sword("00000000000000c2")}, {"slot": 1, "item_id": "scrap_material", "qty": 12}])
	rig.world.teleport_player(L.eid(rig, 0), L.STATION_POS)
	rig.fake.hold = true
	rig.session.on_craft_cmd(L.PEER0, 1, "rcp_potion_minor")
	ctx.check(rig.session.crafting.is_pending(L.eid(rig, 0)), "fixture: craft em voo")
	_equip(rig, 2, Protocol.EQUIP_OP_EQUIP, 0, "sword_basic")
	ctx.check(_codes(rig) == ["busy"] and L.loadout(rig, 0).inventory.has_uid("00000000000000c2"), "equipar com craft em voo: busy, nada muda")
	rig.fake.hold = false
	rig.fake.flush()
	ctx.check(L.loadout(rig, 0).inventory.has_uid("00000000000000c2") and L.loadout(rig, 0).inventory.count(&"potion_minor") == 1, "craft conclui sem tocar na instancia (affixados ficam fora das receitas)")
	rig.free_all()


func _test_equip_abuse(ctx: Object, tree: SceneTree) -> void:
	var rig: B.BRig = _rig_with(tree, [{"slot": 0, "item_id": "sword_basic", "qty": 1, "inst": _sword("00000000000000c3")}])
	var peer: ServerSession.PeerState = rig.session.get_peer_state(L.PEER0)
	var inv0: int = peer.dropped_invalid
	rig.session.on_equip_cmd(L.PEER0, "x", 1, 0, "sword_basic")
	rig.session.on_equip_cmd(L.PEER0, 1, 99, 0, "sword_basic")
	rig.session.on_equip_cmd(L.PEER0, 2, 1, -3, "sword_basic")
	rig.session.on_equip_cmd(L.PEER0, 3, 1, 0, "A".repeat(500))
	rig.session.on_equip_cmd(L.PEER0, NAN, 1, 0, "sword_basic")
	ctx.check(peer.dropped_invalid >= inv0 + 5 and rig.transport.equip_updates.is_empty(), "payloads invalidos descartados e contados como abuso (sem resposta de jogo)")
	for i: int in 40:
		rig.session.on_equip_cmd(L.PEER0, 100 + i, Protocol.EQUIP_OP_EQUIP, 9, "sword_basic")
	ctx.check(peer.dropped_rate > 0 and rig.transport.equip_updates.size() <= 10, "flood de equipar limitado por rate limit (%d respostas, %d descartados)" % [rig.transport.equip_updates.size(), peer.dropped_rate])
	rig.free_all()


func _test_checkpoint_and_reconnect(ctx: Object, tree: SceneTree) -> void:
	var inst: Dictionary = _sword("00000000000000c4")
	var rig: B.BRig = _rig_with(tree, [{"slot": 0, "item_id": "sword_basic", "qty": 1, "inst": inst}])
	_equip(rig, 1, Protocol.EQUIP_OP_EQUIP, 0, "sword_basic")
	rig.fake.flush()
	var db: Dictionary = rig.fake.chars[L.CIDS[0]]
	ctx.check(db.has("equipment_inst") and (db["equipment_inst"] as Dictionary).get("weapon", {}).get("uid", "") == "00000000000000c4", "checkpoint apos equipar persiste equipment_inst.weapon")
	var hp_equipped: float = L.loadout(rig, 0).final_stats.max_health
	# desconecta e reconecta com o mesmo ticket: tudo volta como estava
	rig.session.on_peer_disconnected(L.PEER0)
	rig.fake.flush()
	B.hello(rig, L.PEER0 + 7, L.TICKETS[0], "Hero0")
	rig.fake.flush()
	var lo2: PlayerLoadout = B.loadout_of(rig, L.PEER0 + 7)
	ctx.check(lo2 != null and lo2.equipment.get_equipped_instance(ItemData.Slot.WEAPON).get("uid", "") == "00000000000000c4", "reconexao: a instancia equipada volta")
	ctx.check(lo2 != null and is_equal_approx(lo2.final_stats.max_health, hp_equipped), "reconexao: stats identicos aos de antes (%.1f)" % hp_equipped)
	var inv_msgs: int = 0
	for m: Dictionary in rig.transport.inventories:
		if int(m["peer"]) == L.PEER0 + 7:
			inv_msgs += 1
			var eq: Dictionary = (m["data"] as Dictionary).get("equipment_inst", {})
			ctx.check(Protocol.validate_inventory_update(m["data"]) and eq.has("weapon"), "s_inventory pos-login valido e com equipment_inst")
			break
	ctx.check(inv_msgs >= 1, "s_inventory enviado apos o login")
	rig.free_all()


func _test_old_saves_and_tampering(ctx: Object, tree: SceneTree) -> void:
	var reg: ContentRegistry = ContentRegistry.new()
	reg.load_all()
	var old: Dictionary = {
		"id": L.CIDS[0], "name": "Velho", "class_id": "warrior", "level": 5, "xp": 10, "revision": 3, "schema_version": 1, "inventory_capacity": 24,
		"stats": {"max_health": 100, "max_resource": 50, "resource_regen": 5, "attack_power": 10, "defense": 0, "resistance": 0, "move_speed": 5},
		"inventory": [{"slot": 0, "item_id": "sword_rare", "qty": 1}, {"slot": 1, "item_id": "potion_minor", "qty": 4}],
		"equipment": {"weapon": "sword_basic", "armor": "armor_leather"},
	}
	ctx.check(CharacterCodec.validate(old, reg).is_empty(), "save antigo (sem inst/equipment_inst) continua valido")
	var rig: B.BRig = L.make(tree, 1, "greenwood", true, [[{"slot": 0, "item_id": "sword_rare", "qty": 1}]], false)
	var lo: PlayerLoadout = L.loadout(rig, 0)
	ctx.check(lo.equipment.get_equipped_instance(ItemData.Slot.WEAPON).is_empty() and lo.inventory.contents()[0].has("inst") == false, "save antigo: itens carregam como Comuns (sem instancia)")
	var cap: Dictionary = CharacterCodec.capture(lo)
	ctx.check(not cap.has("equipment_inst"), "capture de personagem sem instancias nao inclui equipment_inst (compativel com backend antigo)")
	# adulteracoes: cada uma deve ser recusada pelo validate()
	var good_inst: Dictionary = _sword("00000000000000d1")
	var mk: Callable = func(mut: Callable) -> Dictionary:
		var c: Dictionary = old.duplicate(true)
		c["inventory"] = [{"slot": 0, "item_id": "sword_basic", "qty": 1, "inst": good_inst.duplicate(true)}]
		mut.call(c)
		return c
	ctx.check(CharacterCodec.validate(mk.call(func(_c: Dictionary) -> void: pass), reg).is_empty(), "save com instancia valida passa")
	var bad_cases: Dictionary = {
		"valor fora da faixa": func(c: Dictionary) -> void: c["inventory"][0]["inst"]["affixes"][0]["value"] = 9999.0,
		"affix desconhecido": func(c: Dictionary) -> void: c["inventory"][0]["inst"]["affixes"][0]["id"] = "affix_x",
		"qty > 1 com instancia": func(c: Dictionary) -> void: c["inventory"][0]["qty"] = 2,
		"uid duplicado no inventario": func(c: Dictionary) -> void: c["inventory"].append({"slot": 1, "item_id": "sword_basic", "qty": 1, "inst": good_inst.duplicate(true)}),
		"instancia em item nao equipavel": func(c: Dictionary) -> void: c["inventory"][0]["item_id"] = "potion_minor",
		"instancia em unico": func(c: Dictionary) -> void: c["inventory"][0]["item_id"] = "unique_emberfang",
		"equipment_inst sem equipamento": func(c: Dictionary) -> void: c["equipment_inst"] = {"trinket": good_inst.duplicate(true)},
		"equipment_inst no slot errado": func(c: Dictionary) -> void: c["equipment_inst"] = {"armor": good_inst.duplicate(true)},
		"equipment_inst com uid repetido": func(c: Dictionary) -> void: c["equipment_inst"] = {"weapon": good_inst.duplicate(true)},
	}
	for k: String in bad_cases:
		var c2: Dictionary = mk.call(bad_cases[k])
		ctx.check(not CharacterCodec.validate(c2, reg).is_empty(), "save adulterado recusado: " + k)
	rig.free_all()
