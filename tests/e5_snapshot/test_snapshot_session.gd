extends RefCounted
## E5.7 - snapshot compacto ponta a ponta: validadores do protocolo, superficie do NetRpc, RPC real em loopback (ENet),
## servidor (negociacao por capacidade, compatibilidade com o formato antigo, interesse por peer, tamanho com 30+
## entidades, medicao) e cliente (ClientSession, predicao, interpolador).

const S = preload("res://tests/e5_snapshot/snapshot_helpers.gd")
const H = preload("res://tests/e3/server_helpers.gd")
const B = preload("res://tests/e4/backend_helpers.gd")
const L = preload("res://tests/e5_loot/loot_helpers.gd")

const TEST_PORT: int = 24793
const GRUNT: String = "res://scenes/enemy/melee_grunt.tscn"
const BOSS: String = "res://scenes/enemy/blight_treant.tscn"

var _got: Dictionary = {}


func run(ctx: Object) -> void:
	var tree: SceneTree = ctx as SceneTree
	await tree.physics_frame
	ServerLog.capturing = true
	ServerLog.reset_capture()
	_test_validators(ctx)
	_test_netrpc_surface(ctx)
	_test_caps_handling(ctx, tree)
	_test_negotiation_and_legacy(ctx, tree)
	_test_thirty_entities(ctx, tree)
	_test_partitioned_server(ctx, tree)
	_test_world_interest(ctx, tree)
	_test_client_session(ctx)
	_test_prediction_noise(ctx)
	await _test_loopback(ctx, tree)
	ServerLog.capturing = false
	await tree.physics_frame


# ---------------------------------------------------------------- protocolo

func _test_validators(ctx: Object) -> void:
	var v: Dictionary = Protocol.validate_caps(1)
	ctx.check(bool(v["ok"]) and int(v["caps"]) == 1, "validate_caps: 1 ok")
	v = Protocol.validate_caps(0)
	ctx.check(bool(v["ok"]) and int(v["caps"]) == 0, "validate_caps: 0 ok (sem capacidades)")
	v = Protocol.validate_caps(0xFF)
	ctx.check(bool(v["ok"]) and int(v["caps"]) == Protocol.CAP_SNAPSHOT_COMPACT, "validate_caps: bits desconhecidos sao mascarados (cliente mais novo)")
	for bad: Variant in [-1, 0x10000, 1.0, "1", null, true, [1], Vector2.ONE]:
		ctx.check(not bool(Protocol.validate_caps(bad)["ok"]), "validate_caps recusa %s" % [bad])
	var blob: PackedByteArray = PackedByteArray([1, 2, 3])
	ctx.check(Protocol.validate_snapshot_part(0, -1, 0, 1, blob), "validate_snapshot_part: minimo valido (tick 0, last_seq -1)")
	ctx.check(Protocol.validate_snapshot_part(9, 5, Protocol.MAX_SNAPSHOT_PARTS - 1, Protocol.MAX_SNAPSHOT_PARTS, blob), "validate_snapshot_part: ultima parte do maximo")
	var big: PackedByteArray = PackedByteArray()
	big.resize(Protocol.MTU_PAYLOAD)
	ctx.check(Protocol.validate_snapshot_part(1, 1, 0, 1, big), "validate_snapshot_part: blob de exatamente %d B passa" % Protocol.MTU_PAYLOAD)
	big.resize(Protocol.MTU_PAYLOAD + 1)
	ctx.check(not Protocol.validate_snapshot_part(1, 1, 0, 1, big), "validate_snapshot_part: blob de %d B recusado" % (Protocol.MTU_PAYLOAD + 1))
	var bads: Array = [[-1, 0, 0, 1, blob], [1.0, 0, 0, 1, blob], [1, "0", 0, 1, blob], [1, 0, -1, 1, blob], [1, 0, 1, 1, blob],
		[1, 0, 0, 0, blob], [1, 0, 0, Protocol.MAX_SNAPSHOT_PARTS + 1, blob], [1, 0, 0, 1, PackedByteArray()], [1, 0, 0, 1, "abc"], [1, 0, 0, 1, [1, 2]]]
	for b: Array in bads:
		ctx.check(not Protocol.validate_snapshot_part(b[0], b[1], b[2], b[3], b[4]), "validate_snapshot_part recusa %s" % [b.slice(0, 4)])


