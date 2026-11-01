extends RefCounted
## E5.3: puzzle cooperativo de placas de pressao. Logica pura (PuzzleState) + servidor autoritativo
## (2 jogadores, 1 jogador sozinho, trava temporizada, jogador morto, portao fisico, reset por reentrada,
## replicacao aditiva no protocolo v2). Sem softlock: o portao nunca fecha com gente dentro.

const W = preload("res://tests/e5_world/world_helpers.gd")


func run(ctx: Object) -> void:
	var tree: SceneTree = ctx as SceneTree
	await tree.physics_frame
	_test_pure_state(ctx)
	_test_server_two_players(ctx, tree)
	_test_server_solo_latch(ctx, tree)
	_test_server_dead_and_authority(ctx, tree)
	await _test_physical_gate(ctx, tree)
	_test_reset_by_reentry(ctx, tree)
	_test_no_softlock_gate_stays_open(ctx, tree)
	_test_events_and_catchup(ctx, tree)
	await tree.physics_frame


func _state() -> PuzzleState:
	return PuzzleState.from_zone(WorldDef.load_region("greenwood").get_zone("zone_ruins"))


func _test_pure_state(ctx: Object) -> void:
	var s: PuzzleState = _state()
	var a: Vector3 = W.PLATE_A
	var b: Vector3 = W.PLATE_B
	ctx.check(s != null and s.plate_count() == 2 and s.state() == PuzzleState.State.IDLE and not s.open, "estado inicial: 2 placas, IDLE, fechado")
	ctx.check(not s.update([], 0.1) and s.lit_count() == 0, "ninguem nas placas: nada muda")
	ctx.check(s.update([a], 0.1) and s.is_pressed(0) and s.is_lit(0) and not s.is_lit(1) and s.state() == PuzzleState.State.PARTIAL, "uma placa pisada: PARTIAL")
	ctx.check(not s.update([a], 0.1), "permanecer na mesma placa nao muda o estado observavel")
	ctx.check(s.update([a, b], 0.1) and s.open and s.state() == PuzzleState.State.OPEN and s.open_count == 1, "duas placas ao mesmo tempo: portao abre")
	s.update([], 5.0)
	ctx.check(s.open and s.state() == PuzzleState.State.OPEN, "depois de aberto o portao permanece aberto")
	s.reset()
	ctx.check(not s.open and s.lit_count() == 0 and s.state() == PuzzleState.State.IDLE, "reset fecha e apaga as placas")
	# trava temporizada
	s.update([a], 0.1)
	s.update([], 9.0)
	ctx.check(s.is_lit(0) and not s.is_pressed(0), "placa solta continua acesa dentro da janela (9 s < 10 s)")
	s.update([], 1.2)
	ctx.check(not s.is_lit(0), "a janela expira (reset por timeout): placa apaga")
	ctx.check(s.update([a], 0.0) == true, "pisar de novo reacende")
	s.update([], 6.0)
	s.update([b], 0.1) # segunda placa dentro da janela da primeira => abre (jogador sozinho)
	ctx.check(s.open, "placa A (solta ha 6 s) + placa B agora: abre")
	# raio e altura
	var s2: PuzzleState = _state()
	s2.update([a + Vector3(1.7, 0, 0)], 0.1)
	var inside: bool = s2.is_pressed(0)
	s2.update([a + Vector3(1.9, 0, 0)], 0.1)
	var outside: bool = not s2.is_pressed(0)
	s2.update([a + Vector3(0, 3.0, 0)], 0.1)
	ctx.check(inside and outside and not s2.is_pressed(0), "raio (1,8 m) e altura (+-2 m) da placa respeitados")
	var ev: Dictionary = s.to_event("zone_ruins")
	ctx.check(Protocol.validate_puzzle_event(ev) and ev["plates"].size() == 2 and bool(ev["open"]), "to_event e valido para o protocolo")
	ctx.check(PuzzleState.from_zone(WorldDef.load_region("greenwood").get_zone("zone_hub")) == null, "zona sem puzzle => null")


