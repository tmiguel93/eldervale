class_name ServerWorld
extends Node3D
## Mundo autoritativo do servidor dedicado (headless): geometria da arena (sem malhas), inimigos
## (Enemy/EnemyAI do E2) e jogadores (player.tscn em modo `use_external_input`). Nada de Input,
## camera, HUD ou feedback visual. Todo dano/morte/XP/drop e decidido aqui; os resultados saem como
## eventos (`event_emitted`) que a sessao replica. O cliente so fornece input (set_input).
## Ordem por tick de fisica: apply_inputs (prioridade -20) -> PlayerCombat (-10) -> Player/Enemy (0).

signal event_emitted(kind: int, data: Dictionary)
## E4: inimigo morto por um jogador. `items` = [{item_id: String, qty: int}] realmente concedidos ao
## inventario do matador (persist_drops) ou os drops rolados (modo dev). XP ja foi dado pelo Enemy (E2).
signal enemy_killed(enemy_id: int, killer_id: int, xp: int, items: Array)
## E5.1: o golpe final foi de um jogador. `enemy_type` = EnemyData.id (progresso de quests de caca).
signal player_killed_enemy(killer_id: int, enemy_id: int, enemy_type: String)
## E5.3: evento so para UM jogador (catch-up de zona/puzzle/chefe ao entrar ou trocar de zona).
signal event_to_player(entity_id: int, kind: int, data: Dictionary)
## E5.4 (loot individual): o pickup `pickup_id` do jogador `owner_id` foi coletado e o item JA esta no inventario dele
## (memoria do servidor). A sessao paga o mesmo item no backend (chave `loot:<sessao>:<pickup_id>:<personagem>`).
signal pickup_collected(pickup_id: int, owner_id: int, item_id: String, qty: int, inst: Dictionary)
## E5.4: `player_id` (nao matador) recebeu `xp` por participar da morte de `enemy_id` (ja somado na memoria do servidor).
signal participant_rewarded(enemy_id: int, player_id: int, xp: int)

const PLAYER_SCENE_PATH: String = "res://scenes/player/player.tscn"
## Nos puramente cosmeticos removidos das instancias do servidor.
const COSMETIC_NODES: Array[String] = ["HitFlash", "DamageNumbers", "DeathEffect"]


class PlayerSlot extends RefCounted:
	var id: int = 0
	var peer_id: int = 0
	var player_name: String = ""
	var node: Player
	var combat: PlayerCombat
	var health: HealthComponent
	var loadout: PlayerLoadout
	var spawn_index: int = 0
	var move: Vector2 = Vector2.ZERO
	var yaw: float = 0.0
	var pending_actions: int = 0
	## E5.3 (modo mundo): zona atual, transicao em andamento, respawn pendente e trava de portal.
	var zone_id: String = ""
	var transit_left: float = 0.0
	var transit_to: String = ""
	var transit_spawn: String = ""
	var respawn_left: float = 0.0
	var portal_lock: float = 0.0


var settings: ServerSettings
var server_tick: int = 0
var geometry: Node3D

var _next_id: int = 1
var _players: Dictionary = {} ## entity_id -> PlayerSlot
var _enemies: Dictionary = {} ## entity_id -> Enemy
var _node_ids: Dictionary = {} ## instance_id -> entity_id
var _enemies_active: bool = true
var _last_hit_by: Dictionary = {} ## target entity_id -> entity_id do ultimo jogador que causou dano
var _difficulty: DifficultyScaling ## E5.2: escala por numero de jogadores (data/difficulty)
## E5.3: diretor do mundo (null = arena de teste do E1/E3, comportamento anterior intacto).
var director: WorldDirector = null
var _entity_zone: Dictionary = {}   ## entity_id (inimigo) -> zone_id
var _zone_active: Dictionary = {}   ## zone_id -> havia jogador vivo na zona no ultimo tick
## E5.4: loot individual. `_contrib`: inimigo -> {jogador: dano acumulado} (nao decai, ao contrario da ameaca);
## `_add_ids`: inimigos invocados por outros (adds): nao rolam loot nem repartem XP (anti-farm).
var loot: LootManager
var _contrib: Dictionary = {}
var _add_ids: Dictionary = {}


