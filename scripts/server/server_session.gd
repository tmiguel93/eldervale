class_name ServerSession
extends Node
## Sessao do servidor: ciclo de vida de peers (hello/welcome/reject), validacao e rate limit do
## input, snapshots e replicacao de eventos. Nao conhece ENet: recebe chamadas de handlers
## (`on_*`, ligados aos sinais do NetRpc) e envia por um ServerTransport.
## Regras (contrato): hello unico por conexao; input so apos welcome; payload invalido -> descarta +
## contador; reincidencia -> reject(4) + disconnect; peer sem hello valido no prazo -> desconecta.
## Tempo: now_msec() (relogio injetavel via test_now_msec para testes deterministicos).

signal player_joined(peer_id: int, entity_id: int)
signal player_left(peer_id: int, entity_id: int)

class PeerState extends RefCounted:
	var peer_id: int = 0
	var connected_msec: int = 0
	var welcomed: bool = false
	var closing: bool = false
	var entity_id: int = 0
	var player_name: String = ""
	## E4: resgate de ticket em andamento (sem simulacao, sem acoes) e personagem ligado ao peer.
	var pending: bool = false
	var pending_since_msec: int = 0
	var pending_token: int = 0
	var character_id: String = ""
	var last_seq: int = -1
	var invalid_in_window: int = 0
	var window_start_msec: int = 0
	var dropped_invalid: int = 0
	var dropped_stale: int = 0
	var dropped_rate: int = 0
	var accepted_inputs: int = 0
	var hello_limiter: RateLimiter
	var input_limiter: RateLimiter
	var ping_limiter: RateLimiter
	var quest_limiter: RateLimiter
	var craft_limiter: RateLimiter
	## E5.6: assinatura do ultimo inventario enviado (so reenvia quando muda) e contagem de envios.
	var inv_sig: String = ""
	var inv_sent: int = 0
	## E5.7: capacidades declaradas pelo cliente (c_caps; mascaradas por Protocol.CAPS_KNOWN_MASK) e seu limitador.
	var caps: int = 0
	var caps_limiter: RateLimiter


var settings: ServerSettings
var world: ServerWorld
var transport: ServerTransport
## >= 0 substitui o relogio real (testes).
var test_now_msec: int = -1

var _peers: Dictionary = {} ## peer_id -> PeerState
var _next_event_id: int = 1
## E4: backend (null = modo dev, como no E3: ticket nao exigido).
var sync: BackendSync = null
var _character_peers: Dictionary = {} ## character_id -> peer_id
var _next_token: int = 1
var _registry: ContentRegistry
## E5.1: quests + dialogo (criado em setup; usa o transporte da sessao).
var quests: QuestService
## E5.4: crafting (criado em setup).
var crafting: CraftingService
## E5.6: medicao de snapshots (so com settings.measure_snapshots): maior payload aproximado (var_to_bytes) e contagens.
## E5.7: `samples`/`max_bytes`/`over_mtu`/`sum_bytes` contam MENSAGENS (uma parte do compacto = uma mensagem; o legado = 1 por snapshot).
var snapshot_stats: Dictionary = {"samples": 0, "max_bytes": 0, "max_entities": 0, "over_mtu": 0, "sum_bytes": 0,
	"snapshots": 0, "compact_snapshots": 0, "max_parts": 0, "encode_skipped": 0}
const MTU_PAYLOAD: int = Protocol.MTU_PAYLOAD


func setup(p_settings: ServerSettings, p_world: ServerWorld, p_transport: ServerTransport) -> void:
	settings = p_settings
	world = p_world
	transport = p_transport
	world.event_emitted.connect(_broadcast_event)
	world.event_to_player.connect(_on_event_to_player)
	world.enemy_killed.connect(_on_enemy_killed)
	world.player_killed_enemy.connect(_on_player_killed_enemy)
	world.pickup_collected.connect(_on_pickup_collected)
	world.participant_rewarded.connect(_on_participant_rewarded)
	quests = QuestService.new(transport)
	quests.position_of = _player_position
	crafting = CraftingService.new(world, transport)
	crafting.loadout_of = _loadout_of_entity
	crafting.peer_of = _peer_id_of_entity
	crafting.character_of = _character_id_of_entity
	process_physics_priority = 20 # depois de jogadores/inimigos


