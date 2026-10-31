extends RefCounted
## Pickups: adicionam uma vez, respeitam capacidade, parcial, permanecem se cheio.
## Trecho de sobreposicao fisica usa frames reais (DEPENDE DE TIMING, com folga).

## NOTA: nunca passar instancia ja liberada como argumento de funcao (Godot 4.7.2 da signal 11);
## por isso os testes usam is_instance_valid(x) inline.
const H = preload("res://tests/e2/loop_helpers.gd")


func run(ctx: Object) -> void:
	var tree: SceneTree = ctx as SceneTree
	var world: Node3D = H.make_world(tree)
	var player: Player = H.spawn_player(world, Vector3(0, 0.05, 0))
	var loadout: PlayerLoadout = player.get_node("Loadout") as PlayerLoadout
	await tree.physics_frame

	# --- coleta direta, uma vez ---
	var p: Pickup = Pickup.create(&"potion_minor", 3)
	world.add_child(p)
	p.position = Vector3(20, 0.1, 0)
	await tree.physics_frame # (area precisa existir no servidor de fisica antes de ser liberada)
	var got: Array[int] = [0]
	p.collected.connect(func(_id: StringName, q: int) -> void: got[0] += q)
	ctx.check(p.try_collect(loadout), "coleta direta ok")
	ctx.check(not p.try_collect(loadout), "segunda coleta do mesmo pickup nao faz nada")
	ctx.check(loadout.inventory.count(&"potion_minor") == 3 and got[0] == 3 and p.is_done(), "adicionado uma vez (3), sinal uma vez")

	# --- por sobreposicao com a Hurtbox do jogador ---
	var p2: Pickup = Pickup.create(&"sword_basic", 1)
	var c2: Array[int] = [0]
	p2.collected.connect(func(_id: StringName, q: int) -> void: c2[0] += q)
	world.add_child(p2)
	p2.global_position = player.global_position + Vector3(0.3, 0.1, 0.0)
	var frames: int = 0
	while c2[0] == 0 and frames < 30:
		await tree.physics_frame
		frames += 1
	ctx.check(c2[0] == 1 and loadout.inventory.count(&"sword_basic") == 1, "pickup coletado ao tocar o jogador (%d frames)" % frames)
	for i: int in 4:
		await tree.physics_frame
	ctx.check(c2[0] == 1 and loadout.inventory.count(&"sword_basic") == 1, "nao duplica nos frames seguintes")
	ctx.check(not is_instance_valid(p2), "pickup removido do chao")

	# --- capacidade cheia: permanece, depois coleta quando ha espaco ---
	loadout.inventory.capacity = loadout.inventory.stack_count() # cheio
	var p3: Pickup = Pickup.create(&"armor_leather", 1)
	var c3: Array[int] = [0]
	p3.collected.connect(func(_id: StringName, q: int) -> void: c3[0] += q)
	world.add_child(p3)
	p3.global_position = player.global_position + Vector3(0.2, 0.1, 0.0)
	for i: int in 6:
		await tree.physics_frame
	ctx.check(c3[0] == 0 and is_instance_valid(p3) and not p3.is_queued_for_deletion(), "inventario cheio: pickup permanece no chao")
	ctx.check(loadout.inventory.count(&"armor_leather") == 0, "nada entrou no inventario cheio")
	loadout.inventory.capacity += 1
	frames = 0
	while c3[0] == 0 and frames < 30:
		await tree.physics_frame
		frames += 1
	ctx.check(c3[0] == 1 and loadout.inventory.count(&"armor_leather") == 1, "com espaco, o pickup e coletado depois")

	# --- coleta parcial de pilha ---
	loadout.inventory.capacity = loadout.inventory.stack_count() + 1
	loadout.inventory.add(&"scrap_material", 45) # pilha max 50 => cabem +5 na pilha; capacidade cheia
	var p4: Pickup = Pickup.create(&"scrap_material", 10)
	world.add_child(p4)
	p4.position = Vector3(40, 0.1, 0)
	ctx.check(not p4.try_collect(loadout), "pilha so cabe parcialmente: pickup nao some")
	ctx.check(p4.quantity == 5 and loadout.inventory.count(&"scrap_material") == 50, "parcial: 5 coletados, 5 restam no chao")
	world.queue_free()
	await tree.physics_frame