func _test_netrpc_surface(ctx: Object) -> void:
	var n: NetRpc = NetRpc.new()
	ctx.check(n.has_method("c_caps") and n.has_method("s_snapshot_c") and n.has_method("send_caps") and n.has_method("send_snapshot_part"), "NetRpc: c_caps / s_snapshot_c / send_caps / send_snapshot_part")
	ctx.check(n.has_signal("caps_received") and n.has_signal("snapshot_part_received"), "NetRpc: sinais caps_received / snapshot_part_received")
	ctx.check(n.has_method("s_snapshot") and n.has_method("send_snapshot") and n.has_signal("snapshot_received"), "NetRpc: o s_snapshot legado continua existindo")
	var cfg: Dictionary = (n.get_script() as GDScript).get_rpc_config()
	ctx.check(cfg.has("s_snapshot_c") and int(cfg["s_snapshot_c"]["transfer_mode"]) == MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED, "NetRpc: s_snapshot_c e unreliable_ordered")
	ctx.check(cfg.has("s_snapshot_c") and int(cfg["s_snapshot_c"]["rpc_mode"]) == MultiplayerAPI.RPC_MODE_AUTHORITY, "NetRpc: s_snapshot_c so do servidor (authority)")
	ctx.check(cfg.has("c_caps") and int(cfg["c_caps"]["transfer_mode"]) == MultiplayerPeer.TRANSFER_MODE_RELIABLE and int(cfg["c_caps"]["rpc_mode"]) == MultiplayerAPI.RPC_MODE_ANY_PEER, "NetRpc: c_caps e reliable/any_peer")
	n.free()
	var tp: ServerTransport = ServerTransport.new()
	tp.send_snapshot_part(1, 1, 1, 0, 1, PackedByteArray())
	ctx.check(true, "ServerTransport.send_snapshot_part existe (no-op na base)")


# ---------------------------------------------------------------- servidor

func _arena(tree: SceneTree, n_players: int, n_enemies: int) -> H.Rig:
	var rig: H.Rig = H.make_rig(tree, false, 4, false, "")
	for i: int in n_players:
		H.join(rig, 10 + i, "Hero%d" % i)
	for i: int in n_enemies:
		var scene: String = BOSS if i == 0 else GRUNT
		rig.world.spawn_enemy(scene, Vector3(-20.0 + float(i % 9) * 5.0, 0.05, 10.0 + float(i / 9) * 5.0))
	return rig


func _last_legacy(rig: H.Rig, peer: int) -> Array:
	for k: int in range(rig.transport.snapshots.size() - 1, -1, -1):
		if int(rig.transport.snapshots[k]["peer"]) == peer:
			return rig.transport.snapshots[k]["entities"]
	return []


## Mescla as partes do ULTIMO tick enviado ao peer com um SnapshotAssembler (devolve a entrega ou {}).
func _last_compact(rig: H.Rig, peer: int) -> Dictionary:
	var tick: int = -1
	for m: Dictionary in rig.transport.snapshot_parts:
		if int(m["peer"]) == peer:
			tick = maxi(tick, int(m["tick"]))
	var a: SnapshotAssembler = SnapshotAssembler.new()
	var out: Dictionary = {}
	for m: Dictionary in rig.transport.snapshot_parts:
		if int(m["peer"]) == peer and int(m["tick"]) == tick:
			var r: Dictionary = a.push(m["tick"], m["last_seq"], m["part"], m["parts"], m["blob"])
			if bool(r["complete"]):
				out = r
	return out


func _same_as_legacy(legacy: Array, got: Array) -> String:
	if legacy.size() != got.size():
		return "tamanhos %d != %d" % [legacy.size(), got.size()]
	var gm: Dictionary = S.by_id(got)
	for e: Dictionary in legacy:
		if not gm.has(int(e["id"])):
			return "falta id %d" % int(e["id"])
		var d: String = S.diff(e, gm[int(e["id"])])
		if not d.is_empty():
			return "id %d: %s" % [int(e["id"]), d]
	return ""


