extends RefCounted
## E5.3 no servidor autoritativo: zonas por dados, spawns corretos por zona, portais e transicao (carregar/
## descarregar, reposicionar, desconexao/morte durante a transicao, destino invalido), interesse por zona
## (snapshots/eventos), dificuldade por zona, respawn por checkpoint, encontro do chefe com gatilho e wipe,
## eventos de area/abate alimentando o QuestService. Tempo do diretor por tick manual (deterministico).

const W = preload("res://tests/e5_world/world_helpers.gd")


func run(ctx: Object) -> void:
	var tree: SceneTree = ctx as SceneTree
	await tree.physics_frame
	_test_join_hub(ctx, tree)
	_test_zone_spawns(ctx, tree)
	_test_portal_transition(ctx, tree)
	_test_no_portal_loop(ctx, tree)
	_test_interest_by_zone(ctx, tree)
	_test_unload_reload(ctx, tree)
	_test_disconnect_in_transit(ctx, tree)
	_test_invalid_and_death_in_transit(ctx, tree)
	_test_four_players(ctx, tree)
	_test_difficulty_by_zone(ctx, tree)
	_test_respawn(ctx, tree)
	_test_boss_encounter(ctx, tree)
	_test_quest_area_and_kills(ctx, tree)
	_test_client_validation(ctx)
	await _test_physics_integration(ctx, tree)
	await tree.physics_frame


func _test_join_hub(ctx: Object, tree: SceneTree) -> void:
	var rig: Object = W.rig(tree, true)
	var a: int = W.H.join(rig, 1, "A")
	ctx.check(rig.world.director != null and rig.world.zone_of_player(a) == "zone_hub", "modo mundo: jogador nasce no hub")
	var pos: Vector3 = rig.world.get_player_node(a).global_position
	var hub: ZoneDef = rig.world.director.world_def.get_zone("zone_hub")
	ctx.check(hub.contains(pos) and pos.distance_to(hub.spawn_point("start", 0)) < 0.01, "posicao inicial = spawn 'start' do hub")
	ctx.check(rig.world.enemy_count() == 0, "hub sem inimigos; selvagem e ruinas ainda nao carregadas (spawn_enemies ligado)")
	ctx.check(rig.world.director.is_loaded("zone_hub") and not rig.world.director.is_loaded("zone_wild") and not rig.world.director.is_loaded("zone_ruins"), "so o hub carregado")
	var evs: Array[Dictionary] = rig.transport.events
	var first: Dictionary = (evs[0]["data"] as Dictionary) if not evs.is_empty() else {}
	ctx.check(not evs.is_empty() and int(evs[0]["kind"]) == Protocol.EVENT_ZONE and String(first.get("zone", "")) == "zone_hub" and int(first.get("phase", -1)) == Protocol.ZONE_PHASE_ARRIVED and Protocol.validate_zone_event(first), "1o evento ao entrar: zone(hub, chegou), valido")
	# segundo jogador: posicoes de spawn distintas
	var b: int = W.H.join(rig, 2, "B")
	var pb: Vector3 = rig.world.get_player_node(b).global_position
	ctx.check(pb.distance_to(pos) > 1.0, "2o jogador nasce em outro ponto do hub")
	rig.session.send_snapshots()
	rig.session.world.server_tick = 0
	rig.free_all()


func _test_zone_spawns(ctx: Object, tree: SceneTree) -> void:
	var rig: Object = W.rig(tree, true)
	var a: int = W.H.join(rig, 1, "A")
	ctx.check(W.travel(rig, a, "zone_wild", "from_hub"), "hub -> selvagem")
	var def: WorldDef = rig.world.director.world_def
	var wild: ZoneDef = def.get_zone("zone_wild")
	ctx.check(rig.world.enemy_ids_in_zone("zone_wild").size() == wild.enemies.size() and rig.world.enemy_count() == wild.enemies.size(), "selvagem carregou %d inimigos dos dados" % wild.enemies.size())
	var grunts: int = W.enemies_of_type(rig, "zone_wild", "melee_grunt").size()
	var alpha: Array[Enemy] = W.enemies_of_type(rig, "zone_wild", "thorn_alpha")
	ctx.check(grunts >= 5 and alpha.size() == 1 and alpha[0].data.tier == &"mini_boss", "tipos corretos: %d melee_grunt e o mini-chefe thorn_alpha" % grunts)
	var positions_ok: bool = true
	for e: Dictionary in wild.enemies:
		var found: bool = false
		for id: int in rig.world.enemy_ids_in_zone("zone_wild"):
			if rig.world.get_enemy_node(id).global_position.distance_to(e["pos"] as Vector3) < 0.5 and String(rig.world.get_enemy_node(id).data.id) == String(e["type"]):
				found = true
		if not found:
			positions_ok = false
	ctx.check(positions_ok, "cada inimigo nasceu na posicao dos dados")
	# eventos de spawn chegaram ao jogador que entrou (catch-up)
	ctx.check(rig.transport.events_of(1, Protocol.EVENT_ENEMY_SPAWN).size() == wild.enemies.size(), "jogador recebeu enemy_spawn dos %d inimigos da zona" % wild.enemies.size())
	ctx.check(W.travel(rig, a, "zone_ruins", "from_wild"), "selvagem -> ruinas")
	var ruins: ZoneDef = def.get_zone("zone_ruins")
	ctx.check(rig.world.enemy_ids_in_zone("zone_ruins").size() == ruins.enemies.size(), "ruinas carregaram %d inimigos" % ruins.enemies.size())
	ctx.check(W.enemies_of_type(rig, "zone_ruins", "ranged_caster").size() >= 3 and W.enemies_of_type(rig, "zone_ruins", "blight_treant").is_empty(), ">= 3 conjuradores e o chefe ainda nao existe (gatilho)")
	# todos os inimigos vivos tem zona e estao dentro dos limites dela
	var inside: bool = true
	for id: int in rig.world.get_enemy_ids():
		var z: ZoneDef = def.get_zone(rig.world.enemy_zone(id))
		if z == null or not z.contains(rig.world.get_enemy_node(id).global_position):
			inside = false
	ctx.check(inside, "todo inimigo pertence a uma zona e esta dentro dela")
	# escala de dificuldade: o encontro nasce com a escala do numero de jogadores da zona
	rig.free_all()


