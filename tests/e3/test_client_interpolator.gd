extends RefCounted
## SnapshotInterpolator: ordem, atraso, descarte, extrapolacao limitada, remocao.

const OFFSET: float = 1000.0  # recv = t + OFFSET
const TICK_MS: float = 1000.0 / 30.0


func _ent(id: int, x: float) -> Dictionary:
	return {"id": id, "kind": 2, "pos": Vector3(x, 0, 0), "yaw": 0.0, "hp": 10.0, "max_hp": 10.0, "state": 0, "type": "grunt"}


func _t(tick: int) -> float:
	return float(tick) * TICK_MS


func _now_for_rt(rt: float, delay: float = 100.0) -> float:
	return rt + OFFSET + delay


func _make() -> SnapshotInterpolator:
	var it: SnapshotInterpolator = SnapshotInterpolator.new()
	it.configure(30)
	for tick: int in range(1, 11):
		it.push(tick, _t(tick) + OFFSET, [_ent(1, float(tick))])
	return it


func run(ctx: Object) -> void:
	var it: SnapshotInterpolator = _make()
	ctx.check(it.accepted == 10 and it.snapshot_count() == 10, "interp: 10 snapshots aceitos")

	# interpolacao no ponto medio entre tick 5 e 6
	var s: Dictionary = it.sample(_now_for_rt(_t(5) + TICK_MS * 0.5))
	ctx.check(s.has(1) and absf((s[1]["pos"] as Vector3).x - 5.5) < 0.01, "interp: ponto medio 5.5")
	ctx.check(not bool(s[1]["extrapolated"]), "interp: nao extrapolado dentro da janela")

	# atraso de 100 ms: no instante de chegada do tick 10, mostra ~3 ticks antes
	var s2: Dictionary = it.sample(_t(10) + OFFSET)
	ctx.check(absf((s2[1]["pos"] as Vector3).x - 7.0) < 0.01, "interp: atraso de 100 ms (x=7.0), obtido %s" % str((s2[1]["pos"] as Vector3).x))

	# atraso configuravel
	var it_d: SnapshotInterpolator = SnapshotInterpolator.new()
	it_d.configure(30, 200.0)
	for tick: int in range(1, 11):
		it_d.push(tick, _t(tick) + OFFSET, [_ent(1, float(tick))])
	var sd: Dictionary = it_d.sample(_t(10) + OFFSET)
	ctx.check(absf((sd[1]["pos"] as Vector3).x - 4.0) < 0.01, "interp: atraso configuravel 200 ms (x=4.0)")

	# fora de ordem / duplicado descartado
	ctx.check(not it.push(10, 0.0, [_ent(1, 99.0)]), "interp: tick duplicado descartado")
	ctx.check(not it.push(3, 0.0, [_ent(1, 99.0)]), "interp: tick velho descartado")
	ctx.check(it.discarded == 2 and it.last_tick == 10 and it.snapshot_count() == 10, "interp: contadores apos descarte")

	# extrapolacao limitada
	var e1: Dictionary = it.sample(_now_for_rt(_t(10) + 50.0))
	ctx.check(bool(e1[1]["extrapolated"]) and absf((e1[1]["pos"] as Vector3).x - 11.5) < 0.02, "interp: extrapola 50 ms (x=11.5)")
	var e2: Dictionary = it.sample(_now_for_rt(_t(10) + 5000.0))
	ctx.check(absf((e2[1]["pos"] as Vector3).x - 14.5) < 0.02, "interp: extrapolacao limitada a 150 ms (x=14.5)")
	it.max_extrapolation_ms = 0.0
	var e3: Dictionary = it.sample(_now_for_rt(_t(10) + 5000.0))
	ctx.check(absf((e3[1]["pos"] as Vector3).x - 10.0) < 0.001 and not bool(e3[1]["extrapolated"]), "interp: sem extrapolacao segura posicao")

	# remocao: entidade 2 existe ate tick 10; tick 11 sem ela
	var it2: SnapshotInterpolator = SnapshotInterpolator.new()
	it2.configure(30)
	for tick: int in range(1, 11):
		it2.push(tick, _t(tick) + OFFSET, [_ent(1, float(tick)), _ent(2, 50.0)])
	it2.push(11, _t(11) + OFFSET, [_ent(1, 11.0)])
	var before: Dictionary = it2.sample(_now_for_rt(_t(10) + TICK_MS * 0.5))
	ctx.check(before.has(2), "interp: entidade presente antes do snapshot sem ela")
	var after: Dictionary = it2.sample(_now_for_rt(_t(11) + 1.0))
	ctx.check(not after.has(2) and after.has(1), "interp: entidade ausente removida")

	# entidade nova aparece
	it2.push(12, _t(12) + OFFSET, [_ent(1, 12.0), _ent(3, 7.0)])
	var spawned: Dictionary = it2.sample(_now_for_rt(_t(12) + 1.0))
	ctx.check(spawned.has(3), "interp: entidade nova aparece")

	# somente um snapshot, e vazio
	var it3: SnapshotInterpolator = SnapshotInterpolator.new()
	ctx.check(it3.sample(1000.0).is_empty(), "interp: sem dados -> vazio")
	it3.push(1, 1000.0, [_ent(1, 3.0)])
	ctx.check(it3.sample(1000.0).has(1), "interp: um snapshot basta")

	# rotacao interpola pelo caminho curto
	var it4: SnapshotInterpolator = SnapshotInterpolator.new()
	it4.configure(30)
	var a: Dictionary = _ent(1, 0.0)
	a["yaw"] = 3.0
	var b: Dictionary = _ent(1, 0.0)
	b["yaw"] = -3.0
	it4.push(1, _t(1) + OFFSET, [a])
	it4.push(2, _t(2) + OFFSET, [b])
	var ys: Dictionary = it4.sample(_now_for_rt(_t(1) + TICK_MS * 0.5))
	ctx.check(absf(absf(float(ys[1]["yaw"])) - PI) < 0.2, "interp: yaw pelo caminho curto (~pi)")

	# reset
	it.reset()
	ctx.check(it.snapshot_count() == 0 and it.push(1, 0.0, []), "interp: reset aceita ticks de novo")