func _ready() -> void:
	process_physics_priority = -20
	if settings == null:
		settings = ServerSettings.new()
	_difficulty = DifficultyScaling.load_default()
	loot = LootManager.new(self, settings)
	loot.alloc_id = _alloc_id
	var seed_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	seed_rng.randomize()
	loot.base_seed = settings.loot_seed if settings.loot_seed >= 0 else seed_rng.randi()
	if not settings.world_id.is_empty():
		var def: WorldDef = WorldDef.shared(settings.world_id)
		var errs: Array[String] = def.validate(NpcDirectory.shared(), AreaSet.shared())
		if errs.is_empty():
			director = WorldDirector.new(self, def)
			director.spawn_enemies = settings.spawn_enemies
			geometry = director.build_geometry()
			director.start()
			return
		for e: String in errs:
			push_error("ServerWorld: mundo '%s' invalido: %s (usando a arena de teste)" % [settings.world_id, e])
	geometry = ArenaGeometry.build(self, false)
	if settings.spawn_enemies:
		for entry: Array in TestArena.ENEMY_SPAWNS:
			spawn_enemy(entry[0] as String, entry[1] as Vector3)


func _physics_process(delta: float) -> void:
	apply_inputs()
	if director != null:
		director.tick(delta)
	if settings.individual_loot:
		step_loot(delta)


func _alloc_id() -> int:
	var id: int = _next_id
	_next_id += 1
	return id


## E5.4: avanca TTL e auto-coleta dos pickups individuais (testes chamam direto, sem depender de frames).
func step_loot(delta: float) -> void:
	for p: LootManager.LootPickup in loot.step(delta):
		pickup_collected.emit(p.id, p.owner_id, p.item_id, p.qty, p.inst)


## Entidades de snapshot (kind 3) dos pickups DO jogador (nunca os de outro dono).
func pickup_entities_for(entity_id: int) -> Array:
	if not settings.individual_loot or loot == null or not _players.has(entity_id):
		return []
	var node: Player = get_player_node(entity_id)
	var center: Vector3 = node.global_position if node != null else Vector3.ZERO
	return loot.entities_for(entity_id, zone_of_player(entity_id), center, settings.aoi_radius)


## E6.2: zona segura para o respec de talentos. Modo mundo: so a zona `sticky` (o hub, sem inimigos). Sem mundo (arena/dev) nao ha hub:
## vale sempre (regra simples documentada em docs/E6_TALENTS.md).
func is_safe_zone(entity_id: int) -> bool:
	if director == null:
		return true
	var slot: PlayerSlot = _players.get(entity_id) as PlayerSlot
	if slot == null:
		return false
	var zone: ZoneDef = director.world_def.get_zone(slot.zone_id)
	return zone != null and zone.sticky


## E5.4 (crafting): "" = o jogador esta ao alcance da estacao `station_id` na zona em que esta;
## "no_station" = a zona dele nao tem essa estacao (ou nao ha mundo); "too_far" = tem, mas fora do raio.
func station_status(entity_id: int, station_id: String) -> String:
	if director == null:
		return "no_station"
	var slot: PlayerSlot = _players.get(entity_id) as PlayerSlot
	if slot == null or not is_instance_valid(slot.node):
		return "no_station"
	var zone: ZoneDef = director.world_def.get_zone(slot.zone_id)
	if zone == null:
		return "no_station"
	var found: bool = false
	for st: Dictionary in zone.stations:
		if String(st["id"]) != station_id:
			continue
		found = true
		var sp: Vector3 = st["pos"]
		var pp: Vector3 = slot.node.global_position
		if Vector2(pp.x - sp.x, pp.z - sp.z).length() <= float(st["radius"]):
			return ""
	return "too_far" if found else "no_station"


# ------------------------------------------------------------------ jogadores

func player_count() -> int:
	return _players.size()


func get_player_node(entity_id: int) -> Player:
	var slot: PlayerSlot = _players.get(entity_id) as PlayerSlot
	if slot == null or not is_instance_valid(slot.node):
		return null
	return slot.node


func get_player_ids() -> Array[int]:
	var ids: Array[int] = []
	for id: int in _players:
		ids.append(id)
	return ids


