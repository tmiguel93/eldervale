extends RefCounted
## E5.2 no servidor autoritativo: escala por numero de jogadores (1-4), alvo por ameaca / mais proximo,
## fases replicadas (snapshot + evento), adds, morte/loot/XP do chefe, reinicio em wipe.
## DEPENDE DE TIMING (frames reais de fisica, com folga); asserts nao dependem da ordem exata de frames.

const H = preload("res://tests/e3/server_helpers.gd")
const BOSS_SCENE: String = "res://scenes/enemy/blight_treant.tscn"
const ALPHA_SCENE: String = "res://scenes/enemy/thorn_alpha.tscn"
const GRUNT_SCENE: String = "res://scenes/enemy/melee_grunt.tscn"


func run(ctx: Object) -> void:
	var tree: SceneTree = ctx as SceneTree
	await tree.physics_frame
	await _test_scaling_by_players(ctx, tree)
	await _test_snapshot_and_phase_event(ctx, tree)
	await _test_threat_targeting(ctx, tree)
	await _test_four_players_fight(ctx, tree)
	await _test_kill_and_loot(ctx, tree)
	await _test_wipe_reset(ctx, tree)


func _hit(target: Enemy, source: Node, amount: float) -> void:
	target.health.apply_damage(DamageInfo.make(amount, source, Hitbox.new_hit_id()))


func _test_scaling_by_players(ctx: Object, tree: SceneTree) -> void:
	var diff: DifficultyScaling = DifficultyScaling.load_default()
	var rig: H.Rig = H.make_rig(tree)
	var boss_id: int = rig.world.spawn_enemy(BOSS_SCENE, Vector3(0, 0.05, -30))
	var grunt_id: int = rig.world.spawn_enemy(GRUNT_SCENE, Vector3(10, 0.05, -30))
	var boss: Enemy = rig.world.get_enemy_node(boss_id)
	var grunt: Enemy = rig.world.get_enemy_node(grunt_id)
	var base_boss: float = boss.data.stats.max_health
	var base_grunt: float = grunt.data.stats.max_health
	ctx.check(is_equal_approx(boss.health.max_health(), base_boss), "sem jogadores: escala de 1 jogador (baseline)")
	var ok_all: bool = true
	var prev: float = 0.0
	for n: int in range(1, 5):
		H.join(rig, n, "P%d" % n)
		var expect_boss: float = base_boss * diff.health_mult(n, &"boss")
		var expect_grunt: float = base_grunt * diff.health_mult(n, &"normal")
		if not (is_equal_approx(boss.health.max_health(), expect_boss) and is_equal_approx(grunt.health.max_health(), expect_grunt)):
			ok_all = false
		if not is_equal_approx(boss.difficulty_damage_mult, diff.damage_mult(n)):
			ok_all = false
		ctx.check(boss.health.max_health() >= prev, "%d jogador(es): vida do chefe %.0f (nao diminui)" % [n, boss.health.max_health()])
		prev = boss.health.max_health()
	ctx.check(ok_all, "1-4 jogadores: vida/dano seguem a funcao pura de DifficultyScaling")
	ctx.check(boss.health.max_health() <= base_boss * diff.max_health_mult + 0.01, "vida do chefe respeita o teto (%.0f <= %.0f)" % [boss.health.max_health(), base_boss * diff.max_health_mult])
	# um enemy invocado depois herda a escala atual
	var late_id: int = rig.world.spawn_enemy(GRUNT_SCENE, Vector3(-10, 0.05, -30))
	ctx.check(is_equal_approx(rig.world.get_enemy_node(late_id).health.max_health(), base_grunt * diff.health_mult(4)), "inimigo criado depois nasce com a escala atual")
	# dano parcial: sair reduz o maximo sem curar
	_hit(boss, null, boss.health.max_health() * 0.25)
	var frac: float = boss.health.current_health / boss.health.max_health()
	rig.session.on_peer_disconnected(4)
	await tree.physics_frame
	var frac2: float = boss.health.current_health / boss.health.max_health()
	ctx.check(absf(frac - frac2) < 0.001 and boss.health.max_health() < base_boss * diff.health_mult(4, &"boss"), "jogador sai: maximo cai, proporcao de vida mantida (%.2f)" % frac2)
	rig.free_all()
	await tree.physics_frame


