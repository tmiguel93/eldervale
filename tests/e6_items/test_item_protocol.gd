extends RefCounted
## E6.3 - protocolo (aditivo, VERSION continua 2): validadores de instancia, c_equip_cmd, s_equip, s_inventory com inst/equipment_inst;
## o snapshot compacto NAO cresce (a instancia so vai em s_inventory/EVENT_PICKUP ao dono); cliente antigo ignora campos novos.

const L = preload("res://tests/e5_loot/loot_helpers.gd")
const S = preload("res://tests/e5_snapshot/snapshot_helpers.gd")


func run(ctx: Object) -> void:
	var tree: SceneTree = ctx as SceneTree
	await tree.physics_frame
	_test_version(ctx)
	_test_instance(ctx)
	_test_equip_cmd(ctx)
	_test_equip_update(ctx)
	_test_inventory_update(ctx)
	_test_events(ctx)
	_test_snapshot_unchanged(ctx, tree)


func _inst() -> Dictionary:
	return {"uid": "0123456789abcdef", "rarity": "rare", "ilvl": 20, "affixes": [{"id": "pre_brutal", "tier": 3, "value": 1.0}, {"id": "suf_of_ward", "tier": 3, "value": 0.01}, {"id": "suf_of_titan", "tier": 3, "value": 4.0}]}


func _test_version(ctx: Object) -> void:
	ctx.check(Protocol.VERSION == 2, "VERSION continua 2 (mudancas E6.3 sao aditivas)")
	ctx.check(Protocol.MAX_INSTANCE_BYTES == 512 and ItemRules.MAX_INSTANCE_BYTES == Protocol.MAX_INSTANCE_BYTES, "limite de instancia (512 bytes) igual no protocolo e nas regras")


func _test_instance(ctx: Object) -> void:
	ctx.check(Protocol.validate_item_instance(_inst()), "instancia valida")
	var js: Variant = JSON.parse_string(JSON.stringify(_inst()))
	ctx.check(Protocol.validate_item_instance(js), "instancia apos JSON (floats) valida")
	var bad: Dictionary = {}
	var m: Dictionary = _inst()
	m["extra"] = 1
	bad["campo extra"] = m
	m = _inst()
	m.erase("ilvl")
	bad["sem ilvl"] = m
	m = _inst()
	m["uid"] = "curto"
	bad["uid curto"] = m
	m = _inst()
	m["uid"] = 12345
	bad["uid nao string"] = m
	m = _inst()
	m["rarity"] = "R A R E"
	bad["raridade nao id"] = m
	m = _inst()
	m["ilvl"] = 0
	bad["ilvl 0"] = m
	m = _inst()
	m["ilvl"] = 101
	bad["ilvl > maximo"] = m
	m = _inst()
	m["affixes"] = "x"
	bad["affixes nao lista"] = m
	m = _inst()
	m["affixes"] = []
	for i: int in 9:
		m["affixes"].append({"id": "pre_brutal", "tier": 3, "value": 1.0})
	bad["affixes demais"] = m
	m = _inst()
	m["affixes"][0]["value"] = NAN
	bad["valor NaN"] = m
	m = _inst()
	m["affixes"][0]["value"] = INF
	bad["valor infinito"] = m
	m = _inst()
	m["affixes"][0]["tier"] = 0
	bad["tier 0"] = m
	m = _inst()
	m["affixes"][0]["id"] = "../etc"
	bad["id de affix invalido"] = m
	m = _inst()
	m["affixes"][0]["extra"] = 1
	bad["campo extra no affix"] = m
	m = _inst()
	m["uid"] = "0123456789abcdef"
	m["affixes"] = []
	for i2: int in 8:
		m["affixes"].append({"id": "a".repeat(40) + str(i2), "tier": 3, "value": 123456789.123456})
	bad["acima de 512 bytes"] = m
	for k: String in bad:
		ctx.check(not Protocol.validate_item_instance(bad[k]), "instancia invalida recusada: " + k)
	ctx.check(not Protocol.validate_item_instance("x") and not Protocol.validate_item_instance(null) and not Protocol.validate_item_instance([]), "nao-objeto recusado")


