extends RefCounted
## E5.3: mundo de Greenwood carregado de DADOS (data/areas/world/greenwood_world.json): zonas, portais,
## spawns, NPCs reais, areas de quest, enchimento de inimigos por zona, validacao de definicoes quebradas e
## geometria (servidor sem malhas x cliente com malhas/occluders). Deterministico.


func run(ctx: Object) -> void:
	await (ctx as SceneTree).physics_frame # arvore pronta (a raiz so esta "dentro da arvore" apos o 1o frame)
	_test_loads_and_validates(ctx)
	_test_zone_contents(ctx)
	_test_quest_integration_data(ctx)
	_test_rejects_broken(ctx)
	await _test_builder(ctx)


func _def() -> WorldDef:
	return WorldDef.load_region("greenwood")


func _test_loads_and_validates(ctx: Object) -> void:
	var def: WorldDef = _def()
	ctx.check(def.load_errors.is_empty(), "greenwood_world.json carrega sem erros (%s)" % str(def.load_errors))
	ctx.check(def.zone_order == (["zone_hub", "zone_wild", "zone_ruins"] as Array[String]) and def.start_zone == "zone_hub", "3 zonas: hub, selvagem, ruinas; inicio no hub")
	var errs: Array[String] = def.validate(NpcDirectory.shared(), AreaSet.shared())
	ctx.check(errs.is_empty(), "validate() sem erros de referencia/jogabilidade (%s)" % str(errs))
	# conectividade: hub <-> selvagem <-> ruinas, ida e volta
	var hub: ZoneDef = def.get_zone("zone_hub")
	var wild: ZoneDef = def.get_zone("zone_wild")
	var ruins: ZoneDef = def.get_zone("zone_ruins")
	ctx.check(hub.portals.size() == 1 and wild.portals.size() == 2 and ruins.portals.size() == 1, "portais: hub 1, selvagem 2, ruinas 1")
	ctx.check(String(hub.portals[0]["to_zone"]) == "zone_wild" and String(ruins.portals[0]["to_zone"]) == "zone_wild", "hub<->selvagem e ruinas<->selvagem conectados")
	# zona por posicao, sem sobreposicao
	ctx.check(def.zone_id_at(Vector3(0, 0, 0)) == "zone_hub" and def.zone_id_at(Vector3(200, 0, 10)) == "zone_wild" and def.zone_id_at(Vector3(400, 0, 0)) == "zone_ruins" and def.zone_id_at(Vector3(100, 0, 0)) == "", "zone_id_at resolve zona por posicao (e vazio no vazio entre zonas)")
	ctx.check(hub.sticky and not wild.sticky and not ruins.sticky, "so o hub fica sempre carregado")
	# pontos de chegada fora de qualquer portal (anti-loop) ja cobertos por validate(); confere o checkpoint
	for z: ZoneDef in [hub, wild, ruins]:
		ctx.check(z.spawns.has(z.checkpoint) and z.contains(z.checkpoint_point(0)), "%s: checkpoint existe e esta dentro da zona" % z.id)


