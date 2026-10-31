extends RefCounted
## Maquina de estados PURA da IA (sem fisica, sem timing de motor: totalmente deterministica).

const DT: float = 1.0 / 60.0


func _melee() -> EnemyAI:
	var ai: EnemyAI = EnemyAI.new()
	ai.aggro_range = 10.0
	ai.attack_range = 2.0
	ai.attack_cooldown = 1.0
	ai.windup = 0.4
	ai.leash_range = 20.0
	ai.origin = Vector3.ZERO
	return ai


func run(ctx: Object) -> void:
	# --- idle -> chase ---
	var ai: EnemyAI = _melee()
	ai.tick(DT, Vector3.ZERO, Vector3(15, 0, 0), true)
	ctx.check(ai.state == EnemyAI.State.IDLE and ai.move_dir == Vector3.ZERO, "alvo fora do aggro: continua IDLE e parado")
	ai.tick(DT, Vector3.ZERO, Vector3(8, 0, 0), true)
	ctx.check(ai.state == EnemyAI.State.CHASE, "alvo no aggro: CHASE")
	ctx.check(ai.move_dir.is_equal_approx(Vector3(1, 0, 0)), "CHASE move em direcao ao alvo")
	var idle_dead: EnemyAI = _melee()
	idle_dead.tick(DT, Vector3.ZERO, Vector3(3, 0, 0), false)
	ctx.check(idle_dead.state == EnemyAI.State.IDLE, "alvo morto nao gera aggro")

	# --- ataque: telegrafo, release unico, cooldown ---
	ai = _melee()
	var telegraphs: Array[int] = [0]
	var releases: Array[int] = [0]
	ai.attack_telegraph_started.connect(func() -> void: telegraphs[0] += 1)
	ai.attack_released.connect(func() -> void: releases[0] += 1)
	ai.tick(DT, Vector3.ZERO, Vector3(1.5, 0, 0), true)
	ctx.check(ai.state == EnemyAI.State.ATTACK and telegraphs[0] == 1, "no alcance: ATTACK com telegrafo")
	ctx.check(releases[0] == 0, "release NAO e imediato (windup)")
	ctx.check(ai.move_dir == Vector3.ZERO, "parado durante o windup")
	var t: float = 0.0
	while ai.state == EnemyAI.State.ATTACK and t < 2.0:
		ai.tick(DT, Vector3.ZERO, Vector3(1.5, 0, 0), true)
		t += DT
	ctx.check(releases[0] == 1 and absf(t - 0.4) < 0.05, "release apos ~windup (%.2fs)" % t)
	ctx.check(ai.state == EnemyAI.State.CHASE and ai.cooldown_left > 0.0, "apos o release: CHASE com cooldown")
	for i: int in 30:
		ai.tick(DT, Vector3.ZERO, Vector3(1.5, 0, 0), true)
	ctx.check(telegraphs[0] == 1 and releases[0] == 1, "cooldown impede novo ataque")
	for i: int in 60:
		ai.tick(DT, Vector3.ZERO, Vector3(1.5, 0, 0), true)
	ctx.check(telegraphs[0] == 2, "ataca de novo apos o cooldown")

	# --- alvo morre durante o windup: cancela sem release ---
	ai = _melee()
	releases = [0]
	ai.attack_released.connect(func() -> void: releases[0] += 1)
	ai.tick(DT, Vector3.ZERO, Vector3(1.5, 0, 0), true)
	ai.tick(DT, Vector3.ZERO, Vector3(1.5, 0, 0), false)
	ctx.check(ai.state == EnemyAI.State.RETURN and releases[0] == 0, "alvo morto no windup: RETURN sem release")

	# --- leash: alvo foge alem do raio -> RETURN -> IDLE na origem ---
	ai = _melee()
	ai.origin = Vector3(10, 0, 0)
	var resets: Array[int] = [0]
	ai.reset_completed.connect(func() -> void: resets[0] += 1)
	var pos: Vector3 = Vector3(25, 0, 0)
	ai.tick(DT, pos, Vector3(30, 0, 0), true)
	ctx.check(ai.state == EnemyAI.State.CHASE, "leash: persegue dentro do raio")
	var far: Vector3 = Vector3(80, 0, 0)
	ai.tick(DT, pos, far, true)
	ctx.check(ai.state == EnemyAI.State.RETURN, "alvo alem do leash: RETURN")
	var steps: int = 0
	while ai.state == EnemyAI.State.RETURN and steps < 2000:
		ai.tick(DT, pos, far, true)
		pos += ai.move_dir * 4.0 * DT
		steps += 1
	ctx.check(ai.state == EnemyAI.State.IDLE and resets[0] == 1, "RETURN termina em IDLE com reset_completed (%d passos)" % steps)
	ctx.check(_flat_dist(pos, ai.origin) <= ai.arrive_radius + 0.1, "voltou a origem")
	# sem re-aggro durante o retorno
	ai = _melee()
	ai.tick(DT, Vector3(15, 0, 0), Vector3(12, 0, 0), true) # inimigo longe da origem, alvo perto
	ctx.check(ai.state == EnemyAI.State.CHASE, "(preparo) persegue")
	ai.tick(DT, Vector3(25, 0, 0), Vector3(24, 0, 0), true) # inimigo alem do leash
	ctx.check(ai.state == EnemyAI.State.RETURN, "inimigo alem do leash: RETURN")
	ai.tick(DT, Vector3(24, 0, 0), Vector3(23, 0, 0), true)
	ctx.check(ai.state == EnemyAI.State.RETURN, "durante RETURN ignora o alvo (sem ping-pong)")

	# --- return_timeout: preso no retorno -> sinal e reset ---
	ai = _melee()
	ai.return_timeout = 1.0
	var timeouts: Array[int] = [0]
	ai.return_timed_out.connect(func() -> void: timeouts[0] += 1)
	ai.tick(DT, Vector3(25, 0, 0), Vector3(25, 0, 0), false) # alvo morto -> ... esta em IDLE
	ai.tick(DT, Vector3(5, 0, 0), Vector3(6, 0, 0), true)
	ai.tick(DT, Vector3(25, 0, 0), Vector3(26, 0, 0), true) # CHASE -> RETURN pelo leash
	for i: int in 90:
		ai.tick(DT, Vector3(25, 0, 0), Vector3(26, 0, 0), true) # nunca sai do lugar
	ctx.check(timeouts[0] == 1 and ai.state == EnemyAI.State.IDLE, "RETURN travado estoura return_timeout uma vez e volta a IDLE")

	# --- morte e terminal ---
	ai = _melee()
	ai.tick(DT, Vector3.ZERO, Vector3(8, 0, 0), true)
	ai.die()
	ctx.check(ai.is_dead() and ai.move_dir == Vector3.ZERO, "die(): DEAD e parado")
	ai.tick(DT, Vector3.ZERO, Vector3(1, 0, 0), true)
	ctx.check(ai.state == EnemyAI.State.DEAD and ai.move_dir == Vector3.ZERO, "DEAD e terminal (nao reage ao alvo)")

	# --- ranged: mantem distancia (recua se perto) e para no alcance ---
	var data: EnemyData = load("res://data/enemies/ranged_caster.tres") as EnemyData
	ai = EnemyAI.from_data(data)
	ai.tick(DT, Vector3.ZERO, Vector3(12, 0, 0), true)
	ctx.check(ai.state == EnemyAI.State.CHASE and ai.move_dir.x > 0.0, "ranged avanca ate o alcance")
	ai.tick(DT, Vector3.ZERO, Vector3(8.5, 0, 0), true)
	ctx.check(ai.state == EnemyAI.State.ATTACK, "ranged ataca a distancia (dentro de attack_range)")
	ai = EnemyAI.from_data(data)
	ai.cooldown_left = 5.0
	ai.tick(DT, Vector3.ZERO, Vector3(3, 0, 0), true)
	ctx.check(ai.state == EnemyAI.State.CHASE and ai.move_dir.x < 0.0, "ranged com alvo colado recua")

	# --- simulacao: chega no alvo e ataca em tempo finito (sem ficar preso) ---
	ai = _melee()
	pos = Vector3.ZERO
	var tgt: Vector3 = Vector3(9, 0, 4)
	var attacked_box: Array[bool] = [false]
	ai.attack_released.connect(func() -> void: attacked_box[0] = true)
	steps = 0
	while not attacked_box[0] and steps < 1200:
		ai.tick(DT, pos, tgt, true)
		pos += ai.move_dir * 3.5 * DT
		steps += 1
	ctx.check(attacked_box[0] and steps < 1200, "simulacao: alcanca e ataca (%d passos)" % steps)
	ctx.check(_flat_dist(pos, tgt) <= ai.attack_range + 0.05, "para em torno do alcance")


static func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
