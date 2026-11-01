extends RefCounted
## E5.3: o roteiro `world_tour` dos bots (puro, dirigido pelos dados do mundo) conclui o percurso
## hub -> selvagem -> ruinas (placas A e B, em ordem) -> salao, simulando portais e portao.


func run(ctx: Object) -> void:
	await (ctx as SceneTree).physics_frame
	ctx.check(BotScript.is_known("world_tour") and not BotScript.needs_backend("world_tour"), "world_tour e um bot conhecido e nao exige backend")
	var def: WorldDef = WorldDef.shared()
	var pos: Vector3 = def.get_zone("zone_hub").spawn_point("start", 0)
	var memo: Dictionary = {}
	var puzzle: PuzzleState = PuzzleState.from_zone(def.get_zone("zone_ruins"))
	var zones: Array[String] = ["zone_hub"]
	var plates_visited: Array[int] = []
	var done: bool = false
	var dt: float = 1.0 / 30.0
	var steps: int = 0
	while steps < 30 * 90 and not done:
		steps += 1
		var r: Dictionary = BotScript.world_tour_step(pos, memo)
		done = bool(r["done"])
		var mv: Vector2 = (r["items"][0] as Dictionary)["move"]
		var next: Vector3 = pos + PlayerMotion.world_direction(mv, 0.0) * 6.0 * dt
		var zid: String = def.zone_id_at(pos)
		# portal: teleporta como o servidor (instantaneo aqui)
		for p: Dictionary in def.get_zone(zid).portals:
			if Vector2(next.x - (p["pos"] as Vector3).x, next.z - (p["pos"] as Vector3).z).length() <= float(p["radius"]):
				next = def.get_zone(String(p["to_zone"])).spawn_point(String(p["to_spawn"]), 0)
				zones.append(String(p["to_zone"]))
				break
		# portao fechado bloqueia
		if puzzle != null and zid == "zone_ruins":
			var gate_x: float = (def.get_zone("zone_ruins").puzzle["gate_pos"] as Vector3).x
			if not puzzle.open and next.x > gate_x - 1.4:
				next.x = gate_x - 1.4
			if next.x > gate_x - 1.2 and next.x < gate_x + 1.2 and absf(next.z) > 3.0:
				next = pos # divisoria de pedra: so a abertura de 6 m do portao e passavel
			puzzle.update([next], dt)
			for i: int in 2:
				if puzzle.is_pressed(i) and not plates_visited.has(i):
					plates_visited.append(i)
		pos = next
	ctx.check(done, "bot concluiu o percurso em %.0f s simulados" % (float(steps) * dt))
	ctx.check(zones == (["zone_hub", "zone_wild", "zone_ruins"] as Array[String]), "zonas visitadas em ordem: %s" % str(zones))
	ctx.check(plates_visited == [0, 1] and puzzle.open, "placas pisadas na ordem A, B e o portao abriu (solo, dentro da janela)")
	ctx.check(pos.x > 395.0, "terminou no salao do chefe (x=%.1f)" % pos.x)
	# os relatorios do bot acumulam so eventos de mundo validos
	var res: BotResult = BotResult.new()
	res.on_world_event(Protocol.EVENT_ZONE, {"id": 3, "zone": "zone_wild", "phase": 1, "pos": Vector3.ZERO}, 3)
	res.on_world_event(Protocol.EVENT_ZONE, {"id": 4, "zone": "zone_ruins", "phase": 1, "pos": Vector3.ZERO}, 3)
	res.on_world_event(Protocol.EVENT_PUZZLE, {"zone": "zone_ruins", "puzzle": "p", "plates": [true], "open": true, "state": 2}, 3)
	res.on_world_event(Protocol.EVENT_RESPAWN, {"id": 3, "zone": "zone_hub", "pos": Vector3.ZERO}, 3)
	var d: Dictionary = res.to_dict()["world"]
	ctx.check(d["zones"] == ["zone_wild"] and d["puzzle_open"] == true and d["respawns"] == 1, "BotResult acumula zona/puzzle/respawn do proprio jogador")