func _test_zone_contents(ctx: Object) -> void:
	var def: WorldDef = _def()
	var hub: ZoneDef = def.get_zone("zone_hub")
	var wild: ZoneDef = def.get_zone("zone_wild")
	var ruins: ZoneDef = def.get_zone("zone_ruins")
	ctx.check(hub.enemies.is_empty() and hub.npcs.size() == 3, "hub: 3 NPCs e nenhum inimigo")
	var counts: Dictionary = _count_types(wild)
	ctx.check(int(counts.get(&"melee_grunt", 0)) >= 5, "selvagem: >= 5 melee_grunt (quest gw_clear_clearing): %d" % int(counts.get(&"melee_grunt", 0)))
	ctx.check(int(counts.get(&"thorn_alpha", 0)) == 1, "selvagem: o mini-chefe thorn_alpha (1)")
	var all_regular: bool = true
	for t: StringName in EnemyCatalog.GREENWOOD_REGULAR:
		if t != &"root_sprout" and int(counts.get(t, 0)) < 1:
			all_regular = false
	ctx.check(all_regular and not counts.has(&"root_sprout"), "selvagem: todos os tipos comuns (root_sprout so como add invocado)")
	ctx.check(not counts.has(&"blight_treant"), "chefe nao esta na lista de spawns (nasce no gatilho)")
	var rc: Dictionary = _count_types(ruins)
	ctx.check(int(rc.get(&"ranged_caster", 0)) >= 3, "ruinas: >= 3 ranged_caster (quest gw_ruin_guardian): %d" % int(rc.get(&"ranged_caster", 0)))
	ctx.check(not ruins.puzzle.is_empty() and (ruins.puzzle["plates"] as Array).size() == 2, "ruinas: puzzle de 2 placas")
	ctx.check(not ruins.encounter.is_empty() and ruins.encounter["boss"] == EnemyCatalog.BOSS_ID, "ruinas: encontro com blight_treant e gatilho")
	# o gatilho do chefe fica DEPOIS do portao (lado do salao), que e o que o puzzle protege
	var gate_x: float = (ruins.puzzle["gate_pos"] as Vector3).x
	ctx.check((ruins.encounter["trigger_center"] as Vector3).x - float(ruins.encounter["trigger_radius"]) > gate_x, "gatilho do chefe so e alcancavel depois do portao")
	# nenhuma placa fica atras do portao (senao o puzzle nao seria resolvivel)
	var plates_ok: bool = true
	for p: Dictionary in ruins.puzzle["plates"]:
		if (p["pos"] as Vector3).x >= gate_x:
			plates_ok = false
	ctx.check(plates_ok, "as placas ficam antes do portao")
	# o corredor entre os portais do selvagem fica fora do aggro dos inimigos (bots/jogadores atravessam)
	var safe: bool = true
	for e: Dictionary in wild.enemies:
		var ed: EnemyData = EnemyCatalog.data_for(e["type"])
		if absf((e["pos"] as Vector3).z) - ed.aggro_range < 3.0:
			safe = false
	ctx.check(safe, "trilha central do selvagem livre do aggro dos inimigos")


func _count_types(z: ZoneDef) -> Dictionary:
	var out: Dictionary = {}
	for e: Dictionary in z.enemies:
		out[e["type"]] = int(out.get(e["type"], 0)) + 1
	return out


func _test_quest_integration_data(ctx: Object) -> void:
	var def: WorldDef = _def()
	var npcs: NpcDirectory = NpcDirectory.shared()
	var hub: ZoneDef = def.get_zone("zone_hub")
	var all_in: bool = true
	for n: String in npcs.ids():
		if not hub.contains(npcs.get_npc(n)["position"] as Vector3, -1.0):
			all_in = false
		ctx.check(not bool(JsonDir.read_json("res://data/npcs/%s.json" % n)["data"].get("placeholder", true)), "NPC %s: posicao real (placeholder=false)" % n)
	ctx.check(all_in, "NPCs no hub, com posicoes reais")
	var areas: AreaSet = AreaSet.shared()
	var ruins: ZoneDef = def.get_zone("zone_ruins")
	var gate: Vector3 = areas.areas["area_ruins_gate"]["center"]
	var hall: Vector3 = areas.areas["area_ruins_hall"]["center"]
	ctx.check(ruins.contains(gate, -2.0) and ruins.contains(hall, -2.0), "areas de quest nas ruinas")
	var gate_x: float = (ruins.puzzle["gate_pos"] as Vector3).x
	ctx.check(gate.x < gate_x and hall.x > gate_x, "area_ruins_gate antes do portao, area_ruins_hall depois (puzzle precede o salao)")
	# ruin_guardian resolvido: a quest aponta para o chefe existente e nao ha pendencias
	var q: QuestCatalog = QuestCatalog.shared()
	var qd: QuestDef = q.get_quest("gw_ruin_guardian")
	var target: String = ""
	for o: QuestDef.Objective in qd.objectives:
		if o.id == "kill_guardian":
			target = o.target
	ctx.check(target == String(EnemyCatalog.BOSS_ID) and EnemyCatalog.data_for(&"blight_treant") != null, "gw_ruin_guardian mata blight_treant (existente)")
	var pending: Dictionary = QuestCatalog.load_pending_refs()
	ctx.check((pending.get("enemies", []) as Array).is_empty() and (pending.get("items", []) as Array).is_empty(), "_pending_refs.json sem pendencias")
	var refs: Array[String] = q.validate_refs(ContentRegistryHolder.get_registry(), npcs, areas, pending)
	ctx.check(refs.is_empty(), "referencias das quests validas com o mundo real: %s" % str(refs))


