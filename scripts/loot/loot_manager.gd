class_name LootManager
extends RefCounted
## Loot INDIVIDUAL do servidor (E5.4). Cada participante elegivel de um inimigo rola o proprio loot, com um RNG
## proprio e reproduzivel; o resultado vira PICKUPS COM DONO: entidades puramente do servidor (sem no/fisica) que so
## aparecem no snapshot do dono e so ele coleta (auto-coleta por proximidade, decidida aqui com a posicao autoritativa).
## Nada vem do cliente. Este objeto nao conhece rede nem backend: o `ServerWorld` emite `pickup_collected` e a
## `ServerSession` paga pelo caminho idempotente de recompensas (chave `loot:<sessao>:<id_do_pickup>:<personagem>`).
##
## Elegibilidade (pura, `eligible_ids`): dano acumulado do jogador no inimigo >= `min_share` x vida maxima (inimigo comum);
## qualquer dano > 0 para mini-chefe/chefe; o matador sempre entra. O chamador ainda exige jogador vivo e na zona do inimigo.
## RNG: semente = hash(base_privada, id_do_inimigo, id_do_jogador); `rng_factory` (Callable(enemy_id, player_id) ->
## RandomNumberGenerator) substitui isso nos testes.

signal pickup_spawned(pickup_id: int, owner_id: int, item_id: String, qty: int)
signal pickup_expired(pickup_id: int, owner_id: int)

class LootPickup extends RefCounted:
	var id: int = 0
	var owner_id: int = 0
	var item_id: String = ""
	var qty: int = 0
	var pos: Vector3 = Vector3.ZERO
	var zone_id: String = ""
	var ttl_left: float = 0.0
	var blocked_full: bool = false ## ja tentou coletar e nao coube (informativo/telemetria)

var world: ServerWorld
var settings: ServerSettings
## Semente-base PRIVADA (ver ServerSettings.loot_seed). Definida pelo ServerWorld.
var base_seed: int = 0
## Opcional: Callable(enemy_id: int, player_id: int) -> RandomNumberGenerator.
var rng_factory: Callable
## Callable() -> int que reserva o proximo id de entidade (ids de pickup nao colidem com jogador/inimigo).
var alloc_id: Callable
var pickups: Dictionary = {} ## id -> LootPickup
var stats: Dictionary = {"spawned": 0, "collected": 0, "expired": 0, "evicted": 0, "blocked_full": 0, "rolls": 0}


func _init(p_world: ServerWorld = null, p_settings: ServerSettings = null) -> void:
	world = p_world
	settings = p_settings


# ------------------------------------------------------------------ regras puras

## Semente do roll de `player_id` contra `enemy_id`. Deterministica; mudar qualquer entrada muda o resultado.
static func seed_for(base: int, enemy_id: int, player_id: int) -> int:
	return absi(("%d:%d:%d" % [base, enemy_id, player_id]).hash()) % 2147483647


## `contrib` = {player_id: dano acumulado}. Devolve os ids elegiveis (ordenados). Nao confere vida/zona.
static func eligible_ids(contrib: Dictionary, max_health: float, tier: String, killer_id: int, min_share: float) -> Array[int]:
	var out: Array[int] = []
	var floor_dmg: float = 0.0
	if tier == "normal":
		floor_dmg = maxf(min_share, 0.0) * maxf(max_health, 0.0)
	for id: Variant in contrib:
		var dmg: float = float(contrib[id])
		if dmg <= 0.0:
			continue
		if int(id) == killer_id or dmg >= floor_dmg:
			out.append(int(id))
	if killer_id > 0 and not out.has(killer_id):
		out.append(killer_id)
	out.sort()
	return out


func make_rng(enemy_id: int, player_id: int) -> RandomNumberGenerator:
	if rng_factory.is_valid():
		var custom: Variant = rng_factory.call(enemy_id, player_id)
		if custom is RandomNumberGenerator:
			return custom as RandomNumberGenerator
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_for(base_seed, enemy_id, player_id)
	return rng


## Rola a tabela do inimigo para UM jogador (sem criar pickups).
func roll_for(table: LootTable, enemy_id: int, player_id: int) -> Array[LootDrop]:
	if table == null:
		return [] as Array[LootDrop]
	stats["rolls"] = int(stats["rolls"]) + 1
	return table.roll(make_rng(enemy_id, player_id))


# ------------------------------------------------------------------ pickups