func _test_portal_transition(ctx: Object, tree: SceneTree) -> void:
	var rig: Object = W.rig(tree, true)
	var a: int = W.H.join(rig, 1, "A")
	var slot: ServerWorld.PlayerSlot = rig.world.get_slot(a)
	W.place(rig, a, W.HUB_PORTAL)
	W.tick(rig, 0.1)
	ctx.check(slot.transit_left > 0.0 and slot.transit_to == "zone_wild" and slot.zone_id == "zone_hub", "pisar no portal inicia a transicao (ainda no hub)")
	var leaving: Array[Dictionary] = rig.transport.events_of(1, Protocol.EVENT_ZONE)
	var last: Dictionary = leaving[leaving.size() - 1]["data"]
	ctx.check(int(last["phase"]) == Protocol.ZONE_PHASE_LEAVING and String(last["zone"]) == "zone_wild", "evento zone(phase=saindo, destino selvagem)")
	ctx.check(rig.world.director.is_loaded("zone_wild"), "zona de destino carregada ANTES de mover o jogador")
	# parado durante a transicao (input ignorado)
	rig.world.set_input(a, Vector2(1, 0), 0.0, Protocol.ACTION_ATTACK)
	rig.world.apply_inputs()
	ctx.check(rig.world.get_player_node(a).external_input == Vector2.ZERO and slot.pending_actions == 0, "durante a transicao o jogador fica parado e sem acoes")
	W.tick(rig, 1.0)
	var wild: ZoneDef = rig.world.director.world_def.get_zone("zone_wild")
	var pos: Vector3 = rig.world.get_player_node(a).global_position
	ctx.check(slot.zone_id == "zone_wild" and slot.transit_left == 0.0 and wild.contains(pos) and pos.distance_to(wild.spawn_point("from_hub", 0)) < 0.01, "chegou ao selvagem no spawn 'from_hub'")
	var zone_evs: Array[Dictionary] = rig.transport.events_of(1, Protocol.EVENT_ZONE)
	var arr: Dictionary = zone_evs[zone_evs.size() - 1]["data"]
	ctx.check(int(arr["phase"]) == Protocol.ZONE_PHASE_ARRIVED and String(arr["zone"]) == "zone_wild" and (arr["pos"] as Vector3).distance_to(pos) < 0.01 and Protocol.validate_zone_event(arr), "evento zone(chegou) com a posicao autoritativa")
	ctx.check(rig.world.director.stats["transitions"] == 1, "contador de transicoes = 1")
	# volta pelo portal do selvagem ate o hub
	var back: Dictionary = wild.portal_by_id("wild_to_hub")
	rig.world.get_slot(a).portal_lock = 0.0
	W.place(rig, a, back["pos"] as Vector3 + Vector3(0, 0.05, 0))
	W.tick(rig, 1.2)
	ctx.check(slot.zone_id == "zone_hub", "portal de volta leva ao hub")
	var hub: ZoneDef = rig.world.director.world_def.get_zone("zone_hub")
	ctx.check(rig.world.get_player_node(a).global_position.distance_to(hub.spawn_point("from_wild", 0)) < 0.01, "...no spawn 'from_wild' do hub")
	rig.free_all()


func _test_no_portal_loop(ctx: Object, tree: SceneTree) -> void:
	var rig: Object = W.rig(tree)
	var a: int = W.H.join(rig, 1, "A")
	W.travel(rig, a, "zone_wild", "from_hub")
	W.tick(rig, 5.0)
	ctx.check(rig.world.zone_of_player(a) == "zone_wild", "apos chegar, ficar parado no spawn nao dispara portal (sem loop)")
	# o spawn de chegada fica fora do raio de todo portal de TODAS as zonas (validado nos dados) e a trava cobre o resto
	var slot: ServerWorld.PlayerSlot = rig.world.get_slot(a)
	W.place(rig, a, Vector3(153, 0.05, 0))
	slot.portal_lock = 1.0
	W.tick(rig, 0.5)
	ctx.check(slot.transit_left == 0.0, "portal_lock ativo: portal ignorado")
	W.tick(rig, 0.8)
	ctx.check(slot.transit_left > 0.0 or slot.zone_id == "zone_hub", "trava expirada: portal volta a funcionar")
	rig.free_all()