## Cria o jogador do servidor para `peer_id`. Devolve o entity_id (> 0) ou 0 em falha.
func add_player(peer_id: int, player_name: String, starting_items: bool = true) -> int:
	if _players.size() >= settings.max_players:
		return 0
	var scene: PackedScene = load(PLAYER_SCENE_PATH) as PackedScene
	if scene == null:
		push_error("ServerWorld: player.tscn indisponivel.")
		return 0
	var player: Player = scene.instantiate() as Player
	if player == null:
		push_error("ServerWorld: raiz de player.tscn nao e Player.")
		return 0
	_strip_cosmetic(player)
	player.use_external_input = true
	player.move_speed *= settings.test_move_speed_mult # E5.6: 1.0 fora do modo de teste
	var slot: PlayerSlot = PlayerSlot.new()
	slot.id = _next_id
	_next_id += 1
	slot.peer_id = peer_id
	slot.player_name = player_name
	slot.spawn_index = _free_spawn_index()
	player.name = "Player_%d" % slot.id
	player.position = settings.spawn_points[slot.spawn_index % settings.spawn_points.size()]
	if director != null:
		slot.zone_id = director.start_zone_id()
		player.position = director.spawn_for(slot.zone_id, director.spawn_name_for_new(), slot.spawn_index)
	slot.combat = player.get_node("Combat") as PlayerCombat
	slot.combat.read_input_actions = false # acoes vem do input validado, nunca de Input
	add_child(player)
	slot.node = player
	slot.health = player.get_node("Health") as HealthComponent
	slot.loadout = PlayerLoadout.find_for(player)
	if slot.loadout != null: # E6.1: classe padrao do servidor (o personagem do backend a substitui no CharacterCodec.apply)
		var def: ClassDef = ClassCatalog.shared().get_def(settings.default_class_id)
		if def == null:
			def = ClassCatalog.shared().default_def()
		slot.loadout.apply_class(def)
		if def.id != ClassCatalog.DEFAULT_CLASS_ID: # dev (--default-class): stats base da classe; o guerreiro mantem os da cena (E1-E5)
			slot.loadout.base_stats = def.base_stats.copy()
			slot.loadout.recalculate()
	if starting_items and slot.loadout != null and slot.loadout.inventory != null:
		for item_id: StringName in TestArena.STARTING_ITEMS:
			slot.loadout.inventory.add(item_id, 1)
	_players[slot.id] = slot
	_node_ids[player.get_instance_id()] = slot.id
	slot.health.damaged.connect(_on_damaged.bind(slot.id))
	slot.health.died.connect(_on_player_died.bind(slot.id).unbind(1))
	event_emitted.emit(Protocol.EVENT_PLAYER_JOINED, {"id": slot.id, "name": player_name})
	refresh_difficulty()
	if director != null:
		director.on_player_added(slot.id)
	return slot.id


## Remove o jogador em estado seguro (golpe encerrado, fora do grupo, inimigos sem alvo).
func remove_player(entity_id: int) -> bool:
	var slot: PlayerSlot = _players.get(entity_id) as PlayerSlot
	if slot == null:
		return false
	_players.erase(entity_id) # transicao/respawn pendentes morrem junto com o slot
	if is_instance_valid(slot.node):
		_node_ids.erase(slot.node.get_instance_id())
		slot.node.remove_from_group(&"player")
		if is_instance_valid(slot.combat) and slot.combat.hitbox != null:
			slot.combat.hitbox.end_strike()
		for enemy: Enemy in _live_enemies():
			if enemy.target == slot.node:
				enemy.target = null
		remove_child(slot.node)
		slot.node.queue_free()
	for enemy: Enemy in _live_enemies():
		enemy.threat.remove(entity_id)
	loot.remove_owner(entity_id) # pickups individuais de quem saiu somem (o item nunca foi concedido)
	event_emitted.emit(Protocol.EVENT_PLAYER_LEFT, {"id": entity_id})
	refresh_difficulty()
	return true


## Guarda o ultimo input VALIDADO (a sessao ja validou/clampou). As acoes ficam latcheadas ate o
## proximo tick para um clique entre dois ticks nao se perder.
func set_input(entity_id: int, move: Vector2, yaw: float, actions: int) -> void:
	var slot: PlayerSlot = _players.get(entity_id) as PlayerSlot
	if slot == null:
		return
	slot.move = move
	slot.yaw = yaw
	slot.pending_actions |= actions


func _free_spawn_index() -> int:
	var used: Dictionary = {}
	for id: int in _players:
		used[(_players[id] as PlayerSlot).spawn_index] = true
	for i: int in settings.spawn_points.size():
		if not used.has(i):
			return i
	return _players.size()


# ------------------------------------------------------------------ inimigos