func _ruins_rig(tree: SceneTree, players: int) -> Dictionary:
	var rig: Object = W.rig(tree)
	var ids: Array[int] = []
	for i: int in players:
		var eid: int = W.H.join(rig, i + 1, "P%d" % (i + 1))
		ids.append(eid)
		W.travel(rig, eid, "zone_wild", "from_hub")
		W.travel(rig, eid, "zone_ruins", "from_wild")
	return {"rig": rig, "ids": ids}


func _puzzle(rig: Object) -> PuzzleState:
	return rig.world.director.runtime("zone_ruins").puzzle


func _gate_layer(rig: Object) -> int:
	return (rig.world.director.runtime("zone_ruins").root.get_node("PuzzleGate") as StaticBody3D).collision_layer


func _test_server_two_players(ctx: Object, tree: SceneTree) -> void:
	var d: Dictionary = _ruins_rig(tree, 2)
	var rig: Object = d["rig"]
	var ids: Array = d["ids"]
	ctx.check(rig.world.zone_of_player(ids[0]) == "zone_ruins" and rig.world.zone_of_player(ids[1]) == "zone_ruins", "preparo: 2 jogadores nas ruinas")
	ctx.check(_puzzle(rig) != null and not _puzzle(rig).open and _gate_layer(rig) != 0, "portao fechado e com colisao ao carregar a zona")
	W.place(rig, ids[0], W.PLATE_A)
	W.tick(rig, 0.2)
	ctx.check(_puzzle(rig).lit_count() == 1 and not _puzzle(rig).open, "J1 na placa A: so uma acesa")
	W.place(rig, ids[1], W.PLATE_B)
	W.tick(rig, 0.2)
	ctx.check(_puzzle(rig).open and _gate_layer(rig) == 0, "J2 na placa B: portao abre (colisao desligada)")
	# replicacao: ambos recebem o evento 9 com open=true; estado monotonico por jogador
	for peer: int in [1, 2]:
		var evs: Array[Dictionary] = rig.transport.events_of(peer, Protocol.EVENT_PUZZLE)
		var last: Dictionary = (evs[evs.size() - 1]["data"] as Dictionary) if not evs.is_empty() else {}
		ctx.check(not evs.is_empty() and bool(last.get("open", false)) and Protocol.validate_puzzle_event(last), "peer %d recebeu puzzle_state aberto e valido" % peer)
	W.place(rig, ids[0], Vector3(370, 0.05, 0))
	W.place(rig, ids[1], Vector3(370, 0.05, 2))
	W.tick(rig, 30.0)
	ctx.check(_puzzle(rig).open and _gate_layer(rig) == 0, "saiu das placas: portao continua aberto")
	rig.free_all()


func _test_server_solo_latch(ctx: Object, tree: SceneTree) -> void:
	var d: Dictionary = _ruins_rig(tree, 1)
	var rig: Object = d["rig"]
	var eid: int = d["ids"][0]
	# sozinho: corre de A para B dentro da janela de 10 s (28 m / 6 m/s ~ 4,7 s)
	W.place(rig, eid, W.PLATE_A)
	W.tick(rig, 0.3)
	W.place(rig, eid, Vector3(380, 0.05, 0))
	W.tick(rig, 5.0)
	ctx.check(not _puzzle(rig).open and _puzzle(rig).is_lit(0), "sozinho: A continua acesa 5 s depois")
	W.place(rig, eid, W.PLATE_B)
	W.tick(rig, 0.2)
	ctx.check(_puzzle(rig).open, "sozinho: chegar a B dentro da janela abre o portao (sem softlock solo)")
	rig.free_all()
	# janela expirada: nao abre e o puzzle volta ao inicio sozinho (reset por timeout)
	d = _ruins_rig(tree, 1)
	rig = d["rig"]
	eid = d["ids"][0]
	W.place(rig, eid, W.PLATE_A)
	W.tick(rig, 0.3)
	W.place(rig, eid, Vector3(380, 0.05, 0))
	W.tick(rig, 11.0)
	ctx.check(_puzzle(rig).lit_count() == 0 and _puzzle(rig).state() == PuzzleState.State.IDLE, "janela expirou: puzzle voltou a IDLE sozinho")
	W.place(rig, eid, W.PLATE_B)
	W.tick(rig, 0.2)
	ctx.check(not _puzzle(rig).open and _puzzle(rig).lit_count() == 1, "chegar a B tarde demais nao abre")
	W.place(rig, eid, W.PLATE_A)
	W.tick(rig, 0.2)
	ctx.check(_puzzle(rig).open, "...mas e recuperavel: voltar a A dentro da janela de B abre")
	rig.free_all()


