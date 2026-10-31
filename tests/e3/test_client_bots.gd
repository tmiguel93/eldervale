extends RefCounted
## BotScript, BotResult (JSON), HUD, constantes de acao vs Protocol.


func run(ctx: Object) -> void:
	ctx.check(LocalInput.ACTION_ATTACK == Protocol.ACTION_ATTACK and LocalInput.ACTION_SKILL_1 == Protocol.ACTION_SKILL_1 \
		and LocalInput.ACTION_SKILL_2 == Protocol.ACTION_SKILL_2 and LocalInput.ACTION_DODGE == Protocol.ACTION_DODGE, "bots: acoes iguais ao Protocol")
	ctx.check(is_equal_approx(LocalInput.normalize_yaw(4.0), 4.0 - TAU) and LocalInput.normalize_yaw(NAN) == 0.0, "bots: normalize_yaw")

	for n: String in BotScript.NAMES:
		ctx.check(BotScript.is_known(n), "bots: conhecido " + n)
	ctx.check(not BotScript.is_known("nope"), "bots: desconhecido rejeitado")

	ctx.check(BotScript.step("idle", 1.0, 1).is_empty(), "bots: idle nao envia")
	var w0: Vector2 = BotScript.step("walk_square", 0.1, 1)[0]["move"]
	var w1: Vector2 = BotScript.step("walk_square", 1.6, 1)[0]["move"]
	var w4: Vector2 = BotScript.step("walk_square", 6.1, 1)[0]["move"]
	ctx.check(w0 != w1 and w0 == w4, "bots: walk_square muda de direcao e fecha o ciclo")
	var atk_a: bool = false
	var atk_b: bool = false
	for i: int in 40:
		var acts: int = int(BotScript.step("attack_loop", float(i) * 0.1, i)[0]["actions"])
		atk_a = atk_a or acts == 1
		atk_b = atk_b or acts == 0
	ctx.check(atk_a and atk_b, "bots: attack_loop ataca periodicamente")
	ctx.check((BotScript.step("cheat_speed", 0.5, 1)[0]["move"] as Vector2).length() > 9.0, "bots: cheat_speed envia modulo 10")
	ctx.check((BotScript.step("cheat_speed", 3.0, 1)[0]["move"] as Vector2).length() <= 1.001, "bots: cheat_speed depois valido")

	var saw_nan: bool = false
	var saw_bits: bool = false
	var saw_repeat: bool = false
	var max_burst: int = 0
	for tk: int in range(30, 38):
		var items: Array[Dictionary] = BotScript.step("invalid_flood", 2.0, tk)
		max_burst = maxi(max_burst, items.size())
		for it: Dictionary in items:
			if not (it["move"] as Vector2).is_finite():
				saw_nan = true
			if (int(it["actions"]) & ~15) != 0:
				saw_bits = true
			if it.has("seq_repeat"):
				saw_repeat = true
	ctx.check(saw_nan and saw_bits and saw_repeat and max_burst >= 10, "bots: invalid_flood cobre NaN, bits, seq repetido e rajada")
	ctx.check(BotScript.hello_version("bad_version", 1) != 1 and BotScript.hello_version("idle", 1) == 1, "bots: bad_version usa versao errada")

	# resultado -> JSON -> parse
	var r: BotResult = BotResult.new()
	r.bot = "walk_square"
	r.on_welcome(3, 30)
	r.on_snapshot(1000.0, 10, [{"id": 3, "kind": 1, "type": "player"}, {"id": 9, "kind": 2, "type": "grunt"}])
	r.on_snapshot(1090.0, 11, [{"id": 3, "kind": 1, "type": "player"}])
	r.on_snapshot(1130.0, 12, [])
	r.on_event(3)
	r.on_event(3)
	r.on_event(4)
	r.on_rtt(40.0)
	r.on_rtt(60.0)
	r.sample_position(0.0, Vector3(1, 0, 2))
	r.sample_position(0.2, Vector3(9, 9, 9))
	r.sample_position(0.6, Vector3(2, 0, 2))
	r.on_reject(1, "versao")
	r.disconnected = true
	var parsed: Variant = JSON.parse_string(r.to_json())
	ctx.check(parsed is Dictionary, "bots: JSON valido")
	var d: Dictionary = parsed
	ctx.check(d["connected"] == true and int(d["welcome"]["player_id"]) == 3 and int(d["welcome"]["tick_rate"]) == 30, "bots: connected/welcome")
	ctx.check(int(d["rejected"]["code"]) == 1 and d["disconnected"] == true, "bots: rejected/disconnected")
	ctx.check(int(d["snapshots_received"]) == 3 and int(d["last_server_tick"]) == 12 and absf(float(d["max_snapshot_gap_ms"]) - 90.0) < 0.01, "bots: snapshots, tick, gap")
	ctx.check(d["entities_seen"].has("3") and d["entities_seen"].has("9") and int(d["entities_seen"]["9"]["kind"]) == 2, "bots: entidades vistas")
	ctx.check(int(d["events_by_kind"]["3"]) == 2 and int(d["events_by_kind"]["4"]) == 1, "bots: eventos por kind")
	ctx.check(absf(float(d["rtt_avg_ms"]) - 50.0) < 0.001, "bots: rtt medio")
	ctx.check((d["positions"] as Array).size() == 2, "bots: posicoes amostradas (0.5 s)")
	ctx.check(BotResult.new().rtt_avg_ms() == -1.0, "bots: sem amostras rtt = -1")

	# HUD
	var ss: ClientSession = ClientSession.new()
	var txt: String = ClientHud.format_status(ss)
	ctx.check(txt.contains("Estado") and txt.contains("RTT: -") and txt.contains("Entidades: 0"), "bots: HUD formata estado inicial")
