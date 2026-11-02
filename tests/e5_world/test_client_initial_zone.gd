extends RefCounted
## Regressao (achado no tour de screenshots): o evento de zona do join chega antes de o ClientWorld conhecer o
## local_id (definido no primeiro update_frame). O visual do hub nunca era montado ate a primeira transicao.


func run(ctx: Object) -> void:
	var tree: SceneTree = ctx as SceneTree
	await tree.physics_frame
	var cw: ClientWorld = ClientWorld.new()
	tree.root.add_child(cw)
	cw.apply_event(Protocol.EVENT_ZONE, {"id": 1, "zone": "zone_hub", "phase": Protocol.ZONE_PHASE_ARRIVED, "pos": Vector3(0, 0, 6)})
	ctx.check(cw.zone_root == null, "evento de zona antes do local_id fica pendente (nada montado ainda)")
	cw.update_frame({}, 1, null, 0.0)
	ctx.check(cw.zone_root != null and cw.zone_id == "zone_hub", "ao conhecer o local_id o visual do hub e montado")
	ctx.check(not (cw.get_node("Ground") as Node3D).visible, "chao generico escondido depois de montar o hub")
	# evento de outro jogador antes do local_id: pendente, mas descartado se o id nao for o local
	var cw2: ClientWorld = ClientWorld.new()
	tree.root.add_child(cw2)
	cw2.apply_event(Protocol.EVENT_ZONE, {"id": 9, "zone": "zone_wild", "phase": Protocol.ZONE_PHASE_ARRIVED, "pos": Vector3(160, 0, 0)})
	cw2.update_frame({}, 1, null, 0.0)
	ctx.check(cw2.zone_root == null, "zona de outro jogador nao monta visual no cliente local")
	cw.queue_free()
	cw2.queue_free()