func _test_server_dead_and_authority(ctx: Object, tree: SceneTree) -> void:
	var d: Dictionary = _ruins_rig(tree, 2)
	var rig: Object = d["rig"]
	var ids: Array = d["ids"]
	W.place(rig, ids[0], W.PLATE_A)
	W.place(rig, ids[1], W.PLATE_B)
	W.kill_player(rig, ids[1]) # morto em cima da placa B
	W.tick(rig, 0.2)
	ctx.check(not _puzzle(rig).open and _puzzle(rig).is_lit(0) and not _puzzle(rig).is_lit(1), "jogador morto nao pressiona a placa")
	# jogador em transicao para fora (ainda na zona) continua valido; quem esta em OUTRA zona nao conta
	rig.free_all()
	d = _ruins_rig(tree, 2)
	rig = d["rig"]
	ids = d["ids"]
	W.place(rig, ids[0], W.PLATE_A)
	W.travel(rig, ids[1], "zone_wild", "from_ruins")
	W.place(rig, ids[1], W.PLATE_B) # posicao de uma placa, mas em outra zona
	W.tick(rig, 0.2)
	ctx.check(not _puzzle(rig).open, "so jogadores da zona pressionam placas (posicao igual em outra zona nao conta)")
	# nenhum RPC/comando do cliente altera o puzzle: a API de rede nao expoe nada de mundo
	var cmds: Array[String] = []
	var probe: ServerSession = ServerSession.new()
	for m: Dictionary in probe.get_method_list():
		if String(m["name"]).begins_with("on_") and (String(m["name"]).contains("puzzle") or String(m["name"]).contains("zone") or String(m["name"]).contains("portal")):
			cmds.append(String(m["name"]))
	probe.free()
	ctx.check(cmds.is_empty(), "ServerSession nao expoe handler de puzzle/zona/portal (estado so do servidor)")
	rig.free_all()


func _test_physical_gate(ctx: Object, tree: SceneTree) -> void:
	for opened: bool in [false, true]:
		var d: Dictionary = _ruins_rig(tree, 1)
		var rig: Object = d["rig"]
		var eid: int = d["ids"][0]
		if opened:
			W.place(rig, eid, W.PLATE_A)
			W.tick(rig, 0.2)
			W.place(rig, eid, W.PLATE_B)
			W.tick(rig, 0.2)
		W.place(rig, eid, Vector3(388.0, 0.05, 0.0))
		rig.world.set_input(eid, Vector2(1.0, 0.0), 0.0, 0) # +X, em direcao ao portao
		for i: int in 100:
			await tree.physics_frame
		var x: float = rig.world.get_player_node(eid).global_position.x
		if opened:
			ctx.check(_puzzle(rig).open and x > 397.0, "portao aberto: o jogador atravessa para o salao (x=%.1f)" % x)
		else:
			ctx.check(x < 395.0, "portao fechado: bloqueia o jogador (x=%.1f)" % x)
		rig.free_all()
		await tree.physics_frame