func spawn_enemy(scene_path: String, pos: Vector3, zone_id: String = "") -> int:
	var scene: PackedScene = load(scene_path) as PackedScene
	if scene == null:
		push_error("ServerWorld: cena ausente: %s" % scene_path)
		return 0
	var enemy: Enemy = scene.instantiate() as Enemy
	if enemy == null:
		push_error("ServerWorld: raiz de %s nao e Enemy." % scene_path)
		return 0
	var id: int = _next_id
	_next_id += 1
	_strip_cosmetic(enemy)
	enemy.spawn_pickups = false # drop = evento informativo no E3
	enemy.loot_seed = absi(settings.session_seed + id * 7919) % 1000000007
	enemy.position = pos
	enemy.name = "Enemy_%d" % id
	add_child(enemy)
	_enemies[id] = enemy
	_node_ids[enemy.get_instance_id()] = id
	if zone_id.is_empty() and director != null:
		zone_id = director.world_def.zone_id_at(pos)
	_entity_zone[id] = zone_id
	enemy.health.damaged.connect(_on_damaged.bind(id))
	enemy.defeated.connect(_on_enemy_defeated.bind(id))
	enemy.phase_changed.connect(_on_enemy_phase_changed.bind(id))
	enemy.summon_handler = _summon_for_enemy
	_apply_difficulty_to(enemy)
	event_emitted.emit(Protocol.EVENT_ENEMY_SPAWN, {"id": id, "type": String(enemy.data.id), "pos": enemy.global_position})
	return id


## Remove o inimigo (e os adds dele) do mundo SEM morte valida: sem drop, XP, sinal ou evento.
## Usado ao descarregar uma zona e ao reiniciar o encontro do chefe depois de um wipe.
func despawn_enemy(entity_id: int) -> bool:
	var e: Enemy = _enemies.get(entity_id) as Enemy
	if e == null:
		return false
	if is_instance_valid(e):
		for add: Enemy in e.summoned.duplicate():
			if is_instance_valid(add):
				despawn_enemy(int(_node_ids.get(add.get_instance_id(), 0)))
		_node_ids.erase(e.get_instance_id())
		e.hitbox.end_strike()
		e.set_physics_process(false)
		remove_child(e)
		e.queue_free()
	_enemies.erase(entity_id)
	_entity_zone.erase(entity_id)
	_last_hit_by.erase(entity_id)
	_contrib.erase(entity_id)
	_add_ids.erase(entity_id)
	return true


## Todos os inimigos (inclusive adds) da zona.
func enemy_ids_in_zone(zone_id: String) -> Array[int]:
	var out: Array[int] = []
	for id: int in get_enemy_ids():
		if String(_entity_zone.get(id, "")) == zone_id:
			out.append(id)
	return out


func enemy_zone(entity_id: int) -> String:
	return String(_entity_zone.get(entity_id, ""))


func enemy_count() -> int:
	return _live_enemies().size()


func get_enemy_node(entity_id: int) -> Enemy:
	var e: Enemy = _enemies.get(entity_id) as Enemy
	return e if is_instance_valid(e) else null


func get_enemy_ids() -> Array[int]:
	var ids: Array[int] = []
	for id: int in _enemies:
		if is_instance_valid(_enemies[id]):
			ids.append(id)
	return ids


## Dados de enemy_spawn dos inimigos vivos (para quem acabou de entrar).
func enemy_spawn_events(zone_id: String = "") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: int in get_enemy_ids():
		var e: Enemy = _enemies[id] as Enemy
		if e.defeat_count == 0 and (zone_id.is_empty() or String(_entity_zone.get(id, "")) == zone_id):
			out.append({"id": id, "type": String(e.data.id), "pos": e.global_position})
	return out


func _live_enemies() -> Array[Enemy]:
	var out: Array[Enemy] = []
	var dead_ids: Array[int] = []
	for id: int in _enemies:
		if is_instance_valid(_enemies[id]):
			out.append(_enemies[id] as Enemy)
		else:
			dead_ids.append(id)
	for id: int in dead_ids:
		_enemies.erase(id)
		_entity_zone.erase(id)
	return out


# ------------------------------------------------------------------ simulacao