## Liga a persistencia (E4). Com backend o ticket e OBRIGATORIO e o jogador nasce do estado salvo.
func attach_backend(p_sync: BackendSync) -> void:
	sync = p_sync
	settings.persist_drops = true
	sync.snapshot_provider = snapshot_character
	sync.conflict_handler = _on_state_conflict
	quests.sync = p_sync
	crafting.sync = p_sync


func now_msec() -> int:
	return test_now_msec if test_now_msec >= 0 else Time.get_ticks_msec()


func _physics_process(_delta: float) -> void:
	step_tick()


## Fim de tick: contagem, timeouts de hello e (a cada N ticks) snapshots.
func step_tick() -> void:
	world.server_tick += 1
	check_timeouts()
	quests.tick()
	if settings.inventory_sync_ticks > 0 and world.server_tick % settings.inventory_sync_ticks == 0:
		sync_inventories()
	if world.server_tick % settings.snapshot_divisor() == 0:
		send_snapshots()


# ------------------------------------------------------------------ consulta

func peer_count() -> int:
	return _peers.size()


func welcomed_count() -> int:
	var n: int = 0
	for p: PeerState in _peers.values():
		if p.welcomed and not p.closing:
			n += 1
	return n


func has_peer(peer_id: int) -> bool:
	return _peers.has(peer_id)


func get_peer_state(peer_id: int) -> PeerState:
	return _peers.get(peer_id) as PeerState


# ------------------------------------------------------------------ conexao

func on_peer_connected(peer_id: int) -> void:
	if _peers.has(peer_id):
		return
	var p: PeerState = PeerState.new()
	p.peer_id = peer_id
	p.connected_msec = now_msec()
	p.window_start_msec = p.connected_msec
	p.hello_limiter = RateLimiter.new(settings.hello_rate_per_sec, settings.hello_burst)
	p.input_limiter = RateLimiter.new(settings.input_rate_per_sec, settings.input_burst)
	p.ping_limiter = RateLimiter.new(settings.ping_rate_per_sec, settings.ping_burst)
	p.quest_limiter = RateLimiter.new(settings.quest_rate_per_sec, settings.quest_burst)
	p.craft_limiter = RateLimiter.new(settings.craft_rate_per_sec, settings.craft_burst)
	p.caps_limiter = RateLimiter.new(1.0, 3)
	_peers[peer_id] = p
	print("[server] peer %d conectou (%d conexoes)" % [peer_id, _peers.size()])


func on_peer_disconnected(peer_id: int) -> void:
	_drop_peer(peer_id, "desconectou")


func check_timeouts() -> void:
	var now: int = now_msec()
	var limit: int = int(settings.hello_timeout_sec * 1000.0)
	var redeem_limit: int = int(settings.redeem_timeout_sec * 1000.0)
	for p: PeerState in _peers.values():
		if p.closing or p.welcomed:
			continue
		if p.pending:
			if now - p.pending_since_msec >= redeem_limit:
				ServerLog.info("[server] peer %d: resgate/carga excedeu o prazo" % p.peer_id)
				_reject_and_close(p, Protocol.REJECT_NOT_AUTHENTICATED, "nao autenticado")
		elif now - p.connected_msec >= limit:
			_reject_and_close(p, Protocol.REJECT_NOT_AUTHENTICATED, "hello nao recebido a tempo")


# ------------------------------------------------------------------ hello

