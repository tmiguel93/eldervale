extends RefCounted
## RateLimiter: burst e reposicao por tempo.


func run(ctx: Object) -> void:
	var rl: RateLimiter = RateLimiter.new(10.0, 5)
	var allowed: int = 0
	for n: int in 20:
		if rl.allow(1000):
			allowed += 1
	ctx.check(allowed == 5, "burst: exatamente 5 de 20 no mesmo instante (%d)" % allowed)
	ctx.check(not rl.allow(1050), "50 ms a 10/s: ainda sem token (0.5)")
	ctx.check(rl.allow(1100), "100 ms a 10/s: 1 token reposto")
	ctx.check(not rl.allow(1100), "sem token extra no mesmo instante")
	ctx.check(rl.allow(1200), "mais 100 ms: outro token")

	var rl2: RateLimiter = RateLimiter.new(10.0, 3)
	for n: int in 3:
		rl2.allow(0)
	var after: int = 0
	for n: int in 10:
		if rl2.allow(10000):
			after += 1
	ctx.check(after == 3, "reposicao limitada ao burst (%d)" % after)

	var rl3: RateLimiter = RateLimiter.new(2.0, 1)
	var ok_count: int = 0
	for t: int in range(0, 10000, 100):
		if rl3.allow(t):
			ok_count += 1
	ctx.check(ok_count >= 19 and ok_count <= 21, "taxa sustentada ~2/s em 10 s (%d)" % ok_count)

	var rl4: RateLimiter = RateLimiter.new(10.0, 1)
	rl4.allow(5000)
	ctx.check(not rl4.allow(4000), "relogio andando para tras nao repoe tokens")
	var rl5: RateLimiter = RateLimiter.new(0.0, 2)
	ctx.check(rl5.allow(0) and rl5.allow(0) and not rl5.allow(100000), "taxa 0: so o burst inicial")