## Aplica o input guardado aos jogadores (velocidade/cooldown/custo sao os do servidor) e escolhe
## o alvo de cada inimigo (maior ameaca / jogador vivo mais proximo DA MESMA ZONA).
func apply_inputs() -> void:
	var alive_by_zone: Dictionary = {} ## zone_id -> Array[Dictionary]  (modo arena: tudo em "")
	for id: int in _players:
		var slot: PlayerSlot = _players[id] as PlayerSlot
		if not is_instance_valid(slot.node):
			continue
		var player: Player = slot.node
		if slot.health.is_dead:
			player.external_input = Vector2.ZERO
			slot.pending_actions = 0
			continue
		if not alive_by_zone.has(slot.zone_id):
			alive_by_zone[slot.zone_id] = []
		(alive_by_zone[slot.zone_id] as Array).append({"node": player, "id": id, "pos": player.global_position})
		if slot.transit_left > 0.0: # em transicao de zona: parado, sem acoes
			player.external_input = Vector2.ZERO
			slot.pending_actions = 0
			continue
		player.external_input = slot.move
		player.external_yaw = slot.yaw
		var actions: int = slot.pending_actions
		slot.pending_actions = 0
		if actions == 0:
			continue
		var combat: PlayerCombat = slot.combat
		if (actions & Protocol.ACTION_DODGE) != 0:
			combat.try_use(combat.dodge_skill)
		elif (actions & Protocol.ACTION_ATTACK) != 0:
			combat.try_use(combat.basic_attack)
		elif (actions & Protocol.ACTION_SKILL_1) != 0:
			combat.try_use(combat.skill_1)
		elif (actions & Protocol.ACTION_SKILL_2) != 0:
			combat.try_use(combat.skill_2)
	var zones_seen: Dictionary = {}
	for enemy: Enemy in _live_enemies():
		var zid: String = String(_entity_zone.get(int(_node_ids.get(enemy.get_instance_id(), 0)), ""))
		zones_seen[zid] = true
		var alive: Array = alive_by_zone.get(zid, [])
		var active: bool = not alive.is_empty()
		if active != bool(_zone_active.get(zid, true)):
			enemy.set_physics_process(active and enemy.ai != null)
		if not active:
			enemy.target = null
			continue
		var typed: Array[Dictionary] = []
		typed.assign(alive)
		enemy.target = _pick_target(enemy, typed)
	for zid: String in zones_seen:
		var now_active: bool = not (alive_by_zone.get(zid, []) as Array).is_empty()
		if not now_active and bool(_zone_active.get(zid, true)):
			for enemy: Enemy in _live_enemies(): # todos morreram na zona: chefes dela reiniciam o encontro
				if enemy.data.is_boss() and String(_entity_zone.get(int(_node_ids.get(enemy.get_instance_id(), 0)), "")) == zid:
					enemy.reset_encounter()
		_zone_active[zid] = now_active


## Alvo do inimigo: maior ameaca entre os vivos dentro do leash (com histerese); sem ameaca, o mais proximo.
func _pick_target(enemy: Enemy, alive: Array[Dictionary]) -> Node3D:
	var current_id: int = 0
	if enemy.target != null and is_instance_valid(enemy.target):
		current_id = int(_node_ids.get(enemy.target.get_instance_id(), 0))
	var leash: float = enemy.ai.leash_range if enemy.ai != null else INF
	var id: int = TargetSelector.pick(alive, enemy.global_position, enemy.threat, current_id, leash)
	for entry: Dictionary in alive:
		if int(entry["id"]) == id:
			return entry["node"] as Node3D
	return null


## Recalcula a escala de dificuldade de todos os inimigos para o numero atual de jogadores.
func refresh_difficulty() -> void:
	for enemy: Enemy in _live_enemies():
		_apply_difficulty_to(enemy)


func difficulty_players() -> int:
	return _players.size()


## Jogadores que contam para a escala de `enemy`: todos (arena) ou so os da zona dele (mundo).
func difficulty_players_for(enemy: Enemy) -> int:
	if director == null:
		return _players.size()
	var zid: String = String(_entity_zone.get(int(_node_ids.get(enemy.get_instance_id(), 0)), ""))
	return players_in_zone(zid).size() + director.incoming_count(zid)


func _apply_difficulty_to(enemy: Enemy) -> void:
	if _difficulty == null or enemy.data == null:
		return
	var n: int = maxi(difficulty_players_for(enemy), 1)
	enemy.set_difficulty(_difficulty.health_mult(n, enemy.data.tier) * settings.test_enemy_hp_mult, _difficulty.damage_mult(n, enemy.data.tier))


