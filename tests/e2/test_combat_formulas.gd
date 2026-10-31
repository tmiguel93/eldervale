extends RefCounted
## DamageCalculator, HealthComponent (morte unica, cura, invulnerabilidade).

const EPS: float = 0.0001


func _near(a: float, b: float) -> bool:
	return absf(a - b) < EPS


func run(ctx: Object) -> void:
	# formula: max(0, (amount - defense) * (1 - resistance))
	ctx.check(_near(DamageCalculator.compute(20.0, 5.0, 0.0), 15.0), "dano: defesa plana (20-5=15)")
	ctx.check(_near(DamageCalculator.compute(20.0, 0.0, 0.5), 10.0), "dano: resistencia 50%")
	ctx.check(_near(DamageCalculator.compute(20.0, 10.0, 0.5), 5.0), "dano: defesa e depois resistencia")
	ctx.check(_near(DamageCalculator.compute(3.0, 50.0, 0.0), DamageCalculator.MIN_DAMAGE), "dano: minimo quando defesa excede")
	ctx.check(_near(DamageCalculator.compute(3.0, 50.0, 0.0, false, 0.0), 0.0), "dano: minimo configuravel (0 permite zero)")
	ctx.check(_near(DamageCalculator.compute(3.0, 50.0, 0.0, false, 2.5), 2.5), "dano: minimo configuravel (2.5)")
	ctx.check(_near(DamageCalculator.compute(0.0, 0.0, 0.0), 0.0), "dano: amount 0 -> 0 (sem minimo)")
	ctx.check(_near(DamageCalculator.compute(-5.0, 0.0, 0.0), 0.0), "dano: amount negativo -> 0")
	ctx.check(_near(DamageCalculator.compute(10.0, 0.0, 0.0, true), 10.0 * DamageCalculator.CRIT_MULTIPLIER), "dano: critico multiplica")
	ctx.check(_near(DamageCalculator.compute(10.0, 5.0, 0.0, true), 10.0 * DamageCalculator.CRIT_MULTIPLIER - 5.0), "dano: critico antes da defesa")
	ctx.check(_near(DamageCalculator.compute(100.0, 0.0, 5.0), DamageCalculator.MIN_DAMAGE), "dano: resistencia > 1 limitada (sem dano negativo)")
	ctx.check(_near(DamageCalculator.compute(100.0, 0.0, -1.0), 100.0), "dano: resistencia negativa limitada a 0")

	var stats: StatBlock = StatBlock.new()
	stats.max_health = 50.0
	stats.defense = 2.0
	stats.resistance = 0.25
	var info: DamageInfo = DamageInfo.make(10.0, null, 1)
	ctx.check(_near(DamageCalculator.from_info(info, stats), 6.0), "from_info usa defense/resistance do StatBlock")
	info.is_critical = true
	ctx.check(_near(DamageCalculator.from_info(info, stats), (15.0 - 2.0) * 0.75), "from_info respeita is_critical")
	ctx.check(_near(DamageCalculator.from_info(info, null), 15.0), "from_info com stats nulo")

	# HealthComponent
	var hc: HealthComponent = HealthComponent.new()
	hc.stats = stats
	hc.reset()
	ctx.check(_near(hc.current_health, 50.0), "vida inicia cheia")
	var state: Dictionary = {"damaged": 0, "died": 0, "last": 0.0, "src": null}
	hc.damaged.connect(func(_i: DamageInfo, f: float) -> void:
		state["damaged"] += 1
		state["last"] = f)
	hc.died.connect(func(s: Node) -> void:
		state["died"] += 1
		state["src"] = s)
	var attacker: Node = Node.new()
	var applied: float = hc.apply_damage(DamageInfo.make(10.0, attacker, 1))
	ctx.check(_near(applied, 6.0) and _near(hc.current_health, 44.0), "apply_damage retorna e aplica o dano final")
	ctx.check(state["damaged"] == 1 and _near(float(state["last"]), 6.0), "sinal damaged com valor final")
	hc.invulnerable = true
	ctx.check(hc.apply_damage(DamageInfo.make(10.0, attacker, 2)) == 0.0 and _near(hc.current_health, 44.0), "invulneravel: sem dano")
	ctx.check(state["damaged"] == 1, "invulneravel: sem sinal damaged")
	hc.invulnerable = false
	ctx.check(_near(hc.heal(100.0), 6.0) and _near(hc.current_health, 50.0), "cura limitada ao maximo")
	hc.apply_damage(DamageInfo.make(1000.0, attacker, 3))
	ctx.check(hc.is_dead and hc.current_health == 0.0 and state["died"] == 1, "morte: died uma vez")
	ctx.check(state["src"] == attacker, "died carrega a fonte")
	hc.apply_damage(DamageInfo.make(1000.0, attacker, 4))
	hc.apply_damage(DamageInfo.make(1000.0, attacker, 5))
	ctx.check(state["died"] == 1, "morte unica: nao dispara died de novo")
	ctx.check(hc.heal(10.0) == 0.0 and hc.current_health == 0.0, "morto nao e curado")
	hc.reset()
	ctx.check(not hc.is_dead and _near(hc.current_health, 50.0), "reset revive com vida cheia")
	hc.apply_damage(DamageInfo.make(1000.0, attacker, 6))
	ctx.check(state["died"] == 2, "apos reset pode morrer de novo")
	attacker.free()
	hc.free()