func _test_interest_by_zone(ctx: Object, tree: SceneTree) -> void:
	var rig: Object = W.rig(tree, true)
	rig.settings.aoi_radius = 0.0 # aqui so o filtro por zona; o raio tem teste proprio abaixo
	var a: int = W.H.join(rig, 1, "A")
	var b: int = W.H.join(rig, 2, "B")
	W.travel(rig, a, "zone_wild", "from_hub")
	rig.transport.snapshots.clear()
	rig.session.send_snapshots()
	var snap_a: Dictionary = {}
	var snap_b: Dictionary = {}
	for s: Dictionary in rig.transport.snapshots:
		if int(s["peer"]) == 1:
			snap_a = s
		else:
			snap_b = s
	var ids_a: Array = []
	for e: Dictionary in snap_a["entities"]:
		ids_a.append(int(e["id"]))
	var ids_b: Array = []
	for e: Dictionary in snap_b["entities"]:
		ids_b.append(int(e["id"]))
	var wild_enemy_ids: Array[int] = rig.world.enemy_ids_in_zone("zone_wild")
	ctx.check(ids_a.has(a) and not ids_a.has(b) and ids_a.size() == 1 + wild_enemy_ids.size(), "J1 (selvagem): ve a si e aos %d inimigos, nao ve J2 (hub)" % wild_enemy_ids.size())
	ctx.check(ids_b == [b], "J2 (hub): so ve a si (snapshot minimo; sem entidades do selvagem)")
	var all_valid: bool = true
	for e: Variant in snap_a["entities"]:
		if not Protocol.validate_entity_dict(e):
			all_valid = false
	ctx.check(all_valid, "snapshots do mundo continuam validos no protocolo v2")
	# raio de interesse (padrao 50 m): so os inimigos proximos viajam; jogadores da zona sempre
	rig.settings.aoi_radius = 50.0
	W.place(rig, b, Vector3(0, 0.05, 0))
	rig.transport.snapshots.clear()
	rig.session.send_snapshots()
	var near: int = 0
	var far_count: int = 0
	for s2: Dictionary in rig.transport.snapshots:
		if int(s2["peer"]) == 1:
			var pa: Vector3 = rig.world.get_player_node(a).global_position
			for e2: Dictionary in s2["entities"]:
				if int(e2["kind"]) == Protocol.KIND_ENEMY:
					near += 1
					if Vector2((e2["pos"] as Vector3).x - pa.x, (e2["pos"] as Vector3).z - pa.z).length() > 50.0:
						far_count += 1
	ctx.check(near < wild_enemy_ids.size() and far_count == 0, "AOI 50 m: J1 recebe %d de %d inimigos, nenhum alem do raio" % [near, wild_enemy_ids.size()])
	# eventos de combate da zona so vao a quem esta nela
	rig.transport.events.clear()
	var grunt: Enemy = W.enemies_of_type(rig, "zone_wild", "melee_grunt")[0]
	W.hit(grunt, rig.world.get_player_node(a), 5.0)
	ctx.check(not rig.transport.events_of(1, Protocol.EVENT_DAMAGE).is_empty() and rig.transport.events_of(2, Protocol.EVENT_DAMAGE).is_empty(), "dano no selvagem: so J1 recebe")
	# joined/left continuam globais
	rig.transport.events.clear()
	var c: int = W.H.join(rig, 3, "C")
	ctx.check(not rig.transport.events_of(1, Protocol.EVENT_PLAYER_JOINED).is_empty() and c > 0, "player_joined segue global")
	rig.free_all()


func _test_unload_reload(ctx: Object, tree: SceneTree) -> void:
	var rig: Object = W.rig(tree, true)
	var a: int = W.H.join(rig, 1, "A")
	W.travel(rig, a, "zone_wild", "from_hub")
	var total: int = rig.world.enemy_ids_in_zone("zone_wild").size()
	var g: Enemy = W.enemies_of_type(rig, "zone_wild", "melee_grunt")[0]
	W.hit(g, rig.world.get_player_node(a))
	rig.world.get_slot(a).portal_lock = 0.0
	W.travel(rig, a, "zone_hub", "from_wild")
	W.tick(rig, 6.0)
	ctx.check(rig.world.director.is_loaded("zone_wild") and rig.world.enemy_ids_in_zone("zone_wild").size() >= total - 1, "periodo de graca: zona vazia segue carregada")
	W.tick(rig, 7.0)
	ctx.check(not rig.world.director.is_loaded("zone_wild") and rig.world.enemy_ids_in_zone("zone_wild").is_empty() and rig.world.get_enemy_ids().is_empty(), "apos a graca: zona descarregada, 0 inimigos no mundo")
	ctx.check(rig.world.director.stats["unloads"] == 1, "1 descarga registrada")
	W.travel(rig, a, "zone_wild", "from_hub")
	ctx.check(rig.world.enemy_ids_in_zone("zone_wild").size() == total, "reentrada: zona recarregada com todos os %d inimigos (inclusive o morto)" % total)
	rig.free_all()


