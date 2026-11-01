extends RefCounted
## E5.7 - SnapshotCodec: round-trip, limites de quantizacao, entidades invalidas, blobs truncados/corrompidos,
## particionamento e tamanho maximo (30 entidades).

const S = preload("res://tests/e5_snapshot/snapshot_helpers.gd")


func run(ctx: Object) -> void:
	var tree: SceneTree = ctx as SceneTree
	await tree.physics_frame
	_test_roundtrip(ctx)
	_test_quantization_limits(ctx)
	_test_hp_rules(ctx)
	_test_wide_positions(ctx)
	_test_invalid_entities(ctx)
	_test_strict_decode(ctx)
	_test_fuzz(ctx)
	_test_partitioning(ctx)
	_test_max_size(ctx)
	await tree.physics_frame


func _test_roundtrip(ctx: Object) -> void:
	var ents: Array = [
		S.player(1, Vector3(1.234, 0.05, -9.876), 87.4, 120.0, 1.1),
		S.player(2, Vector3(0.0, 0.0, 0.0), 120.0, 120.0, 0.0),
		S.enemy(40, Vector3(33.33, 0.0, 12.0), 60.0, 60.0, "melee_grunt", 0, "", 1),
		S.enemy(41, Vector3(-3.0, 0.2, 4.0), 12.5, 80.0, "bow_scout", 0, "shoot", 2),
		S.enemy(42, Vector3(10.0, 0.0, 10.0), 2999.0, 4200.0, "blight_treant", 3, "slam", 2),
		S.enemy(43, Vector3(10.0, 0.0, -10.0), 0.0, 40.0, "root_sprout", 0, "", 4),
		S.pickup(500, Vector3(2.0, 0.1, 2.0), "scrap_material", 3),
	]
	var enc: Dictionary = SnapshotCodec.encode(ents)
	ctx.check((enc["parts"] as Array).size() == 1 and int(enc["skipped"]) == 0 and int(enc["encoded"]) == ents.size(), "codec: 7 entidades -> 1 parte, nenhuma pulada")
	var got: Dictionary = S.roundtrip(ents)
	ctx.check(got.size() == ents.size(), "codec: round-trip devolve as 7 entidades")
	for e: Dictionary in ents:
		var g: Variant = got.get(int(e["id"]))
		ctx.check(g != null and S.diff(e, g) == "", "codec: entidade %d identica (dentro da quantizacao) %s" % [int(e["id"]), "" if g == null else S.diff(e, g)])
	# formato das entidades decodificadas passa no validador do protocolo (o cliente ainda valida cada uma)
	var all_valid: bool = true
	for g2: Variant in got.values():
		all_valid = all_valid and Protocol.validate_entity_dict(g2)
	ctx.check(all_valid, "codec: toda entidade decodificada passa em Protocol.validate_entity_dict")
	var g_boss: Dictionary = got[42]
	ctx.check(int(g_boss["phase"]) == 3 and g_boss["atk"] == "slam", "codec: phase e atk do chefe preservados (BossBar)")
	ctx.check(got[40].has("phase") and got[40]["atk"] == "" and int(got[40]["phase"]) == 0, "codec: inimigo sem fase/ataque ainda traz phase=0 e atk=\"\" (presenca de phase mantida)")
	ctx.check(not got[1].has("phase") and not got[500].has("atk") and int(got[500]["qty"]) == 3, "codec: jogador sem phase/atk; pickup com qty")
	ctx.check(float(got[1]["hp"]) == 87.0 and float(got[1]["max_hp"]) == 120.0, "codec: hp 87.4 -> 87 (inteiro), max_hp 120")
	# lista vazia -> 1 parte vazia valida (o cliente precisa do tick/last_seq)
	var empty: Dictionary = SnapshotCodec.encode([])
	ctx.check((empty["parts"] as Array).size() == 1, "codec: lista vazia gera 1 parte")
	var dec: Dictionary = SnapshotCodec.decode_part((empty["parts"] as Array)[0])
	ctx.check(bool(dec["ok"]) and (dec["entities"] as Array).is_empty(), "codec: parte vazia decodifica para 0 entidades")