func on_hello(peer_id: int, version: Variant, build: Variant, player_name: Variant, ticket: Variant) -> void:
	var p: PeerState = _peers.get(peer_id) as PeerState
	if p == null or p.closing:
		return
	if p.welcomed or p.pending:
		_reject_and_close(p, Protocol.REJECT_NOT_AUTHENTICATED, "hello repetido")
		return
	if not p.hello_limiter.allow(now_msec()):
		_reject_and_close(p, Protocol.REJECT_RATE_LIMIT, "hello rapido demais")
		return
	var v: Dictionary = Protocol.validate_hello(version, build, player_name, ticket)
	if not bool(v["ok"]):
		_reject_and_close(p, int(v["code"]), String(v["message"]))
		return
	if world.player_count() + _pending_count() >= settings.max_players:
		_reject_and_close(p, Protocol.REJECT_SERVER_FULL, "servidor cheio")
		return
	if sync == null:
		# Modo dev (sem backend): ticket nao exigido, jogador com o kit inicial (como no E3).
		var entity_id: int = world.add_player(peer_id, String(v["name"]))
		if entity_id == 0:
			_reject_and_close(p, Protocol.REJECT_SERVER_FULL, "sem vaga")
			return
		p.player_name = String(v["name"])
		_complete_join(p, entity_id)
		return
	# Modo com backend: ticket obrigatorio, resgate assincrono; peer fica "pendente".
	var tk: String = String(v["ticket"])
	if tk.is_empty() or not sync.is_ready():
		_reject_and_close(p, Protocol.REJECT_NOT_AUTHENTICATED, "nao autenticado")
		return
	if _pending_count() >= settings.max_pending:
		_reject_and_close(p, Protocol.REJECT_SERVER_FULL, "ocupado")
		return
	p.pending = true
	p.pending_since_msec = now_msec()
	p.pending_token = _next_token
	_next_token += 1
	p.player_name = String(v["name"])
	sync.redeem(tk, _on_redeemed.bind(peer_id, p.pending_token))


func _pending_count() -> int:
	var n: int = 0
	for p: PeerState in _peers.values():
		if p.pending and not p.closing:
			n += 1
	return n


## Peer ainda existe e e a MESMA tentativa (token)? Senao a resposta chegou tarde.
func _live_pending(peer_id: int, token: int) -> PeerState:
	var p: PeerState = _peers.get(peer_id) as PeerState
	if p == null or p.closing or not p.pending or p.pending_token != token:
		return null
	return p


func _on_redeemed(r: Dictionary, peer_id: int, token: int) -> void:
	var p: PeerState = _live_pending(peer_id, token)
	var cid: String = String(r.get("character_id", ""))
	if p == null:
		# Chegou tarde (peer saiu/estourou o prazo): se o resgate deu certo o lock foi adquirido -> solta.
		if bool(r["ok"]) and not cid.is_empty() and not _character_peers.has(cid) and sync != null:
			sync.release_character(cid, {})
		return
	if not bool(r["ok"]):
		ServerLog.info("[server] peer %d: resgate recusado (status %d, %s)" % [peer_id, int(r["status"]), String(r["code"])])
		_reject_and_close(p, Protocol.REJECT_NOT_AUTHENTICATED, "nao autenticado")
		return
	if _character_peers.has(cid):
		ServerLog.info("[server] peer %d: personagem ja conectado neste servidor" % peer_id)
		_reject_and_close(p, Protocol.REJECT_NOT_AUTHENTICATED, "nao autenticado")
		return
	_character_peers[cid] = peer_id
	p.character_id = cid
	sync.load_character(cid, _on_loaded.bind(peer_id, token))


func _on_loaded(r: Dictionary, peer_id: int, token: int) -> void:
	var p: PeerState = _live_pending(peer_id, token)
	if p == null:
		return # _drop_peer ja soltou o personagem
	if not bool(r["ok"]):
		ServerLog.info("[server] peer %d: carga do personagem falhou (status %d, %s)" % [peer_id, int(r["status"]), String(r["code"])])
		_reject_and_close(p, Protocol.REJECT_NOT_AUTHENTICATED, "nao autenticado")
		return
	var ch: Dictionary = r["character"]
	if _registry == null:
		_registry = ContentRegistry.new()
		_registry.load_all()
	var err: String = CharacterCodec.validate(ch, _registry)
	if not err.is_empty():
		ServerLog.warn("[server] peer %d: estado do personagem invalido (%s)" % [peer_id, err])
		_reject_and_close(p, Protocol.REJECT_NOT_AUTHENTICATED, "nao autenticado")
		return
	if world.player_count() >= settings.max_players:
		_reject_and_close(p, Protocol.REJECT_SERVER_FULL, "servidor cheio")
		return
	var char_name: String = String(ch.get("name", ""))
	var nm: Dictionary = Protocol.validate_name(char_name)
	if bool(nm["ok"]):
		p.player_name = String(nm["name"])
	var entity_id: int = world.add_player(peer_id, p.player_name, false)
	if entity_id == 0:
		_reject_and_close(p, Protocol.REJECT_SERVER_FULL, "sem vaga")
		return
	var loadout: PlayerLoadout = PlayerLoadout.find_for(world.get_player_node(entity_id))
	if loadout == null:
		world.remove_player(entity_id)
		_reject_and_close(p, Protocol.REJECT_NOT_AUTHENTICATED, "nao autenticado")
		return
	CharacterCodec.apply(loadout, ch)
	p.pending = false
	sync.mark_live(p.character_id)
	_complete_join(p, entity_id)