func _test_disconnect_in_transit(ctx: Object, tree: SceneTree) -> void:
	var rig: Object = W.rig(tree, true)
	var a: int = W.H.join(rig, 1, "A")
	var b: int = W.H.join(rig, 2, "B")
	ctx.check(rig.world.director.begin_transition(a, "zone_wild", "from_hub"), "preparo: A iniciou a transicao")
	ctx.check(rig.world.director.incoming_count("zone_wild") == 1, "destino conta 1 jogador a caminho")
	W.tick(rig, 0.2)
	rig.session.on_peer_disconnected(1) # A cai no meio da transicao
	ctx.check(rig.world.player_count() == 1 and rig.world.get_slot(a) == null and rig.world.director.incoming_count("zone_wild") == 0, "A removido; nenhuma transicao fantasma")
	W.tick(rig, 3.0)
	ctx.check(rig.world.zone_of_player(b) == "zone_hub" and rig.world.director.stats["transitions"] == 0, "B nao e afetado e nenhuma transicao concluiu")
	W.tick(rig, 13.0)
	ctx.check(not rig.world.director.is_loaded("zone_wild") and rig.world.get_enemy_ids().is_empty(), "destino que ninguem alcançou e descarregado depois da graca")
	# sobrevive a ticks e a snapshots sem erro
	rig.session.send_snapshots()
	ctx.check(rig.world.director.is_loaded("zone_hub"), "mundo segue consistente")
	rig.free_all()


func _test_invalid_and_death_in_transit(ctx: Object, tree: SceneTree) -> void:
	var rig: Object = W.rig(tree, true)
	var a: int = W.H.join(rig, 1, "A")
	var slot: ServerWorld.PlayerSlot = rig.world.get_slot(a)
	ctx.check(not rig.world.director.begin_transition(a, "zone_nada", "from_hub") and slot.transit_left == 0.0 and slot.zone_id == "zone_hub", "destino inexistente: recusado, jogador livre (sem softlock)")
	ctx.check(not rig.world.director.begin_transition(999, "zone_wild", "from_hub"), "entidade inexistente: recusada")
	# morte durante a transicao: cancela e reaparece na ORIGEM
	ctx.check(rig.world.director.begin_transition(a, "zone_wild", "from_hub"), "preparo: transicao iniciada")
	W.kill_player(rig, a)
	ctx.check(slot.transit_left == 0.0 and slot.transit_to == "" and slot.zone_id == "zone_hub", "morte cancela a transicao")
	ctx.check(not rig.world.director.begin_transition(a, "zone_wild", "from_hub"), "morto nao inicia transicao")
	W.tick(rig, 3.5)
	var hub: ZoneDef = rig.world.director.world_def.get_zone("zone_hub")
	ctx.check(not rig.world.is_player_dead(a) and rig.world.zone_of_player(a) == "zone_hub" and rig.world.get_player_node(a).global_position.distance_to(hub.checkpoint_point(slot.spawn_index)) < 0.01, "reaparece no checkpoint do hub (origem)")
	rig.free_all()


func _test_four_players(ctx: Object, tree: SceneTree) -> void:
	var rig: Object = W.rig(tree, true)
	var ids: Array[int] = []
	for i: int in 4:
		ids.append(W.H.join(rig, i + 1, "P%d" % (i + 1)))
	for eid: int in ids:
		W.travel(rig, eid, "zone_wild", "from_hub")
	var arr: Array[Vector3] = []
	for eid: int in ids:
		arr.append(rig.world.get_player_node(eid).global_position)
	var distinct: bool = true
	for i: int in 4:
		for j: int in range(i + 1, 4):
			if arr[i].distance_to(arr[j]) < 0.5:
				distinct = false
	ctx.check(rig.world.players_in_zone("zone_wild").size() == 4 and distinct, "4 jogadores no selvagem em pontos de chegada distintos")
	for eid: int in ids:
		W.travel(rig, eid, "zone_ruins", "from_wild")
	ctx.check(rig.world.players_in_zone("zone_ruins").size() == 4 and rig.world.director.stats["transitions"] == 8, "4 jogadores nas ruinas (8 transicoes)")
	# 5o jogador nao entra (limite do servidor)
	ctx.check(W.H.join(rig, 5, "P5") == 0, "servidor cheio continua recusando o 5o")
	rig.free_all()


func _test_difficulty_by_zone(ctx: Object, tree: SceneTree) -> void:
	var rig: Object = W.rig(tree, true)
	var diff: DifficultyScaling = DifficultyScaling.load_default()
	var ids: Array[int] = []
	for i: int in 4:
		ids.append(W.H.join(rig, i + 1, "P%d" % (i + 1)))
	W.travel(rig, ids[0], "zone_wild", "from_hub")
	var g: Enemy = W.enemies_of_type(rig, "zone_wild", "melee_grunt")[0]
	var base: float = g.data.stats.max_health
	ctx.check(is_equal_approx(g.health.max_health(), base * diff.health_mult(1)), "1 jogador no selvagem (3 no hub): escala de 1 jogador")
	W.travel(rig, ids[1], "zone_wild", "from_hub")
	ctx.check(is_equal_approx(g.health.max_health(), base * diff.health_mult(2)), "2 jogadores na zona: escala de 2")
	rig.free_all()