func _test_caps_handling(ctx: Object, tree: SceneTree) -> void:
	var rig: H.Rig = H.make_rig(tree, false, 4, false, "")
	# antes do welcome: rejeitado como os outros comandos
	rig.session.on_peer_connected(7)
	rig.session.on_caps(7, Protocol.CAP_SNAPSHOT_COMPACT)
	ctx.check(rig.transport.reject_codes(7) == [Protocol.REJECT_NOT_AUTHENTICATED] and rig.transport.disconnects.has(7), "caps antes do welcome: reject(5) e desconexao")
	var eid: int = H.join(rig, 8, "Ana")
	var st: ServerSession.PeerState = rig.session.get_peer_state(8)
	ctx.check(eid > 0 and st.caps == 0, "peer novo comeca sem capacidades (formato legado)")
	rig.session.on_caps(8, 0xFF)
	ctx.check(st.caps == Protocol.CAP_SNAPSHOT_COMPACT, "caps: bits desconhecidos mascarados")
	rig.session.test_now_msec += 5000
	rig.session.on_caps(8, 0)
	ctx.check(st.caps == 0, "caps: o cliente pode voltar ao formato legado")
	# payload invalido: descartado e contado, sem mudar o estado
	rig.session.test_now_msec += 5000
	for bad: Variant in ["x", -3, 1.5, 70000, null]:
		rig.session.test_now_msec += 2000
		rig.session.on_caps(8, bad)
	ctx.check(st.dropped_invalid == 5 and st.caps == 0, "caps invalido: 5 descartes contados (%d), estado intacto" % st.dropped_invalid)
	# rate limit (burst 3)
	rig.session.test_now_msec += 20000
	for i: int in 8:
		rig.session.on_caps(8, 1)
	ctx.check(st.dropped_rate >= 4, "caps: rate limit descarta o excesso (%d)" % st.dropped_rate)
	# reincidencia => desconecta
	var rig2: H.Rig = H.make_rig(tree, false, 4, false, "")
	H.join(rig2, 9, "Bob")
	for i: int in rig2.settings.max_invalid_inputs + 5:
		rig2.session.on_caps(9, "lixo")
	ctx.check(rig2.transport.reject_codes(9).has(Protocol.REJECT_RATE_LIMIT), "caps invalido em excesso => reject(4)")
	rig.free_all()
	rig2.free_all()


func _test_negotiation_and_legacy(ctx: Object, tree: SceneTree) -> void:
	var rig: _Rig = _Rig.new(_arena(tree, 2, 8))
	var r: H.Rig = rig.rig
	# sem capacidade: s_snapshot legado, nenhuma parte
	r.session.send_snapshots()
	ctx.check(r.transport.snapshots.size() == 2 and r.transport.snapshot_parts.is_empty(), "legado: peers sem c_caps recebem s_snapshot (formato antigo) e nenhuma parte")
	var legacy0: Array = _last_legacy(r, 10)
	ctx.check(legacy0.size() == 10 and Protocol.validate_entity_dict(legacy0[0]), "legado: 10 entidades no formato Dictionary (2 jogadores + 8 inimigos)")
	# so o peer 10 declara a capacidade: negociacao por peer
	r.session.on_caps(10, Protocol.CAP_SNAPSHOT_COMPACT)
	r.transport.snapshots.clear()
	r.session.send_snapshots()
	ctx.check(r.transport.snapshots.size() == 1 and int(r.transport.snapshots[0]["peer"]) == 11, "negociacao: peer 11 (sem caps) segue no legado")
	ctx.check(not r.transport.snapshot_parts.is_empty() and r.transport.snapshot_parts.all(func(m: Dictionary) -> bool: return int(m["peer"]) == 10), "negociacao: peer 10 recebe so partes compactas")
	var got: Dictionary = _last_compact(r, 10)
	ctx.check(not got.is_empty(), "compacto: o snapshot do peer 10 monta")
	var why: String = _same_as_legacy(legacy0, got["entities"])
	ctx.check(why.is_empty(), "compacto == legado (mesmas entidades, dentro da quantizacao)" + ("" if why.is_empty() else ": " + why))
	var boss_ok: bool = false
	for e: Dictionary in got["entities"]:
		if e["type"] == "blight_treant":
			boss_ok = e.has("phase") and e.has("atk")
	ctx.check(boss_ok, "compacto: o chefe chega com phase e atk (BossBar)")
	# kill-switch do servidor
	r.settings.compact_snapshots = false
	r.transport.snapshots.clear()
	r.transport.snapshot_parts.clear()
	r.session.send_snapshots()
	ctx.check(r.transport.snapshots.size() == 2 and r.transport.snapshot_parts.is_empty(), "kill-switch: compact_snapshots=false forca o legado mesmo com caps")
	r.settings.compact_snapshots = true
	# tick e last_seq iguais em todas as partes; o last_input_seq do peer vai junto
	r.session.on_input(10, 41, Vector2(0, -1), 0.0, 0)
	r.transport.snapshot_parts.clear()
	r.session.send_snapshots()
	var all_seq: bool = true
	for m: Dictionary in r.transport.snapshot_parts:
		all_seq = all_seq and int(m["last_seq"]) == 41 and int(m["tick"]) == r.world.server_tick
	ctx.check(not r.transport.snapshot_parts.is_empty() and all_seq, "compacto: partes levam o tick do servidor e o last_input_seq do proprio peer (41)")
	r.free_all()