func _test_equip_cmd(ctx: Object) -> void:
	var ok: Dictionary = Protocol.validate_equip_cmd(1, Protocol.EQUIP_OP_EQUIP, 3, "sword_basic")
	ctx.check(bool(ok["ok"]) and int(ok["index"]) == 3 and String(ok["item_id"]) == "sword_basic", "equipar valido")
	ctx.check(bool(Protocol.validate_equip_cmd(2, Protocol.EQUIP_OP_UNEQUIP, 0, "")["ok"]), "desequipar valido (item_id opcional)")
	var bads: Array = [
		["req_id string", ["x", 1, 0, "sword_basic"]], ["req_id negativo", [-1, 1, 0, "sword_basic"]], ["req_id NaN", [NAN, 1, 0, "sword_basic"]],
		["op desconhecido", [1, 9, 0, "sword_basic"]], ["op string", [1, "1", 0, "sword_basic"]], ["indice negativo", [1, 1, -1, "sword_basic"]],
		["indice enorme", [1, 1, 9999, "sword_basic"]], ["item vazio ao equipar", [1, 1, 0, ""]], ["item com caminho", [1, 1, 0, "../x"]],
		["item gigante", [1, 1, 0, "a".repeat(200)]], ["slot de desequipar 3", [1, 2, 3, ""]], ["item_id nao string", [1, 1, 0, 5]], ["index float", [1, 1, 0.5, "sword_basic"]],
	]
	for b: Array in bads:
		var a: Array = b[1]
		ctx.check(not bool(Protocol.validate_equip_cmd(a[0], a[1], a[2], a[3])["ok"]), "c_equip_cmd invalido recusado: " + String(b[0]))


func _test_equip_update(ctx: Object) -> void:
	ctx.check(Protocol.validate_equip_update(Protocol.EQUIP_OK, {"req_id": 1, "op": 1}), "s_equip OK valido")
	ctx.check(Protocol.validate_equip_update(Protocol.EQUIP_ERROR, {"req_id": 1, "op": 1, "code": "busy"}), "s_equip erro valido")
	ctx.check(not Protocol.validate_equip_update(Protocol.EQUIP_ERROR, {"req_id": 1, "op": 1}), "erro sem code recusado")
	ctx.check(not Protocol.validate_equip_update(99, {"req_id": 1, "op": 1}) and not Protocol.validate_equip_update(Protocol.EQUIP_OK, {"op": 1}) and not Protocol.validate_equip_update(Protocol.EQUIP_OK, "x"), "kind desconhecido / sem req_id / nao-objeto recusados")


func _test_inventory_update(ctx: Object) -> void:
	var base: Dictionary = {"capacity": 24, "slots": [{"item_id": "sword_basic", "qty": 1, "inst": _inst()}, {"item_id": "potion_minor", "qty": 3}], "equipment": {"weapon": "sword_basic"}, "equipment_inst": {"weapon": _inst()}}
	ctx.check(Protocol.validate_inventory_update(base), "s_inventory com inst e equipment_inst valido")
	var legacy: Dictionary = {"capacity": 24, "slots": [{"item_id": "potion_minor", "qty": 3}], "equipment": {}}
	ctx.check(Protocol.validate_inventory_update(legacy), "s_inventory legado (sem inst) continua valido")
	var m: Dictionary = base.duplicate(true)
	m["slots"][0]["qty"] = 2
	ctx.check(not Protocol.validate_inventory_update(m), "inst com qty != 1 recusado")
	m = base.duplicate(true)
	m["slots"][0]["inst"]["uid"] = "x"
	ctx.check(not Protocol.validate_inventory_update(m), "inst invalida recusada")
	m = base.duplicate(true)
	m["equipment_inst"] = {"cabeca": _inst()}
	ctx.check(not Protocol.validate_inventory_update(m), "equipment_inst em slot desconhecido recusado")
	m = base.duplicate(true)
	m["equipment_inst"] = {"weapon": "x"}
	ctx.check(not Protocol.validate_inventory_update(m), "equipment_inst nao-objeto recusado")
	m = base.duplicate(true)
	m["equipment_inst"] = "x"
	ctx.check(not Protocol.validate_inventory_update(m), "equipment_inst nao dicionario recusado")