func _test_respawn(ctx: Object, tree: SceneTree) -> void:
	var rig: Object = W.rig(tree, true)
	var a: int = W.H.join(rig, 1, "A")
	W.travel(rig, a, "zone_wild", "from_hub")
	var slot: ServerWorld.PlayerSlot = rig.world.get_slot(a)
	var wild: ZoneDef = rig.world.director.world_def.get_zone("zone_wild")
	W.place(rig, a, Vector3(200, 0.05, 20)) # longe do checkpoint
	var g: Enemy = W.enemies_of_type(rig, "zone_wild", "melee_grunt")[0]
	g.threat.add(a, 50.0)
	W.kill_player(rig, a)
	ctx.check(rig.world.is_player_dead(a), "preparo: morto no selvagem")
	W.tick(rig, 1.5)
	ctx.check(rig.world.is_player_dead(a), "antes do atraso (3 s) continua morto")
	W.tick(rig, 2.0)
	var node: Player = rig.world.get_player_node(a)
	var hp: HealthComponent = node.get_node("Health") as HealthComponent
	ctx.check(not rig.world.is_player_dead(a) and is_equal_approx(hp.current_health, hp.max_health()), "apos o atraso: vivo com vida cheia")
	ctx.check(node.global_position.distance_to(wild.checkpoint_point(slot.spawn_index)) < 0.01 and slot.zone_id == "zone_wild", "reapareceu no checkpoint da zona (from_hub) sem trocar de zona")
	ctx.check(g.threat.get_threat(a) == 0.0, "ameaca nos inimigos da zona limpa")
	var rs: Array[Dictionary] = rig.transport.events_of(1, Protocol.EVENT_RESPAWN)
	ctx.check(rs.size() == 1 and Protocol.validate_respawn_event(rs[0]["data"]) and int((rs[0]["data"] as Dictionary)["id"]) == a, "evento respawn valido enviado")
	ctx.check(rig.world.director.stats["respawns"] == 1, "contador de respawn")
	# o jogador reanimado pode agir: ataque via input volta a funcionar
	rig.world.set_input(a, Vector2.ZERO, 0.0, Protocol.ACTION_ATTACK)
	rig.world.apply_inputs()
	var combat: PlayerCombat = node.get_node("Combat") as PlayerCombat
	ctx.check(not combat.machine.is_dead() and combat.machine.state == CharacterStateMachine.State.ATTACK, "apos o respawn o jogador ataca de novo (maquina de estados revivida)")
	# morrer de novo e reaparecer de novo (sem estado preso)
	rig.free_all()
	rig = W.rig(tree)
	a = W.H.join(rig, 1, "A")
	slot = rig.world.get_slot(a)
	for i: int in 3:
		W.kill_player(rig, a)
		W.tick(rig, 3.5)
	ctx.check(not rig.world.is_player_dead(a) and rig.world.director.stats["respawns"] == 3, "3 mortes seguidas: 3 respawns")
	# morte com o jogador desconectando antes do respawn
	W.kill_player(rig, a)
	rig.session.on_peer_disconnected(1)
	W.tick(rig, 5.0)
	ctx.check(rig.world.player_count() == 0, "desconectar morto nao deixa slot nem erro")
	rig.free_all()


func _boss_of(rig: Object) -> Array[Enemy]:
	return W.enemies_of_type(rig, "zone_ruins", "blight_treant")


