extends RefCounted
## PlayerLoadout: equipar altera stats finais E o dano real aplicado; nivel aplica bonus;
## proporcao de vida/recurso preservada. Tempo avancado via combat.step (deterministico);
## o golpe real usa frames de fisica (DEPENDE DE TIMING, com folga).

const H = preload("res://tests/e2/loop_helpers.gd")


func _swing(tree: SceneTree, combat: PlayerCombat, target: HealthComponent) -> float:
	var before: float = target.current_health
	combat.cooldowns.clear()
	combat.try_use(combat.basic_attack)
	combat.step(combat.basic_attack.windup + 0.001)
	for i: int in 8:
		await tree.physics_frame
	combat.step(combat.basic_attack.active + combat.basic_attack.recover + 0.01)
	for i: int in 3:
		await tree.physics_frame
	return before - target.current_health


func _idx(loadout: PlayerLoadout, id: StringName) -> int:
	var c: Array[Dictionary] = loadout.inventory.contents()
	for i: int in c.size():
		if c[i]["id"] == id:
			return i
	return -1


func run(ctx: Object) -> void:
	var tree: SceneTree = ctx as SceneTree
	var world: Node3D = H.make_world(tree)
	var player: Player = H.spawn_player(world, Vector3(0, 0.05, 0))
	var combat: PlayerCombat = player.get_node("Combat") as PlayerCombat
	var health: HealthComponent = player.get_node("Health") as HealthComponent
	var loadout: PlayerLoadout = player.get_node("Loadout") as PlayerLoadout
	var dummy: HealthComponent = H.make_dummy_target(world, Vector3(0, 0.95, -1.2), 5000.0)
	await tree.physics_frame

	ctx.check(loadout.final_stats.attack_power == 12.0 and health.stats.max_health == 120.0, "sem equipamento: stats = base (ATK 12, vida 120)")
	var base_damage: float = await _swing(tree, combat, dummy)
	ctx.check(absf(base_damage - 12.0) < 0.01, "dano real base = 12 (%.1f)" % base_damage)

	loadout.inventory.add(&"sword_rare", 1) # +12 ATK
	ctx.check(loadout.equip_from_index(0), "equipa sword_rare pelo indice")
	ctx.check(health.stats.attack_power == 24.0 and loadout.inventory.count(&"sword_rare") == 0, "stats aplicados (ATK 24), item saiu do inventario")
	var new_damage: float = await _swing(tree, combat, dummy)
	ctx.check(absf(new_damage - 24.0) < 0.01 and new_damage > base_damage, "equipar arma aumenta o dano REAL aplicado (%.1f -> %.1f)" % [base_damage, new_damage])
	ctx.check(loadout.unequip_slot(ItemData.Slot.WEAPON) and health.stats.attack_power == 12.0, "desequipar volta ao dano base")
	ctx.check(not loadout.equip_from_index(5), "indice invalido nao equipa")
	ctx.check(not loadout.unequip_slot(ItemData.Slot.ARMOR), "slot vazio nao desequipa")

	# --- proporcao de vida preservada ---
	health.current_health = 60.0 # 50% de 120
	loadout.inventory.add(&"armor_heavy", 1) # +30 vida
	loadout.equip_from_index(_idx(loadout, &"armor_heavy"))
	ctx.check(health.max_health() == 150.0 and absf(health.current_health - 75.0) < 0.01, "equipar armadura: vida mantem 50%% (%.1f/150)" % health.current_health)
	loadout.unequip_slot(ItemData.Slot.ARMOR)
	ctx.check(health.max_health() == 120.0 and absf(health.current_health - 60.0) < 0.01, "desequipar: volta a 60/120 (sem exploit de troca)")

	# --- recurso ---
	combat.resource_pool.current = 30.0 # 50% de 60
	var lvl_gained: int = loadout.grant_xp(100) # nivel 2
	ctx.check(lvl_gained == 1 and loadout.progress.level == 2, "XP 100 sobe para o nivel 2")
	ctx.check(health.max_health() == 130.0 and combat.resource_pool.max_value() == 63.0 and health.stats.attack_power == 13.0, "bonus de nivel aplicado (vida 130, recurso 63, ATK 13)")
	ctx.check(absf(health.current_health - 65.0) < 0.01 and absf(combat.resource_pool.current - 31.5) < 0.01, "proporcao de vida/recurso preservada no level up")
	var dmg2: float = await _swing(tree, combat, dummy)
	ctx.check(absf(dmg2 - 13.0) < 0.01, "dano real reflete o nivel (13)")

	# --- morto continua morto apos recalculo ---
	health.apply_damage(DamageInfo.make(100000.0, null, Hitbox.new_hit_id()))
	loadout.grant_xp(10000)
	ctx.check(health.is_dead and health.current_health == 0.0, "recalculo nao revive jogador morto")
	world.queue_free()
	await tree.physics_frame