class _Rig extends RefCounted:
	var rig: H.Rig

	func _init(r: H.Rig) -> void:
		rig = r


func _stats_blank() -> Dictionary:
	return {"samples": 0, "max_bytes": 0, "max_entities": 0, "over_mtu": 0, "sum_bytes": 0, "snapshots": 0, "compact_snapshots": 0, "max_parts": 0, "encode_skipped": 0}


func _test_thirty_entities(ctx: Object, tree: SceneTree) -> void:
	var r: H.Rig = _arena(tree, 4, 30)  # 34 entidades, arena (sem AOI): pior caso de entidades por peer
	r.settings.measure_snapshots = true
	r.session.snapshot_stats = _stats_blank()
	r.session.send_snapshots()
	var legacy: Dictionary = r.session.snapshot_stats.duplicate()
	ctx.check(int(legacy["max_entities"]) == 34 and int(legacy["max_bytes"]) > Protocol.MTU_PAYLOAD and int(legacy["over_mtu"]) == 4, "ANTES (legado, 34 entidades): %d B/mensagem, %d de 4 acima do MTU" % [int(legacy["max_bytes"]), int(legacy["over_mtu"])])
	for i: int in 4:
		r.session.on_caps(10 + i, Protocol.CAP_SNAPSHOT_COMPACT)
	r.transport.snapshots.clear()
	r.session.snapshot_stats = _stats_blank()
	r.session.send_snapshots()
	var st: Dictionary = r.session.snapshot_stats
	ctx.check(int(st["max_entities"]) == 34 and int(st["compact_snapshots"]) == 4, "DEPOIS (compacto): 4 snapshots de 34 entidades")
	ctx.check(int(st["max_bytes"]) <= Protocol.MTU_PAYLOAD and int(st["over_mtu"]) == 0, "DEPOIS: maior mensagem %d B <= %d, 0 acima do MTU (%d partes no maximo)" % [int(st["max_bytes"]), Protocol.MTU_PAYLOAD, int(st["max_parts"])])
	ctx.check(int(st["max_bytes"]) * 5 < int(legacy["max_bytes"]), "DEPOIS: reducao > 5x (%d -> %d B)" % [int(legacy["max_bytes"]), int(st["max_bytes"])])
	var worst: int = 0
	for m: Dictionary in r.transport.snapshot_parts:
		worst = maxi(worst, S.msg_bytes(int(m["tick"]), int(m["last_seq"]), int(m["part"]), int(m["parts"]), m["blob"]))
	ctx.check(worst <= Protocol.MTU_PAYLOAD and worst == int(st["max_bytes"]), "medicao do servidor == tamanho recalculado das mensagens (%d B)" % worst)
	r.free_all()


