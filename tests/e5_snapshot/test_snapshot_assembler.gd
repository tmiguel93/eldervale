extends RefCounted
## E5.7 - SnapshotAssembler: mescla de particoes fora de ordem, perdidas, duplicadas, velhas e inconsistentes.

const S = preload("res://tests/e5_snapshot/snapshot_helpers.gd")


func run(ctx: Object) -> void:
	var tree: SceneTree = ctx as SceneTree
	await tree.physics_frame
	_test_in_order_and_shuffled(ctx)
	_test_lost_part(ctx)
	_test_duplicates_and_stale(ctx)
	_test_inconsistent(ctx)
	_test_eviction(ctx)
	_test_invalid_headers(ctx)
	_test_entity_limit(ctx)
	await tree.physics_frame


## Partes de um snapshot de `n` entidades com orcamento pequeno (>= 3 partes).
func _parts(n: int = 60, budget: int = 300, seed_value: int = 11) -> Array:
	return SnapshotCodec.encode(S.crowd(n, seed_value), budget)["parts"]


func _push_all(a: SnapshotAssembler, tick: int, seq: int, parts: Array, order: Array) -> Dictionary:
	var last: Dictionary = {"complete": false}
	for i: int in order:
		last = a.push(tick, seq, i, parts.size(), parts[i])
	return last


func _test_in_order_and_shuffled(ctx: Object) -> void:
	var parts: Array = _parts()
	ctx.check(parts.size() >= 3, "montagem: base com %d partes" % parts.size())
	var order: Array = range(parts.size())
	var a: SnapshotAssembler = SnapshotAssembler.new()
	var done: Array = []
	for i: int in parts.size():
		var r: Dictionary = a.push(10, 77, i, parts.size(), parts[i])
		done.append(bool(r["complete"]))
		if i == parts.size() - 1:
			ctx.check(bool(r["complete"]) and int(r["tick"]) == 10 and int(r["last_seq"]) == 77 and (r["entities"] as Array).size() == 60, "montagem em ordem: completa na ultima parte com 60 entidades, tick e last_seq")
	ctx.check(not done.slice(0, -1).has(true), "montagem em ordem: nunca entrega antes de ter todas as partes")
	# fora de ordem: todas as permutacoes de ate 4 partes + ordem inversa
	var rev: Array = order.duplicate()
	rev.reverse()
	var b: SnapshotAssembler = SnapshotAssembler.new()
	var rb: Dictionary = _push_all(b, 5, 1, parts, rev)
	ctx.check(bool(rb["complete"]) and (rb["entities"] as Array).size() == 60, "montagem invertida: completa com 60 entidades")
	var ids: Dictionary = S.by_id(rb["entities"])
	var all_ids: bool = true
	for e: Dictionary in S.crowd(60, 11):
		all_ids = all_ids and ids.has(int(e["id"]))
	ctx.check(all_ids, "montagem invertida: nenhuma entidade perdida na mescla")
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 3
	var all_complete: bool = true
	for t: int in 50:
		var shuffled: Array = order.duplicate()
		for i: int in range(shuffled.size() - 1, 0, -1):
			var j: int = rng.randi_range(0, i)
			var tmp: Variant = shuffled[i]
			shuffled[i] = shuffled[j]
			shuffled[j] = tmp
		var c: SnapshotAssembler = SnapshotAssembler.new()
		var rc: Dictionary = _push_all(c, 1, 0, parts, shuffled)
		all_complete = all_complete and bool(rc["complete"]) and (rc["entities"] as Array).size() == 60
	ctx.check(all_complete, "montagem: 50 permutacoes aleatorias das partes completam o snapshot")
	# parte unica (caso comum)
	var one: Array = _parts(10, SnapshotCodec.MAX_PART_BYTES)
	var d: SnapshotAssembler = SnapshotAssembler.new()
	var rd: Dictionary = d.push(3, 4, 0, 1, one[0])
	ctx.check(one.size() == 1 and bool(rd["complete"]) and (rd["entities"] as Array).size() == 10, "parte unica: entrega imediata")