## Handler de invocacao dos inimigos: cria os adds no mundo do servidor (ids, eventos, escala).
func _summon_for_enemy(summoner: Enemy, type_id: StringName, count: int) -> Array:
	var made: Array = []
	var path: String = EnemyCatalog.scene_path(type_id)
	if path == "" or not ResourceLoader.exists(path):
		return made
	for i: int in count:
		var pos: Vector3 = Enemy.summon_position(summoner.global_position, i, count)
		var eid: int = spawn_enemy(path, pos)
		var add: Enemy = get_enemy_node(eid)
		if add == null:
			continue
		add.set_origin(pos)
		add.target = summoner.target
		_add_ids[eid] = true
		made.append(add)
	return made


# ------------------------------------------------------------------ snapshot

## Entidades no formato do contrato. Mortos recentes aparecem com hp 0 ate o corpo sumir.
func build_entities() -> Array:
	var out: Array = []
	for id: int in _players:
		var slot: PlayerSlot = _players[id] as PlayerSlot
		if not is_instance_valid(slot.node):
			continue
		out.append({
			"id": id, "kind": Protocol.KIND_PLAYER, "pos": slot.node.global_position,
			"yaw": slot.node.facing_yaw_value, "hp": slot.health.current_health,
			"max_hp": slot.health.max_health(), "state": int(slot.combat.machine.state),
			"type": "player",
		})
	for enemy: Enemy in _live_enemies():
		out.append({
			"id": int(_node_ids.get(enemy.get_instance_id(), 0)), "kind": Protocol.KIND_ENEMY,
			"pos": enemy.global_position, "yaw": enemy.visual.rotation.y,
			"hp": enemy.health.current_health, "max_hp": enemy.health.max_health(),
			"state": int(enemy.ai.state), "type": String(enemy.data.id),
			"phase": enemy.phase_index(), "atk": enemy.current_attack_id(),
		})
	return out


## Entidades visiveis para quem esta em `zone_id` (interesse por zona): jogadores e inimigos da zona.
## Com `center` e `radius > 0` os INIMIGOS alem do raio (plano XZ) ficam de fora; jogadores da zona sempre entram.
func build_entities_for_zone(zone_id: String, center: Vector3 = Vector3.ZERO, radius: float = 0.0) -> Array:
	if director == null:
		return build_entities()
	var out: Array = []
	for e: Variant in build_entities():
		var d: Dictionary = e
		var eid: int = int(d["id"])
		var is_player: bool = int(d["kind"]) == Protocol.KIND_PLAYER
		var z: String = zone_of_player(eid) if is_player else String(_entity_zone.get(eid, ""))
		if z != zone_id:
			continue
		if radius > 0.0 and not is_player:
			var p: Vector3 = d["pos"]
			if Vector2(p.x - center.x, p.z - center.z).length() > radius:
				continue
		out.append(e)
	return out


# ------------------------------------------------------------------ mundo (E5.3)

func zone_of_player(entity_id: int) -> String:
	var slot: PlayerSlot = _players.get(entity_id) as PlayerSlot
	return slot.zone_id if slot != null else ""


## Jogadores (ids) cuja zona atual e `zone_id`.
func players_in_zone(zone_id: String) -> Array[int]:
	var out: Array[int] = []
	for id: int in _players:
		if (_players[id] as PlayerSlot).zone_id == zone_id:
			out.append(id)
	return out


func get_slot(entity_id: int) -> PlayerSlot:
	return _players.get(entity_id) as PlayerSlot


func is_player_dead(entity_id: int) -> bool:
	var slot: PlayerSlot = _players.get(entity_id) as PlayerSlot
	return slot != null and slot.health.is_dead


## Move o jogador (teleporte do servidor) e zera velocidade/input. Nao mexe na zona do slot.
func teleport_player(entity_id: int, pos: Vector3) -> bool:
	var slot: PlayerSlot = _players.get(entity_id) as PlayerSlot
	if slot == null or not is_instance_valid(slot.node):
		return false
	slot.node.global_position = pos
	slot.node.velocity = Vector3.ZERO
	slot.move = Vector2.ZERO
	slot.pending_actions = 0
	return true


## Reanima o jogador morto: vida cheia, maquina de estados em IDLE. Posicao e do chamador.
func revive_player(entity_id: int) -> bool:
	var slot: PlayerSlot = _players.get(entity_id) as PlayerSlot
	if slot == null or not slot.health.is_dead:
		return false
	slot.health.reset()
	slot.combat.machine.revive()
	if is_instance_valid(slot.node):
		slot.node.velocity = Vector3.ZERO
	return true


