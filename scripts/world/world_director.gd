class_name WorldDirector
extends RefCounted
## Diretor do mundo no SERVIDOR (E5.3): zonas carregadas sob demanda (inimigos, puzzle, chefe), portais e
## transicao entre zonas, respawn por checkpoint, puzzle de placas, encontro do chefe com gatilho.
## Autoritativo: so le posicoes/estados do ServerWorld; o cliente nunca pede nada disto (nenhum RPC novo).
## Regras anti-softlock (ver docs/E5_WORLD.md):
##  - toda zona tem portal de volta ao hub; spawns de chegada ficam fora do raio de qualquer portal e o
##    jogador recebe `portal_lock` apos chegar (nao cai em loop de portais);
##  - transicao dura `transition_time`; morrer ou desconectar durante ela cancela e nada fica preso;
##  - zona sem jogadores por `unload_grace` e descarregada (inimigos removidos, puzzle e chefe reiniciam);
##  - portao do puzzle nunca fecha com gente dentro: so reinicia quando a zona esvazia;
##  - jogador morto reaparece no checkpoint da zona apos `respawn_delay`; wipe reinicia o chefe.

class ZoneRuntime extends RefCounted:
	var zone: ZoneDef
	var root: Node3D
	var loaded: bool = false
	var empty_time: float = 0.0
	var puzzle: PuzzleState = null
	var boss_state: int = Protocol.BOSS_ARMED
	var boss_id: int = 0
	var boss_retry_left: float = 0.0
	var spawn_failures: int = 0

var world: ServerWorld
var world_def: WorldDef
## false: zonas carregam sem inimigos nem chefe (testes de puzzle/transicao).
var spawn_enemies: bool = true
var runtimes: Dictionary = {}  ## zone_id -> ZoneRuntime
var _scene_cache: Array[PackedScene] = []  ## cenas de inimigos aquecidas (evita engasgo ao carregar uma zona)
var geometry_root: Node3D
## Contadores para testes/telemetria.
var stats: Dictionary = {"loads": 0, "unloads": 0, "transitions": 0, "respawns": 0, "boss_resets": 0, "aborted": 0}


func _init(p_world: ServerWorld, p_def: WorldDef) -> void:
	world = p_world
	world_def = p_def
	for id: String in world_def.zone_order:
		var rt: ZoneRuntime = ZoneRuntime.new()
		rt.zone = world_def.get_zone(id)
		runtimes[id] = rt


## Cria a colisao de todas as zonas (estatica, sempre presente) sob um no "World".
func build_geometry() -> Node3D:
	geometry_root = Node3D.new()
	geometry_root.name = "World"
	world.add_child(geometry_root)
	for id: String in world_def.zone_order:
		var rt: ZoneRuntime = runtimes[id]
		rt.root = WorldBuilder.build_zone(geometry_root, rt.zone, false)
	return geometry_root


func start() -> void:
	_warm_scenes()
	for id: String in world_def.zone_order:
		if (runtimes[id] as ZoneRuntime).zone.sticky or id == world_def.start_zone:
			load_zone(id)


## Mantem as cenas de inimigos em memoria: a 1a carga de uma zona nao trava o tick do servidor.
func _warm_scenes() -> void:
	if not spawn_enemies:
		return
	var seen: Dictionary = {}
	for id: String in world_def.zone_order:
		var zone: ZoneDef = (runtimes[id] as ZoneRuntime).zone
		var types: Array[StringName] = []
		for e: Dictionary in zone.enemies:
			types.append(e["type"])
		if not zone.encounter.is_empty():
			types.append(zone.encounter["boss"])
		for t: StringName in types:
			var path: String = EnemyCatalog.scene_path(t)
			if not seen.has(path) and ResourceLoader.exists(path):
				seen[path] = true
				var scene: PackedScene = load(path) as PackedScene
				if scene != null:
					_scene_cache.append(scene)
				EnemyCatalog.data_for(t)
	# adds invocados (root_sprout, forest_stalker...) tambem
	for t2: StringName in EnemyCatalog.all_ids():
		var p2: String = EnemyCatalog.scene_path(t2)
		if not seen.has(p2) and ResourceLoader.exists(p2):
			seen[p2] = true
			_scene_cache.append(load(p2) as PackedScene)


