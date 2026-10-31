extends RefCounted
## Mundo do servidor em um unico processo, SEM rede real: input injetado via ServerSession.on_input,
## efeitos observados nos nos do servidor e nos eventos gravados.
## DEPENDE DE TIMING: usa frames reais de fisica (60 Hz no runner); folgas generosas e limite de
## frames em todos os loops. Os resultados de dano/morte nao dependem de ordem exata de frames.

const H = preload("res://tests/e3/server_helpers.gd")


func run(ctx: Object) -> void:
	var tree: SceneTree = ctx as SceneTree
	await _test_geometry(ctx, tree)
	await _test_speed_clamp(ctx, tree)
	await _test_server_cooldown(ctx, tree)
	await _test_damage_death_drop(ctx, tree)
	await _test_player_death_once(ctx, tree)
	await _test_targeting(ctx, tree)
	await _test_idle_without_players(ctx, tree)


func _test_geometry(ctx: Object, tree: SceneTree) -> void:
	var rig: H.Rig = H.make_rig(tree)
	await tree.physics_frame
	var g: Node3D = rig.world.geometry
	ctx.check(g != null and g.get_child_count() > 20, "geometria da arena criada no servidor (%d corpos)" % g.get_child_count())
	var meshes: int = 0
	for c: Node in g.get_children():
		if c.get_node_or_null("Mesh") != null:
			meshes += 1
	ctx.check(meshes == 0, "servidor: geometria sem malhas (so colisao)")
	ctx.check(g.get_node_or_null("Floor/Collision") != null and g.get_node_or_null("Ramp/Collision") != null, "colisoes do piso e da rampa presentes")
	var local_arena: Node3D = Node3D.new()
	var local_geo: Node3D = ArenaGeometry.build(local_arena, true)
	ctx.check(local_geo.get_child_count() == g.get_child_count() and local_geo.get_node_or_null("Floor/Mesh") != null, "arena local usa a mesma geometria, com malhas")
	local_arena.free()
	rig.free_all()
	await tree.physics_frame


func _test_speed_clamp(ctx: Object, tree: SceneTree) -> void:
	var rig: H.Rig = H.make_rig(tree)
	var id: int = H.join(rig, 1)
	var player: Player = rig.world.get_player_node(id)
	await tree.physics_frame
	await tree.physics_frame
	rig.session.on_input(1, 1, Vector2(10, 0), 0.0, 0, 0) # 10x o permitido
	var start: Vector3 = player.global_position
	var frames: int = 30
	var max_speed: float = 0.0
	for i: int in frames:
		await tree.physics_frame
		max_speed = maxf(max_speed, Vector2(player.velocity.x, player.velocity.z).length())
	var dt: float = 1.0 / float(Engine.physics_ticks_per_second)
	var dist: float = Vector2(player.global_position.x - start.x, player.global_position.z - start.z).length()
	var cap: float = player.move_speed * float(frames) * dt
	ctx.check(max_speed <= player.move_speed * 1.001, "velocidade nunca excede a do servidor (max %.3f <= %.1f)" % [max_speed, player.move_speed])
	ctx.check(dist <= cap * 1.02 and dist > cap * 0.7, "deslocamento %.2f m em %d frames (teto %.2f m, 10x daria %.1f m)" % [dist, frames, cap, cap * 10.0])
	ctx.check(player.global_position.x > start.x + 0.5, "move +x com yaw 0 anda para +x")
	# o cliente nao tem como enviar posicao: o ultimo input so carrega move/yaw/actions
	var snap: Array = rig.world.build_entities()
	ctx.check((snap[0] as Dictionary)["pos"] == player.global_position, "snapshot publica a posicao do SERVIDOR")
	rig.free_all()
	await tree.physics_frame


