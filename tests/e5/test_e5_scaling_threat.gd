extends RefCounted
## E5.2: escala de dificuldade (funcao pura com teto), fases (controle puro), ameaca e escolha de alvo.
## Deterministico, sem fisica.


func _phases(thresholds: Array) -> Array[EnemyPhase]:
	var out: Array[EnemyPhase] = []
	for t: float in thresholds:
		var p: EnemyPhase = EnemyPhase.new()
		p.health_threshold = t
		out.append(p)
	return out


func _cand(id: int, x: float) -> Dictionary:
	return {"id": id, "pos": Vector3(x, 0, 0)}


func run(ctx: Object) -> void:
	var tree: SceneTree = ctx as SceneTree
	await tree.physics_frame
	await _test_difficulty(ctx, tree)
	_test_phase_controller(ctx)
	_test_threat(ctx)
	_test_selector(ctx)
	_test_protocol(ctx)


func _test_difficulty(ctx: Object, tree: SceneTree) -> void:
	var d: DifficultyScaling = DifficultyScaling.load_default()
	ctx.check(d.id == &"greenwood_coop" and d.validate().is_empty(), "escala carregada dos dados e valida")
	ctx.check(is_equal_approx(d.health_mult(1), 1.0) and is_equal_approx(d.damage_mult(1), 1.0), "1 jogador => 1.0x vida e dano (baseline)")
	var prev_h: float = 0.0
	var prev_d: float = 0.0
	var mono: bool = true
	for n: int in range(1, 5):
		var h: float = d.health_mult(n)
		var dm: float = d.damage_mult(n)
		if h < prev_h or dm < prev_d:
			mono = false
		prev_h = h
		prev_d = dm
	ctx.check(mono, "vida e dano nao diminuem com mais jogadores")
	ctx.check(d.health_mult(4) > d.health_mult(2) and d.damage_mult(4) > d.damage_mult(2), "4 jogadores > 2 jogadores")
	ctx.check(d.damage_mult(4) < d.health_mult(4), "dano escala menos que vida (controlado)")
	ctx.check(d.health_mult(4, &"boss") > d.health_mult(4, &"normal"), "chefe ganha mais vida que comum")
	ctx.check(d.health_mult(4, &"mini_boss") == d.health_mult(4, &"boss"), "mini-chefe usa o bonus de chefe")
	ctx.check(d.health_mult(0) == d.health_mult(1) and d.health_mult(99) == d.health_mult(d.max_players), "jogadores fora de faixa sao limitados")
	ctx.check(d.health_mult(4, &"boss") <= d.max_health_mult and d.damage_mult(4) <= d.max_damage_mult, "respeita tetos dos dados")
	# dados absurdos: teto absoluto do codigo
	var wild: DifficultyScaling = DifficultyScaling.new()
	wild.health_bonus_per_player = 100.0
	wild.boss_health_bonus_per_player = 100.0
	wild.damage_bonus_per_player = 100.0
	wild.max_health_mult = 999.0
	wild.max_damage_mult = 999.0
	ctx.check(wild.health_mult(4, &"boss") <= DifficultyScaling.HARD_MAX_HEALTH_MULT and wild.damage_mult(4) <= DifficultyScaling.HARD_MAX_DAMAGE_MULT, "teto absoluto vale mesmo com dados absurdos")
	var errs: Array[String] = wild.validate()
	ctx.check(errs.size() >= 2, "validacao rejeita tetos acima do limite do codigo (%d erros)" % errs.size())
	var neg: DifficultyScaling = DifficultyScaling.new()
	neg.health_bonus_per_player = -1.0
	ctx.check(not neg.validate().is_empty() and neg.health_mult(4) >= 1.0, "bonus negativo invalido e nunca reduz abaixo de 1.0")
	# Enemy.set_difficulty preserva a proporcao de vida
	var enemy: Enemy = (load(EnemyCatalog.scene_path(&"bark_brute")) as PackedScene).instantiate() as Enemy
	var holder: Node3D = Node3D.new()
	tree.root.add_child(holder)
	holder.add_child(enemy)
	enemy.set_physics_process(false)
	await tree.physics_frame
	var base_max: float = enemy.data.stats.max_health
	enemy.health.current_health = base_max * 0.5
	enemy.set_difficulty(2.0, 1.3)
	ctx.check(is_equal_approx(enemy.health.max_health(), base_max * 2.0) and is_equal_approx(enemy.health.current_health, base_max), "set_difficulty: vida maxima x2 mantendo 50%")
	ctx.check(is_equal_approx(enemy.data.stats.max_health, base_max), "recurso EnemyData intacto")
	enemy.set_difficulty(1.0, 1.0)
	ctx.check(is_equal_approx(enemy.health.max_health(), base_max) and is_equal_approx(enemy.health.current_health, base_max * 0.5), "voltar a 1 jogador reduz sem curar")
	holder.queue_free()
	await tree.physics_frame