func _test_snapshot_and_phase_event(ctx: Object, tree: SceneTree) -> void:
	var rig: H.Rig = H.make_rig(tree)
	var pid: int = H.join(rig, 1)
	var boss_id: int = rig.world.spawn_enemy(BOSS_SCENE, Vector3(0, 0.05, -40))
	var boss: Enemy = rig.world.get_enemy_node(boss_id)
	var ents: Array = rig.world.build_entities()
	var boss_ent: Dictionary = {}
	var all_valid: bool = true
	for e: Variant in ents:
		if not Protocol.validate_entity_dict(e):
			all_valid = false
		if int((e as Dictionary)["id"]) == boss_id:
			boss_ent = e as Dictionary
	ctx.check(all_valid and int(boss_ent["phase"]) == 0 and String(boss_ent["atk"]) == "" and String(boss_ent["type"]) == "blight_treant", "snapshot: chefe com type, phase=0, atk vazio; todas as entidades validas")
	var spawn_evts: Array[Dictionary] = rig.transport.all_events_of_kind(Protocol.EVENT_ENEMY_SPAWN)
	var saw_boss_spawn: bool = false
	for ev: Dictionary in spawn_evts:
		if String((ev["data"] as Dictionary).get("type", "")) == "blight_treant":
			saw_boss_spawn = true
	ctx.check(saw_boss_spawn, "evento enemy_spawn do chefe replicado")
	var player: Player = rig.world.get_player_node(pid)
	_hit(boss, player, boss.health.max_health() * 0.4) # 60%: fase 1
	for i: int in 4:
		await tree.physics_frame
	var phase_evts: Array[Dictionary] = rig.transport.events_of(1, Protocol.EVENT_ENEMY_PHASE)
	var d0: Dictionary = (phase_evts[0]["data"] as Dictionary) if not phase_evts.is_empty() else {}
	ctx.check(phase_evts.size() == 1 and int(d0.get("id", -1)) == boss_id and int(d0.get("phase", -1)) == 1, "evento enemy_phase {id, phase=1} enviado uma vez")
	for e: Variant in rig.world.build_entities():
		if int((e as Dictionary)["id"]) == boss_id:
			boss_ent = e as Dictionary
	ctx.check(int(boss_ent["phase"]) == 1 and Protocol.validate_entity_dict(boss_ent), "snapshot passa a publicar phase=1")
	# adds da fase 1 existem no mundo do servidor com ids proprios e evento de spawn
	ctx.check(boss.summoned.size() == 3 and rig.world.enemy_count() == 4, "adds da fase 1 registrados no servidor (%d inimigos)" % rig.world.enemy_count())
	var add_spawns: int = 0
	for ev: Dictionary in rig.transport.events_of(1, Protocol.EVENT_ENEMY_SPAWN):
		if String((ev["data"] as Dictionary).get("type", "")) == "root_sprout":
			add_spawns += 1
	ctx.check(add_spawns == 3, "3 eventos enemy_spawn de root_sprout")
	rig.free_all()
	await tree.physics_frame


func _test_threat_targeting(ctx: Object, tree: SceneTree) -> void:
	var rig: H.Rig = H.make_rig(tree)
	var a: int = H.join(rig, 1, "A")
	var b: int = H.join(rig, 2, "B")
	var pa: Player = rig.world.get_player_node(a)
	var pb: Player = rig.world.get_player_node(b)
	pa.global_position = Vector3(0.0, 0.05, -20.0)
	pb.global_position = Vector3(12.0, 0.05, -20.0)
	var boss_id: int = rig.world.spawn_enemy(BOSS_SCENE, Vector3(-3.0, 0.05, -20.0))
	var boss: Enemy = rig.world.get_enemy_node(boss_id)
	boss.ai.cooldown_left = 99.0 # so queremos observar o alvo
	await tree.physics_frame
	await tree.physics_frame
	ctx.check(boss.target == pa, "sem ameaca: alvo = jogador mais proximo (A)")
	_hit(boss, pb, 40.0)
	await tree.physics_frame
	await tree.physics_frame
	ctx.check(boss.threat.get_threat(b) > 0.0 and boss.target == pb, "B causou dano: ameaca > 0 e o chefe passa a mirar B (mesmo mais longe)")
	_hit(boss, pa, 30.0) # menos que B * 1.25
	await tree.physics_frame
	ctx.check(boss.target == pb, "histerese: A com menos ameaca nao rouba o alvo")
	_hit(boss, pa, 400.0)
	await tree.physics_frame
	await tree.physics_frame
	ctx.check(boss.target == pa, "A passa a ter muito mais ameaca: alvo troca para A")
	# alvo morre: o chefe escolhe outro vivo no mesmo tick, sem ir para RETURN nem congelar
	(pa.get_node("Health") as HealthComponent).apply_damage(DamageInfo.make(99999.0, null, Hitbox.new_hit_id()))
	await tree.physics_frame
	await tree.physics_frame
	ctx.check(boss.target == pb and boss.is_physics_processing(), "alvo morto: chefe retarget no vivo (B), continua processando")
	# jogador sai: ameaca dele some
	rig.session.on_peer_disconnected(2)
	await tree.physics_frame
	ctx.check(boss.threat.get_threat(b) == 0.0 and boss.target == null, "jogador saiu: ameaca removida e sem alvo pendente")
	rig.free_all()
	await tree.physics_frame