func _test_partitioned_server(ctx: Object, tree: SceneTree) -> void:
	var r: H.Rig = _arena(tree, 2, 20)
	r.session.send_snapshots()
	var legacy: Array = _last_legacy(r, 10)
	r.session.on_caps(10, Protocol.CAP_SNAPSHOT_COMPACT)
	r.settings.snapshot_part_bytes = 150  # forca varias partes por snapshot
	r.transport.snapshot_parts.clear()
	r.session.send_snapshots()
	var n_parts: int = 0
	var sizes_ok: bool = true
	for m: Dictionary in r.transport.snapshot_parts:
		if int(m["peer"]) == 10:
			n_parts = maxi(n_parts, int(m["parts"]))
			sizes_ok = sizes_ok and (m["blob"] as PackedByteArray).size() <= 150
	ctx.check(n_parts >= 3 and sizes_ok, "particionado: 22 entidades com orcamento de 150 B => %d partes, todas <= 150 B" % n_parts)
	var got: Dictionary = _last_compact(r, 10)
	ctx.check(not got.is_empty() and _same_as_legacy(legacy, got["entities"]).is_empty(), "particionado: a mescla das partes == snapshot legado")
	r.free_all()


func _test_world_interest(ctx: Object, tree: SceneTree) -> void:
	# modo mundo: interesse por zona/AOI e pickups SO do dono continuam por peer no formato compacto
	var rig: B.BRig = L.make(tree, 2, "greenwood", true)
	var e0: int = L.eid(rig, 0)
	var e1: int = L.eid(rig, 1)
	var p0: Vector3 = L.node(rig, 0).global_position
	var p1: Vector3 = L.node(rig, 1).global_position
	rig.world.spawn_enemy(L.GRUNT, L.STATION_POS + Vector3(2.0, 0.0, 2.0))
	rig.world.spawn_enemy(L.GRUNT, L.STATION_POS + Vector3(-3.0, 0.0, 1.0))
	rig.world.spawn_enemy(L.GRUNT, Vector3(400.0, 0.05, 400.0))  # longe: fora do AOI e/ou de outra zona
	rig.world.loot.spawn_for(e0, [LootDrop.make(&"amulet_vigor", 1)] as Array[LootDrop], p0, rig.world.zone_of_player(e0))
	rig.world.loot.spawn_for(e1, [LootDrop.make(&"potion_minor", 3)] as Array[LootDrop], p1, rig.world.zone_of_player(e1))
	L.send_snapshots(rig)
	var legacy: Array[Array] = [[], []]
	for i: int in 2:
		for k: int in range(rig.transport.snapshots.size() - 1, -1, -1):
			if int(rig.transport.snapshots[k]["peer"]) == L.PEER0 + i:
				legacy[i] = rig.transport.snapshots[k]["entities"]
				break
	ctx.check(legacy[0].size() >= 4 and legacy[1].size() >= 4, "mundo: base legada com jogadores, inimigos e pickups (%d / %d)" % [legacy[0].size(), legacy[1].size()])
	for i: int in 2:
		rig.session.on_caps(L.PEER0 + i, Protocol.CAP_SNAPSHOT_COMPACT)
	rig.transport.snapshots.clear()
	rig.session.send_snapshots()
	ctx.check(rig.transport.snapshots.is_empty() and not rig.transport.snapshot_parts.is_empty(), "mundo: com caps o servidor so envia partes")
	for i: int in 2:
		var got: Dictionary = _last_compact_for(rig, L.PEER0 + i)
		ctx.check(not got.is_empty(), "mundo: snapshot compacto do peer %d monta" % i)
		var why: String = _same_as_legacy(legacy[i], got.get("entities", []))
		ctx.check(why.is_empty(), "mundo: peer %d recebe exatamente o mesmo interesse do legado%s" % [i, "" if why.is_empty() else " (" + why + ")"])
		var pick_ids: Array = []
		for e: Dictionary in got.get("entities", []):
			if int(e["kind"]) == Protocol.KIND_PICKUP:
				pick_ids.append(int(e["id"]))
		var mine: Array = []
		for pk: LootManager.LootPickup in rig.world.loot.pickups_of(L.eid(rig, i)):
			mine.append(pk.id)
		var others: Array = []
		for pk: LootManager.LootPickup in rig.world.loot.pickups_of(L.eid(rig, 1 - i)):
			others.append(pk.id)
		pick_ids.sort()
		mine.sort()
		var leak: bool = false
		for o: Variant in others:
			leak = leak or pick_ids.has(o)
		ctx.check(pick_ids == mine and not mine.is_empty() and not leak, "mundo: peer %d recebe SO os proprios pickups (%s) e nenhum alheio" % [i, pick_ids])
	rig.free_all()