func _test_boss_encounter(ctx: Object, tree: SceneTree) -> void:
	var rig: Object = W.rig(tree, true)
	var a: int = W.H.join(rig, 1, "A")
	var b: int = W.H.join(rig, 2, "B")
	W.travel(rig, a, "zone_wild", "from_hub")
	W.travel(rig, a, "zone_ruins", "from_wild")
	W.travel(rig, b, "zone_wild", "from_hub")
	W.travel(rig, b, "zone_ruins", "from_wild")
	var rt: WorldDirector.ZoneRuntime = rig.world.director.runtime("zone_ruins")
	ctx.check(rt.boss_state == Protocol.BOSS_ARMED and _boss_of(rig).is_empty(), "chefe armado e ausente antes do gatilho")
	W.place(rig, a, Vector3(380, 0.05, 0))
	W.tick(rig, 0.5)
	ctx.check(_boss_of(rig).is_empty(), "antecâmara nao dispara o encontro")
	W.place(rig, a, W.BOSS_TRIGGER)
	W.tick(rig, 0.2)
	var boss_list: Array[Enemy] = _boss_of(rig)
	ctx.check(boss_list.size() == 1 and rt.boss_state == Protocol.BOSS_ACTIVE and boss_list[0].global_position.distance_to(rt.zone.encounter["spawn"] as Vector3) < 0.5, "gatilho: o chefe nasce na posicao do encontro")
	var be: Array[Dictionary] = rig.transport.events_of(1, Protocol.EVENT_BOSS)
	ctx.check(not be.is_empty() and int((be[be.size() - 1]["data"] as Dictionary)["state"]) == Protocol.BOSS_ACTIVE and Protocol.validate_boss_event(be[be.size() - 1]["data"]), "evento boss(ativo) para os jogadores da zona")
	var diff: DifficultyScaling = DifficultyScaling.load_default()
	ctx.check(is_equal_approx(boss_list[0].health.max_health(), boss_list[0].data.stats.max_health * diff.health_mult(2, &"boss")), "chefe com a escala de 2 jogadores")
	W.tick(rig, 1.0)
	ctx.check(_boss_of(rig).size() == 1, "o gatilho nao gera um segundo chefe")
	# wipe: todos morrem -> encontro reinicia (chefe removido, armado de novo)
	W.hit(boss_list[0], rig.world.get_player_node(a), boss_list[0].health.max_health() * 0.3)
	W.kill_player(rig, a)
	W.kill_player(rig, b)
	W.tick(rig, 0.2)
	ctx.check(_boss_of(rig).is_empty() and rt.boss_state == Protocol.BOSS_ARMED and rig.world.director.stats["boss_resets"] == 1, "wipe: chefe removido e encontro rearmado")
	be = rig.transport.events_of(1, Protocol.EVENT_BOSS)
	ctx.check(int((be[be.size() - 1]["data"] as Dictionary)["state"]) == Protocol.BOSS_ARMED, "evento boss(reiniciado)")
	W.tick(rig, 3.5)
	var ruins: ZoneDef = rig.world.director.world_def.get_zone("zone_ruins")
	ctx.check(not rig.world.is_player_dead(a) and not rig.world.is_player_dead(b) and rig.world.get_player_node(a).global_position.distance_to(ruins.checkpoint_point(rig.world.get_slot(a).spawn_index)) < 0.01, "jogadores reaparecem no checkpoint das ruinas")
	# nova tentativa: chefe novo com vida cheia
	W.place(rig, a, W.BOSS_TRIGGER)
	W.tick(rig, 0.2)
	boss_list = _boss_of(rig)
	ctx.check(boss_list.size() == 1 and is_equal_approx(boss_list[0].health.current_health, boss_list[0].health.max_health()) and boss_list[0].phase_index() == 0, "nova tentativa: chefe novo, vida cheia, fase 0")
	# vitoria: evento de derrota, sem novo chefe na reentrada, XP uma vez
	var kills: Array[Dictionary] = []
	rig.world.enemy_killed.connect(func(eid: int, killer: int, xp: int, _items: Array) -> void: kills.append({"eid": eid, "killer": killer, "xp": xp}))
	W.hit(boss_list[0], rig.world.get_player_node(a))
	ctx.check(rt.boss_state == Protocol.BOSS_DEFEATED and kills.size() == 1 and int(kills[0]["xp"]) == 1200, "chefe derrotado: estado DEFEATED e 1 recompensa de 1200 XP")
	be = rig.transport.events_of(2, Protocol.EVENT_BOSS)
	ctx.check(int((be[be.size() - 1]["data"] as Dictionary)["state"]) == Protocol.BOSS_DEFEATED, "J2 tambem recebeu boss(derrotado)")
	W.tick(rig, 2.0)
	W.place(rig, a, Vector3(380, 0.05, 0))
	W.tick(rig, 0.2)
	W.place(rig, a, W.BOSS_TRIGGER)
	W.tick(rig, 0.5)
	var alive_bosses: int = 0
	for bb: Enemy in _boss_of(rig):
		if bb.defeat_count == 0:
			alive_bosses += 1
	ctx.check(alive_bosses == 0 and rt.boss_state == Protocol.BOSS_DEFEATED, "derrotado: reentrar no gatilho nao recria o chefe")
	# descarregar e recarregar rearma o encontro
	W.travel(rig, a, "zone_wild", "from_ruins")
	W.travel(rig, b, "zone_wild", "from_ruins")
	W.tick(rig, 13.0)
	ctx.check(not rig.world.director.is_loaded("zone_ruins"), "ruinas descarregadas")
	W.travel(rig, a, "zone_ruins", "from_wild")
	ctx.check(rig.world.director.runtime("zone_ruins").boss_state == Protocol.BOSS_ARMED, "recarregar as ruinas rearma o encontro")
	rig.free_all()
	# jogador que foge pelo portal durante a luta: encontro reinicia (sem chefe orfao)
	rig = W.rig(tree, true)
	a = W.H.join(rig, 1, "A")
	W.travel(rig, a, "zone_wild", "from_hub")
	W.travel(rig, a, "zone_ruins", "from_wild")
	W.place(rig, a, W.BOSS_TRIGGER)
	W.tick(rig, 0.2)
	ctx.check(_boss_of(rig).size() == 1, "(fuga) chefe ativo")
	W.travel(rig, a, "zone_wild", "from_ruins")
	W.tick(rig, 0.2)
	ctx.check(_boss_of(rig).is_empty() and rig.world.director.runtime("zone_ruins").boss_state == Protocol.BOSS_ARMED, "(fuga) sem jogadores na zona o encontro reinicia")
	rig.free_all()


func _lo(rig: Object, eid: int) -> PlayerLoadout:
	return PlayerLoadout.find_for(rig.world.get_player_node(eid))