func _test_four_players_fight(ctx: Object, tree: SceneTree) -> void:
	for n: int in [1, 4]:
		var rig: H.Rig = H.make_rig(tree)
		var players: Array[Player] = []
		var health_list: Array[HealthComponent] = []
		for i: int in n:
			var id: int = H.join(rig, i + 1, "P%d" % (i + 1))
			var p: Player = rig.world.get_player_node(id)
			p.global_position = Vector3(float(i) * 1.5 - 2.0, 0.05, -2.0)
			players.append(p)
			health_list.append(p.get_node("Health") as HealthComponent)
		var boss_id: int = rig.world.spawn_enemy(BOSS_SCENE, Vector3(0.0, 0.05, -9.0))
		var boss: Enemy = rig.world.get_enemy_node(boss_id)
		var seen: Dictionary = {"to_player": 0, "attacks": 0}
		rig.world.event_emitted.connect(func(kind: int, data: Dictionary) -> void:
			if kind == Protocol.EVENT_DAMAGE and int(data["source_id"]) == boss_id:
				seen["to_player"] = int(seen["to_player"]) + 1)
		var states: Dictionary = {}
		var frames: int = 0
		while frames < 360:
			await tree.physics_frame
			frames += 1
			states[boss.ai.state] = true
		ctx.check(boss.attack_count >= 2, "%d jogador(es): chefe ataca (%d ataques em %d frames)" % [n, boss.attack_count, frames])
		ctx.check(int(seen["to_player"]) >= 1, "%d jogador(es): chefe causa dano (eventos damage com source=chefe: %d)" % [n, int(seen["to_player"])])
		ctx.check(states.has(EnemyAI.State.CHASE) and states.has(EnemyAI.State.ATTACK), "%d jogador(es): IA passou por CHASE e ATTACK (sem travar)" % n)
		ctx.check(boss.target != null or boss.ai.state == EnemyAI.State.IDLE, "%d jogador(es): chefe tem alvo" % n)
		rig.free_all()
		await tree.physics_frame