func _test_quantization_limits(ctx: Object) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 99
	var worst: float = 0.0
	var worst_yaw: float = 0.0
	var worst_eucl: float = 0.0
	var n_bad: int = 0
	for batch: int in 12:
		var ents: Array = []
		for i: int in 40:
			var p: Vector3 = Vector3(rng.randf_range(-300.0, 300.0), rng.randf_range(-5.0, 20.0), rng.randf_range(-300.0, 300.0))
			ents.append(S.player(i + 1, p, 50.0, 100.0, rng.randf_range(-PI, PI)))
		var got: Dictionary = S.roundtrip(ents)
		if got.size() != ents.size():
			n_bad += 1
			continue
		for e: Dictionary in ents:
			var g: Dictionary = got[int(e["id"])]
			var d: Vector3 = ((e["pos"] as Vector3) - (g["pos"] as Vector3)).abs()
			worst = maxf(worst, maxf(d.x, maxf(d.y, d.z)))
			worst_eucl = maxf(worst_eucl, ((e["pos"] as Vector3) - (g["pos"] as Vector3)).length())
			worst_yaw = maxf(worst_yaw, absf(angle_difference(float(e["yaw"]), float(g["yaw"]))))
	ctx.check(n_bad == 0, "quantizacao: 480 posicoes em +-300 m decodificam")
	ctx.check(worst <= 0.0051, "quantizacao: erro maximo por eixo %.5f m <= 0,5 cm (+ folga float32)" % worst)
	ctx.check(worst_eucl <= 0.0088, "quantizacao: erro euclidiano maximo %.5f m <= 0,87 cm (< 1 cm)" % worst_eucl)
	ctx.check(worst_yaw <= S.YAW_TOL, "quantizacao: erro maximo de yaw %.7f rad <= 4,8e-5" % worst_yaw)
	# yaw nas bordas e fora de [-PI, PI]
	for y: float in [0.0, PI, -PI, PI - 0.00001, 3.0 * PI, -7.5, 100.0]:
		var g2: Dictionary = S.roundtrip([S.player(1, Vector3.ZERO, 1.0, 1.0, y)])
		ctx.check(g2.size() == 1 and absf(angle_difference(y, float(g2[1]["yaw"]))) <= S.YAW_TOL, "quantizacao: yaw %.4f preservado modulo 2*PI" % y)
	# arredondamento ao cm mais proximo (nao trunca): 1.004 -> 1.00; 1.006 -> 1.01
	var g3: Dictionary = S.roundtrip([S.player(1, Vector3(1.004, 2.006, -1.006))])
	var p3: Vector3 = g3[1]["pos"]
	ctx.check(is_equal_approx(p3.x, 1.00) and is_equal_approx(p3.y, 2.01) and is_equal_approx(p3.z, -1.01), "quantizacao: arredonda ao cm mais proximo (%s)" % p3)


func _test_hp_rules(ctx: Object) -> void:
	var cases: Array = [[0.0, 0.0], [-5.0, 0.0], [0.2, 1.0], [0.49, 1.0], [1.0, 1.0], [99.6, 100.0], [1.0e12, float(SnapshotCodec.MAX_VARINT)]]
	for c: Array in cases:
		var g: Dictionary = S.roundtrip([S.enemy(1, Vector3.ZERO, float(c[0]), 1.0e12)])
		ctx.check(g.size() == 1 and float(g[1]["hp"]) == float(c[1]), "hp %s -> %s" % [c[0], c[1]])
	var g2: Dictionary = S.roundtrip([S.enemy(1, Vector3.ZERO, 0.3, 100.0)])
	ctx.check(float(g2[1]["hp"]) > 0.0, "hp > 0 nunca vira 0 (continua vivo na UI)")
	var g3: Dictionary = S.roundtrip([S.pickup(9, Vector3.ONE, "potion_minor", 999)])
	ctx.check(g3.size() == 1 and float(g3[9]["hp"]) == 0.0 and float(g3[9]["max_hp"]) == 0.0 and int(g3[9]["qty"]) == 999, "pickup: hp/max_hp 0 e qty 999")
	# hp cheio gasta menos que hp parcial
	var full: int = (SnapshotCodec.encode([S.enemy(1, Vector3.ZERO, 60.0, 60.0)])["parts"] as Array)[0].size()
	var part: int = (SnapshotCodec.encode([S.enemy(1, Vector3.ZERO, 59.0, 60.0)])["parts"] as Array)[0].size()
	ctx.check(part == full + 1, "hp cheio omite o campo hp (%d vs %d B)" % [full, part])