## Welcome + estado inicial para quem entrou (caminho comum dev/backend).
func _complete_join(p: PeerState, entity_id: int) -> void:
	p.entity_id = entity_id
	p.welcomed = true
	var peer_id: int = p.peer_id
	transport.send_welcome(peer_id, entity_id, settings.tick_rate, settings.session_seed)
	# Estado atual para quem chegou agora (eventos novos, ids crescentes so para este peer).
	for other: PeerState in _peers.values():
		if other != p and other.welcomed and not other.closing:
			_send_event_to(p, Protocol.EVENT_PLAYER_JOINED, {"id": other.entity_id, "name": other.player_name})
	for ev: Dictionary in world.state_events_for_player(entity_id): # arena: enemy_spawn; mundo: zona+inimigos+puzzle+chefe
		_send_event_to(p, int(ev["kind"]), ev["data"] as Dictionary)
	print("[server] peer %d entrou como '%s' (jogador %d)" % [peer_id, p.player_name, entity_id])
	var join_loadout: PlayerLoadout = _loadout_of(p)
	if join_loadout != null:
		quests.attach(entity_id, peer_id, p.character_id, join_loadout)
	crafting.attach(entity_id)
	send_inventory(p, true) # E5.6: estado completo logo apos o welcome (depois, so quando mudar)
	player_joined.emit(peer_id, entity_id)


# ------------------------------------------------------------------ inventario sincronizado (E5.6)

## Compara o inventario/equipamento de cada jogador com o ultimo enviado e manda `s_inventory` so se mudou. Cobre TODAS as
## vias (coleta, craft e seu desfazer, recompensa de quest, drop legado, reaplicacao por conflito de revision) sem hooks.
func sync_inventories() -> void:
	for p: PeerState in _peers.values():
		if p.welcomed and not p.closing:
			send_inventory(p, false)


## Envia o inventario completo do jogador. `force` ignora a comparacao (entrada). Devolve true se enviou.
func send_inventory(p: PeerState, force: bool) -> bool:
	var loadout: PlayerLoadout = _loadout_of(p)
	if loadout == null:
		return false
	var payload: Dictionary = CharacterCodec.inventory_payload(loadout)
	var sig: String = JSON.stringify(payload)
	if not force and sig == p.inv_sig:
		return false
	p.inv_sig = sig
	p.inv_sent += 1
	transport.send_inventory(p.peer_id, payload)
	return true


# ------------------------------------------------------------------ persistencia (E4)

func _loadout_of(p: PeerState) -> PlayerLoadout:
	if p == null or p.entity_id == 0:
		return null
	var node: Player = world.get_player_node(p.entity_id)
	return PlayerLoadout.find_for(node) if node != null else null


func _peer_of_character(character_id: String) -> PeerState:
	return _peers.get(int(_character_peers.get(character_id, -1))) as PeerState


## Estado completo do personagem ({} se nao ha jogador). Usado pelo autosave.
func snapshot_character(character_id: String) -> Dictionary:
	var p: PeerState = _peer_of_character(character_id)
	var loadout: PlayerLoadout = _loadout_of(p)
	if p == null or not p.welcomed or p.closing or loadout == null:
		return {}
	if crafting.is_pending(p.entity_id):
		return {} # E5.4: craft em voo no backend -> sem autosave (nao persistir estado a desfazer); o proximo ciclo salva
	return CharacterCodec.capture(loadout)


## 409 de revision: o backend e a fonte; reaplica o estado recarregado ao jogador vivo.
func _on_state_conflict(character_id: String, ch: Dictionary) -> void:
	var p: PeerState = _peer_of_character(character_id)
	var loadout: PlayerLoadout = _loadout_of(p)
	if loadout == null or not p.welcomed:
		return
	if _registry == null:
		_registry = ContentRegistry.new()
		_registry.load_all()
	var err: String = CharacterCodec.validate(ch, _registry)
	if not err.is_empty():
		ServerLog.warn("[server] estado recarregado invalido (%s); mantendo o da memoria" % err)
		return
	CharacterCodec.apply(loadout, ch)
	quests.resync(p.entity_id)
	ServerLog.warn("[server] estado do personagem %s reaplicado a partir do backend (conflito de revision)" % character_id)