func _test_quest_area_and_kills(ctx: Object, tree: SceneTree) -> void:
	var rig: Object = W.rig(tree, true)
	rig.session.quests.enforce_range = true
	var a: int = W.H.join(rig, 1, "A")
	var lo: PlayerLoadout = _lo(rig, a)
	for q: String in ["gw_welcome", "gw_clear_clearing", "gw_ruins_expedition"]:
		lo.quest_state.completed.append(q)
	lo.progress.level = 3
	var svc: QuestService = rig.session.quests
	# NPC nas posicoes reais do hub: aceitar longe falha, perto funciona
	var far: Dictionary = svc.cmd_quest(a, 1, Protocol.QUEST_OP_ACCEPT, "gw_ruin_guardian")
	ctx.check(not bool(far.get("ok", true)), "longe do Ilmar: aceitar recusado (distancia validada com a posicao real)")
	W.place(rig, a, NpcDirectory.shared().get_npc("npc_scholar_ilmar")["position"])
	svc.cmd_quest(a, 2, Protocol.QUEST_OP_ACCEPT, "gw_ruin_guardian")
	var t: QuestTracker = svc.tracker_of(a)
	ctx.check(t.state.is_active("gw_ruin_guardian"), "perto do Ilmar (hub): gw_ruin_guardian aceita")
	# ate as ruinas pelos portais
	W.travel(rig, a, "zone_wild", "from_hub")
	W.travel(rig, a, "zone_ruins", "from_wild")
	var node: Player = rig.world.get_player_node(a)
	# 3 conjuradores das ruinas: abate real pelo jogador -> progresso do objetivo kill ranged_caster
	var casters: Array[Enemy] = W.enemies_of_type(rig, "zone_ruins", "ranged_caster")
	for i: int in 3:
		W.hit(casters[i], node)
	ctx.check(t.state.progress_of("gw_ruin_guardian", "kill_casters") == 3, "3 conjuradores abatidos nas ruinas avancam kill_casters")
	W.place(rig, a, W.BOSS_TRIGGER)
	W.tick(rig, 0.2)
	var boss_list: Array[Enemy] = _boss_of(rig)
	ctx.check(boss_list.size() == 1, "chefe nasce")
	W.hit(boss_list[0], node)
	ctx.check(t.state.progress_of("gw_ruin_guardian", "kill_guardian") == 1 and t.status_of("gw_ruin_guardian", 1) == "ready", "abater blight_treant conclui o objetivo: quest pronta para entregar")
	rig.free_all()
	# reach_area com as posicoes reais (gate e hall), via ticks do servidor
	rig = W.rig(tree)
	rig.session.quests.enforce_range = true
	a = W.H.join(rig, 1, "A")
	lo = _lo(rig, a)
	lo.quest_state.completed.append("gw_welcome")
	lo.quest_state.completed.append("gw_clear_clearing")
	lo.progress.level = 2
	W.place(rig, a, NpcDirectory.shared().get_npc("npc_scholar_ilmar")["position"])
	rig.session.quests.cmd_quest(a, 1, Protocol.QUEST_OP_ACCEPT, "gw_ruins_expedition")
	t = rig.session.quests.tracker_of(a)
	W.travel(rig, a, "zone_wild", "from_hub")
	W.travel(rig, a, "zone_ruins", "from_wild")
	for i: int in 6:
		rig.session.step_tick()
	ctx.check(t.state.progress_of("gw_ruins_expedition", "reach_gate") == 0, "chegar as ruinas (spawn) nao conta: o portao fica mais adiante")
	W.place(rig, a, AreaSet.shared().areas["area_ruins_gate"]["center"])
	for i: int in 6:
		rig.session.step_tick()
	ctx.check(t.state.progress_of("gw_ruins_expedition", "reach_gate") == 1, "area_ruins_gate: evento de entrada alimenta o QuestService")
	W.place(rig, a, W.PLATE_A)
	W.tick(rig, 0.2)
	W.place(rig, a, W.PLATE_B)
	W.tick(rig, 0.2)
	W.place(rig, a, AreaSet.shared().areas["area_ruins_hall"]["center"])
	for i: int in 6:
		rig.session.step_tick()
	ctx.check(t.status_of("gw_ruins_expedition", 2) == "ready", "area_ruins_hall (depois do puzzle): quest pronta")
	rig.free_all()