func _test_wide_positions(ctx: Object) -> void:
	# distancia > 327 m entre entidades da mesma parte: cai no modo largo (float32) sem perder precisao
	var ents: Array = [
		S.player(1, Vector3(0.0, 0.0, 0.0)),
		S.player(2, Vector3(1000.0, 5.0, -2500.123)),
		S.player(3, Vector3(-300.0, 0.0, 300.0)),
		S.player(4, Vector3(3.0e7, 0.0, 0.0)),
	]
	var g: Dictionary = S.roundtrip(ents)
	ctx.check(g.size() == 4, "larga: 4 entidades distantes decodificam")
	ctx.check(g[2]["pos"] == Vector3(1000.0, 5.0, -2500.123), "larga: posicao distante exata (float32)")
	ctx.check((g[3]["pos"] as Vector3).distance_to(Vector3(-300.0, 0.0, 300.0)) <= 0.0087, "larga: posicao dentro do alcance estreito segue quantizada")
	ctx.check(g[4]["pos"] == Vector3(3.0e7, 0.0, 0.0), "larga: |pos*100| > int32 cai no float32 exato")
	# primeira entidade muito longe da origem: base propria, as proximas continuam estreitas
	var near: Array = [S.player(1, Vector3(5000.0, 0.0, 5000.0)), S.player(2, Vector3(5001.5, 0.0, 4999.25))]
	var enc: Dictionary = SnapshotCodec.encode(near)
	var g2: Dictionary = S.roundtrip(near)
	ctx.check(g2.size() == 2 and (g2[2]["pos"] as Vector3).distance_to(Vector3(5001.5, 0.0, 4999.25)) <= 0.0087, "base: mundo longe da origem continua com erro <= 1 cm")
	var narrow_size: int = (enc["parts"] as Array)[0].size()
	var wide_enc: Dictionary = SnapshotCodec.encode([near[0], S.player(2, Vector3(9000.0, 0.0, 0.0))])
	ctx.check((wide_enc["parts"] as Array)[0].size() > narrow_size, "larga: o modo largo custa mais bytes (6 a mais/entidade)")


func _test_invalid_entities(ctx: Object) -> void:
	var good: Dictionary = S.player(1, Vector3(1, 2, 3))
	var bad: Array = [
		"nao dicionario", 7, null,
		{"id": 2, "kind": 1},
		S.ent(3, 9, Vector3.ZERO),
		S.ent(4, 1, Vector3(INF, 0, 0)),
		S.ent(5, 1, Vector3(0, NAN, 0)),
		S.ent(6, 1, Vector3.ZERO, NAN),
		S.ent(7, 1, Vector3.ZERO, 1.0, INF),
		S.ent(8, 1, Vector3.ZERO, 1.0, 1.0, "player", NAN),
		S.ent(9, 1, Vector3.ZERO, 1.0, 1.0, "player", 0.0, 256),
		S.ent(10, 1, Vector3.ZERO, 1.0, 1.0, "player", 0.0, -1),
		S.ent(-1, 1, Vector3.ZERO),
		S.ent(SnapshotCodec.MAX_VARINT + 1, 1, Vector3.ZERO),
		S.ent(12, 1, Vector3.ZERO, 1.0, 1.0, "tipo com espaco"),
		S.ent(13, 1, Vector3.ZERO, 1.0, 1.0, "acaoção"),
		S.ent(14, 1, Vector3.ZERO, 1.0, 1.0, "x".repeat(33)),
		S.ent(15, 2, Vector3.ZERO, 1.0, 1.0, "melee_grunt", 0.0, 1, {"phase": 16}),
		S.ent(16, 2, Vector3.ZERO, 1.0, 1.0, "melee_grunt", 0.0, 1, {"phase": "2"}),
		S.ent(17, 2, Vector3.ZERO, 1.0, 1.0, "melee_grunt", 0.0, 1, {"atk": "a b"}),
		S.ent(18, 3, Vector3.ZERO, 0.0, 0.0, "potion_minor"),
		S.ent(19, 3, Vector3.ZERO, 0.0, 0.0, "potion_minor", 0.0, 0, {"qty": 0}),
		S.ent(20, 3, Vector3.ZERO, 0.0, 0.0, "potion_minor", 0.0, 0, {"qty": 1000}),
		{"id": 21, "kind": 1, "pos": "nao vetor", "yaw": 0.0, "hp": 1.0, "max_hp": 1.0, "state": 0, "type": "player"},
		{"id": 22.0, "kind": 1, "pos": Vector3.ZERO, "yaw": 0.0, "hp": 1.0, "max_hp": 1.0, "state": 0, "type": "player"},
	]
	var all: Array = [good]
	all.append_array(bad)
	all.append(S.player(99, Vector3(4, 5, 6)))
	var enc: Dictionary = SnapshotCodec.encode(all)
	ctx.check(int(enc["skipped"]) == bad.size() and int(enc["encoded"]) == 2, "invalidas: %d entidades invalidas puladas e contadas; as 2 validas seguem" % bad.size())
	var g: Dictionary = S.roundtrip(all)
	ctx.check(g.size() == 2 and g.has(1) and g.has(99), "invalidas: so as validas chegam ao decodificador")
	# tamanho de tipo no limite (32 chars) e passa
	var g2: Dictionary = S.roundtrip([S.ent(1, 1, Vector3.ZERO, 1.0, 1.0, "x".repeat(32))])
	ctx.check(g2.size() == 1 and (g2[1]["type"] as String).length() == 32, "tipo com 32 chars passa")


