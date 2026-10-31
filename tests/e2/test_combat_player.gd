extends RefCounted
## PlayerCombat integrado ao Player real (tempo avancado manualmente via step(), deterministico).

const PLAYER_SCENE: String = "res://scenes/player/player.tscn"


func _spawn(tree: SceneTree) -> Player:
	var player: Player = (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	tree.root.add_child(player)
	player.use_external_input = true
	player.set_physics_process(false)
	var combat: PlayerCombat = player.get_node("Combat") as PlayerCombat
	combat.read_input_actions = false
	combat.set_physics_process(false)
	return player


func run(ctx: Object) -> void:
	var tree: SceneTree = ctx as SceneTree
	var player: Player = _spawn(tree)
	var combat: PlayerCombat = player.get_node("Combat") as PlayerCombat
	var health: HealthComponent = player.get_node("Health") as HealthComponent
	ctx.check(combat != null and health != null, "Player tem Combat e Health")
	ctx.check(health.current_health == health.stats.max_health, "vida inicial = stats.max_health")
	var attacker: Node = Node.new()

	# --- custo e cooldown ---
	var heavy: SkillData = combat.skill_1
	var pool_before: float = combat.resource_pool.current
	ctx.check(combat.try_use(heavy), "usa heavy_strike")
	ctx.check(absf(combat.resource_pool.current - (pool_before - heavy.resource_cost)) < 0.001, "custo consumido")
	ctx.check(not combat.cooldowns.is_ready(heavy.id), "cooldown iniciado")
	combat.step(heavy.total_duration() + 0.01)
	ctx.check(combat.machine.state == CharacterStateMachine.State.IDLE, "volta a IDLE apos o golpe")
	var after_first: float = combat.resource_pool.current
	ctx.check(not combat.try_use(heavy), "cooldown impede novo uso")
	ctx.check(combat.resource_pool.current >= after_first, "uso negado por cooldown nao consome")
	combat.step(heavy.cooldown)
	ctx.check(combat.try_use(heavy), "usa de novo apos cooldown")
	combat.step(heavy.total_duration() + 0.01)

	var whirl: SkillData = combat.skill_2
	combat.resource_pool.current = whirl.resource_cost - 1.0
	var cur: float = combat.resource_pool.current
	ctx.check(not combat.try_use(whirl), "custo insuficiente nega")
	ctx.check(combat.resource_pool.current == cur and combat.cooldowns.is_ready(whirl.id), "negado por custo: nada consumido, sem cooldown")
	combat.resource_pool.current = combat.resource_pool.max_value()
	combat.cooldowns.clear()

	# --- travamento de movimento durante ataque ---
	var basic: SkillData = combat.basic_attack
	combat.try_use(basic)
	combat.step(0.001)
	ctx.check(player.movement_locked, "movimento travado no windup")
	combat.step(basic.windup + basic.active + basic.recover)
	ctx.check(not player.movement_locked, "movimento liberado ao terminar")
	combat.cooldowns.clear()

	# --- golpe real acerta alvo a frente (facing yaw 0 => -Z) uma unica vez ---
	var troot: Node3D = Node3D.new()
	var thc: HealthComponent = HealthComponent.new()
	var tstats: StatBlock = StatBlock.new()
	tstats.max_health = 500.0
	thc.stats = tstats
	troot.add_child(thc)
	var thb: Hurtbox = Hurtbox.new()
	thb.team = CombatLayers.Team.ENEMY
	thb.health = thc
	var tcol: CollisionShape3D = CollisionShape3D.new()
	var tshape: BoxShape3D = BoxShape3D.new()
	tshape.size = Vector3(0.8, 1.0, 0.8)
	tcol.shape = tshape
	thb.add_child(tcol)
	troot.add_child(thb)
	tree.root.add_child(troot)
	troot.position = Vector3(0, 0.9, -1.2)
	await tree.physics_frame
	combat.try_use(basic)
	combat.step(basic.windup + 0.001) # entra em ACTIVE
	for i: int in 8:
		await tree.physics_frame
	var expected: float = 500.0 - health.stats.attack_power * basic.damage_multiplier
	ctx.check(absf(thc.current_health - expected) < 0.01, "golpe basico acerta uma vez: %.1f (esperado %.1f)" % [thc.current_health, expected])
	combat.step(basic.active + basic.recover + 0.01)
	for i: int in 4:
		await tree.physics_frame
	ctx.check(absf(thc.current_health - expected) < 0.01, "sem dano extra apos o golpe terminar")
	troot.queue_free()
	combat.cooldowns.clear()
	combat.resource_pool.restore(1000.0)

	# --- esquiva: i-frames so durante a janela ---
	var dodge: SkillData = combat.dodge_skill
	ctx.check(combat.try_use(dodge), "esquiva inicia")
	ctx.check(health.invulnerable, "invulneravel ao iniciar a esquiva")
	combat.step(0.001)
	ctx.check(player.use_forced_velocity and player.forced_velocity.length() > 0.0, "esquiva desloca o jogador")
	ctx.check(not combat.try_use(dodge), "nao esquiva durante esquiva")
	var hp: float = health.current_health
	ctx.check(health.apply_damage(DamageInfo.make(30.0, attacker, 9001)) == 0.0 and health.current_health == hp, "dano bloqueado dentro da janela")
	combat.step(dodge.i_frames * 0.5)
	ctx.check(health.apply_damage(DamageInfo.make(30.0, attacker, 9002)) == 0.0, "ainda bloqueado a meio da janela")
	combat.step(dodge.i_frames)
	ctx.check(not health.invulnerable, "invulnerabilidade acaba depois de i_frames")
	var dealt: float = health.apply_damage(DamageInfo.make(30.0, attacker, 9003))
	ctx.check(dealt > 0.0 and health.current_health < hp, "dano volta a entrar apos a janela")
	combat.step(2.0)
	ctx.check(combat.machine.state != CharacterStateMachine.State.DODGE, "esquiva termina")
	ctx.check(not player.use_forced_velocity, "deslocamento forcado desligado")

	# --- morte ---
	health.apply_damage(DamageInfo.make(100000.0, attacker, 9004))
	ctx.check(combat.machine.is_dead(), "morte leva a maquina para DEAD")
	ctx.check(not combat.try_use(combat.basic_attack), "morto nao ataca")
	ctx.check(not combat.try_use(combat.dodge_skill), "morto nao esquiva")

	attacker.free()
	player.queue_free()
	await tree.physics_frame
