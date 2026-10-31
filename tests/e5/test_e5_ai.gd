extends RefCounted
## E5.2: IA com lista de ataques (puro, deterministico): selecao por alcance/recarga/peso, telegrafo
## obrigatorio, trava de transicao, e simulacao de TODOS os tipos (sem ficar parado nem travar).

const DT: float = 1.0 / 60.0


func _ai_for(id: StringName, seed_value: int = 1) -> EnemyAI:
	var d: EnemyData = load(EnemyCatalog.data_path(id)) as EnemyData
	var ai: EnemyAI = EnemyAI.from_data(d)
	if not d.phases.is_empty():
		ai.attacks = d.phases[0].attacks.duplicate()
	ai.rng.seed = seed_value
	return ai


func run(ctx: Object) -> void:
	_test_pick(ctx)
	_test_cooldowns_and_lock(ctx)
	_test_simulations(ctx)
	_test_boss_cadence(ctx)


func _test_pick(ctx: Object) -> void:
	var ai: EnemyAI = _ai_for(&"bark_brute")
	var close_ids: Dictionary = {}
	for i: int in 40:
		var a: EnemyAttack = ai.pick_attack(2.0)
		if a != null:
			close_ids[a.id] = true
	ctx.check(close_ids.has(&"swipe") and close_ids.has(&"slam"), "a 2 m o brutamontes sorteia swipe e slam")
	var far: EnemyAttack = ai.pick_attack(3.1)
	ctx.check(far != null and far.id == &"slam", "a 3.1 m so o slam alcanca")
	ctx.check(ai.pick_attack(8.0) == null, "fora do alcance: nenhum ataque")
	# arqueiro: nao atira colado (min_range 3)
	var archer: EnemyAI = _ai_for(&"bow_scout")
	ctx.check(archer.pick_attack(1.5) == null and archer.pick_attack(8.0) != null, "arqueiro nao atira a queima-roupa (min 3 m)")
	# lurker: pounce so entre 2.8 e 6.5
	var lurker: EnemyAI = _ai_for(&"burrow_lurker")
	var near_ids: Dictionary = {}
	var mid_ids: Dictionary = {}
	for i: int in 30:
		near_ids[lurker.pick_attack(1.5).id] = true
		mid_ids[lurker.pick_attack(4.0).id] = true
	ctx.check(near_ids.keys() == [&"claw"] and mid_ids.keys() == [&"pounce"], "emboscador: garra de perto, bote a media distancia")
	# determinismo por semente
	var a1: EnemyAI = _ai_for(&"bark_brute", 77)
	var a2: EnemyAI = _ai_for(&"bark_brute", 77)
	var same: bool = true
	for i: int in 20:
		var x: EnemyAttack = a1.pick_attack(2.0)
		var y: EnemyAttack = a2.pick_attack(2.0)
		a1.last_attack_id = x.id
		a2.last_attack_id = y.id
		if x.id != y.id:
			same = false
	ctx.check(same, "mesma semente => mesma sequencia de ataques")
	# variedade: nunca repete o anterior se ha alternativa
	var v: EnemyAI = _ai_for(&"bark_brute", 5)
	var repeats: int = 0
	for i: int in 30:
		var x: EnemyAttack = v.pick_attack(2.0)
		if x.id == v.last_attack_id:
			repeats += 1
		v.last_attack_id = x.id
	ctx.check(repeats == 0, "nao repete o mesmo ataque em sequencia quando ha alternativa")
	# bloqueio de invocacao
	var sh: EnemyAI = _ai_for(&"grove_shaman")
	sh.blocked[&"summon_sprouts"] = true
	var only_bolt: bool = true
	for i: int in 30:
		if sh.pick_attack(6.0).id != &"thorn_bolt":
			only_bolt = false
	ctx.check(only_bolt, "invocacao bloqueada (limite de adds): so atira")


