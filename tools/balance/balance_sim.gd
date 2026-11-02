extends SceneTree
## E6.5: CLI do simulador de balanceamento (a logica fica em balance_core.gd, class_name BalanceSim, tambem usada pelos testes).
## Uso (raiz do projeto):
##   $G --headless --path . --script res://tools/balance/balance_sim.gd -- --label=before --out=docs/balance/e6_before.json [--quick]
##   $G --headless --path . --script res://tools/balance/balance_sim.gd -- --evaluate=docs/balance/e6_before.json --out=docs/balance/e6_before.json
## `--quick` reduz amostras (testes). `--evaluate` so reavalia os criterios de um resultado ja medido com a configuracao atual.
## `--config=<res://...>` usa outra configuracao. Codigo de saida 0 (medicao concluida; veja as linhas FALHA), 2 em erro de uso.

func _initialize() -> void:
	quit(_main(_parse_args()))


func _parse_args() -> Dictionary:
	var out: Dictionary = {}
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv: PackedStringArray = a.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1] if kv.size() > 1 else "1"
	return out


func _main(args: Dictionary) -> int:
	var sim: BalanceSim = BalanceSim.new()
	if not sim.load_config(String(args.get("config", BalanceSim.DEFAULT_CONFIG))):
		printerr("config invalida")
		return 2
	if args.has("evaluate"):
		var prev: Variant = BalanceSim.read_json(String(args["evaluate"]))
		if typeof(prev) != TYPE_DICTIONARY:
			printerr("--evaluate: JSON invalido")
			return 2
		var res: Dictionary = prev
		sim.setup()
		res["criteria"] = sim.evaluate(res)
		return _write_out(res, args)
	sim.quick = args.has("quick")
	return _write_out(sim.run_all(String(args.get("label", "run"))), args)


func _write_out(res: Dictionary, args: Dictionary) -> int:
	var text: String = JSON.stringify(res, "  ", true)
	if args.has("out"):
		var f: FileAccess = FileAccess.open(String(args["out"]), FileAccess.WRITE)
		if f == null:
			printerr("nao foi possivel escrever ", args["out"])
			return 2
		f.store_string(text + "\n")
		f.close()
		print("escrito: ", args["out"])
	var failed: int = 0
	for c: Variant in (res.get("criteria", []) as Array):
		var d: Dictionary = c
		print("%s  %s  %s" % ["OK   " if bool(d["pass"]) else "FALHA", String(d["id"]), String(d["detail"])])
		if not bool(d["pass"]):
			failed += 1
	print("criterios: %d, falhas: %d" % [(res.get("criteria", []) as Array).size(), failed])
	return 0