func _last_compact_for(rig: B.BRig, peer: int) -> Dictionary:
	var tick: int = -1
	for m: Dictionary in rig.transport.snapshot_parts:
		if int(m["peer"]) == peer:
			tick = maxi(tick, int(m["tick"]))
	var a: SnapshotAssembler = SnapshotAssembler.new()
	var out: Dictionary = {}
	for m: Dictionary in rig.transport.snapshot_parts:
		if int(m["peer"]) == peer and int(m["tick"]) == tick:
			var r: Dictionary = a.push(m["tick"], m["last_seq"], m["part"], m["parts"], m["blob"])
			if bool(r["complete"]):
				out = r
	return out


# ---------------------------------------------------------------- cliente

func _playing_session(caps_log: Array) -> ClientSession:
	var ss: ClientSession = ClientSession.new()
	ss.send_caps = func(c: int) -> void: caps_log.append(c)
	ss.begin(Protocol.VERSION, "test", "Ana")
	ss.on_welcome(5, 30, 1)
	return ss


func _test_client_session(ctx: Object) -> void:
	var caps_log: Array = []
	var ss: ClientSession = _playing_session(caps_log)
	ctx.check(caps_log == [Protocol.CAP_SNAPSHOT_COMPACT], "cliente: declara a capacidade de snapshot compacto ao receber o welcome")
	var local_pos: Vector3 = Vector3(12.3456, 0.05, -7.891)
	var ents: Array = [S.player(5, local_pos, 73.0, 100.0, 0.5), S.player(6, Vector3(1, 0, 1), 100.0, 100.0)]
	ents.append(S.enemy(40, Vector3(5, 0, 5), 2500.0, 4200.0, "blight_treant", 2, "slam"))
	for i: int in 30:
		ents.append(S.enemy(100 + i, Vector3(float(i), 0.0, 3.0), 40.0, 40.0))
	var enc: Dictionary = SnapshotCodec.encode(ents, 250)
	var parts: Array = enc["parts"]
	ctx.check(parts.size() >= 3, "cliente: snapshot de 33 entidades em %d partes" % parts.size())
	for i: int in parts.size():
		ss.on_snapshot_part(100, 9, i, parts.size(), parts[i], 1000.0)
		if i < parts.size() - 1:
			ctx.check(ss.entity_count == 0 and ss.compact_snapshots == 0, "cliente: parte %d/%d nao entrega snapshot pela metade" % [i + 1, parts.size()])
	ctx.check(ss.entity_count == 33 and ss.compact_snapshots == 1 and ss.result.compact_snapshots == 1, "cliente: ao completar entrega 33 entidades (1 snapshot compacto)")
	ctx.check(ss.last_input_seq_ack == 9 and ss.interpolator.accepted == 1, "cliente: last_input_seq e interpolador alimentados")
	ctx.check(not ss.local_entity.is_empty() and (ss.local_entity["pos"] as Vector3).distance_to(local_pos) <= 0.0088, "cliente: entidade local com erro de posicao <= 1 cm")
	ctx.check(ss.prediction.initialized and ss.prediction.pos.distance_to(local_pos) <= 0.0088, "cliente: predicao inicializada na posicao do servidor (erro <= 1 cm)")
	ctx.check(float(ss.local_entity["hp"]) == 73.0 and float(ss.local_entity["max_hp"]) == 100.0, "cliente: hp/max_hp inteiros para a UI de grupo")
	var view: Dictionary = ss.interpolator.sample(1100.0)
	ctx.check(view.has(40) and int(view[40]["phase"]) == 2 and view[40]["atk"] == "slam" and view[40]["type"] == "blight_treant", "cliente: interpolador expoe phase/atk/type do chefe (BossBar)")
	# partes lixo e velhas nao mexem no estado
	var before: int = ss.snapshot_assembler.parts_malformed
	ss.on_snapshot_part(101, 9, 0, 1, PackedByteArray([9, 9, 9, 9]), 1033.0)
	ss.on_snapshot_part(101, 9, 5, 2, parts[0], 1033.0)
	ctx.check(ss.snapshot_assembler.parts_malformed == before + 2 and ss.entity_count == 33 and ss.compact_snapshots == 1, "cliente: partes malformadas descartadas e contadas, estado intacto")
	ss.on_snapshot_part(100, 9, 0, parts.size(), parts[0], 1066.0)
	ctx.check(ss.snapshot_assembler.parts_stale == 1 and ss.compact_snapshots == 1, "cliente: reenvio do tick ja entregue e ignorado")
	# legado e compacto coexistem (troca de formato no meio da sessao): ticks continuam monotonicos
	ss.on_snapshot(101, 10, [S.player(5, local_pos)], 1100.0)
	ctx.check(ss.last_input_seq_ack == 10 and ss.interpolator.accepted == 2, "cliente: s_snapshot legado ainda funciona na mesma sessao")
	ss.on_snapshot_part(101, 9, 0, 1, (SnapshotCodec.encode([S.player(5, local_pos)])["parts"] as Array)[0], 1133.0)
	ctx.check(ss.snapshot_assembler.parts_stale == 1 and ss.interpolator.accepted == 2, "cliente: parte compacta de tick ja coberto pelo legado nao regride o estado")
	# fora de PLAYING: ignora
	var idle: ClientSession = ClientSession.new()
	idle.on_snapshot_part(1, 0, 0, 1, parts[0], 0.0)
	ctx.check(idle.entity_count == 0 and idle.snapshot_assembler.parts_accepted == 0 and idle.snapshot_assembler.parts_malformed == 0, "cliente: parte antes do welcome e ignorada")
	# sem send_caps injetado (bots antigos): nao quebra
	var legacy_only: ClientSession = ClientSession.new()
	legacy_only.begin(Protocol.VERSION, "test", "Bob")
	legacy_only.on_welcome(7, 30, 1)
	ctx.check(legacy_only.state == ClientSession.State.PLAYING, "cliente sem send_caps (build antigo) entra normalmente")