func _test_events(ctx: Object) -> void:
	var drop: Dictionary = {"pos": Vector3(1, 0, 1), "item_id": "sword_basic", "qty": 1, "id": 5}
	ctx.check(Protocol.validate_world_event(Protocol.EVENT_DROP, drop), "evento de drop legado (sem raridade) valido")
	var d2: Dictionary = drop.duplicate()
	d2["rarity"] = "rare"
	ctx.check(Protocol.validate_world_event(Protocol.EVENT_DROP, d2), "evento de drop com raridade valido")
	d2["rarity"] = "../x"
	ctx.check(not Protocol.validate_world_event(Protocol.EVENT_DROP, d2), "raridade invalida no drop recusada")
	var pk: Dictionary = {"id": 5, "item_id": "sword_basic", "qty": 1}
	ctx.check(Protocol.validate_world_event(Protocol.EVENT_PICKUP, pk), "pickup legado valido")
	pk["inst"] = _inst()
	ctx.check(Protocol.validate_world_event(Protocol.EVENT_PICKUP, pk), "pickup com instancia valido")
	pk["inst"]["uid"] = "x"
	ctx.check(not Protocol.validate_world_event(Protocol.EVENT_PICKUP, pk), "pickup com instancia invalida recusado")


func _test_snapshot_unchanged(ctx: Object, tree: SceneTree) -> void:
	# pickup com instancia ocupa exatamente o mesmo no snapshot compacto que um pickup simples do mesmo tipo
	var plain: Dictionary = SnapshotCodec.encode([S.pickup(9, Vector3(1, 0, 1), "sword_basic", 1)])
	var with_inst_ent: Dictionary = S.pickup(9, Vector3(1, 0, 1), "sword_basic", 1)
	with_inst_ent["inst"] = _inst()
	var rich: Dictionary = SnapshotCodec.encode([with_inst_ent])
	var plain_bytes: int = 0
	var rich_bytes: int = 0
	for p: Variant in plain["parts"]:
		plain_bytes += (p as PackedByteArray).size()
	for p2: Variant in rich["parts"]:
		rich_bytes += (p2 as PackedByteArray).size()
	ctx.check(plain_bytes > 0 and plain_bytes == rich_bytes, "snapshot: pickup com instancia = mesmos %d bytes (campo inst nunca serializado)" % plain_bytes)
	# e o servidor nem coloca `inst` nas entidades de pickup
	var rig: Object = L.make(tree, 1, "greenwood", true, [[]], false)
	rig.settings.rolled_loot = true
	rig.settings.test_force_rarity = "epic"
	var enemy: Enemy = L.spawn(rig)
	L.hit(enemy, L.node(rig, 0), 99999.0)
	var ents: Array = rig.world.loot.entities_for(L.eid(rig, 0), "", L.ENEMY_POS, 9999.0)
	var leaked: int = 0
	for e: Dictionary in ents:
		leaked += 1 if e.has("inst") else 0
	var has_rolled: bool = false
	for pk: LootManager.LootPickup in L.pickups_of(rig, 0):
		has_rolled = has_rolled or not pk.inst.is_empty()
	ctx.check(has_rolled and leaked == 0, "entidades de pickup do servidor (%d) nao carregam a instancia" % ents.size())
	rig.free_all()