func start_zone_id() -> String:
	return world_def.start_zone


func spawn_name_for_new() -> String:
	return world_def.get_zone(world_def.start_zone).checkpoint


func spawn_for(zone_id: String, spawn_name: String, index: int) -> Vector3:
	return world_def.get_zone(zone_id).spawn_point(spawn_name, index)


func runtime(zone_id: String) -> ZoneRuntime:
	return runtimes.get(zone_id) as ZoneRuntime


func is_loaded(zone_id: String) -> bool:
	var rt: ZoneRuntime = runtime(zone_id)
	return rt != null and rt.loaded


## Jogadores com transicao em andamento PARA `zone_id` (contam como presentes para nao descarregar).
func incoming_count(zone_id: String) -> int:
	var n: int = 0
	for id: int in world.get_player_ids():
		var slot: ServerWorld.PlayerSlot = world.get_slot(id)
		if slot != null and slot.transit_left > 0.0 and slot.transit_to == zone_id:
			n += 1
	return n


# ------------------------------------------------------------------ carregar / descarregar

## Carrega a zona (inimigos, puzzle fechado, chefe armado). Idempotente.
func load_zone(zone_id: String) -> bool:
	var rt: ZoneRuntime = runtime(zone_id)
	if rt == null:
		return false
	if rt.loaded:
		return true
	rt.empty_time = 0.0
	rt.puzzle = PuzzleState.from_zone(rt.zone)
	if rt.root != null:
		WorldBuilder.set_gate_open(rt.root, false)
	rt.boss_state = Protocol.BOSS_ARMED
	rt.boss_id = 0
	rt.boss_retry_left = 0.0
	rt.spawn_failures = 0
	rt.loaded = true
	if spawn_enemies:
		for e: Dictionary in rt.zone.enemies:
			var path: String = EnemyCatalog.scene_path(e["type"])
			if path.is_empty() or not ResourceLoader.exists(path) or world.spawn_enemy(path, e["pos"] as Vector3, zone_id) == 0:
				rt.spawn_failures += 1
				push_error("WorldDirector: falha ao criar %s em %s" % [e["type"], zone_id])
	stats["loads"] = int(stats["loads"]) + 1
	return true


## Descarrega: remove inimigos (e adds), reinicia puzzle e chefe. Sem jogadores presentes, nada a avisar.
func unload_zone(zone_id: String) -> void:
	var rt: ZoneRuntime = runtime(zone_id)
	if rt == null or not rt.loaded:
		return
	for id: int in world.enemy_ids_in_zone(zone_id):
		world.despawn_enemy(id)
	if rt.puzzle != null:
		rt.puzzle.reset()
	if rt.root != null:
		WorldBuilder.set_gate_open(rt.root, false)
	rt.boss_state = Protocol.BOSS_ARMED
	rt.boss_id = 0
	rt.loaded = false
	stats["unloads"] = int(stats["unloads"]) + 1


# ------------------------------------------------------------------ tick

func tick(delta: float) -> void:
	for id: int in world.get_player_ids():
		var slot: ServerWorld.PlayerSlot = world.get_slot(id)
		if slot != null:
			_tick_player(slot, delta)
	for zid: String in world_def.zone_order:
		var rt: ZoneRuntime = runtimes[zid]
		if rt.loaded:
			_tick_zone(rt, delta)


func _tick_player(slot: ServerWorld.PlayerSlot, delta: float) -> void:
	slot.portal_lock = maxf(0.0, slot.portal_lock - delta)
	if slot.health.is_dead:
		if slot.respawn_left == 0.0:
			slot.respawn_left = world_def.respawn_delay
		slot.respawn_left -= delta
		if slot.respawn_left <= 0.0:
			_respawn(slot)
		return
	if slot.transit_left > 0.0:
		slot.transit_left -= delta
		if slot.transit_left <= 0.0:
			_finish_transition(slot)
		return
	if slot.portal_lock <= 0.0 and is_instance_valid(slot.node):
		_check_portals(slot)