func _peer_by_entity(entity_id: int) -> PeerState:
	for p: PeerState in _peers.values():
		if p.entity_id == entity_id and p.welcomed and not p.closing:
			return p
	return null


func _loadout_of_entity(entity_id: int) -> PlayerLoadout:
	return _loadout_of(_peer_by_entity(entity_id))


func _peer_id_of_entity(entity_id: int) -> int:
	var p: PeerState = _peer_by_entity(entity_id)
	return p.peer_id if p != null else -1


func _character_id_of_entity(entity_id: int) -> String:
	var p: PeerState = _peer_by_entity(entity_id)
	return p.character_id if p != null else ""


func _player_position(entity_id: int) -> Variant:
	var node: Player = world.get_player_node(entity_id)
	return node.global_position if node != null else null


func _on_player_killed_enemy(killer_id: int, _enemy_id: int, enemy_type: String) -> void:
	quests.on_enemy_killed(killer_id, enemy_type)


## E5.4: pickup individual coletado (item JA no inventario em memoria). Quest de coleta + pagamento no backend pelo
## caminho idempotente de recompensas com chave ESTAVEL por drop: `loot:<sessao>:<pickup_id>:<personagem>`.
func _on_pickup_collected(pickup_id: int, owner_id: int, item_id: String, qty: int) -> void:
	quests.on_items_gained(owner_id, [{"item_id": item_id, "qty": qty}])
	var p: PeerState = _peer_by_entity(owner_id)
	if p == null:
		return
	_send_event_to(p, Protocol.EVENT_PICKUP, {"id": pickup_id, "item_id": item_id, "qty": qty})
	if sync != null and not p.character_id.is_empty():
		var key: String = "loot:%s:%d:%s" % [sync.session_id, pickup_id, p.character_id]
		sync.enqueue_reward(p.character_id, key, 0, [{"item_id": item_id, "qty": qty}])


## E5.4: XP de participante (nao matador) na morte de um inimigo; mesma chave estavel por evento e personagem.
func _on_participant_rewarded(enemy_id: int, player_id: int, xp: int) -> void:
	var p: PeerState = _peer_by_entity(player_id)
	if sync == null or p == null or p.character_id.is_empty() or xp <= 0:
		return
	sync.enqueue_reward(p.character_id, "kill:%s:%d:%s" % [sync.session_id, enemy_id, p.character_id], xp, [])


func _on_enemy_killed(enemy_id: int, killer_id: int, xp: int, items: Array) -> void:
	# Coleta para quests: so o que REALMENTE entrou no inventario (persist_drops); em modo dev os drops
	# sao apenas informativos e nao contam.
	if settings.persist_drops:
		quests.on_items_gained(killer_id, items)
	if sync == null:
		return
	for p: PeerState in _peers.values():
		if p.entity_id == killer_id and p.welcomed and not p.closing and not p.character_id.is_empty():
			if xp <= 0 and items.is_empty():
				return
			# Chave ESTAVEL por evento: o retry (e qualquer replay) reutiliza a mesma.
			var key: String = "kill:%s:%d:%s" % [sync.session_id, enemy_id, p.character_id]
			sync.enqueue_reward(p.character_id, key, xp, items)
			return


# ------------------------------------------------------------------ input / ping

func on_input(peer_id: int, seq: Variant, move: Variant, yaw: Variant, actions: Variant, _client_tick: Variant = 0) -> void:
	var p: PeerState = _peers.get(peer_id) as PeerState
	if p == null or p.closing:
		return
	if not p.welcomed:
		_reject_and_close(p, Protocol.REJECT_NOT_AUTHENTICATED, "input antes do welcome")
		return
	if not p.input_limiter.allow(now_msec()):
		p.dropped_rate += 1
		_count_invalid(p, "rate limit de input")
		return
	var v: Dictionary = Protocol.validate_input(seq, move, yaw, actions, p.last_seq)
	if not bool(v["ok"]):
		if bool(v.get("stale", false)):
			p.dropped_stale += 1 # reordenacao/duplicata: descarta sem contar como abuso
			return
		p.dropped_invalid += 1
		_count_invalid(p, String(v["message"]))
		return
	p.last_seq = int(seq)
	p.accepted_inputs += 1
	world.set_input(p.entity_id, v["move"] as Vector2, float(v["yaw"]), int(actions))