## Remove a ameaca do jogador nos inimigos de `zone_id` (ele saiu da zona / reapareceu).
func clear_threat_in_zone(entity_id: int, zone_id: String) -> void:
	for enemy: Enemy in _live_enemies():
		if String(_entity_zone.get(int(_node_ids.get(enemy.get_instance_id(), 0)), "")) == zone_id:
			enemy.threat.remove(entity_id)


func emit_to_player(entity_id: int, kind: int, data: Dictionary) -> void:
	event_to_player.emit(entity_id, kind, data)


## Quem recebe o evento: `null` = todos (arena ou eventos globais); senao a lista de entity_ids
## (jogadores da zona do evento). Interesse por zona: dano/morte/drop de outra zona nao viaja.
func event_targets(kind: int, data: Dictionary) -> Variant:
	if director == null:
		return null
	var zone_id: String = ""
	match kind:
		Protocol.EVENT_PLAYER_JOINED, Protocol.EVENT_PLAYER_LEFT:
			return null
		Protocol.EVENT_DAMAGE:
			zone_id = _zone_of_any(int(data.get("target_id", 0)))
		Protocol.EVENT_DEATH, Protocol.EVENT_ENEMY_PHASE, Protocol.EVENT_RESPAWN:
			zone_id = _zone_of_any(int(data.get("id", 0)))
		Protocol.EVENT_ENEMY_SPAWN:
			zone_id = _zone_of_any(int(data.get("id", 0)))
		Protocol.EVENT_DROP:
			zone_id = director.world_def.zone_id_at(data.get("pos", Vector3.ZERO) as Vector3)
		Protocol.EVENT_PUZZLE, Protocol.EVENT_BOSS:
			zone_id = String(data.get("zone", ""))
		Protocol.EVENT_ZONE:
			return [int(data.get("id", 0))]
		_:
			return null
	if zone_id.is_empty():
		return null
	return players_in_zone(zone_id)


func _zone_of_any(entity_id: int) -> String:
	if _players.has(entity_id):
		return (_players[entity_id] as PlayerSlot).zone_id
	return String(_entity_zone.get(entity_id, ""))