func _blob(entities: Array) -> PackedByteArray:
	return (SnapshotCodec.encode(entities)["parts"] as Array)[0]


## Parte montada a mao (para testar o decodificador contra bytes que o codificador nunca produz).
func _manual(strings: Array, ents: Array, fmt: int = 1, count_override: int = -1) -> PackedByteArray:
	var sp: StreamPeerBuffer = StreamPeerBuffer.new()
	sp.put_u8(fmt)
	sp.put_u8(strings.size())
	for s: String in strings:
		sp.put_u8(s.length())
		sp.put_data(s.to_ascii_buffer())
	sp.put_32(0)
	sp.put_32(0)
	sp.put_32(0)
	sp.put_u8(ents.size() if count_override < 0 else count_override)
	for e: Variant in ents:
		sp.put_data(e)
	return sp.data_array


## Entidade minima manual: flags, id (1 byte), idx_type, state, pos(0,0,0) estreito, yaw, max_hp.
func _min_ent(flags: int, id: int, type_idx: int = 0) -> PackedByteArray:
	var sp: StreamPeerBuffer = StreamPeerBuffer.new()
	sp.put_u8(flags)
	sp.put_u8(id)
	sp.put_u8(type_idx)
	sp.put_u8(0)
	sp.put_16(0)
	sp.put_16(0)
	sp.put_16(0)
	sp.put_u16(0)
	sp.put_u8(5)
	return sp.data_array