func _test_client_validation(ctx: Object) -> void:
	var good_zone: Dictionary = {"id": 1, "zone": "zone_wild", "phase": 1, "pos": Vector3(1, 0, 2)}
	ctx.check(Protocol.validate_zone_event(good_zone), "validate_zone_event: valido")
	var bad_cases: Array = [
		{"id": 1, "zone": "ZONA!", "phase": 1, "pos": Vector3.ZERO}, {"id": "x", "zone": "zone_wild", "phase": 1, "pos": Vector3.ZERO},
		{"id": 1, "zone": "zone_wild", "phase": 7, "pos": Vector3.ZERO}, {"id": 1, "zone": "zone_wild", "phase": 1, "pos": Vector3(NAN, 0, 0)},
		{"id": 1, "zone": "zone_wild", "phase": 1}, "texto", null]
	var all_bad: bool = true
	for c: Variant in bad_cases:
		if Protocol.validate_zone_event(c):
			all_bad = false
	ctx.check(all_bad, "validate_zone_event rejeita id/zone/phase/pos invalidos e nao-dicionarios")
	var good_p: Dictionary = {"zone": "zone_ruins", "puzzle": "ruins_plates", "plates": [true, false], "open": false, "state": 1}
	var bad_p: Array = [
		{"zone": "zone_ruins", "puzzle": "p", "plates": [], "open": false, "state": 0}, {"zone": "zone_ruins", "puzzle": "p", "plates": [1, 0], "open": false, "state": 0},
		{"zone": "zone_ruins", "puzzle": "p", "plates": [true], "open": "sim", "state": 0}, {"zone": "zone_ruins", "puzzle": "p", "plates": [true], "open": true, "state": 9},
		{"zone": "zone_ruins", "puzzle": "p", "plates": [true, true, true, true, true, true, true, true, true], "open": true, "state": 2}, {"puzzle": "p"}]
	var p_ok: bool = Protocol.validate_puzzle_event(good_p)
	for c: Variant in bad_p:
		if Protocol.validate_puzzle_event(c):
			p_ok = false
	ctx.check(p_ok, "validate_puzzle_event: aceita o valido e rejeita placas vazias/nao-bool/estado fora de faixa/excesso de placas")
	ctx.check(Protocol.validate_boss_event({"zone": "zone_ruins", "encounter": "ruins_boss", "boss": "blight_treant", "state": 1}) and not Protocol.validate_boss_event({"zone": "zone_ruins", "encounter": "x", "boss": "b", "state": 5}), "validate_boss_event")
	ctx.check(Protocol.validate_respawn_event({"id": 2, "zone": "zone_hub", "pos": Vector3.ZERO}) and not Protocol.validate_respawn_event({"id": 2, "zone": "zone_hub", "pos": 3}), "validate_respawn_event")
	ctx.check(Protocol.validate_world_event(Protocol.EVENT_DAMAGE, {"qualquer": 1}) and not Protocol.validate_world_event(Protocol.EVENT_PUZZLE, {}), "validate_world_event: kinds antigos passam, kinds novos validados")
	ctx.check(Protocol.VERSION == 2, "VERSION continua 2 (extensao aditiva)")
	# ClientSession: descarta evento malformado, acompanha zona/puzzle/chefe, refaz a predicao no teleporte
	var cs: ClientSession = ClientSession.new()
	cs.state = ClientSession.State.PLAYING
	cs.player_id = 5
	cs.prediction.init_at(Vector3(1, 0, 1))
	cs.on_event(1, Protocol.EVENT_PUZZLE, {"zone": "zone_ruins"})
	ctx.check(cs.world_events_rejected == 1 and cs.drain_events().is_empty(), "cliente descarta evento de puzzle malformado")
	cs.on_event(2, Protocol.EVENT_ZONE, {"id": 5, "zone": "zone_wild", "phase": 1, "pos": Vector3(160, 0, 0)})
	ctx.check(cs.zone_id == "zone_wild" and not cs.prediction.initialized, "evento zone(chegou) do jogador local: zona atual e predicao invalidada")
	cs.prediction.init_at(Vector3(160, 0, 0))
	cs.on_event(3, Protocol.EVENT_ZONE, {"id": 9, "zone": "zone_ruins", "phase": 1, "pos": Vector3(360, 0, 0)})
	ctx.check(cs.zone_id == "zone_wild" and cs.prediction.initialized, "zone de OUTRO jogador nao muda a zona local")
	cs.on_event(4, Protocol.EVENT_PUZZLE, good_p)
	cs.on_event(5, Protocol.EVENT_BOSS, {"zone": "zone_wild", "encounter": "e", "boss": "b", "state": 1})
	ctx.check(cs.boss_state == 1 and cs.puzzle_state.is_empty(), "estado do chefe acompanhado; puzzle de OUTRA zona ignorado")
	cs.on_event(6, Protocol.EVENT_RESPAWN, {"id": 5, "zone": "zone_wild", "pos": Vector3(160, 0, 0)})
	ctx.check(not cs.prediction.initialized, "respawn do jogador local invalida a predicao")
	# ClientWorld monta o visual da zona e aplica o puzzle
	var cw: ClientWorld = ClientWorld.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(cw)
	cw.local_id = 5
	cw.apply_event(Protocol.EVENT_ZONE, {"id": 5, "zone": "zone_ruins", "phase": 1, "pos": Vector3(364, 0, 0)})
	ctx.check(cw.zone_root != null and cw.zone_id == "zone_ruins" and not (cw.get_node("Ground") as Node3D).visible, "ClientWorld: visual da zona montado e chao generico escondido")
	cw.apply_event(Protocol.EVENT_PUZZLE, {"zone": "zone_ruins", "puzzle": "ruins_plates", "plates": [true, true], "open": true, "state": 2})
	var gate: StaticBody3D = WorldBuilder.gate_of(cw.zone_root)
	ctx.check(gate.collision_layer == 0 and ((cw.zone_root.get_node("Plate_0") as MeshInstance3D).material_override as StandardMaterial3D).albedo_color == WorldBuilder.PLATE_ON, "ClientWorld: placas acesas e portao aberto")
	cw.apply_event(Protocol.EVENT_ZONE, {"id": 5, "zone": "zone_wild", "phase": 1, "pos": Vector3(160, 0, 0)})
	ctx.check(cw.zone_id == "zone_wild" and cw.zone_root.name == "Zone_zone_wild", "trocar de zona substitui o visual")
	cw.queue_free()


func _test_physics_integration(ctx: Object, tree: SceneTree) -> void:
	# Com frames reais: andar ate o portal do hub pelo INPUT e cruzar para o selvagem (servidor completo).
	var rig: Object = W.rig(tree, false)
	var a: int = W.H.join(rig, 1, "A")
	W.place(rig, a, Vector3(14.0, 0.05, 0.0))
	rig.world.set_input(a, Vector2(1.0, 0.0), 0.0, 0) # +X ate o portal em x=27
	var frames: int = 0
	while frames < 240 and rig.world.zone_of_player(a) != "zone_wild":
		await tree.physics_frame
		frames += 1
	ctx.check(rig.world.zone_of_player(a) == "zone_wild", "andando pelo input ate o portal, o servidor troca para o selvagem (%d frames)" % frames)
	rig.world.set_input(a, Vector2.ZERO, 0.0, 0)
	for i: int in 30:
		await tree.physics_frame
	var wild: ZoneDef = rig.world.director.world_def.get_zone("zone_wild")
	ctx.check(wild.contains(rig.world.get_player_node(a).global_position) and rig.world.get_player_node(a).global_position.y < 1.0, "no selvagem, em pe no chao")
	rig.free_all()
	await tree.physics_frame