## Cria os pickups do dono em volta de `center`. Devolve os criados.
func spawn_for(owner_id: int, drops: Array[LootDrop], center: Vector3, zone_id: String) -> Array[LootPickup]:
	var out: Array[LootPickup] = []
	var n: int = drops.size()
	for i: int in n:
		var d: LootDrop = drops[i]
		if d == null or d.quantity < 1 or d.quantity > Protocol.MAX_PICKUP_QTY:
			continue
		var p: LootPickup = LootPickup.new()
		p.id = int(alloc_id.call()) if alloc_id.is_valid() else (pickups.size() + 1)
		p.owner_id = owner_id
		p.item_id = String(d.item_id)
		p.qty = d.quantity
		var ang: float = TAU * float(i) / float(maxi(n, 1))
		p.pos = center + Vector3(cos(ang), 0.0, sin(ang)) * (0.6 if n > 1 else 0.0)
		p.pos.y = center.y + 0.1
		p.zone_id = zone_id
		p.ttl_left = settings.pickup_ttl_sec
		_evict_if_needed(owner_id)
		pickups[p.id] = p
		stats["spawned"] = int(stats["spawned"]) + 1
		out.append(p)
		pickup_spawned.emit(p.id, owner_id, p.item_id, p.qty)
	return out


func _evict_if_needed(owner_id: int) -> void:
	var mine: Array[LootPickup] = pickups_of(owner_id)
	var limit: int = maxi(settings.max_pickups_per_player, 1)
	while mine.size() >= limit:
		var oldest: LootPickup = mine[0]
		for p: LootPickup in mine:
			if p.ttl_left < oldest.ttl_left or (p.ttl_left == oldest.ttl_left and p.id < oldest.id):
				oldest = p
		pickups.erase(oldest.id)
		mine.erase(oldest)
		stats["evicted"] = int(stats["evicted"]) + 1
		pickup_expired.emit(oldest.id, owner_id)


func pickups_of(owner_id: int) -> Array[LootPickup]:
	var out: Array[LootPickup] = []
	for id: int in pickups:
		var p: LootPickup = pickups[id] as LootPickup
		if p.owner_id == owner_id:
			out.append(p)
	out.sort_custom(func(a: LootPickup, b: LootPickup) -> bool: return a.id < b.id)
	return out


func get_pickup(pickup_id: int) -> LootPickup:
	return pickups.get(pickup_id) as LootPickup


func count() -> int:
	return pickups.size()


## O dono saiu da sessao: seus pickups somem (nao ha dono para coletar; o item nunca foi concedido).
func remove_owner(owner_id: int) -> void:
	for p: LootPickup in pickups_of(owner_id):
		pickups.erase(p.id)


## Entidades de snapshot do dono (kind 3): so os dele, na zona atual dele e (se > 0) dentro de `radius` m.
func entities_for(owner_id: int, zone_id: String, center: Vector3, radius: float) -> Array:
	var out: Array = []
	for p: LootPickup in pickups_of(owner_id):
		if p.zone_id != zone_id:
			continue
		if radius > 0.0 and Vector2(p.pos.x - center.x, p.pos.z - center.z).length() > radius:
			continue
		out.append({
			"id": p.id, "kind": Protocol.KIND_PICKUP, "pos": p.pos, "yaw": 0.0, "hp": 0.0, "max_hp": 0.0,
			"state": 0, "type": p.item_id, "qty": p.qty,
		})
	return out


## Avanca o tempo e tenta a auto-coleta. Devolve os pickups coletados neste passo.
func step(delta: float) -> Array[LootPickup]:
	var collected: Array[LootPickup] = []
	if pickups.is_empty():
		return collected
	for id: int in pickups.keys():
		var p: LootPickup = pickups.get(id) as LootPickup
		if p == null:
			continue
		p.ttl_left -= delta
		var slot: ServerWorld.PlayerSlot = world.get_slot(p.owner_id)
		if slot == null:
			pickups.erase(id)
			continue
		if p.ttl_left <= 0.0:
			pickups.erase(id)
			stats["expired"] = int(stats["expired"]) + 1
			pickup_expired.emit(id, p.owner_id)
			continue
		if not _can_collect(p, slot):
			continue
		var inv: Inventory = slot.loadout.inventory if slot.loadout != null else null
		if inv == null:
			continue
		if inv.room_for(StringName(p.item_id), p.qty) < p.qty:
			# Inventario cheio: o pickup PERMANECE (ate expirar). Tudo-ou-nada: nunca coleta parcial.
			if not p.blocked_full:
				p.blocked_full = true
				stats["blocked_full"] = int(stats["blocked_full"]) + 1
			continue
		p.blocked_full = false
		if inv.add(StringName(p.item_id), p.qty) > 0:
			continue # defesa: room_for disse que cabia
		pickups.erase(id) # remove ANTES de avisar: nenhuma segunda coleta do mesmo pickup
		stats["collected"] = int(stats["collected"]) + 1
		collected.append(p)
	return collected


func _can_collect(p: LootPickup, slot: ServerWorld.PlayerSlot) -> bool:
	if slot.health == null or slot.health.is_dead or slot.transit_left > 0.0 or not is_instance_valid(slot.node):
		return false
	if slot.zone_id != p.zone_id:
		return false
	var d: Vector3 = slot.node.global_position - p.pos
	return Vector2(d.x, d.z).length() <= settings.pickup_radius and absf(d.y) <= 3.0
