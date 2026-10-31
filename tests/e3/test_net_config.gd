extends RefCounted
## NetConfig: parse, faixas, ambiente.


func run(ctx: Object) -> void:
	var d: NetConfig = NetConfig.parse(PackedStringArray())
	ctx.check(d.errors.is_empty() and d.port == 24680 and d.max_players == 4 and d.tick_rate == 30 and d.snapshot_rate == 15, "defaults seguros")
	ctx.check(d.role == "client" and d.host == "127.0.0.1" and d.sim_latency_ms == 0 and d.sim_loss_pct == 0.0 and d.bot_script == "", "defaults de role/host/sim")

	var a: NetConfig = NetConfig.parse(PackedStringArray([
		"--role", "server", "--port", "30000", "--max-players", "2", "--tick-rate", "60", "--snapshot-rate", "20",
		"--sim-latency-ms", "80", "--sim-jitter-ms", "10", "--sim-loss-pct", "2.5",
		"--host", "game.example.com", "--name", "Ana", "--bot", "res://bot.gd", "--out", "out.json"]))
	ctx.check(a.errors.is_empty(), "parse completo sem erros: " + ", ".join(a.errors))
	ctx.check(a.role == "server" and a.port == 30000 and a.max_players == 2 and a.tick_rate == 60 and a.snapshot_rate == 20, "valores basicos")
	ctx.check(a.sim_latency_ms == 80 and a.sim_jitter_ms == 10 and is_equal_approx(a.sim_loss_pct, 2.5), "valores de simulacao")
	ctx.check(a.host == "game.example.com" and a.name == "Ana" and a.bot_script == "res://bot.gd" and a.out_path == "out.json", "host/name/bot/out")

	var e: NetConfig = NetConfig.parse(PackedStringArray(["--port=30001", "--sim_loss_pct=5"]))
	ctx.check(e.port == 30001 and e.sim_loss_pct == 5.0 and e.errors.is_empty(), "formato --k=v e underscore")

	var bad: NetConfig = NetConfig.parse(PackedStringArray(["--port", "80", "--max-players", "0", "--tick-rate", "abc", "--sim-loss-pct", "150", "--sim-latency-ms", "-5", "--name", "x<y", "--role", "admin"]))
	ctx.check(bad.port == 24680 and bad.max_players == 4 and bad.tick_rate == 30 and bad.sim_loss_pct == 0.0 and bad.sim_latency_ms == 0, "invalidos voltam ao default")
	ctx.check(bad.name == "Player" and bad.role == "client", "name/role invalidos voltam ao default")
	ctx.check(bad.errors.size() == 7, "7 erros listados (%d)" % bad.errors.size())
	ctx.check(NetConfig.parse(PackedStringArray(["--port", "65536"])).port == 24680, "porta > 65535 rejeitada")
	ctx.check(NetConfig.parse(PackedStringArray(["--port", "65535"])).port == 65535, "porta 65535 aceita")
	ctx.check(NetConfig.parse(PackedStringArray(["--sim-loss-pct", "nan"])).errors.size() == 1, "loss NaN rejeitado")

	var sr: NetConfig = NetConfig.parse(PackedStringArray(["--tick-rate", "20", "--snapshot-rate", "30"]))
	ctx.check(sr.snapshot_rate <= sr.tick_rate and sr.errors.size() == 1, "snapshot-rate > tick-rate corrigido")

	var u: NetConfig = NetConfig.parse(PackedStringArray(["--bogus", "1", "--port", "--host", "stray", "--sim-loss-pct"]))
	ctx.check(u.errors.size() >= 3, "chave desconhecida / sem valor / solto geram erros (%d)" % u.errors.size())

	var host_bad: NetConfig = NetConfig.parse(PackedStringArray(["--host", "a b;rm"]))
	ctx.check(host_bad.host == "127.0.0.1" and host_bad.errors.size() == 1, "host com caracteres invalidos rejeitado")

	# ambiente
	var env: Dictionary = {"ELDERVALE_PORT": "31000", "ELDERVALE_ROLE": "server", "ELDERVALE_NAME": "Envy", "ELDERVALE_SIM_LOSS_PCT": "1.5"}
	var ev: NetConfig = NetConfig.parse(PackedStringArray(), env)
	ctx.check(ev.port == 31000 and ev.role == "server" and ev.name == "Envy" and is_equal_approx(ev.sim_loss_pct, 1.5) and ev.errors.is_empty(), "ELDERVALE_* aplicados")
	var ov: NetConfig = NetConfig.parse(PackedStringArray(["--port", "32000"]), env)
	ctx.check(ov.port == 32000 and ov.role == "server", "argumento tem precedencia sobre ambiente")
	ctx.check(NetConfig.parse(PackedStringArray(), {"ELDERVALE_PORT": "x"}).errors.size() == 1, "ambiente invalido gera erro")
