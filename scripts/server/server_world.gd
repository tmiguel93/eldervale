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


func _ready() -> void:
	process_physics_priority = -20
	if settings == null:
		settings = ServerSettings.new()
	geometry = ArenaGeometry.build(self, false)
	_difficulty = DifficultyScaling.load_default()
	if settings.spawn_enemies:
		for entry: Array in TestArena.ENEMY_SPAWNS:
			spawn_enemy(entry[0] as String, entry[1] as Vector3)


func _physics_process(_delta: float) -> void:
	apply_inputs()


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
	var slot: PlayerSlot = PlayerSlot.new()
	slot.id = _next_id
	_next_id += 1
	slot.peer_id = peer_id
	slot.player_name = player_name
	slot.spawn_index = _free_spawn_index()
	player.name = "Player_%d" % slot.id
	player.position = settings.spawn_points[slot.spawn_index % settings.spawn_points.size()]
	slot.combat = player.get_node("Combat") as PlayerCombat
	slot.combat.read_input_actions = false # acoes vem do input validado, nunca de Input
	add_child(player)
	slot.node = player
	slot.health = player.get_node("Health") as HealthComponent
	slot.loadout = PlayerLoadout.find_for(player)
	if starting_items and slot.loadout != null and slot.loadout.inventory != null:
		for item_id: StringName in TestArena.STARTING_ITEMS:
			slot.loadout.inventory.add(item_id, 1)
	_players[slot.id] = slot
	_node_ids[player.get_instance_id()] = slot.id
	slot.health.damaged.connect(_on_damaged.bind(slot.id))
	slot.health.died.connect(_on_player_died.bind(slot.id).unbind(1))
	event_emitted.emit(Protocol.EVENT_PLAYER_JOINED, {"id": slot.id, "name": player_name})
	refresh_difficulty()
	return slot.id


## Remove o jogador em estado seguro (golpe encerrado, fora do grupo, inimigos sem alvo).
func remove_player(entity_id: int) -> bool:
	var slot: PlayerSlot = _players.get(entity_id) as PlayerSlot
	if slot == null:
		return false
	_players.erase(entity_id)
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

func spawn_enemy(scene_path: String, pos: Vector3) -> int:
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
	enemy.health.damaged.connect(_on_damaged.bind(id))
	enemy.defeated.connect(_on_enemy_defeated.bind(id))
	enemy.phase_changed.connect(_on_enemy_phase_changed.bind(id))
	enemy.summon_handler = _summon_for_enemy
	_apply_difficulty_to(enemy)
	event_emitted.emit(Protocol.EVENT_ENEMY_SPAWN, {"id": id, "type": String(enemy.data.id), "pos": enemy.global_position})
	return id


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
func enemy_spawn_events() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: int in get_enemy_ids():
		var e: Enemy = _enemies[id] as Enemy
		if e.defeat_count == 0:
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
	return out


# ------------------------------------------------------------------ simulacao

## Aplica o input guardado aos jogadores (velocidade/cooldown/custo sao os do servidor) e escolhe
## o alvo de cada inimigo (jogador vivo mais proximo).
func apply_inputs() -> void:
	var alive_positions: Array[Dictionary] = []
	for id: int in _players:
		var slot: PlayerSlot = _players[id] as PlayerSlot
		if not is_instance_valid(slot.node):
			continue
		var player: Player = slot.node
		if slot.health.is_dead:
			player.external_input = Vector2.ZERO
			slot.pending_actions = 0
			continue
		alive_positions.append({"node": player, "id": id, "pos": player.global_position})
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
	var active: bool = not alive_positions.is_empty()
	for enemy: Enemy in _live_enemies():
		if active != _enemies_active:
			enemy.set_physics_process(active and enemy.ai != null)
		if not active:
			enemy.target = null
			continue
		enemy.target = _pick_target(enemy, alive_positions)
	if not active and _enemies_active:
		for enemy: Enemy in _live_enemies(): # todos morreram: chefes reiniciam o encontro
			if enemy.data.is_boss():
				enemy.reset_encounter()
	_enemies_active = active


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


func _apply_difficulty_to(enemy: Enemy) -> void:
	if _difficulty == null or enemy.data == null:
		return
	var n: int = maxi(_players.size(), 1)
	enemy.set_difficulty(_difficulty.health_mult(n, enemy.data.tier), _difficulty.damage_mult(n, enemy.data.tier))


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
	event_emitted.emit(Protocol.EVENT_DAMAGE, {
		"source_id": source_id, "target_id": target_id,
		"amount": final_amount, "crit": info.is_critical,
	})


func _on_enemy_phase_changed(_enemy: Enemy, phase_index: int, entity_id: int) -> void:
	event_emitted.emit(Protocol.EVENT_ENEMY_PHASE, {"id": entity_id, "phase": phase_index})


func _on_player_died(entity_id: int) -> void:
	event_emitted.emit(Protocol.EVENT_DEATH, {"id": entity_id})


func _on_enemy_defeated(enemy: Enemy, xp: int, drops: Array[LootDrop], entity_id: int) -> void:
	event_emitted.emit(Protocol.EVENT_DEATH, {"id": entity_id})
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