func _test_lost_part(ctx: Object) -> void:
	var parts: Array = _parts()
	var a: SnapshotAssembler = SnapshotAssembler.new()
	a.push(10, 1, 0, parts.size(), parts[0])
	a.push(10, 1, 2, parts.size(), parts[2])  # a parte 1 nunca chega
	ctx.check(a.pending_count() == 1 and a.snapshots_completed == 0, "perda: tick incompleto fica pendente e NAO e entregue pela metade")
	var next: Array = _parts(60, 300, 12)
	var r: Dictionary = _push_all(a, 11, 2, next, range(next.size()))
	ctx.check(bool(r["complete"]) and int(r["tick"]) == 11, "perda: o tick seguinte completa normalmente")
	ctx.check(a.pending_count() == 0 and a.snapshots_dropped_incomplete == 1, "perda: tick 10 descartado e contado (dropped_incomplete=%d), sem vazamento" % a.snapshots_dropped_incomplete)
	# a parte que faltava chega tarde: velha
	var late: Dictionary = a.push(10, 1, 1, parts.size(), parts[1])
	ctx.check(not bool(late["complete"]) and a.parts_stale == 1, "perda: parte atrasada de tick ja superado e ignorada (stale)")


func _test_duplicates_and_stale(ctx: Object) -> void:
	var parts: Array = _parts()
	var a: SnapshotAssembler = SnapshotAssembler.new()
	a.push(20, 1, 0, parts.size(), parts[0])
	var dup: Dictionary = a.push(20, 1, 0, parts.size(), parts[0])
	ctx.check(not bool(dup["complete"]) and a.parts_duplicate == 1, "duplicata: parte repetida ignorada e contada")
	var r: Dictionary = {"complete": false}
	for i: int in range(1, parts.size()):
		r = a.push(20, 1, i, parts.size(), parts[i])
	ctx.check(bool(r["complete"]) and (r["entities"] as Array).size() == 60, "duplicata: a duplicata nao atrapalha a montagem (60 entidades, sem repeticao)")
	var again: Dictionary = a.push(20, 1, 0, parts.size(), parts[0])
	ctx.check(not bool(again["complete"]) and a.parts_stale == 1, "velha: reenvio do tick ja entregue e ignorado")
	var older: Dictionary = a.push(19, 1, 0, 1, _parts(5, SnapshotCodec.MAX_PART_BYTES)[0])
	ctx.check(not bool(older["complete"]) and a.parts_stale == 2, "velha: tick anterior ao ultimo entregue e ignorado")
	# fora de ordem entre ticks: o 22 completa antes do 21 => o 21 chega tarde e nao e entregue (como o interpolador exigiria)
	var p21: Array = _parts(30, 200, 21)
	var p22: Array = _parts(30, 200, 22)
	a.push(21, 5, 0, p21.size(), p21[0])
	var r22: Dictionary = _push_all(a, 22, 6, p22, range(p22.size()))
	ctx.check(bool(r22["complete"]), "fora de ordem entre ticks: 22 completa primeiro")
	var rest21: Dictionary = {"complete": false}
	for i: int in range(1, p21.size()):
		rest21 = a.push(21, 5, i, p21.size(), p21[i])
	ctx.check(not bool(rest21["complete"]), "fora de ordem entre ticks: 21 completo depois do 22 nao e entregue (monotonico)")
	ctx.check(a.last_tick == 22 and a.pending_count() == 0, "fora de ordem entre ticks: last_tick=22, nada pendente")


func _test_inconsistent(ctx: Object) -> void:
	var parts: Array = _parts()
	var a: SnapshotAssembler = SnapshotAssembler.new()
	a.push(30, 9, 0, parts.size(), parts[0])
	var r1: Dictionary = a.push(30, 9, 1, parts.size() + 1, parts[1])
	ctx.check(not bool(r1["complete"]) and a.parts_malformed == 1, "inconsistente: 'parts' diferente do declarado na primeira parte")
	var r2: Dictionary = a.push(30, 10, 1, parts.size(), parts[1])
	ctx.check(not bool(r2["complete"]) and a.parts_malformed == 2, "inconsistente: last_input_seq diferente entre partes do mesmo tick")
	# ids repetidos entre partes (mesma parte reenviada como indice diferente)
	var r3: Dictionary = a.push(30, 9, 1, parts.size(), parts[0])
	ctx.check(not bool(r3["complete"]) and a.parts_malformed == 3, "inconsistente: entidade repetida entre partes e recusada")
	# depois dos erros o tick ainda completa com as partes corretas
	var rr: Dictionary = {"complete": false}
	for i: int in range(1, parts.size()):
		rr = a.push(30, 9, i, parts.size(), parts[i])
	ctx.check(bool(rr["complete"]) and (rr["entities"] as Array).size() == 60, "inconsistente: partes validas posteriores ainda completam o tick")


