extends RefCounted
## Inimigo na fisica real: melee acerta uma vez por ataque, leash/reset no mundo, anti-preso,
## e para de atacar jogador morto. Os loops de step() sao sincronos (sem timing do motor); so o
## trecho "melee acerta" usa frames reais de fisica (DEPENDE DE TIMING, com folga).

const H = preload("res://tests/e2/loop_helpers.gd")
const DT: float = 1.0 / 60.0


func run(ctx: Object) -> void:
	var tree: SceneTree = ctx as SceneTree
	var world: Node3D = H.make_world(tree)
	await tree.physics_frame

	# --- melee: windup, um unico dano por ataque ---
	var player: Player = H.spawn_player(world, Vector3(0, 0.05, 0), true)
	var phealth: HealthComponent = player.get_node("Health") as HealthComponent
	var enemy: Enemy = H.spawn_enemy(world, H.GRUNT_SCENE, Vector3(0, 0.05, -4), player)
	var dmg: Array[int] = [0]
	phealth.damaged.connect(func(_i: DamageInfo, _f: float) -> void: dmg[0] += 1)
	var frames: int = 0
	while dmg[0] == 0 and frames < 400:
		await tree.physics_frame
		frames += 1
	ctx.check(dmg[0] == 1, "grunt aproxima, telegrafa e acerta o jogador (%d frames)" % frames)
	var expect: float = DamageCalculator.compute(enemy.data.stats.attack_power * enemy.data.attack_damage_multiplier, 1.0, 0.0)
	ctx.check(absf((phealth.max_health() - phealth.current_health) - expect) < 0.01, "dano melee = formula (%.1f)" % expect)
	for i: int in 25: # < attack_cooldown (1.4s = 84 frames): nenhum segundo dano
		await tree.physics_frame
	ctx.check(dmg[0] == 1, "hitbox ativo nao causa dano multiplo no mesmo ataque")

	# --- jogador morto: inimigo para de atacar e reseta ---
	var attacks_before: int = enemy.attack_count
	phealth.apply_damage(DamageInfo.make(100000.0, enemy, Hitbox.new_hit_id()))
	for i: int in 5:
		await tree.physics_frame
	ctx.check(enemy.ai.state == EnemyAI.State.RETURN or enemy.ai.state == EnemyAI.State.IDLE, "alvo morto: IA sai de CHASE/ATTACK")
	frames = 0
	while enemy.ai.state != EnemyAI.State.IDLE and frames < 600:
		await tree.physics_frame
		frames += 1
	ctx.check(enemy.ai.state == EnemyAI.State.IDLE and enemy.attack_count <= attacks_before + 1, "volta a IDLE sem atacar o cadaver")
	world.queue_free()
	await tree.physics_frame

	# --- leash/reset no mundo (loops sincronos) ---
	world = H.make_world(tree)
	var dummy: Node3D = Node3D.new()
	world.add_child(dummy)
	dummy.position = Vector3(19, 0, 0)
	await tree.physics_frame
	var e: Enemy = H.spawn_enemy(world, H.GRUNT_SCENE, Vector3(10, 0.05, 0), dummy)
	e.set_physics_process(false)
	var resets: Array[int] = [0]
	e.ai.reset_completed.connect(func() -> void: resets[0] += 1)
	await tree.physics_frame
	for i: int in 150:
		e.step(DT)
	ctx.check(e.ai.state != EnemyAI.State.IDLE and e.global_position.x > 14.0, "alvo no aggro: inimigo persegue e se afasta da origem (x=%.1f)" % e.global_position.x)
	e.health.apply_damage(DamageInfo.make(20.0, null, Hitbox.new_hit_id()))
	var wounded: float = e.health.current_health
	dummy.position = Vector3(80, 0, 0) # foge para alem do leash
	var steps: int = 0
	while e.ai.state != EnemyAI.State.IDLE and steps < 1500:
		e.step(DT)
		steps += 1
	ctx.check(e.ai.state == EnemyAI.State.IDLE and resets[0] == 1, "leash: voltou e resetou (%d passos)" % steps)
	ctx.check(steps > 30 and Vector2(e.global_position.x - 10.0, e.global_position.z).length() < 1.0, "posicao final perto da origem")
	ctx.check(wounded < e.health.max_health() and e.health.current_health == e.health.max_health(), "reset cura o inimigo")

	# --- retorno bloqueado por parede: return_timeout teleporta, nao fica preso ---
	var wall: StaticBody3D = StaticBody3D.new()
	var wc: CollisionShape3D = CollisionShape3D.new()
	var ws: BoxShape3D = BoxShape3D.new()
	ws.size = Vector3(1, 6, 400)
	wc.shape = ws
	wall.add_child(wc)
	world.add_child(wall)
	wall.position = Vector3(20, 3, 0)
	await tree.physics_frame
	await tree.physics_frame
	e.global_position = Vector3(27, 0.05, 0) # atras da parede (x=20), a 17 m da origem
	e.ai.return_timeout = 1.0
	dummy.position = Vector3(29, 0, 0)
	for i: int in 3:
		e.step(DT)
	ctx.check(e.ai.state != EnemyAI.State.IDLE, "(preparo) inimigo atras da parede reage ao alvo")
	dummy.position = Vector3(300, 0, 0)
	steps = 0
	while e.ai.state != EnemyAI.State.IDLE and steps < 1000:
		e.step(DT)
		steps += 1
	ctx.check(e.ai.state == EnemyAI.State.IDLE, "retorno bloqueado resolve por timeout (%d passos)" % steps)
	ctx.check(steps > 30, "(nao foi instantaneo: ficou preso ate o timeout)")
	ctx.check(Vector2(e.global_position.x - 10.0, e.global_position.z).length() < 1.5, "teleporte de seguranca para a origem")
	world.queue_free()
	await tree.physics_frame
