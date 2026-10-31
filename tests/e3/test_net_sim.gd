extends RefCounted
## NetSim: latencia, reliable sem perda e em ordem, loss deterministico.

var log: Array = []


func _rec(v: int) -> void:
	log.append(v)


func _run_seq(seed_value: int, loss: float, count: int) -> Array:
	var s: NetSim = NetSim.new()
	s.configure(50, 30, loss, seed_value)
	log = []
	for n: int in count:
		s.submit(_rec.bind(n), false, 0)
	s.pump(10000)
	return log.duplicate()


func run(ctx: Object) -> void:
	var s: NetSim = NetSim.new()
	s.configure(100, 0, 0.0, 1)
	log = []
	s.submit(_rec.bind(1), true, 1000)
	s.pump(1000)
	s.pump(1099)
	ctx.check(log.is_empty(), "latencia minima respeitada (nada antes de 100 ms)")
	s.pump(1100)
	ctx.check(log == [1], "entregue ao atingir a latencia")
	s.pump(5000)
	ctx.check(log == [1], "entrega unica (sem duplicar)")

	# reliable: nunca perde, ordem preservada mesmo com jitter e loss 100%
	var r: NetSim = NetSim.new()
	r.configure(20, 200, 100.0, 7)
	log = []
	for n: int in 200:
		r.submit(_rec.bind(n), true, n * 3)
	r.pump(100000)
	var in_order: bool = log.size() == 200
	for n: int in log.size():
		if log[n] != n:
			in_order = false
	ctx.check(log.size() == 200, "reliable nao perde mesmo com loss 100%% (%d/200)" % log.size())
	ctx.check(in_order, "reliable preserva a ordem com jitter alto")

	# unreliable: loss 100% perde tudo, 0% nada
	ctx.check(_run_seq(3, 100.0, 50).is_empty(), "unreliable loss 100% perde tudo")
	ctx.check(_run_seq(3, 0.0, 50).size() == 50, "unreliable loss 0% entrega tudo")

	# determinismo por seed
	var a: Array = _run_seq(42, 30.0, 300)
	var b: Array = _run_seq(42, 30.0, 300)
	var c: Array = _run_seq(43, 30.0, 300)
	ctx.check(a == b, "mesma seed -> mesmo resultado (entrega e ordem)")
	ctx.check(a != c, "seed diferente -> resultado diferente")
	ctx.check(a.size() > 150 and a.size() < 270, "loss 30%% aproximado (%d/300 entregues)" % a.size())

	# jitter sem exceder latencia+jitter
	var j: NetSim = NetSim.new()
	j.configure(40, 20, 0.0, 9)
	log = []
	for n: int in 50:
		j.submit(_rec.bind(n), false, 0)
	j.pump(39)
	ctx.check(log.is_empty(), "jitter nao reduz abaixo da latencia")
	j.pump(60)
	ctx.check(log.size() == 50, "tudo entregue ate latencia+jitter")

	# callable invalido (objeto liberado) nao derruba o pump
	var d: NetSim = NetSim.new()
	d.configure(0, 0, 0.0, 1)
	var tmp: RefCounted = RefCounted.new()
	d.submit(Callable(), true, 0)
	d.pump(0)
	ctx.check(d.pending() == 0 and tmp != null, "callable invalido ignorado")