func _test_prediction_noise(ctx: Object) -> void:
	# a quantizacao (<= 0,87 cm) fica abaixo da zona morta da reconciliacao (5 cm): nenhuma correcao espuria
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 5
	var pr: Prediction = Prediction.new()
	var server: Vector3 = Vector3(10.1234, 0.05, -20.5678)
	pr.init_at(server)
	var seq: int = 0
	var spurious: bool = false
	for step: int in 200:
		for k: int in 2:
			seq += 1
			pr.apply_input(seq, Vector2(0.0, -1.0), 0.3, 1.0 / 60.0)
			server += PlayerMotion.world_direction(Vector2(0.0, -1.0), 0.3) * Prediction.BASE_SPEED * (1.0 / 60.0)
		var q: Dictionary = S.roundtrip([S.player(1, server, 100.0, 100.0)])
		var sp: Vector3 = q[1]["pos"]
		pr.reconcile(sp, seq)
		if pr.smooth_corrections > 0 or pr.snaps > 0:
			spurious = true
		pr.update(1.0 / 30.0)
	ctx.check(not spurious, "predicao: 200 reconciliacoes com posicao quantizada nao geram correcao suave nem snap")
	ctx.check(pr.pos.distance_to(server) <= 0.0088 + 0.0001, "predicao: apos 200 passos o erro continua <= 1 cm (%.4f m)" % pr.pos.distance_to(server))


# ---------------------------------------------------------------- RPC real

func _on(key: String, args: Array) -> void:
	if not _got.has(key):
		_got[key] = []
	(_got[key] as Array).append(args)


func _wait_n(tree: SceneTree, key: String, n: int, timeout_msec: int) -> bool:
	var t0: int = Time.get_ticks_msec()
	while (not _got.has(key) or (_got[key] as Array).size() < n) and Time.get_ticks_msec() - t0 < timeout_msec:
		await tree.process_frame
	return _got.has(key) and (_got[key] as Array).size() >= n