func _test_reset_by_reentry(ctx: Object, tree: SceneTree) -> void:
	var d: Dictionary = _ruins_rig(tree, 1)
	var rig: Object = d["rig"]
	var eid: int = d["ids"][0]
	W.place(rig, eid, W.PLATE_A)
	W.tick(rig, 0.2)
	W.place(rig, eid, W.PLATE_B)
	W.tick(rig, 0.2)
	ctx.check(_puzzle(rig).open, "preparo: puzzle resolvido")
	W.travel(rig, eid, "zone_wild", "from_ruins")
	W.tick(rig, 5.0)
	ctx.check(rig.world.director.is_loaded("zone_ruins") and _puzzle(rig).open, "dentro do periodo de graca a zona vazia mantem o estado")
	W.tick(rig, 8.0)
	ctx.check(not rig.world.director.is_loaded("zone_ruins"), "zona vazia ha mais de 12 s: descarregada")
	ctx.check(rig.world.director.runtime("zone_ruins").puzzle.open == false and _gate_layer(rig) != 0, "descarregar reinicia o puzzle e fecha o portao")
	W.travel(rig, eid, "zone_ruins", "from_wild")
	ctx.check(rig.world.director.is_loaded("zone_ruins") and not _puzzle(rig).open and _puzzle(rig).state() == PuzzleState.State.IDLE and _gate_layer(rig) != 0, "reentrada: puzzle novo, fechado e IDLE")
	W.place(rig, eid, W.PLATE_A)
	W.tick(rig, 0.2)
	W.place(rig, eid, W.PLATE_B)
	W.tick(rig, 0.2)
	ctx.check(_puzzle(rig).open, "...e pode ser resolvido de novo")
	rig.free_all()


func _test_no_softlock_gate_stays_open(ctx: Object, tree: SceneTree) -> void:
	var d: Dictionary = _ruins_rig(tree, 2)
	var rig: Object = d["rig"]
	var ids: Array = d["ids"]
	W.place(rig, ids[0], W.PLATE_A)
	W.place(rig, ids[1], W.PLATE_B)
	W.tick(rig, 0.2)
	W.place(rig, ids[0], Vector3(420, 0.05, 0)) # ambos dentro do salao do chefe
	W.place(rig, ids[1], Vector3(420, 0.05, 3))
	W.tick(rig, 120.0)
	ctx.check(_puzzle(rig).open and _gate_layer(rig) == 0, "com jogadores no salao o portao nunca fecha (120 s)")
	# jogador morre no salao e reaparece fora do salao: o portao continua aberto para quem voltar
	W.kill_player(rig, ids[0])
	W.tick(rig, 4.0)
	var pos: Vector3 = rig.world.get_player_node(ids[0]).global_position
	ctx.check(not rig.world.is_player_dead(ids[0]) and pos.x < 370.0, "morto no salao: reaparece no checkpoint antes do portao")
	ctx.check(_puzzle(rig).open, "...e o portao segue aberto (a luta continua acessivel)")
	rig.free_all()


func _test_events_and_catchup(ctx: Object, tree: SceneTree) -> void:
	var rig: Object = W.rig(tree)
	var a: int = W.H.join(rig, 1, "A")
	W.travel(rig, a, "zone_wild", "from_hub")
	W.travel(rig, a, "zone_ruins", "from_wild")
	W.place(rig, a, W.PLATE_A)
	W.tick(rig, 0.2)
	# J2 entra depois: recebe o estado ATUAL do puzzle ao chegar nas ruinas
	var b: int = W.H.join(rig, 2, "B")
	W.travel(rig, b, "zone_wild", "from_hub")
	W.travel(rig, b, "zone_ruins", "from_wild")
	var evs: Array[Dictionary] = rig.transport.events_of(2, Protocol.EVENT_PUZZLE)
	ctx.check(not evs.is_empty() and (evs[evs.size() - 1]["data"] as Dictionary)["plates"] == [true, false], "quem chega depois recebe o estado atual das placas ([true, false])")
	# eventos de puzzle nao vazam para outras zonas
	var c: int = W.H.join(rig, 3, "C")
	var before: int = rig.transport.events_of(3, Protocol.EVENT_PUZZLE).size()
	W.place(rig, b, W.PLATE_B)
	W.tick(rig, 0.2)
	ctx.check(rig.transport.events_of(3, Protocol.EVENT_PUZZLE).size() == before and c > 0, "jogador no hub nao recebe eventos do puzzle das ruinas")
	rig.free_all()