func _test_server_cooldown(ctx: Object, tree: SceneTree) -> void:
	var rig: H.Rig = H.make_rig(tree)
	var id: int = H.join(rig, 1)
	var player: Player = rig.world.get_player_node(id)
	var combat: PlayerCombat = player.get_node("Combat") as PlayerCombat
	var started: Array[int] = [0]
	combat.skill_started.connect(func(_s: SkillData) -> void: started[0] += 1)
	await tree.physics_frame
	rig.session.on_input(1, 1, Vector2.ZERO, 0.0, Protocol.ACTION_ATTACK, 0)
	rig.world.apply_inputs()
	ctx.check(started[0] == 1 and not combat.cooldowns.is_ready(combat.basic_attack.id), "ataque do input inicia golpe e cooldown no servidor")
	rig.session.on_input(1, 2, Vector2.ZERO, 0.0, Protocol.ACTION_ATTACK, 0)
	rig.world.apply_inputs()
	rig.session.on_input(1, 3, Vector2.ZERO, 0.0, Protocol.ACTION_ATTACK, 0)
	rig.world.apply_inputs()
	ctx.check(started[0] == 1, "spam de ataque no mesmo instante nao fura cooldown/estado (%d inicios)" % started[0])
	# skill_2 custa recurso: com o pool esgotado o servidor nega
	combat.resource_pool.current = 0.0
	combat.machine.die() # estado morto nega qualquer acao
	rig.session.on_input(1, 4, Vector2.ZERO, 0.0, Protocol.ACTION_SKILL_2 | Protocol.ACTION_DODGE, 0)
	rig.world.apply_inputs()
	ctx.check(started[0] == 1, "morto/sem recurso: acoes negadas pelo servidor")
	rig.free_all()
	await tree.physics_frame


func _test_damage_death_drop(ctx: Object, tree: SceneTree) -> void:
	var rig: H.Rig = H.make_rig(tree)
	var id: int = H.join(rig, 1)
	var player: Player = rig.world.get_player_node(id)
	var loadout: PlayerLoadout = PlayerLoadout.find_for(player)
	var health: HealthComponent = player.get_node("Health") as HealthComponent
	var eid: int = rig.world.spawn_enemy(H.GRUNT_SCENE, Vector3(0.0, 0.05, -1.8))
	var enemy: Enemy = rig.world.get_enemy_node(eid)
	var seen: Dictionary = {"defeats": 0, "drops": -1, "hp_after_first": -1.0}
	enemy.defeated.connect(func(_e: Enemy, _x: int, d: Array[LootDrop]) -> void:
		seen["defeats"] = int(seen["defeats"]) + 1
		seen["drops"] = d.size())
	rig.session.test_now_msec = -1 # relogio real: 1 input a cada 3 frames << rate limit
	var seq: int = 0
	var frames: int = 0
	while int(seen["defeats"]) == 0 and frames < 900 and not health.is_dead:
		if frames % 3 == 0:
			seq += 1
			rig.session.on_input(1, seq, Vector2.ZERO, 0.0, Protocol.ACTION_ATTACK, 0)
		await tree.physics_frame
		frames += 1
	ctx.check(int(seen["defeats"]) == 1, "inimigo derrubado pelo ataque do jogador no servidor (%d frames)" % frames)
	var dmg: Array[Dictionary] = rig.transport.events_of(1, Protocol.EVENT_DAMAGE)
	var to_enemy: int = 0
	var bad_source: int = 0
	for e: Dictionary in dmg:
		var d: Dictionary = e["data"] as Dictionary
		if int(d["target_id"]) == eid:
			to_enemy += 1
			if int(d["source_id"]) != id or float(d["amount"]) <= 0.0:
				bad_source += 1
	ctx.check(to_enemy >= 5 and bad_source == 0, "eventos damage jogador->inimigo com source_id e amount do servidor (%d)" % to_enemy)
	var deaths: int = 0
	for e: Dictionary in rig.transport.events_of(1, Protocol.EVENT_DEATH):
		if int((e["data"] as Dictionary)["id"]) == eid:
			deaths += 1
	for i: int in 60: # corpo some; nenhum segundo death
		await tree.physics_frame
	var deaths_after: int = 0
	for e: Dictionary in rig.transport.events_of(1, Protocol.EVENT_DEATH):
		if int((e["data"] as Dictionary)["id"]) == eid:
			deaths_after += 1
	ctx.check(deaths == 1 and deaths_after == 1, "morte unica: 1 evento death do inimigo (antes=%d, depois=%d)" % [deaths, deaths_after])
	ctx.check(rig.transport.events_of(1, Protocol.EVENT_DROP).size() == int(seen["drops"]), "eventos drop = drops decididos no servidor (%d)" % int(seen["drops"]))
	ctx.check(loadout.progress.total_xp == 40, "XP do inimigo concedido no servidor (%d)" % loadout.progress.total_xp)
	var pickups: int = 0
	for c: Node in rig.world.get_children():
		if c is Pickup:
			pickups += 1
	ctx.check(pickups == 0, "sem pickups no mundo do servidor (drop e so evento)")
	ctx.check(rig.world.get_enemy_node(eid) == null, "corpo removido apos o tempo de corpse")
	rig.free_all()
	await tree.physics_frame