func _tick_zone(rt: ZoneRuntime, delta: float) -> void:
	var zid: String = rt.zone.id
	var members: Array[int] = world.players_in_zone(zid)
	if members.is_empty() and incoming_count(zid) == 0 and not rt.zone.sticky:
		rt.empty_time += delta
		if rt.empty_time >= world_def.unload_grace:
			unload_zone(zid)
			return
	else:
		rt.empty_time = 0.0
	var alive: Array[Vector3] = []
	for id: int in members:
		var n: Player = world.get_player_node(id)
		if n != null and not world.is_player_dead(id):
			alive.append(n.global_position)
	if rt.puzzle != null and rt.puzzle.update(alive, delta):
		_apply_puzzle(rt)
	if not rt.zone.encounter.is_empty():
		_tick_encounter(rt, alive, delta)


# ------------------------------------------------------------------ portais / transicao

func _check_portals(slot: ServerWorld.PlayerSlot) -> void:
	var zone: ZoneDef = world_def.get_zone(slot.zone_id)
	if zone == null:
		return
	var pos: Vector3 = slot.node.global_position
	for portal: Dictionary in zone.portals:
		var c: Vector3 = portal["pos"]
		if Vector2(pos.x - c.x, pos.z - c.z).length() <= float(portal["radius"]) and absf(pos.y - c.y) <= 3.0:
			begin_transition(slot.id, String(portal["to_zone"]), String(portal["to_spawn"]))
			return


## Inicia a troca de zona (o servidor decide; portais chamam isto). Carrega a zona de destino antes.
func begin_transition(entity_id: int, to_zone: String, to_spawn: String) -> bool:
	var slot: ServerWorld.PlayerSlot = world.get_slot(entity_id)
	var dest: ZoneDef = world_def.get_zone(to_zone)
	if slot == null or dest == null or slot.health.is_dead or slot.transit_left > 0.0:
		return false
	if not load_zone(to_zone):
		stats["aborted"] = int(stats["aborted"]) + 1
		slot.portal_lock = world_def.portal_lock
		return false
	slot.transit_to = to_zone
	slot.transit_spawn = to_spawn
	slot.transit_left = maxf(world_def.transition_time, 0.001)
	slot.move = Vector2.ZERO
	slot.pending_actions = 0
	world.emit_to_player(entity_id, Protocol.EVENT_ZONE, {
		"id": entity_id, "zone": to_zone, "phase": Protocol.ZONE_PHASE_LEAVING, "pos": dest.spawn_point(to_spawn, 0)})
	return true


func _finish_transition(slot: ServerWorld.PlayerSlot) -> void:
	var dest_id: String = slot.transit_to
	var old_zone: String = slot.zone_id
	var spawn_name: String = slot.transit_spawn
	slot.transit_left = 0.0
	slot.transit_to = ""
	slot.transit_spawn = ""
	if not load_zone(dest_id):
		stats["aborted"] = int(stats["aborted"]) + 1
		return
	var dest: ZoneDef = world_def.get_zone(dest_id)
	var pos: Vector3 = dest.spawn_point(spawn_name, world.players_in_zone(dest_id).size())
	slot.zone_id = dest_id
	slot.portal_lock = world_def.portal_lock
	world.teleport_player(slot.id, pos)
	world.clear_threat_in_zone(slot.id, old_zone)
	world.refresh_difficulty()
	stats["transitions"] = int(stats["transitions"]) + 1
	for ev: Dictionary in world.state_events_for_player(slot.id):
		world.emit_to_player(slot.id, int(ev["kind"]), ev["data"] as Dictionary)


func on_player_added(_entity_id: int) -> void:
	var rt: ZoneRuntime = runtime(world_def.start_zone)
	if rt != null:
		rt.empty_time = 0.0
		load_zone(world_def.start_zone)


# ------------------------------------------------------------------ morte / respawn

func on_player_died(entity_id: int) -> void:
	var slot: ServerWorld.PlayerSlot = world.get_slot(entity_id)
	if slot == null:
		return
	if slot.transit_left > 0.0: # morreu durante a transicao: cancela, reaparece na zona de origem
		slot.transit_left = 0.0
		slot.transit_to = ""
		slot.transit_spawn = ""
		stats["aborted"] = int(stats["aborted"]) + 1
	slot.respawn_left = world_def.respawn_delay


