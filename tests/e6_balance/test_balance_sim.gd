extends RefCounted
## E6.5 - simulador de balanceamento (BalanceSim): estrutura do resultado, determinismo, modelo vs conta a mao e
## criterios-alvo satisfeitos pelos dados atuais (modo rapido; a medicao completa fica em docs/E6_BALANCE.md).


func run(ctx: Object) -> void:
	var sim: BalanceSim = BalanceSim.new()
	ctx.check(sim.load_config(), "configuracao data/balance/balance_config.json carrega")
	_test_config(ctx, sim)
	sim.quick = true
	var res: Dictionary = sim.run_all("test")
	_test_structure(ctx, res)
	_test_criteria(ctx, res)
	_test_determinism(ctx, sim, res)
	_test_model(ctx, sim)


func _test_config(ctx: Object, sim: BalanceSim) -> void:
	var c: Dictionary = sim.cfg["criteria"] as Dictionary
	for key: String in ["boss_ttk_1p_window_s", "boss_ttk_4p_window_s", "loot_boss_legendary_kills_window", "unique_kills_window"]:
		var w: Array = c[key] as Array
		ctx.check(w.size() == 2 and float(w[0]) < float(w[1]), "janela %s ordenada" % key)
	ctx.check(float(c["class_dps_parity_pct"]) > 0.0 and int(sim.cfg["seed"]) > 0, "paridade e semente definidas")
	sim.setup()
	var bad: Array[String] = []
	for cid: String in (sim.cfg["builds"] as Dictionary).keys():
		for b: Variant in (sim.cfg["builds"] as Dictionary)[cid]:
			var r: Dictionary = sim.alloc_build(cid, b as Dictionary, 20)
			for why: Variant in (r["skipped"] as Array):
				if String(why).contains("unknown"):
					bad.append("%s/%s:%s" % [cid, String((b as Dictionary).get("id", "?")), String(why)])
			if int(r["spent"]) > int(r["avail"]):
				bad.append("%s: gasta mais que os pontos" % cid)
	ctx.check(bad.is_empty(), "todas as builds alocam sem no desconhecido (falhas: %s)" % str(bad))


func _test_structure(ctx: Object, res: Dictionary) -> void:
	for k: String in ["meta", "xp", "enemies", "classes", "uniques", "talents", "loot", "criteria"]:
		ctx.check(res.has(k), "resultado tem a secao '%s'" % k)
	ctx.check(not JSON.stringify(res).is_empty() and JSON.parse_string(JSON.stringify(res)) is Dictionary, "resultado serializa para JSON")
	for c: Variant in res["criteria"]:
		ctx.check((c as Dictionary).has("id") and (c as Dictionary).has("pass") and (c as Dictionary).has("detail"), "criterio %s com id/pass/detail" % str((c as Dictionary).get("id")))
		break
	ctx.check((res["criteria"] as Array).size() >= 40, "numero de criterios avaliados (%d)" % (res["criteria"] as Array).size())


func _test_criteria(ctx: Object, res: Dictionary) -> void:
	var failed: Array[String] = []
	for c: Variant in res["criteria"]:
		if not bool((c as Dictionary)["pass"]):
			failed.append("%s: %s" % [(c as Dictionary)["id"], (c as Dictionary)["detail"]])
	ctx.check(failed.is_empty(), "dados atuais satisfazem todos os criterios de balanceamento (falhas: %s)" % str(failed))


func _test_determinism(ctx: Object, sim: BalanceSim, res: Dictionary) -> void:
	var a: Dictionary = sim.roll_gear_set("rare", 10, "k1")
	var b: Dictionary = sim.roll_gear_set("rare", 10, "k1")
	var c: Dictionary = sim.roll_gear_set("rare", 10, "k2")
	ctx.check(JSON.stringify(a) == JSON.stringify(b), "mesmo seed_key -> mesmo conjunto de equipamentos")
	ctx.check(JSON.stringify(a) != JSON.stringify(c), "seed_key diferente -> conjunto diferente")
	var res2: Dictionary = sim.run_all("test")
	ctx.check(JSON.stringify(res["classes"]) == JSON.stringify(res2["classes"]) and JSON.stringify(res["loot"]) == JSON.stringify(res2["loot"]), "duas execucoes rapidas dao resultados identicos (determinismo)")


func _test_model(ctx: Object, sim: BalanceSim) -> void:
	# conta a mao: alvo parado, guerreiro nivel 1 sem equipamento, so ataque basico -> dano por golpe = max(1, ap*mult - def)
	var d: float = DamageCalculator.compute(100.0, 6.0, 0.0)
	ctx.check(is_equal_approx(d, 94.0), "DamageCalculator: (100-6)*(1-0) = 94")
	ctx.check(is_equal_approx(DamageCalculator.compute(3.0, 50.0, 0.0), 1.0), "dano minimo 1")
	var st: TalentState = TalentState.new()
	var eq: Equipment = sim.make_equipment({})
	var ch: Dictionary = sim.make_character("warrior", 5, st, eq)
	var ev: Dictionary = sim.eval_character(ch, ["melee_grunt"], false)
	ctx.check(not ev.is_empty(), "eval_character devolve medidas")
	var ev2: Dictionary = sim.eval_character(sim.make_character("warrior", 5, TalentState.new(), sim.make_equipment({})), ["melee_grunt"], false)
	ctx.check(JSON.stringify(ev) == JSON.stringify(ev2), "eval_character determinista para o mesmo personagem")
