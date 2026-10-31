extends RefCounted
## Projetil: acerta uma vez, expira, some no mundo, esquiva (i-frames) o consome sem dano.
## DEPENDE DE TIMING: usa frames reais de fisica (60 Hz) com folga generosa.

const H = preload("res://tests/e2/loop_helpers.gd")


func _make_proj(world: Node3D, pos: Vector3, dir: Vector3, dmg: float, life: float) -> Projectile:
	var pr: Projectile = Projectile.new()
	pr.direction = dir
	pr.speed = 12.0
	pr.damage = dmg
	pr.lifetime = life
	world.add_child(pr)
	pr.global_position = pos
	return pr


func _make_player_target(world: Node3D, pos: Vector3) -> HealthComponent:
	var root: Node3D = Node3D.new()
	var hc: HealthComponent = HealthComponent.new()
	var st: StatBlock = StatBlock.new()
	st.max_health = 100.0
	st.defense = 0.0
	hc.stats = st
	root.add_child(hc)
	var hb: Hurtbox = Hurtbox.new()
	hb.team = CombatLayers.Team.PLAYER
	hb.health = hc
	var col: CollisionShape3D = CollisionShape3D.new()
	var sh: BoxShape3D = BoxShape3D.new()
	sh.size = Vector3(1, 1.8, 1)
	col.shape = sh
	hb.add_child(col)
	root.add_child(hb)
	world.add_child(root)
	root.position = pos
	return hc


func run(ctx: Object) -> void:
	var tree: SceneTree = ctx as SceneTree
	var world: Node3D = H.make_world(tree)
	var target: HealthComponent = _make_player_target(world, Vector3(6, 1, 0))
	await tree.physics_frame

	# --- acerta uma vez ---
	var hits: Array[int] = [0]
	var pr: Projectile = _make_proj(world, Vector3(0, 1, 0), Vector3.RIGHT, 10.0, 3.0)
	pr.hit_target.connect(func(_h: Hurtbox, _a: float) -> void: hits[0] += 1)
	for i: int in 60:
		await tree.physics_frame
	ctx.check(hits[0] == 1 and absf(target.current_health - 90.0) < 0.01, "projetil acerta uma vez: vida %.1f" % target.current_health)
	ctx.check(not is_instance_valid(pr) or pr.is_queued_for_deletion(), "projetil some apos o acerto")

	# --- expira ---
	var expired: Array[int] = [0]
	var pe: Projectile = _make_proj(world, Vector3(0, 1, 20), Vector3.BACK, 10.0, 0.1)
	pe.expired.connect(func() -> void: expired[0] += 1)
	for i: int in 20:
		await tree.physics_frame
	ctx.check(expired[0] == 1, "projetil expira pelo tempo de vida")
	ctx.check(not is_instance_valid(pe) or pe.is_queued_for_deletion(), "projetil expirado liberado")

	# --- some ao colidir com o mundo, sem dano ---
	var wall: StaticBody3D = StaticBody3D.new()
	var wc: CollisionShape3D = CollisionShape3D.new()
	var ws: BoxShape3D = BoxShape3D.new()
	ws.size = Vector3(0.5, 4, 10)
	wc.shape = ws
	wall.add_child(wc)
	world.add_child(wall)
	wall.position = Vector3(3, 2, 0)
	await tree.physics_frame
	await tree.physics_frame
	var pw: Projectile = _make_proj(world, Vector3(0, 1, 0), Vector3.RIGHT, 10.0, 3.0)
	var before: float = target.current_health
	for i: int in 40:
		await tree.physics_frame
	ctx.check(not is_instance_valid(pw) or pw.is_queued_for_deletion(), "projetil some ao bater na parede")
	ctx.check(target.current_health == before, "parede bloqueou: alvo atras sem dano")
	wall.queue_free()
	await tree.physics_frame

	# --- esquiva: invulneravel consome o projetil mas nao toma dano ---
	target.invulnerable = true
	var pd: Projectile = _make_proj(world, Vector3(0, 1, 0), Vector3.RIGHT, 10.0, 3.0)
	var hp: float = target.current_health
	for i: int in 60:
		await tree.physics_frame
	ctx.check(target.current_health == hp, "invulneravel: sem dano")
	ctx.check(not is_instance_valid(pd) or pd.is_queued_for_deletion(), "projetil consumido mesmo assim (dano unico)")

	# --- caster dispara contra o jogador real ---
	var player: Player = H.spawn_player(world, Vector3(0, 0.05, 40), true)
	var caster: Enemy = H.spawn_enemy(world, H.CASTER_SCENE, Vector3(0, 0.05, 32), player)
	var hurt: Array[int] = [0]
	var phealth: HealthComponent = player.get_node("Health") as HealthComponent
	phealth.damaged.connect(func(_i: DamageInfo, _f: float) -> void: hurt[0] += 1)
	var frames: int = 0
	while hurt[0] == 0 and frames < 300:
		await tree.physics_frame
		frames += 1
	ctx.check(hurt[0] == 1, "caster acerta o jogador com projetil (%d frames)" % frames)
	var expect_dmg: float = DamageCalculator.compute(caster.data.stats.attack_power * caster.data.attack_damage_multiplier, 1.0, 0.0)
	ctx.check(absf((phealth.max_health() - phealth.current_health) - expect_dmg) < 0.01, "dano do projetil = formula (%.2f)" % expect_dmg)
	ctx.check(caster.attack_count >= 1, "caster atacou via release da IA")
	world.queue_free()
	await tree.physics_frame