## E5.1: c_quest_cmd. Payload invalido/rate limit contam como abuso; regra de jogo violada vira
## s_quest(QUEST_ERROR) sem punir o peer.
func on_quest_cmd(peer_id: int, req_id: Variant, op: Variant, quest_id: Variant) -> void:
	var p: PeerState = _quest_peer_ok(peer_id)
	if p == null:
		return
	var v: Dictionary = Protocol.validate_quest_cmd(req_id, op, quest_id)
	if not bool(v["ok"]):
		p.dropped_invalid += 1
		_count_invalid(p, String(v["message"]))
		return
	quests.cmd_quest(p.entity_id, int(v["req_id"]), int(v["op"]), String(v["quest_id"]))


## E5.1: c_dialogue_cmd (mesmas regras de on_quest_cmd).
func on_dialogue_cmd(peer_id: int, req_id: Variant, op: Variant, npc_id: Variant, choice: Variant) -> void:
	var p: PeerState = _quest_peer_ok(peer_id)
	if p == null:
		return
	var v: Dictionary = Protocol.validate_dialogue_cmd(req_id, op, npc_id, choice)
	if not bool(v["ok"]):
		p.dropped_invalid += 1
		_count_invalid(p, String(v["message"]))
		return
	quests.cmd_dialogue(p.entity_id, int(v["req_id"]), int(v["op"]), String(v["npc_id"]), int(v["choice"]))


## Peer apto a enviar comandos de quest/dialogo (welcomed + dentro do rate limit) ou null.
func _quest_peer_ok(peer_id: int) -> PeerState:
	var p: PeerState = _peers.get(peer_id) as PeerState
	if p == null or p.closing:
		return null
	if not p.welcomed:
		_reject_and_close(p, Protocol.REJECT_NOT_AUTHENTICATED, "comando antes do welcome")
		return null
	if not p.quest_limiter.allow(now_msec()):
		p.dropped_rate += 1
		_count_invalid(p, "rate limit de quest")
		return null
	return p


## E5.4: c_craft_cmd. Payload invalido/rate limit contam como abuso; regra de jogo violada vira
## s_craft(CRAFT_ERROR) sem punir o peer.
func on_craft_cmd(peer_id: int, req_id: Variant, recipe_id: Variant) -> void:
	var p: PeerState = _peers.get(peer_id) as PeerState
	if p == null or p.closing:
		return
	if not p.welcomed:
		_reject_and_close(p, Protocol.REJECT_NOT_AUTHENTICATED, "comando antes do welcome")
		return
	if not p.craft_limiter.allow(now_msec()):
		p.dropped_rate += 1
		_count_invalid(p, "rate limit de craft")
		return
	var v: Dictionary = Protocol.validate_craft_cmd(req_id, recipe_id)
	if not bool(v["ok"]):
		p.dropped_invalid += 1
		_count_invalid(p, String(v["message"]))
		return
	crafting.cmd_craft(p.entity_id, int(v["req_id"]), String(v["recipe_id"]))


## E5.7: c_caps(caps) — o cliente declara o que entende (hoje: snapshot compacto). Valido so apos o welcome.
func on_caps(peer_id: int, caps: Variant) -> void:
	var p: PeerState = _peers.get(peer_id) as PeerState
	if p == null or p.closing:
		return
	if not p.welcomed:
		_reject_and_close(p, Protocol.REJECT_NOT_AUTHENTICATED, "comando antes do welcome")
		return
	if not p.caps_limiter.allow(now_msec()):
		p.dropped_rate += 1
		_count_invalid(p, "rate limit de caps")
		return
	var v: Dictionary = Protocol.validate_caps(caps)
	if not bool(v["ok"]):
		p.dropped_invalid += 1
		_count_invalid(p, String(v["message"]))
		return
	p.caps = int(v["caps"])