func _test_rejects_broken(ctx: Object) -> void:
	var base: Dictionary = JsonDir.read_json("res://data/areas/world/greenwood_world.json")["data"]
	var npcs: NpcDirectory = NpcDirectory.shared()
	var areas: AreaSet = AreaSet.shared()
	# portal para zona inexistente
	var d1: Dictionary = base.duplicate(true)
	d1["zones"][0]["portals"][0]["to_zone"] = "zone_nada"
	ctx.check(_errors_of(d1, npcs, areas).size() > 0, "portal para zona inexistente: invalido")
	# spawn dentro do raio de um portal (loop de portais)
	var d2: Dictionary = base.duplicate(true)
	d2["zones"][1]["spawns"]["from_hub"][0] = [153, 0.05, 0]
	ctx.check(_errors_of(d2, npcs, areas).size() > 0, "spawn dentro de portal: invalido")
	# zona sem caminho de volta ao hub
	var d3: Dictionary = base.duplicate(true)
	d3["zones"][2]["portals"] = []
	ctx.check(_errors_of(d3, npcs, areas).size() > 0, "zona armadilha (sem portal de volta): invalida")
	# inimigo desconhecido
	var d4: Dictionary = base.duplicate(true)
	d4["zones"][1]["enemies"][0]["type"] = "ruin_guardian"
	ctx.check(_errors_of(d4, npcs, areas).size() > 0, "inimigo inexistente (ruin_guardian): invalido")
	# zonas sobrepostas
	var d5: Dictionary = base.duplicate(true)
	d5["zones"][1]["center"] = [40, 0, 0]
	ctx.check(_errors_of(d5, npcs, areas).size() > 0, "zonas sobrepostas/coladas: invalidas")
	# NPC fora da zona
	var d6: Dictionary = base.duplicate(true)
	d6["zones"][0]["size"] = [20, 20]
	ctx.check(_errors_of(d6, npcs, areas).size() > 0, "NPC fora da zona: invalido")
	# estrutura invalida
	var w: WorldDef = WorldDef.new()
	ctx.check(w.parse([]) != "" and w.parse({"zones": []}) != "" and w.parse({"start_zone": "x", "zones": [{"id": "x"}]}) != "", "estruturas quebradas rejeitadas no parse")
	var bad_start: Dictionary = base.duplicate(true)
	bad_start["start_zone"] = "zone_nada"
	ctx.check(WorldDef.new().parse(bad_start) != "", "start_zone inexistente: invalido")
	var z: ZoneDef = ZoneDef.new()
	ctx.check(z.parse({"id": "zone_x", "center": [0, 0, 0], "size": [60, 60], "spawns": {"a": [[0, 0, 0]]}, "checkpoint": "b"}) != "", "checkpoint inexistente: invalido")
	ctx.check(ZoneDef.new().parse({"id": "zone_x", "center": [0, 0, 0], "size": [60, 60], "spawns": {"a": [[0, 0, NAN]]}, "checkpoint": "a"}) != "", "spawn nao finito: invalido")


func _errors_of(raw: Dictionary, npcs: NpcDirectory, areas: AreaSet) -> Array[String]:
	var w: WorldDef = WorldDef.new()
	w.region = "greenwood"
	var err: String = w.parse(raw)
	if not err.is_empty():
		return [err]
	return w.validate(npcs, areas)


