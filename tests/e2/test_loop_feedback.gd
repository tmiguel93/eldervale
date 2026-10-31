extends RefCounted
## Feedback visual (flash, numero de dano, efeito de morte) e HUD. Apresentacao separada da logica:
## o dano/morte funcionam sem esses nos (verificado removendo-os). NAO verifica render real
## (headless): apenas estado dos nos/sinais. Sem audio nesta entrega.

const H = preload("res://tests/e2/loop_helpers.gd")


func run(ctx: Object) -> void:
	var tree: SceneTree = ctx as SceneTree
	var world: Node3D = H.make_world(tree)
	var player: Player = H.spawn_player(world, Vector3(0, 0.05, 0))
	var enemy: Enemy = H.spawn_enemy(world, H.GRUNT_SCENE, Vector3(0, 0.05, -30), player)
	enemy.set_physics_process(false)
	await tree.physics_frame

	var flash: HitFlash = enemy.get_node("HitFlash") as HitFlash
	var numbers: DamageNumbers = enemy.get_node("DamageNumbers") as DamageNumbers
	var body: MeshInstance3D = enemy.get_node("Visual/Body") as MeshInstance3D
	var original: Material = body.material_override
	enemy.health.apply_damage(DamageInfo.make(10.0, player, Hitbox.new_hit_id()))
	ctx.check(flash.flashing and body.material_override != original, "inimigo pisca ao receber dano")
	ctx.check(numbers.spawned == 1, "numero de dano criado")
	var label_found: bool = false
	for c: Node in world.get_children():
		if c is DamageNumber:
			label_found = (c as DamageNumber).text == str(int(roundf(9.0))) # 10 - 1 defesa
	ctx.check(label_found, "numero mostra o dano final aplicado (9)")
	for i: int in 20: # 0.33 s > 0.12 s de flash
		await tree.physics_frame
	await tree.process_frame
	ctx.check(not flash.flashing and body.material_override == original, "material original restaurado apos o flash")
	var alive: int = 0
	await tree.create_timer(1.0).timeout
	for c: Node in world.get_children():
		if c is DamageNumber:
			alive += 1
	ctx.check(alive == 0, "numero de dano some e e liberado (~0,9 s)")

	# jogador tambem tem feedback
	var pflash: HitFlash = player.get_node("HitFlash") as HitFlash
	(player.get_node("Health") as HealthComponent).apply_damage(DamageInfo.make(5.0, enemy, Hitbox.new_hit_id()))
	ctx.check(pflash.flashing, "jogador pisca ao receber dano")

	# efeito de morte nao afeta a logica: morre uma vez mesmo sem o no de efeito
	enemy.get_node("DeathEffect").free()
	var e2: Enemy = H.spawn_enemy(world, H.GRUNT_SCENE, Vector3(5, 0.05, -30), player)
	e2.set_physics_process(false)
	e2.get_node("HitFlash").free()
	e2.get_node("DamageNumbers").free()
	await tree.physics_frame
	e2.health.apply_damage(DamageInfo.make(100000.0, player, Hitbox.new_hit_id()))
	ctx.check(e2.defeat_count == 1, "logica de morte nao depende dos componentes de feedback")
	var e3: Enemy = H.spawn_enemy(world, H.GRUNT_SCENE, Vector3(10, 0.05, -30), player)
	e3.set_physics_process(false)
	await tree.physics_frame
	var fx: DeathEffect = e3.get_node("DeathEffect") as DeathEffect
	e3.health.apply_damage(DamageInfo.make(100000.0, player, Hitbox.new_hit_id()))
	ctx.check(fx.playing, "efeito de morte iniciado")
	for i: int in 10:
		await tree.process_frame
	ctx.check((e3.get_node("Visual") as Node3D).scale.x < 1.0, "Visual encolhe durante o efeito")

	# --- HUD: le estado, sem afetar gameplay ---
	var hud: PlaytestHud = PlaytestHud.new()
	world.add_child(hud)
	hud.setup(player)
	var loadout: PlayerLoadout = player.get_node("Loadout") as PlayerLoadout
	loadout.inventory.add(&"sword_basic", 1)
	await tree.process_frame
	ctx.check(hud.build_info_text().contains("Nivel 1"), "HUD mostra nivel")
	ctx.check(hud.build_skills_text().contains("Golpe Pesado") or hud.build_skills_text().contains("pronto"), "HUD lista skills/cooldowns")
	var inv_text: String = hud.build_inventory_text()
	ctx.check(inv_text.contains("1. sword_basic x1") and inv_text.contains("Arma: -"), "HUD lista inventario e slots")
	loadout.equip_from_index(0)
	ctx.check(hud.build_inventory_text().contains("Arma: sword_basic"), "HUD reflete equipamento")
	var restart: Array[int] = [0]
	hud.restart_requested.connect(func() -> void: restart[0] += 1)
	var ev: InputEventAction = InputEventAction.new()
	ev.action = &"restart"
	ev.pressed = true
	hud._unhandled_input(ev)
	ctx.check(restart[0] == 0, "R nao reinicia com o jogador vivo")
	(player.get_node("Health") as HealthComponent).apply_damage(DamageInfo.make(100000.0, null, Hitbox.new_hit_id()))
	ctx.check(hud.death_label.visible, "mensagem de morte aparece")
	hud._unhandled_input(ev)
	ctx.check(restart[0] == 1, "R reinicia apos a morte (sinal)")
	world.queue_free()
	await tree.physics_frame