func on_ping(peer_id: int, client_time_ms: Variant) -> void:
	var p: PeerState = _peers.get(peer_id) as PeerState
	if p == null or p.closing or typeof(client_time_ms) != TYPE_INT:
		return
	if not p.ping_limiter.allow(now_msec()):
		return
	transport.send_pong(peer_id, int(client_time_ms))


func _count_invalid(p: PeerState, reason: String) -> void:
	var now: int = now_msec()
	if now - p.window_start_msec >= int(settings.invalid_window_sec * 1000.0):
		p.window_start_msec = now
		p.invalid_in_window = 0
	p.invalid_in_window += 1
	if p.invalid_in_window > settings.max_invalid_inputs:
		print("[server] peer %d acima do limite de mensagens invalidas (%s)" % [p.peer_id, reason])
		_reject_and_close(p, Protocol.REJECT_RATE_LIMIT, "mensagens invalidas em excesso")


# ------------------------------------------------------------------ snapshots / eventos

func send_snapshots() -> void:
	if welcomed_count() == 0:
		return
	var entities: Array = world.build_entities()
	for p: PeerState in _peers.values():
		if p.welcomed and not p.closing:
			if world.director != null:
				# modo mundo: interesse por zona + raio (settings.aoi_radius) em volta do proprio jogador
				var node: Player = world.get_player_node(p.entity_id)
				var center: Vector3 = node.global_position if node != null else Vector3.ZERO
				entities = world.build_entities_for_zone(world.zone_of_player(p.entity_id), center, settings.aoi_radius)
			var mine: Array = entities
			if settings.individual_loot:
				# E5.4: SO os pickups do proprio dono entram no snapshot deste peer (nunca os de outro jogador).
				mine = entities.duplicate()
				mine.append_array(world.pickup_entities_for(p.entity_id))
			if settings.compact_snapshots and (p.caps & Protocol.CAP_SNAPSHOT_COMPACT) != 0:
				_send_snapshot_compact(p, mine)
				continue
			if settings.measure_snapshots:
				_measure_snapshot(world.server_tick, p.last_seq, mine)
			transport.send_snapshot(p.peer_id, world.server_tick, p.last_seq, mine)


## E5.7: snapshot compacto do peer (as entidades `mine` ja sao o interesse DESTE peer: AOI/zona/pickups do dono). Particiona
## em mensagens <= settings.snapshot_part_bytes de blob; todas levam o mesmo tick/last_input_seq.
func _send_snapshot_compact(p: PeerState, mine: Array) -> void:
	var enc: Dictionary = SnapshotCodec.encode(mine, settings.snapshot_part_bytes)
	var parts: Array = enc["parts"]
	if parts.size() > Protocol.MAX_SNAPSHOT_PARTS:
		# Excede o limite do protocolo (nao ocorre com <= 256 entidades): descarta este snapshot em vez de enviar mensagens invalidas.
		print("[server] snapshot do peer %d com %d partes excede o limite; descartado" % [p.peer_id, parts.size()])
		return
	if settings.measure_snapshots:
		snapshot_stats["snapshots"] = int(snapshot_stats["snapshots"]) + 1
		snapshot_stats["compact_snapshots"] = int(snapshot_stats["compact_snapshots"]) + 1
		snapshot_stats["max_parts"] = maxi(int(snapshot_stats["max_parts"]), parts.size())
		snapshot_stats["encode_skipped"] = int(snapshot_stats["encode_skipped"]) + int(enc["skipped"])
		snapshot_stats["max_entities"] = maxi(int(snapshot_stats["max_entities"]), mine.size())
	for i: int in parts.size():
		var blob: PackedByteArray = parts[i]
		if settings.measure_snapshots:
			_measure_bytes(var_to_bytes(world.server_tick).size() + var_to_bytes(p.last_seq).size() + var_to_bytes(i).size()
				+ var_to_bytes(parts.size()).size() + var_to_bytes(blob).size())
		transport.send_snapshot_part(p.peer_id, world.server_tick, p.last_seq, i, parts.size(), blob)


## Tamanho aproximado do s_snapshot no fio (codificacao Variant do Godot dos 3 argumentos; sem cabecalhos de RPC/ENet).
func _measure_snapshot(tick: int, last_seq: int, entities: Array) -> void:
	var bytes: int = var_to_bytes(tick).size() + var_to_bytes(last_seq).size() + var_to_bytes(entities).size()
	snapshot_stats["snapshots"] = int(snapshot_stats["snapshots"]) + 1
	snapshot_stats["max_parts"] = maxi(int(snapshot_stats["max_parts"]), 1)
	snapshot_stats["max_entities"] = maxi(int(snapshot_stats["max_entities"]), entities.size())
	_measure_bytes(bytes)