func _test_kill_and_loot(ctx: Object, tree: SceneTree) -> void:
	var rig: H.Rig = H.make_rig(tree)
	var pid: int = H.join(rig, 1)
	var player: Player = rig.world.get_player_node(pid)
	player.global_position = Vector3(0, 0.05, -45)
	var loadout: PlayerLoadout = PlayerLoadout.find_for(player)
	var kills: Array[Dictionary] = []
	rig.world.enemy_killed.connect(func(eid: int, killer: int, xp: int, items: Array) -> void:
		kills.append({"eid": eid, "killer": killer, "xp": xp, "items": items}))
	var boss_id: int = rig.world.spawn_enemy(BOSS_SCENE, Vector3(0.0, 0.05, -40.0))
	var boss: Enemy = rig.world.get_enemy_node(boss_id)
	_hit(boss, player, boss.health.max_health() * 0.45) # fase 1 (adds)
	await tree.physics_frame
	await tree.physics_frame
	var adds: Array[Enemy] = boss.summoned.duplicate()
	ctx.check(adds.size() == 3, "(preparo) 3 adds vivos")
	for i: int in 80: # a transicao de fase (1 s) deixa o chefe invulneravel
		await tree.physics_frame
	var xp0: int = loadout.progress.total_xp
	_hit(boss, player, 1000000.0)
	await tree.physics_frame
	await tree.physics_frame
	ctx.check(kills.size() == 1 and int(kills[0]["eid"]) == boss_id and int(kills[0]["killer"]) == pid, "enemy_killed do chefe, creditado ao jogador que deu o golpe final")
	ctx.check(int(kills[0]["xp"]) == 1200 and loadout.progress.total_xp == xp0 + 1200, "XP do chefe (1200) concedido uma vez")
	var items: Array = kills[0]["items"] as Array
	var known: bool = true
	for it: Variant in items:
		if not ContentRegistryHelper.item_exists(String((it as Dictionary)["item_id"])):
			known = false
	ctx.check(known and rig.transport.events_of(1, Protocol.EVENT_DROP).size() >= 1, "drops do chefe replicados (%d eventos) com itens existentes" % rig.transport.events_of(1, Protocol.EVENT_DROP).size())
	var death_evts: int = 0
	for ev: Dictionary in rig.transport.events_of(1, Protocol.EVENT_DEATH):
		if int((ev["data"] as Dictionary)["id"]) == boss_id:
			death_evts += 1
	ctx.check(death_evts == 1, "um unico evento death do chefe")
	var add_deaths: int = 0
	for ev: Dictionary in rig.transport.events_of(1, Protocol.EVENT_DEATH):
		for a: Enemy in adds:
			if is_instance_valid(a) and int((ev["data"] as Dictionary)["id"]) == rig.world._node_ids.get(a.get_instance_id(), -1):
				add_deaths += 1
	var all_dismissed: bool = true
	for a: Enemy in adds:
		if is_instance_valid(a) and not a.dismissed:
			all_dismissed = false
	ctx.check(all_dismissed and add_deaths == 0 and kills.size() == 1, "adds dispensados: sem morte, sem XP, sem enemy_killed extra")
	for i: int in 60:
		await tree.physics_frame
	ctx.check(rig.world.enemy_count() == 0, "chefe e adds saem do mundo apos o corpo")
	rig.free_all()
	await tree.physics_frame


func _test_wipe_reset(ctx: Object, tree: SceneTree) -> void:
	var rig: H.Rig = H.make_rig(tree)
	var a: int = H.join(rig, 1, "A")
	var b: int = H.join(rig, 2, "B")
	var pa: Player = rig.world.get_player_node(a)
	var pb: Player = rig.world.get_player_node(b)
	pa.global_position = Vector3(0, 0.05, -2)
	pb.global_position = Vector3(2, 0.05, -2)
	var boss_id: int = rig.world.spawn_enemy(BOSS_SCENE, Vector3(0.0, 0.05, -10.0))
	var boss: Enemy = rig.world.get_enemy_node(boss_id)
	var origin: Vector3 = boss.global_position
	_hit(boss, pa, boss.health.max_health() * 0.4)
	for i: int in 120:
		await tree.physics_frame
	ctx.check(boss.phase_index() == 1 and boss.health.current_health < boss.health.max_health(), "(preparo) chefe ferido na fase 1")
	for p: Player in [pa, pb]:
		(p.get_node("Health") as HealthComponent).apply_damage(DamageInfo.make(99999.0, null, Hitbox.new_hit_id()))
	for i: int in 4:
		await tree.physics_frame
	ctx.check(boss.phase_index() == 0 and boss.health.current_health == boss.health.max_health(), "todos mortos: chefe reinicia (fase 0, vida cheia)")
	ctx.check(boss.global_position.distance_to(origin) < 0.5 and boss.ai.state == EnemyAI.State.IDLE and boss.threat.is_empty(), "volta a origem em IDLE com a ameaca limpa")
	rig.free_all()
	await tree.physics_frame


## Registro carregado uma vez para checar ids de item.
class ContentRegistryHelper extends RefCounted:
	static var _reg: ContentRegistry

	static func item_exists(id: String) -> bool:
		if _reg == null:
			_reg = ContentRegistry.new()
			_reg.load_all()
		return _reg.items.has(StringName(id))
