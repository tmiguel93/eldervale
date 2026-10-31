extends RefCounted
## ResourcePool e CooldownTracker.

const EPS: float = 0.0001


func _near(a: float, b: float) -> bool:
	return absf(a - b) < EPS


func run(ctx: Object) -> void:
	var stats: StatBlock = StatBlock.new()
	stats.max_resource = 50.0
	stats.resource_regen = 5.0
	var pool: ResourcePool = ResourcePool.new()
	pool.setup(stats)
	ctx.check(_near(pool.current, 50.0), "pool inicia cheio")
	ctx.check(pool.can_afford(50.0) and not pool.can_afford(50.1), "can_afford limite exato")
	ctx.check(not pool.can_afford(-1.0), "custo negativo nao e aceito")
	var events: Array[float] = []
	pool.changed.connect(func(c: float, _m: float) -> void: events.append(c))
	ctx.check(pool.spend(20.0) and _near(pool.current, 30.0), "spend consome")
	ctx.check(events.size() == 1, "spend emite changed")
	ctx.check(not pool.spend(31.0) and _near(pool.current, 30.0), "spend insuficiente falha SEM consumir")
	pool.tick(2.0)
	ctx.check(_near(pool.current, 40.0), "regen por segundo (5/s * 2s)")
	pool.tick(100.0)
	ctx.check(_near(pool.current, 50.0), "regen limitada ao maximo")
	pool.tick(1.0)
	pool.spend(50.0)
	ctx.check(pool.spend(0.0), "custo 0 sempre ok")
	pool.spend(0.0)
	var bigger: StatBlock = stats.copy()
	bigger.max_resource = 80.0
	pool.set_stats(bigger)
	ctx.check(_near(pool.max_value(), 80.0), "set_stats atualiza maximo")

	var cd: CooldownTracker = CooldownTracker.new()
	var finished: Array[StringName] = []
	cd.cooldown_finished.connect(func(id: StringName) -> void: finished.append(id))
	ctx.check(cd.is_ready(&"a"), "id desconhecido esta pronto")
	cd.start(&"a", 1.0)
	cd.start(&"b", 2.0)
	ctx.check(not cd.is_ready(&"a") and _near(cd.remaining(&"a"), 1.0), "start: em cooldown")
	cd.tick(0.4)
	ctx.check(_near(cd.remaining(&"a"), 0.6) and not cd.is_ready(&"a"), "tick reduz remaining")
	cd.tick(0.6)
	ctx.check(cd.is_ready(&"a") and cd.remaining(&"a") == 0.0, "pronto ao zerar")
	ctx.check(not cd.is_ready(&"b") and finished == [&"a"], "outro id independente; sinal emitido")
	cd.start(&"c", 0.0)
	ctx.check(cd.is_ready(&"c"), "cooldown 0 = pronto")