## Acumula o tamanho (bytes de argumentos Variant) de UMA mensagem de snapshot nas estatisticas.
func _measure_bytes(bytes: int) -> void:
	snapshot_stats["samples"] = int(snapshot_stats["samples"]) + 1
	snapshot_stats["sum_bytes"] = int(snapshot_stats["sum_bytes"]) + bytes
	var new_max: bool = bytes > int(snapshot_stats["max_bytes"])
	snapshot_stats["max_bytes"] = maxi(int(snapshot_stats["max_bytes"]), bytes)
	if bytes > MTU_PAYLOAD:
		snapshot_stats["over_mtu"] = int(snapshot_stats["over_mtu"]) + 1
	# Linha de resumo a cada novo maximo (e a cada 200 amostras): o harness le a ultima; nao depende do encerramento limpo.
	if new_max or int(snapshot_stats["samples"]) % 200 == 0:
		print("[server] snapshots: %s" % JSON.stringify(snapshot_stats))


func _broadcast_event(kind: int, data: Dictionary) -> void:
	var event_id: int = _next_event_id
	_next_event_id += 1
	var targets: Variant = world.event_targets(kind, data) # null = todos (arena); mundo: so a zona do evento
	for p: PeerState in _peers.values():
		if p.welcomed and not p.closing and (targets == null or (targets as Array).has(p.entity_id)):
			transport.send_event(p.peer_id, event_id, kind, data)


## E5.3: evento so para um jogador (catch-up ao trocar de zona / aviso de transicao).
func _on_event_to_player(entity_id: int, kind: int, data: Dictionary) -> void:
	for p: PeerState in _peers.values():
		if p.entity_id == entity_id and p.welcomed and not p.closing:
			_send_event_to(p, kind, data)
			return


func _send_event_to(p: PeerState, kind: int, data: Dictionary) -> void:
	var event_id: int = _next_event_id
	_next_event_id += 1
	transport.send_event(p.peer_id, event_id, kind, data)


# ------------------------------------------------------------------ encerramento de peers

func _reject_and_close(p: PeerState, code: int, message: String) -> void:
	if p.closing:
		return
	p.closing = true
	print("[server] peer %d rejeitado (codigo %d: %s)" % [p.peer_id, code, message])
	transport.send_reject(p.peer_id, code, message)
	transport.disconnect_peer(p.peer_id)
	_drop_peer(p.peer_id, "")


func _drop_peer(peer_id: int, reason: String) -> void:
	var p: PeerState = _peers.get(peer_id) as PeerState
	if p == null:
		return
	_peers.erase(peer_id)
	if not reason.is_empty():
		print("[server] peer %d %s" % [peer_id, reason])
	if not p.character_id.is_empty():
		_character_peers.erase(p.character_id)
		if sync != null:
			if p.welcomed:
				# Estado capturado ANTES de remover o no: checkpoint final + disconnect (reconexao 90 s).
				sync.disconnect_character(p.character_id, CharacterCodec.capture(_loadout_of(p)) if _loadout_of(p) != null else {})
			else:
				sync.release_character(p.character_id, {}) # lock adquirido mas jogador nunca entrou
	if p.entity_id != 0:
		quests.detach(p.entity_id)
		crafting.detach(p.entity_id)
		world.remove_player(p.entity_id) # emite player_left para os demais
		player_left.emit(peer_id, p.entity_id)


## Chamado no encerramento do servidor: checkpoint de todos + release (nao disconnect).
func shutdown() -> void:
	for id: int in _peers.keys():
		var p: PeerState = _peers[id] as PeerState
		if sync != null and p != null and not p.character_id.is_empty() and p.welcomed:
			var loadout: PlayerLoadout = _loadout_of(p)
			sync.release_character(p.character_id, CharacterCodec.capture(loadout) if loadout != null else {})
			_character_peers.erase(p.character_id)
			p.character_id = "" # ja tratado: _drop_peer nao enfileira disconnect
		_drop_peer(id, "")