func _test_phase_controller(ctx: Object) -> void:
	var ph: Array[EnemyPhase] = _phases([1.0, 0.66, 0.33])
	ctx.check(EnemyPhaseController.index_for_fraction(ph, 1.0) == 0 and EnemyPhaseController.index_for_fraction(ph, 0.67) == 0, "100%..67% => fase 0")
	ctx.check(EnemyPhaseController.index_for_fraction(ph, 0.66) == 1 and EnemyPhaseController.index_for_fraction(ph, 0.34) == 1, "66%..34% => fase 1 (limiar inclusivo)")
	ctx.check(EnemyPhaseController.index_for_fraction(ph, 0.33) == 2 and EnemyPhaseController.index_for_fraction(ph, 0.0) == 2, "<=33% => fase 2")
	var c: EnemyPhaseController = EnemyPhaseController.new()
	c.setup(ph)
	ctx.check(c.advance(0.9).is_empty() and c.index == 0, "sem cruzar limiar: nada")
	ctx.check(Array(c.advance(0.6)) == [1], "cruza 66%: entra na fase 1")
	ctx.check(c.advance(0.6).is_empty(), "repetir a mesma vida nao reentra")
	ctx.check(c.advance(0.9).is_empty() and c.index == 1, "vida subindo nao volta de fase (monotonico)")
	var c2: EnemyPhaseController = EnemyPhaseController.new()
	c2.setup(ph)
	ctx.check(Array(c2.advance(0.1)) == [1, 2], "golpe que cruza dois limiares entra nas duas fases, em ordem")
	c2.reset()
	ctx.check(c2.index == 0 and Array(c2.advance(0.5)) == [1], "reset volta a fase 0")
	ctx.check(EnemyPhaseController.new().advance(0.1).is_empty(), "sem fases: nada acontece")


func _test_threat(ctx: Object) -> void:
	var t: ThreatTable = ThreatTable.new()
	t.add(1, 10.0)
	t.add(1, 5.0)
	t.add(2, 4.0)
	t.add(0, 99.0)
	t.add(3, -5.0)
	t.add(3, NAN)
	ctx.check(is_equal_approx(t.get_threat(1), 15.0) and is_equal_approx(t.get_threat(2), 4.0), "ameaca acumula")
	ctx.check(t.get_threat(0) == 0.0 and t.get_threat(3) == 0.0, "ids invalidos/valores negativos ou NaN ignorados")
	t.decay(0.5, 1.0)
	ctx.check(is_equal_approx(t.get_threat(1), 7.5), "decaimento proporcional")
	t.decay(1.0, 1.0)
	ctx.check(t.is_empty(), "decaimento total esvazia a tabela")
	t.add(2, 3.0)
	t.remove(2)
	ctx.check(t.get_threat(2) == 0.0, "remove apaga a entrada")


func _test_selector(ctx: Object) -> void:
	var origin: Vector3 = Vector3.ZERO
	ctx.check(TargetSelector.pick([], origin, ThreatTable.new()) == 0, "sem candidatos: 0")
	var one: Array = [_cand(7, 20.0)]
	ctx.check(TargetSelector.pick(one, origin, ThreatTable.new()) == 7, "1 jogador: ele")
	var four: Array = [_cand(1, 12.0), _cand(2, 5.0), _cand(3, 8.0), _cand(4, 30.0)]
	var none: ThreatTable = ThreatTable.new()
	ctx.check(TargetSelector.pick(four, origin, none) == 2, "sem ameaca: o mais proximo (de 4)")
	ctx.check(TargetSelector.pick([_cand(5, 4.0), _cand(2, 4.0)], origin, none) == 2, "empate de distancia: menor id")
	var th: ThreatTable = ThreatTable.new()
	th.add(4, 50.0)
	th.add(1, 10.0)
	ctx.check(TargetSelector.pick(four, origin, th) == 4, "com ameaca: o de maior ameaca, mesmo distante")
	ctx.check(TargetSelector.pick(four, origin, th, 0, 20.0) == 1, "ameaca alem do leash e ignorada (usa o de ameaca valida)")
	th.remove(1)
	ctx.check(TargetSelector.pick(four, origin, th, 0, 20.0) == 2, "so ameaca fora do leash => cai para o mais proximo")
	# histerese: nao troca por pouco
	var h: ThreatTable = ThreatTable.new()
	h.add(1, 100.0)
	h.add(2, 110.0)
	ctx.check(TargetSelector.pick(four, origin, h, 1) == 1, "histerese: 110 nao supera 100 x 1.25 (mantem o atual)")
	h.add(2, 40.0)
	ctx.check(TargetSelector.pick(four, origin, h, 1) == 2, "histerese: 150 supera 125 (troca)")
	# alvo atual morto (fora da lista): escolhe entre os vivos
	var alive: Array = [_cand(2, 5.0), _cand(3, 8.0)]
	ctx.check(TargetSelector.pick(alive, origin, h, 1) == 2, "alvo atual morto: reescolhe entre vivos")
	var h2: ThreatTable = ThreatTable.new()
	h2.add(1, 500.0) # jogador 1 ja morreu
	ctx.check(TargetSelector.pick(alive, origin, h2, 1) == 2, "ameaca de jogador morto/ausente nao prende o alvo")


func _test_protocol(ctx: Object) -> void:
	var e: Dictionary = {"id": 3, "kind": Protocol.KIND_ENEMY, "pos": Vector3(1, 0, 2), "yaw": 0.1, "hp": 5.0, "max_hp": 9.0, "state": 2, "type": "blight_treant"}
	ctx.check(Protocol.validate_entity_dict(e), "entidade sem campos E5.2 continua valida (compatibilidade)")
	e["phase"] = 2
	e["atk"] = "seed_volley"
	ctx.check(Protocol.validate_entity_dict(e), "entidade com phase/atk validos")
	var bad: Array[Dictionary] = [{"phase": -1}, {"phase": 99}, {"phase": 1.5}, {"phase": "1"}, {"atk": 5}, {"atk": "x".repeat(33)}]
	var accepted: int = 0
	for patch: Dictionary in bad:
		var m: Dictionary = e.duplicate()
		m.merge(patch, true)
		if Protocol.validate_entity_dict(m):
			accepted += 1
	ctx.check(accepted == 0, "phase/atk malformados rejeitados")
	ctx.check(Protocol.EVENT_ENEMY_PHASE == 7 and Protocol.VERSION == 2, "EVENT_ENEMY_PHASE=7 e VERSION segue 2")