func _test_loopback(ctx: Object, tree: SceneTree) -> void:
	var srv_root: Node = Node.new()
	srv_root.name = "SrvRootSnap"
	var cli_root: Node = Node.new()
	cli_root.name = "CliRootSnap"
	tree.root.add_child(srv_root)
	tree.root.add_child(cli_root)
	var srv: NetRpc = NetRpc.new()
	srv.name = "NetRpc"
	var cli: NetRpc = NetRpc.new()
	cli.name = "NetRpc"
	srv_root.add_child(srv)
	cli_root.add_child(cli)
	var sapi: SceneMultiplayer = SceneMultiplayer.new()
	var capi: SceneMultiplayer = SceneMultiplayer.new()
	tree.set_multiplayer(sapi, srv_root.get_path())
	tree.set_multiplayer(capi, cli_root.get_path())
	var sp: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var cp: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	if sp.create_server(TEST_PORT, 2) != OK:
		ctx.check(false, "loopback: create_server falhou")
		_cleanup(tree, srv_root, cli_root)
		return
	cp.create_client("127.0.0.1", TEST_PORT)
	sapi.multiplayer_peer = sp
	capi.multiplayer_peer = cp
	srv.caps_received.connect(func(p: int, c: int) -> void: _on("caps", [p, c]))
	cli.snapshot_part_received.connect(func(t: int, ls: int, pt: int, pts: int, b: PackedByteArray) -> void: _on("part", [t, ls, pt, pts, b]))
	var t0: int = Time.get_ticks_msec()
	while cp.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED and Time.get_ticks_msec() - t0 < 5000:
		await tree.process_frame
	var connected: bool = cp.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED
	ctx.check(connected, "loopback: cliente conectou")
	if connected:
		var cid: int = capi.get_unique_id()
		cli.send_caps(Protocol.CAP_SNAPSHOT_COMPACT)
		ctx.check(await _wait_n(tree, "caps", 1, 3000) and _got["caps"][0] == [cid, 1], "loopback: c_caps chegou com o remetente correto")
		# mensagens invalidas do servidor sao descartadas no RPC do cliente; a valida chega
		var big: PackedByteArray = PackedByteArray()
		big.resize(Protocol.MTU_PAYLOAD + 1)
		srv.send_snapshot_part(cid, 5, 0, 3, 2, PackedByteArray([1, 2, 3]))      # part >= parts
		srv.send_snapshot_part(cid, 6, 0, 0, 1, big)                              # acima do MTU
		var ents: Array = S.crowd(30, 2)
		var blobs: Array = SnapshotCodec.encode(ents)["parts"]
		srv.send_snapshot_part(cid, 7, 123, 0, blobs.size(), blobs[0])
		ctx.check(await _wait_n(tree, "part", 1, 3000), "loopback: s_snapshot_c valido chegou")
		var parts_in: Array = _got.get("part", [])
		ctx.check(parts_in.size() == 1 and parts_in[0][0] == 7 and parts_in[0][1] == 123 and parts_in[0][2] == 0 and parts_in[0][3] == blobs.size(), "loopback: so a parte valida passou (as 2 invalidas foram descartadas no RPC)")
		ctx.check(parts_in[0][4] == blobs[0], "loopback: blob integro (%d B)" % (blobs[0] as PackedByteArray).size())
		var dec: Dictionary = SnapshotCodec.decode_part(parts_in[0][4])
		ctx.check(bool(dec["ok"]) and (dec["entities"] as Array).size() == 30, "loopback: blob recebido decodifica (30 entidades)")
	_cleanup(tree, srv_root, cli_root)


func _cleanup(tree: SceneTree, srv_root: Node, cli_root: Node) -> void:
	for r: Node in [srv_root, cli_root]:
		var api: MultiplayerAPI = tree.get_multiplayer(r.get_path())
		if api.multiplayer_peer != null:
			api.multiplayer_peer.close()
			api.multiplayer_peer = null
		tree.set_multiplayer(MultiplayerAPI.create_default_interface(), r.get_path())
		tree.root.remove_child(r)
		r.free()