func _test_strict_decode(ctx: Object) -> void:
	var blob: PackedByteArray = _blob(S.crowd(12))
	var d0: Dictionary = SnapshotCodec.decode_part(blob)
	ctx.check(bool(d0["ok"]) and (d0["entities"] as Array).size() == 12, "estrito: base de 12 entidades decodifica")
	# qualquer prefixo proprio (truncado) e recusado
	var all_trunc_bad: bool = true
	for n: int in blob.size():
		if bool(SnapshotCodec.decode_part(blob.slice(0, n))["ok"]):
			all_trunc_bad = false
	ctx.check(all_trunc_bad, "estrito: todos os %d prefixos truncados sao recusados" % blob.size())
	var extra: PackedByteArray = blob.duplicate()
	extra.append(0)
	ctx.check(not bool(SnapshotCodec.decode_part(extra)["ok"]), "estrito: byte sobrando no fim e recusado")
	ctx.check(not bool(SnapshotCodec.decode_part(PackedByteArray())["ok"]), "estrito: blob vazio recusado")
	var wrong_fmt: PackedByteArray = blob.duplicate()
	wrong_fmt[0] = 2
	ctx.check(not bool(SnapshotCodec.decode_part(wrong_fmt)["ok"]), "estrito: formato desconhecido recusado")
	# manual: valido x variantes invalidas
	var ok_blob: PackedByteArray = _manual(["player"], [_min_ent(1 | 16, 1), _min_ent(1 | 16, 2)])
	var d1: Dictionary = SnapshotCodec.decode_part(ok_blob)
	ctx.check(bool(d1["ok"]) and (d1["entities"] as Array).size() == 2, "manual: parte montada a mao e valida")
	var bads: Array = [
		["id repetido", _manual(["player"], [_min_ent(1 | 16, 7), _min_ent(1 | 16, 7)])],
		["kind 0", _manual(["player"], [_min_ent(0 | 16, 1)])],
		["flag reservada", _manual(["player"], [_min_ent(1 | 16 | 32, 1)])],
		["indice de tipo fora da tabela", _manual(["player"], [_min_ent(1 | 16, 1, 1)])],
		["contagem maior que os dados", _manual(["player"], [_min_ent(1 | 16, 1)], 1, 40)],
		["extras em jogador", _manual(["player"], [_min_ent(1 | 4 | 16, 1)])],
		["pickup sem qty valida", _manual(["potion_minor"], [_min_ent(3 | 16, 1)])],
		["string da tabela com espaco", _manual(["a b"], [_min_ent(1 | 16, 1)])],
		["string da tabela longa", _manual(["x".repeat(33)], [_min_ent(1 | 16, 1)])],
	]
	for b: Array in bads:
		ctx.check(not bool(SnapshotCodec.decode_part(b[1])["ok"]), "manual: " + String(b[0]) + " e recusado")
	# varint com 5o byte de continuacao
	var sp: StreamPeerBuffer = StreamPeerBuffer.new()
	sp.put_u8(1)
	sp.put_u8(1)
	sp.put_u8(6)
	sp.put_data("player".to_ascii_buffer())
	for i: int in 3:
		sp.put_32(0)
	for b2: int in [0x81, 0x81, 0x81, 0x81, 0x01]:
		sp.put_u8(b2)
	ctx.check(not bool(SnapshotCodec.decode_part(sp.data_array)["ok"]), "manual: varint de 5 bytes recusado")


func _test_fuzz(ctx: Object) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 4242
	var base: PackedByteArray = _blob(S.crowd(15, 3))
	var crashes_free: bool = true
	var invariants: bool = true
	var accepted: int = 0
	for i: int in 3000:
		var b: PackedByteArray = base.duplicate()
		for k: int in rng.randi_range(1, 4):
			b[rng.randi() % b.size()] = rng.randi() & 0xFF
		if rng.randf() < 0.2:
			b = b.slice(0, rng.randi() % b.size())
		var d: Dictionary = SnapshotCodec.decode_part(b)
		if bool(d["ok"]):
			accepted += 1
			var seen: Dictionary = {}
			for e: Dictionary in d["entities"]:
				if seen.has(e["id"]) or int(e["kind"]) < 1 or int(e["kind"]) > 3 or not (e["pos"] as Vector3).is_finite():
					invariants = false
				seen[e["id"]] = true
	ctx.check(crashes_free, "fuzz: 3000 blobs corrompidos decodificados sem travar")
	ctx.check(invariants, "fuzz: quando aceita, a parte tem ids unicos, kind valido e posicao finita (%d aceitas)" % accepted)
	# aleatorio puro
	var junk_ok: bool = true
	for i: int in 500:
		var jb: PackedByteArray = PackedByteArray()
		for k: int in rng.randi_range(0, 80):
			jb.append(rng.randi() & 0xFF)
		if bool(SnapshotCodec.decode_part(jb)["ok"]) and jb.size() < 15:
			junk_ok = false
	ctx.check(junk_ok, "fuzz: lixo curto nunca e aceito")