func _test_cooldowns_and_lock(ctx: Object) -> void:
	# recarga propria: slam do brutamontes fica indisponivel apos o uso
	var ai: EnemyAI = _ai_for(&"bark_brute", 3)
	ai.attacks = [ai.attacks[1]] as Array[EnemyAttack] # so o slam
	var releases: Array[int] = [0]
	var telegraphs: Array[int] = [0]
	ai.attack_released.connect(func() -> void: releases[0] += 1)
	ai.attack_telegraph_started.connect(func() -> void: telegraphs[0] += 1)
	var t: float = 0.0
	var first_release_t: float = -1.0
	var second_release_t: float = -1.0
	while t < 12.0 and second_release_t < 0.0:
		ai.tick(DT, Vector3.ZERO, Vector3(2.0, 0, 0), true)
		t += DT
		if releases[0] == 1 and first_release_t < 0.0:
			first_release_t = t
		if releases[0] == 2:
			second_release_t = t
	ctx.check(first_release_t > 0.85 and first_release_t < 1.1, "telegrafo do slam dura ~0.9 s antes do golpe (%.2f)" % first_release_t)
	ctx.check(second_release_t - first_release_t >= 3.9, "recarga propria do slam (4 s): intervalo %.2f s" % (second_release_t - first_release_t))
	ctx.check(telegraphs[0] == releases[0], "todo golpe foi precedido de telegrafo")

	# trava (transicao de fase): parado, sem ataque, e cancela windup em andamento
	ai = _ai_for(&"blight_treant", 9)
	var rel: Array[int] = [0]
	ai.attack_released.connect(func() -> void: rel[0] += 1)
	ai.tick(DT, Vector3.ZERO, Vector3(2.0, 0, 0), true)
	ctx.check(ai.state == EnemyAI.State.ATTACK, "(preparo) chefe a 2 m comeca a telegrafar")
	ai.begin_lock(1.0)
	ctx.check(ai.state == EnemyAI.State.CHASE, "trava cancela o windup em andamento")
	var moved: bool = false
	var started: bool = false
	ai.attack_telegraph_started.connect(func() -> void: started = true)
	for i: int in 55: # < 1 s
		ai.tick(DT, Vector3.ZERO, Vector3(12.0, 0, 0), true)
		if ai.move_dir != Vector3.ZERO:
			moved = true
	ctx.check(not moved and rel[0] == 0 and not started, "durante a trava: nao anda nem ataca")
	for i: int in 10:
		ai.tick(DT, Vector3.ZERO, Vector3(12.0, 0, 0), true)
	ctx.check(ai.lock_left == 0.0 and ai.move_dir != Vector3.ZERO, "apos a trava volta a perseguir")
	ai.reset_to_idle()
	ctx.check(ai.state == EnemyAI.State.IDLE and ai.current_attack == null and ai.lock_left == 0.0, "reset_to_idle limpa tudo")
	# escala de pausa (fase furiosa ataca mais rapido)
	var fast: EnemyAI = _ai_for(&"bark_brute", 3)
	fast.cooldown_scale = 0.5
	fast.attacks = [fast.attacks[0]] as Array[EnemyAttack]
	var gaps: Array[float] = []
	var last: Array[float] = [0.0]
	var clock: Array[float] = [0.0]
	fast.attack_released.connect(func() -> void:
		gaps.append(clock[0] - last[0])
		last[0] = clock[0])
	while clock[0] < 8.0:
		fast.tick(DT, Vector3.ZERO, Vector3(2.0, 0, 0), true)
		clock[0] += DT
	var normal: EnemyAI = _ai_for(&"bark_brute", 3)
	normal.attacks = [normal.attacks[0]] as Array[EnemyAttack]
	var n_rel: Array[int] = [0]
	normal.attack_released.connect(func() -> void: n_rel[0] += 1)
	for i: int in 480:
		normal.tick(DT, Vector3.ZERO, Vector3(2.0, 0, 0), true)
	ctx.check(gaps.size() > n_rel[0], "cooldown_scale < 1 => mais ataques no mesmo tempo (%d > %d)" % [gaps.size(), n_rel[0]])


func _test_simulations(ctx: Object) -> void:
	for id: StringName in EnemyCatalog.all_ids():
		var d: EnemyData = load(EnemyCatalog.data_path(id)) as EnemyData
		var ai: EnemyAI = _ai_for(id, 11)
		var pos: Vector3 = Vector3.ZERO
		var target: Vector3 = Vector3(d.aggro_range * 0.8, 0, 3.0)
		var seen: Dictionary = {}
		var cur: Array[String] = [""]
		ai.attack_released.connect(func() -> void:
			if ai.current_attack != null:
				seen[ai.current_attack.id] = int(seen.get(ai.current_attack.id, 0)) + 1
			else:
				seen[&"legacy"] = int(seen.get(&"legacy", 0)) + 1)
		var steps: int = 0
		var stuck_attack: int = 0
		var max_attack_steps: int = 0
		while steps < 60 * 40:
			var was_attack: bool = ai.state == EnemyAI.State.ATTACK
			ai.tick(DT, pos, target, true)
			var speed: float = d.stats.move_speed
			pos += ai.move_dir * speed * DT
			steps += 1
			if ai.state == EnemyAI.State.ATTACK:
				stuck_attack = stuck_attack + 1 if was_attack else 1
				max_attack_steps = maxi(max_attack_steps, stuck_attack)
			else:
				stuck_attack = 0
		ctx.check(not seen.is_empty(), "'%s' ataca em 40 s simulados (%s)" % [id, str(seen)])
		var longest: float = 0.0
		for a: EnemyAttack in d.all_attacks():
			longest = maxf(longest, a.windup)
		longest = maxf(longest, d.windup)
		ctx.check(float(max_attack_steps) * DT <= longest + 0.1, "'%s': telegrafo nunca passa de %.2f s (max %.2f)" % [id, longest, float(max_attack_steps) * DT])
	# chefe/mini-chefe a pe: varios ataques distintos ao longo do tempo (ciclo de ataques)
	for id: StringName in [&"blight_treant", &"thorn_alpha"]:
		var ai: EnemyAI = _ai_for(id, 21)
		var kinds: Dictionary = {}
		ai.attack_released.connect(func() -> void: kinds[ai.current_attack.id] = true)
		for i: int in 60 * 60:
			ai.tick(DT, Vector3.ZERO, Vector3(3.0, 0, 0), true)
		ctx.check(kinds.size() >= 2, "'%s' fase 0 alterna ataques (%s)" % [id, str(kinds.keys())])


func _test_boss_cadence(ctx: Object) -> void:
	# Ritmo: o chefe nunca ataca duas vezes seguidas mais rapido que o menor cooldown+windup.
	var ai: EnemyAI = _ai_for(&"blight_treant", 31)
	var times: Array[float] = []
	var clock: Array[float] = [0.0]
	ai.attack_released.connect(func() -> void: times.append(clock[0]))
	for i: int in 60 * 60:
		ai.tick(DT, Vector3.ZERO, Vector3(2.5, 0, 0), true)
		clock[0] += DT
	var min_gap: float = INF
	for i: int in range(1, times.size()):
		min_gap = minf(min_gap, times[i] - times[i - 1])
	ctx.check(times.size() >= 10, "chefe ataca regularmente em 60 s (%d golpes)" % times.size())
	ctx.check(min_gap >= 1.8 + 0.8 - 0.1, "intervalo minimo entre golpes >= cooldown+windup (%.2f s)" % min_gap)