func _test_eviction(ctx: Object) -> void:
	var a: SnapshotAssembler = SnapshotAssembler.new()
	var p: Array = _parts(30, 200, 5)
	for t: int in range(1, 8):
		a.push(t, 0, 0, p.size(), p[0])  # so a primeira parte de 7 ticks distintos
	ctx.check(a.pending_count() <= SnapshotAssembler.MAX_PENDING_TICKS, "evicao: no maximo %d montagens pendentes (%d)" % [SnapshotAssembler.MAX_PENDING_TICKS, a.pending_count()])
	ctx.check(a.snapshots_dropped_incomplete == 3, "evicao: as 3 mais antigas descartadas e contadas (%d)" % a.snapshots_dropped_incomplete)
	# o mais antigo evictado nao completa mais
	var rr: Dictionary = {"complete": false}
	for i: int in range(1, p.size()):
		rr = a.push(1, 0, i, p.size(), p[i])
	ctx.check(not bool(rr["complete"]), "evicao: tick evictado nao pode completar com partes tardias")
	a.reset()
	ctx.check(a.pending_count() == 0 and a.last_tick == -1, "reset limpa pendentes e last_tick")


func _test_invalid_headers(ctx: Object) -> void:
	var good: PackedByteArray = _parts(5, SnapshotCodec.MAX_PART_BYTES)[0]
	var a: SnapshotAssembler = SnapshotAssembler.new()
	var cases: Array = [
		["tick float", 1.5, 0, 0, 1, good], ["tick negativo", -1, 0, 0, 1, good], ["seq string", 1, "0", 0, 1, good],
		["part negativa", 1, 0, -1, 2, good], ["part == parts", 1, 0, 2, 2, good], ["parts 0", 1, 0, 0, 0, good],
		["parts acima do limite", 1, 0, 0, Protocol.MAX_SNAPSHOT_PARTS + 1, good], ["blob nao e PackedByteArray", 1, 0, 0, 1, [1, 2, 3]],
		["blob vazio", 1, 0, 0, 1, PackedByteArray()], ["blob acima do MTU", 1, 0, 0, 1, _big_blob()],
		["blob lixo", 1, 0, 0, 1, PackedByteArray([1, 2, 3, 4, 5, 6, 7, 8, 9, 10])], ["blob truncado", 1, 0, 0, 1, good.slice(0, good.size() - 1)],
	]
	for c: Array in cases:
		var before: int = a.parts_malformed
		var r: Dictionary = a.push(c[1], c[2], c[3], c[4], c[5])
		ctx.check(not bool(r["complete"]) and a.parts_malformed == before + 1, "cabecalho invalido descartado e contado: " + String(c[0]))
	ctx.check(a.pending_count() == 0 and a.snapshots_completed == 0, "cabecalhos invalidos nao deixam estado")
	var ok: Dictionary = a.push(1, 0, 0, 1, good)
	ctx.check(bool(ok["complete"]), "depois dos invalidos, uma parte valida ainda completa")


func _big_blob() -> PackedByteArray:
	var b: PackedByteArray = PackedByteArray()
	b.resize(Protocol.MTU_PAYLOAD + 1)
	return b


func _test_entity_limit(ctx: Object) -> void:
	# 4 partes de 80 entidades com ids distintos: a 4a ultrapassa as 256 entidades por snapshot
	var a: SnapshotAssembler = SnapshotAssembler.new()
	var results: Array = []
	for p: int in 4:
		var ents: Array = []
		for i: int in 80:
			ents.append(S.player(1000 + p * 100 + i, Vector3(i * 0.5, 0, 0)))
		var blob: PackedByteArray = (SnapshotCodec.encode(ents, 100000)["parts"] as Array)[0]
		ctx.check(blob.size() <= Protocol.MTU_PAYLOAD, "limite: parte de 80 entidades cabe no MTU (%d B)" % blob.size())
		results.append(a.push(1, 0, p, 5, blob))
	ctx.check(a.parts_malformed == 1 and a.parts_accepted == 3, "limite: acima de %d entidades por snapshot a parte excedente e recusada" % SnapshotAssembler.MAX_ENTITIES)