## Eventos de "estado atual" para quem entrou na zona do jogador (entrada na sessao ou fim de transicao).
## Arena: so os enemy_spawn (como no E3). Mundo: zona, inimigos, puzzle e chefe.
func state_events_for_player(entity_id: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var zone_id: String = zone_of_player(entity_id)
	if director == null:
		for d: Dictionary in enemy_spawn_events():
			out.append({"kind": Protocol.EVENT_ENEMY_SPAWN, "data": d})
		return out
	var node: Player = get_player_node(entity_id)
	var pos: Vector3 = node.global_position if node != null else Vector3.ZERO
	out.append({"kind": Protocol.EVENT_ZONE, "data": {"id": entity_id, "zone": zone_id, "phase": Protocol.ZONE_PHASE_ARRIVED, "pos": pos}})
	for d2: Dictionary in enemy_spawn_events(zone_id):
		out.append({"kind": Protocol.EVENT_ENEMY_SPAWN, "data": d2})
	out.append_array(director.zone_state_events(zone_id))
	return out


# ------------------------------------------------------------------ eventos

func _strip_cosmetic(root: Node) -> void:
	for n: String in COSMETIC_NODES:
		var node: Node = root.get_node_or_null(n)
		if node != null:
			root.remove_child(node)
			node.free()


func _on_damaged(info: DamageInfo, final_amount: float, target_id: int) -> void:
	var source_id: int = 0
	if is_instance_valid(info.source):
		source_id = int(_node_ids.get(info.source.get_instance_id(), 0))
	if _players.has(source_id) and _enemies.has(target_id):
		_last_hit_by[target_id] = source_id # `damaged` precede `died`: ao morrer, este e o matador
		var hit_enemy: Enemy = _enemies[target_id] as Enemy
		if is_instance_valid(hit_enemy):
			hit_enemy.add_threat(source_id, final_amount)
		if final_amount > 0.0:
			var c: Dictionary = _contrib.get(target_id, {})
			c[source_id] = float(c.get(source_id, 0.0)) + final_amount
			_contrib[target_id] = c
	event_emitted.emit(Protocol.EVENT_DAMAGE, {
		"source_id": source_id, "target_id": target_id,
		"amount": final_amount, "crit": info.is_critical,
	})


func _on_enemy_phase_changed(_enemy: Enemy, phase_index: int, entity_id: int) -> void:
	event_emitted.emit(Protocol.EVENT_ENEMY_PHASE, {"id": entity_id, "phase": phase_index})


func _on_player_died(entity_id: int) -> void:
	event_emitted.emit(Protocol.EVENT_DEATH, {"id": entity_id})
	if director != null:
		director.on_player_died(entity_id)


func _on_enemy_defeated(enemy: Enemy, xp: int, drops: Array[LootDrop], entity_id: int) -> void:
	event_emitted.emit(Protocol.EVENT_DEATH, {"id": entity_id})
	if director != null:
		director.on_enemy_defeated(entity_id)
	if settings.individual_loot:
		_defeat_individual(enemy, xp, entity_id)
		return
	for drop: LootDrop in drops:
		event_emitted.emit(Protocol.EVENT_DROP, {
			"pos": enemy.global_position, "item_id": String(drop.item_id), "qty": drop.quantity,
		})
	var killer_id: int = int(_last_hit_by.get(entity_id, 0))
	_last_hit_by.erase(entity_id)
	var killer: PlayerSlot = _players.get(killer_id) as PlayerSlot
	if killer == null:
		return
	player_killed_enemy.emit(killer_id, entity_id, String(enemy.data.id))
	var items: Array = []
	for drop: LootDrop in drops:
		var qty: int = drop.quantity
		if settings.persist_drops and killer.loadout != null and killer.loadout.inventory != null:
			qty -= killer.loadout.inventory.add(drop.item_id, drop.quantity) # so o que coube
		if qty > 0:
			items.append({"item_id": String(drop.item_id), "qty": qty})
	enemy_killed.emit(entity_id, killer_id, xp, items)


## E5.4: morte com LOOT INDIVIDUAL. Cada participante elegivel (dano suficiente, vivo, na zona do inimigo) rola o proprio
## loot com RNG proprio e recebe PICKUPS COM DONO (evento `drop` so para ele); o matador continua recebendo o XP do
## `Enemy` e os demais participantes recebem o mesmo XP (`xp_for_participants`). Adds invocados nao rolam nem repartem XP.
## O drop que o `Enemy` rolou sozinho (`defeated.drops`) e IGNORADO neste modo.
func _defeat_individual(enemy: Enemy, xp: int, entity_id: int) -> void:
	var killer_id: int = int(_last_hit_by.get(entity_id, 0))
	_last_hit_by.erase(entity_id)
	var contrib: Dictionary = _contrib.get(entity_id, {})
	_contrib.erase(entity_id)
	var is_add: bool = _add_ids.has(entity_id)
	_add_ids.erase(entity_id)
	var zone: String = String(_entity_zone.get(entity_id, ""))
	var killer: PlayerSlot = _players.get(killer_id) as PlayerSlot
	if killer != null:
		player_killed_enemy.emit(killer_id, entity_id, String(enemy.data.id))
	if not is_add:
		var max_hp: float = enemy.health.max_health()
		for pid: int in LootManager.eligible_ids(contrib, max_hp, String(enemy.data.tier), killer_id, settings.loot_min_share):
			var slot: PlayerSlot = _players.get(pid) as PlayerSlot
			if slot == null or slot.health.is_dead or slot.zone_id != zone:
				continue
			# E6.3: ilvl = nivel do participante (limitado a ilvl_max), tier do inimigo ajusta os pesos de raridade.
			var plevel: int = slot.loadout.progress.level if slot.loadout != null else 1
			var ilvl: int = clampi(plevel, 1, ItemRules.shared().ilvl_max)
			var rolled: Array[LootDrop] = loot.roll_for(enemy.data.loot_table, entity_id, pid, ilvl, String(enemy.data.tier), plevel)
			for pk: LootManager.LootPickup in loot.spawn_for(pid, rolled, enemy.global_position, zone):
				var dev: Dictionary = {"pos": pk.pos, "item_id": pk.item_id, "qty": pk.qty, "id": pk.id}
				if not pk.inst.is_empty():
					dev["rarity"] = String(pk.inst["rarity"])
				emit_to_player(pid, Protocol.EVENT_DROP, dev)
			if pid != killer_id and settings.xp_for_participants and xp > 0 and slot.loadout != null:
				slot.loadout.grant_xp(xp)
				participant_rewarded.emit(entity_id, pid, xp)
	if killer != null:
		enemy_killed.emit(entity_id, killer_id, xp, [])