func _test_partitioning(ctx: Object) -> void:
	var ents: Array = S.crowd(120, 5)
	var enc: Dictionary = SnapshotCodec.encode(ents, 300)
	var parts: Array = enc["parts"]
	ctx.check(parts.size() > 4, "particao: 120 entidades com orcamento de 300 B geram varias partes (%d)" % parts.size())
	var within: bool = true
	for p: PackedByteArray in parts:
		within = within and p.size() <= 300
	ctx.check(within, "particao: toda parte respeita o orcamento")
	var g: Dictionary = S.roundtrip(ents, 300)
	var same: bool = g.size() == ents.size()
	for e: Dictionary in ents:
		same = same and g.has(int(e["id"])) and S.diff(e, g[int(e["id"])]) == ""
	ctx.check(same, "particao: juntar as partes devolve as 120 entidades, cada uma exata na tolerancia")
	# orcamento absurdamente pequeno: ainda progride (1 entidade por parte), nunca laco infinito
	var tiny: Dictionary = SnapshotCodec.encode(S.crowd(10), 1)
	ctx.check((tiny["parts"] as Array).size() == 10 and int(tiny["encoded"]) == 10, "particao: orcamento minimo => 1 entidade por parte")
	# 256 entidades (limite do NetRpc) com o orcamento real cabem no limite de partes e de MTU
	var big: Dictionary = SnapshotCodec.encode(S.crowd(256, 8))
	var big_parts: Array = big["parts"]
	var worst: int = 0
	for i: int in big_parts.size():
		worst = maxi(worst, S.msg_bytes(1234567, 1234567, i, big_parts.size(), big_parts[i]))
	ctx.check(big_parts.size() <= Protocol.MAX_SNAPSHOT_PARTS and worst <= Protocol.MTU_PAYLOAD, "particao: 256 entidades -> %d partes, maior mensagem %d B <= %d" % [big_parts.size(), worst, Protocol.MTU_PAYLOAD])
	# partes cheias de pickups/strings distintas: respeita o limite de 254 strings por parte
	var many: Array = []
	for i: int in 300:
		many.append(S.pickup(i + 1, Vector3(i * 0.1, 0, 0), "item_%d" % i, 1))
	var enc2: Dictionary = SnapshotCodec.encode(many, 100000)
	var ok_strings: bool = true
	for p2: PackedByteArray in enc2["parts"]:
		var d: Dictionary = SnapshotCodec.decode_part(p2)
		ok_strings = ok_strings and bool(d["ok"]) and (d["entities"] as Array).size() <= SnapshotCodec.MAX_ENTITIES_PER_PART
	ctx.check(ok_strings and (enc2["parts"] as Array).size() >= 2, "particao: 300 tipos distintos viram >= 2 partes validas (limites de strings/entidades por parte)")


func _test_max_size(ctx: Object) -> void:
	var legacy30: int = var_to_bytes(S.crowd(30)).size()
	var enc: Dictionary = SnapshotCodec.encode(S.crowd(30))
	var parts: Array = enc["parts"]
	var msg: int = S.msg_bytes(1234567, 1234567, 0, 1, parts[0])
	ctx.check(parts.size() == 1, "tamanho: 30 entidades cabem em 1 mensagem")
	ctx.check(msg <= Protocol.MTU_PAYLOAD, "tamanho: 30 entidades = %d B por mensagem <= %d (legado: %d B)" % [msg, Protocol.MTU_PAYLOAD, legacy30])
	ctx.check(msg * 5 < legacy30, "tamanho: reducao > 5x frente ao legado (%d -> %d B)" % [legacy30, msg])
	# pior caso realista: 30 entidades todas com hp parcial, extras, tipo de 32 chars distintos e posicao larga
	var worst: Array = []
	for i: int in 30:
		worst.append(S.ent(100000 + i, 2, Vector3(i * 700.0, 1.0, -i * 650.0), 33.0, 99999.0, ("t%02d" % i).repeat(1) + "x".repeat(28), 1.0, 2, {"phase": 15, "atk": "a%02d" % i + "y".repeat(28)}))
	var wenc: Dictionary = SnapshotCodec.encode(worst)
	var wparts: Array = wenc["parts"]
	var wmax: int = 0
	for i: int in wparts.size():
		wmax = maxi(wmax, S.msg_bytes(1234567, 1234567, i, wparts.size(), wparts[i]))
	ctx.check(wmax <= Protocol.MTU_PAYLOAD, "tamanho: pior caso artificial (30 entidades, tudo distinto e largo) = %d partes, maior mensagem %d B <= %d" % [wparts.size(), wmax, Protocol.MTU_PAYLOAD])