func _respawn(slot: ServerWorld.PlayerSlot) -> void:
	var zone: ZoneDef = world_def.get_zone(slot.zone_id)
	slot.respawn_left = 0.0
	if zone == null:
		return
	var pos: Vector3 = zone.checkpoint_point(slot.spawn_index)
	if not world.revive_player(slot.id):
		return
	world.teleport_player(slot.id, pos)
	world.clear_threat_in_zone(slot.id, slot.zone_id)
	slot.portal_lock = world_def.portal_lock
	stats["respawns"] = int(stats["respawns"]) + 1
	world.event_emitted.emit(Protocol.EVENT_RESPAWN, {"id": slot.id, "zone": slot.zone_id, "pos": pos})


# ------------------------------------------------------------------ puzzle

func _apply_puzzle(rt: ZoneRuntime) -> void:
	if rt.root != null:
		WorldBuilder.set_gate_open(rt.root, rt.puzzle.open)
	world.event_emitted.emit(Protocol.EVENT_PUZZLE, rt.puzzle.to_event(rt.zone.id))


# ------------------------------------------------------------------ chefe

func _tick_encounter(rt: ZoneRuntime, alive: Array[Vector3], delta: float) -> void:
	var enc: Dictionary = rt.zone.encounter
	rt.boss_retry_left = maxf(0.0, rt.boss_retry_left - delta)
	match rt.boss_state:
		Protocol.BOSS_ARMED:
			if not spawn_enemies or rt.boss_retry_left > 0.0:
				return
			var c: Vector3 = enc["trigger_center"]
			for p: Vector3 in alive:
				if Vector2(p.x - c.x, p.z - c.z).length() <= float(enc["trigger_radius"]):
					_start_boss(rt)
					return
		Protocol.BOSS_ACTIVE:
			if alive.is_empty(): # wipe (ou todos fugiram): o encontro reinicia do zero
				_reset_boss(rt)


func _start_boss(rt: ZoneRuntime) -> void:
	var enc: Dictionary = rt.zone.encounter
	var path: String = EnemyCatalog.scene_path(enc["boss"])
	var id: int = world.spawn_enemy(path, enc["spawn"] as Vector3, rt.zone.id) if not path.is_empty() else 0
	if id == 0:
		rt.boss_retry_left = 5.0
		push_error("WorldDirector: falha ao criar o chefe %s" % enc["boss"])
		return
	rt.boss_id = id
	rt.boss_state = Protocol.BOSS_ACTIVE
	_emit_boss(rt)


func _reset_boss(rt: ZoneRuntime) -> void:
	world.despawn_enemy(rt.boss_id)
	rt.boss_id = 0
	rt.boss_state = Protocol.BOSS_ARMED
	stats["boss_resets"] = int(stats["boss_resets"]) + 1
	_emit_boss(rt)


func on_enemy_defeated(entity_id: int) -> void:
	for zid: String in world_def.zone_order:
		var rt: ZoneRuntime = runtimes[zid]
		if rt.boss_id == entity_id and rt.boss_state == Protocol.BOSS_ACTIVE:
			rt.boss_state = Protocol.BOSS_DEFEATED
			_emit_boss(rt)


func _emit_boss(rt: ZoneRuntime) -> void:
	world.event_emitted.emit(Protocol.EVENT_BOSS, boss_event(rt))


func boss_event(rt: ZoneRuntime) -> Dictionary:
	var enc: Dictionary = rt.zone.encounter
	return {"zone": rt.zone.id, "encounter": String(enc["id"]), "boss": String(enc["boss"]), "state": rt.boss_state}


## Estado atual de puzzle/chefe da zona (catch-up para quem chega).
func zone_state_events(zone_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var rt: ZoneRuntime = runtime(zone_id)
	if rt == null:
		return out
	if rt.puzzle != null:
		out.append({"kind": Protocol.EVENT_PUZZLE, "data": rt.puzzle.to_event(zone_id)})
	if not rt.zone.encounter.is_empty():
		out.append({"kind": Protocol.EVENT_BOSS, "data": boss_event(rt)})
	return out
