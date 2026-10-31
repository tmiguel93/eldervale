extends RefCounted
## Prediction: reconciliacao por last_input_seq (erro pequeno ignorado, medio suavizado, grande corrigido).


func _fwd(pr: Prediction, seq_from: int, seq_to: int) -> void:
	for s: int in range(seq_from, seq_to + 1):
		pr.apply_input(s, Vector2(0, 1), 0.0, 1.0 / 30.0)


func run(ctx: Object) -> void:
	var pr: Prediction = Prediction.new()
	pr.apply_input(1, Vector2(0, 1), 0.0, 0.1)
	ctx.check(pr.pos == Vector3.ZERO and pr.pending_count() == 0, "pred: sem init nao move")

	pr.init_at(Vector3.ZERO)
	_fwd(pr, 1, 3)
	ctx.check(absf(pr.pos.z - (-0.6)) < 0.0001, "pred: 3 inputs a 6 m/s andam 0.6 m (frente = -Z)")
	ctx.check(pr.pending_count() == 3, "pred: 3 pendentes")

	# servidor confirmou seq 1 em z=-0.2: replay dos pendentes coincide com a predicao
	pr.reconcile(Vector3(0, 0, -0.2), 1)
	ctx.check(pr.pending_count() == 2, "pred: confirmados removidos dos pendentes")
	ctx.check(absf(pr.pos.z - (-0.6)) < 0.0001 and pr.smooth_corrections == 0 and pr.snaps == 0, "pred: sem erro, sem correcao")

	# erro pequeno (3 cm) ignorado
	pr.reconcile(Vector3(0, 0, -0.2 + 0.03), 1)
	ctx.check(absf(pr.pos.z - (-0.6)) < 0.0001 and pr.smooth_corrections == 0, "pred: erro pequeno ignorado")

	# erro medio (0.5 m) corrigido suavemente: nao salta, converge
	var before: Vector3 = pr.pos
	pr.reconcile(Vector3(0, 0, -0.2 + 0.5), 1)
	ctx.check(pr.pos.distance_to(before) < 0.0001 and pr.smooth_corrections == 1, "pred: erro medio nao salta no reconcile")
	pr.update(1.0 / 60.0)
	var d1: float = pr.pos.distance_to(before)
	ctx.check(d1 > 0.0 and d1 < 0.2, "pred: primeiro frame corrige so uma fracao (%.3f)" % d1)
	for i: int in 120:
		pr.update(1.0 / 60.0)
	ctx.check(absf(pr.pos.z - (-0.6 + 0.5)) < 0.01, "pred: converge para o alvo do servidor apos 2 s")
	ctx.check(pr.snaps == 0, "pred: sem snap no erro medio")

	# erro grande (5 m): teleporta
	pr.reconcile(Vector3(5, 0, 0), 3)
	ctx.check(pr.snaps == 1 and absf(pr.pos.x - 5.0) < 0.0001 and pr.pending_count() == 0, "pred: erro grande corrigido de imediato")

	# Y vem do servidor
	pr.reconcile(Vector3(5, 2.5, 0), 3)
	ctx.check(absf(pr.pos.y - 2.5) < 0.0001, "pred: Y sempre do servidor")

	# entradas invalidas nao sao previstas
	var p2: Prediction = Prediction.new()
	p2.init_at(Vector3.ZERO)
	p2.apply_input(1, Vector2(NAN, 0), 0.0, 0.1)
	p2.apply_input(2, Vector2(0, 1), INF, 0.1)
	ctx.check(p2.pos == Vector3.ZERO and p2.pending_count() == 0, "pred: NaN/INF ignorados")

	# primeiro snapshot inicializa
	var p3: Prediction = Prediction.new()
	p3.reconcile(Vector3(1, 0, 2), 0)
	ctx.check(p3.initialized and p3.pos == Vector3(1, 0, 2), "pred: primeiro reconcile inicializa")