func _test_builder(ctx: Object) -> void:
	var def: WorldDef = _def()
	var holder: Node3D = Node3D.new()
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	tree.root.add_child(holder)
	var ruins: ZoneDef = def.get_zone("zone_ruins")
	var server_root: Node3D = WorldBuilder.build_zone(holder, ruins, false)
	var client_root: Node3D = WorldBuilder.build_zone(holder, ruins, true, NpcDirectory.shared())
	ctx.check(server_root.find_children("*", "MeshInstance3D", true, false).is_empty(), "servidor: geometria sem malhas")
	ctx.check(client_root.find_children("*", "MeshInstance3D", true, false).size() > 10, "cliente: geometria com malhas placeholder")
	var gate_s: StaticBody3D = WorldBuilder.gate_of(server_root)
	var gate_c: StaticBody3D = WorldBuilder.gate_of(client_root)
	ctx.check(gate_s != null and gate_c != null and gate_s.collision_layer == gate_c.collision_layer, "portao existe nos dois lados com a mesma colisao")
	# occluders: corpos do grupo `occluder` do cliente tem malha filha (compat. com o OcclusionFader do E1)
	var occ_total: int = 0
	var occ_with_mesh: int = 0
	for n: Node in client_root.get_children():
		if n.is_in_group(WorldBuilder.OCCLUDER_GROUP):
			occ_total += 1
			if not n.find_children("*", "MeshInstance3D", true, false).is_empty():
				occ_with_mesh += 1
	ctx.check(occ_total >= 8 and occ_total == occ_with_mesh, "occluders do grupo `occluder` (%d) todos com MeshInstance3D" % occ_total)
	# o chao NAO e occluder (senao apagaria a cena inteira)
	var floor_node: Node = client_root.get_node("Floor")
	ctx.check(not floor_node.is_in_group(WorldBuilder.OCCLUDER_GROUP), "chao nao e occluder")
	# portao abre/fecha (colisao e malha)
	var layer: int = gate_c.collision_layer
	WorldBuilder.set_gate_open(client_root, true)
	WorldBuilder.set_gate_open(server_root, true)
	ctx.check(gate_c.collision_layer == 0 and gate_s.collision_layer == 0 and not (gate_c.get_node("Mesh") as Node3D).visible and not gate_c.is_in_group(WorldBuilder.OCCLUDER_GROUP), "portao aberto: sem colisao, malha escondida, fora do grupo occluder")
	WorldBuilder.set_gate_open(client_root, false)
	ctx.check(gate_c.collision_layer == layer and (gate_c.get_node("Mesh") as Node3D).visible and gate_c.is_in_group(WorldBuilder.OCCLUDER_GROUP), "portao fechado de novo: colisao e malha restauradas")
	WorldBuilder.set_plate_lit(client_root, 0, true)
	var mat: StandardMaterial3D = (client_root.get_node("Plate_0") as MeshInstance3D).material_override as StandardMaterial3D
	ctx.check(mat.albedo_color == WorldBuilder.PLATE_ON and mat.emission_enabled, "placa acesa muda a cor")
	# o OcclusionFader do E1 funciona com os occluders do mundo (pilar entre camera e jogador some parcialmente)
	var fader_ok: bool = await _fader_check(ctx, holder, client_root)
	ctx.check(fader_ok, "OcclusionFader do E1 enxerga os occluders do mundo")
	holder.queue_free()
	await tree.process_frame


func _fader_check(_ctx: Object, holder: Node3D, client_root: Node3D) -> bool:
	var cam: Camera3D = Camera3D.new()
	holder.add_child(cam)
	var target: Node3D = Node3D.new()
	holder.add_child(target)
	# pilar Pillar1 em (372, 3, -17); jogador logo atras dele em relacao a camera
	cam.global_position = Vector3(372.0, 8.0, -11.0)
	target.global_position = Vector3(372.0, 0.0, -23.0)
	cam.look_at(target.global_position + Vector3.UP * 0.9)
	var fader: OcclusionFader = OcclusionFader.new()
	fader.camera = cam
	fader.target = target
	holder.add_child(fader)
	fader.refresh_blocked()
	var n: int = fader.faded_count()
	fader.restore_all()
	return n >= 1 and client_root != null


class ContentRegistryHolder extends RefCounted:
	static var _reg: ContentRegistry

	static func get_registry() -> ContentRegistry:
		if _reg == null:
			_reg = ContentRegistry.new()
			_reg.load_all()
		return _reg