func _test_player_death_once(ctx: Object, tree: SceneTree) -> void:
	var rig: H.Rig = H.make_rig(tree)
	var id: int = H.join(rig, 1)
	var player: Player = rig.world.get_player_node(id)
	var health: HealthComponent = player.get_node("Health") as HealthComponent
	await tree.physics_frame
	var first: float = health.apply_damage(DamageInfo.make(9999.0, null, Hitbox.new_hit_id()))
	var second: float = health.apply_damage(DamageInfo.make(9999.0, null, Hitbox.new_hit_id()))
	ctx.check(first > 0.0 and second == 0.0, "jogador morto nao toma dano de novo")
	var deaths: Array[Dictionary] = rig.transport.events_of(1, Protocol.EVENT_DEATH)
	ctx.check(deaths.size() == 1 and int((deaths[0]["data"] as Dictionary)["id"]) == id, "morte do jogador: um unico evento death")
	var before: Vector3 = player.global_position
	rig.session.on_input(1, 1, Vector2(1, 0), 0.0, Protocol.ACTION_ATTACK, 0)
	for i: int in 10:
		await tree.physics_frame
	ctx.check(player.global_position.distance_to(before) < 0.05, "jogador morto nao se move por input")
	var ent: Dictionary = rig.world.build_entities()[0] as Dictionary
	ctx.check(float(ent["hp"]) == 0.0 and int(ent["state"]) == int(CharacterStateMachine.State.DEAD), "snapshot mostra hp 0 e estado DEAD")
	rig.free_all()
	await tree.physics_frame


func _test_targeting(ctx: Object, tree: SceneTree) -> void:
	var rig: H.Rig = H.make_rig(tree)
	var a: int = H.join(rig, 1, "A")
	var b: int = H.join(rig, 2, "B")
	var pa: Player = rig.world.get_player_node(a)
	var pb: Player = rig.world.get_player_node(b)
	pa.global_position = Vector3(0.0, 0.05, 0.0)
	pb.global_position = Vector3(4.0, 0.05, 0.0)
	var eid: int = rig.world.spawn_enemy(H.GRUNT_SCENE, Vector3(9.0, 0.05, 0.0))
	var enemy: Enemy = rig.world.get_enemy_node(eid)
	await tree.physics_frame
	await tree.physics_frame
	ctx.check(enemy.target == pb, "inimigo mira o jogador mais proximo (B)")
	pa.global_position = Vector3(enemy.global_position.x + 1.0, 0.05, 0.0)
	await tree.physics_frame
	await tree.physics_frame
	ctx.check(enemy.target == pa, "alvo muda para o jogador que ficou mais perto (A)")
	rig.session.on_peer_disconnected(1)
	await tree.physics_frame
	await tree.physics_frame
	ctx.check(enemy.target == pb, "ao A sair, inimigo passa a mirar B (sem alvo pendente)")
	rig.session.on_peer_disconnected(2)
	await tree.physics_frame
	ctx.check(enemy.target == null and rig.world.player_count() == 0, "sem jogadores: sem alvo")
	rig.free_all()
	await tree.physics_frame


func _test_idle_without_players(ctx: Object, tree: SceneTree) -> void:
	var rig: H.Rig = H.make_rig(tree, true)
	await tree.physics_frame
	await tree.physics_frame
	var ids: Array[int] = rig.world.get_enemy_ids()
	var all_idle: bool = ids.size() == 5
	for eid: int in ids:
		var e: Enemy = rig.world.get_enemy_node(eid)
		if e.ai.state != EnemyAI.State.IDLE or e.is_physics_processing():
			all_idle = false
	ctx.check(all_idle, "sem jogadores os 5 inimigos ficam parados (IDLE, sem processar)")
	var id: int = H.join(rig, 1)
	await tree.physics_frame
	await tree.physics_frame
	var e0: Enemy = rig.world.get_enemy_node(ids[0])
	ctx.check(e0.is_physics_processing() and id > 0, "com jogador presente os inimigos voltam a processar")
	rig.free_all()
	await tree.physics_frame
