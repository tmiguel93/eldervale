class_name CraftingService
extends RefCounted
## Crafting do servidor (E5.4), 100% autoritativo. O cliente so envia `c_craft_cmd(req_id, recipe_id)`.
## Validacoes (nesta ordem): jogador conhecido/vivo/fora de transicao -> pedido repetido -> receita existente ->
## nenhum craft em andamento do mesmo jogador (`busy`) -> estacao (zona certa e ao alcance: `no_station`/`too_far`) ->
## ingredientes no INVENTARIO (equipados nao contam: `insufficient_ingredients`) -> espaco para o resultado depois de
## remover os ingredientes (`inventory_full`). So entao aplica.
##
## Consistencia memoria x banco (otimista com desfazer, ver docs/E5_LOOT_CRAFTING.md):
##  - sem backend (modo dev): aplica na memoria e responde na hora;
##  - com backend: aplica na MEMORIA, bloqueia o autosave do personagem enquanto o craft esta em voo e enfileira
##    `POST /internal/characters/:id/craft` (mesma fila serializada dos checkpoints/recompensas) com a chave estavel
##    `craft:<sessao>:<n>:<personagem>`. OK -> `CRAFT_OK`. Recusa DEFINITIVA do backend (409/4xx) -> desfaz a memoria
##    (remove o resultado, devolve os ingredientes; se nao der, recarrega o personagem do banco) e `CRAFT_ERROR`.
##    Resultado DESCONHECIDO (rede/5xx esgotados) -> recarrega do banco (o banco e a verdade; a chave garante replay).

var world: ServerWorld
var transport: ServerTransport
var sync: BackendSync = null
var catalog: RecipeCatalog
## Callable(entity_id) -> PlayerLoadout | null  e  Callable(entity_id) -> int peer_id | -1  e  Callable(entity_id) -> String character_id.
var loadout_of: Callable
var peer_of: Callable
var character_of: Callable

var _players: Dictionary = {} ## entity_id -> PlayerCtx
var _next_n: int = 1
var stats: Dictionary = {"ok": 0, "rejected": 0, "rolled_back": 0, "reloaded": 0}


class PlayerCtx extends RefCounted:
	var entity_id: int = 0
	var last_req_id: int = -1
	var pending: bool = false
	var pending_character: String = ""


func _init(p_world: ServerWorld, p_transport: ServerTransport, p_catalog: RecipeCatalog = null) -> void:
	world = p_world
	transport = p_transport
	catalog = p_catalog if p_catalog != null else RecipeCatalog.shared()


func attach(entity_id: int) -> void:
	if not _players.has(entity_id):
		var pc: PlayerCtx = PlayerCtx.new()
		pc.entity_id = entity_id
		_players[entity_id] = pc


func detach(entity_id: int) -> void:
	_players.erase(entity_id)


func is_pending(entity_id: int) -> bool:
	var pc: PlayerCtx = _players.get(entity_id) as PlayerCtx
	return pc != null and pc.pending


func is_pending_character(character_id: String) -> bool:
	for pc: PlayerCtx in _players.values():
		if pc.pending and pc.pending_character == character_id:
			return true
	return false


## Pedido JA validado por Protocol.validate_craft_cmd. Devolve {ok, code}. Responde ao cliente (CRAFT_OK/CRAFT_ERROR).
func cmd_craft(entity_id: int, req_id: int, recipe_id: String) -> Dictionary:
	var pc: PlayerCtx = _players.get(entity_id) as PlayerCtx
	if pc == null:
		return {"ok": false, "code": "not_ready"}
	var slot: ServerWorld.PlayerSlot = world.get_slot(entity_id)
	if slot == null or slot.health.is_dead or slot.transit_left > 0.0:
		return _fail(pc, req_id, recipe_id, "not_available")
	if req_id == pc.last_req_id:
		return _fail(pc, req_id, recipe_id, "duplicate_request")
	pc.last_req_id = req_id
	var def: RecipeDef = catalog.get_recipe(recipe_id)
	if def == null:
		return _fail(pc, req_id, recipe_id, "unknown_recipe")
	if pc.pending:
		return _fail(pc, req_id, recipe_id, "busy")
	var st: String = world.station_status(entity_id, def.station)
	if not st.is_empty():
		return _fail(pc, req_id, recipe_id, st)
	var loadout: PlayerLoadout = loadout_of.call(entity_id) as PlayerLoadout
	if loadout == null or loadout.inventory == null:
		return _fail(pc, req_id, recipe_id, "not_ready")
	var chk: String = preview(loadout.inventory, def)
	if not chk.is_empty():
		return _fail(pc, req_id, recipe_id, chk)
	apply_to(loadout.inventory, def)
	var character_id: String = String(character_of.call(entity_id)) if character_of.is_valid() else ""
	if sync == null or character_id.is_empty():
		return _ok(pc, req_id, def)
	pc.pending = true
	pc.pending_character = character_id
	var key: String = "craft:%s:%d:%s" % [sync.session_id, _next_n, character_id]
	_next_n += 1
	sync.enqueue_craft(character_id, key, def.id, _on_backend_done.bind(entity_id, req_id, def, character_id))
	return {"ok": true, "code": ""}


# ------------------------------------------------------------------ regras puras (inventario)

## "" se der para fazer; senao "insufficient_ingredients" ou "inventory_full". Nao altera o inventario.
static func preview(inv: Inventory, def: RecipeDef) -> String:
	for s: Dictionary in def.ingredients:
		if inv.count(StringName(String(s["item_id"]))) < int(s["qty"]):
			return "insufficient_ingredients"
	var snap: Array[ItemStack] = inv.snapshot()
	var ok: bool = true
	for s: Dictionary in def.ingredients:
		ok = ok and inv.remove(StringName(String(s["item_id"])), int(s["qty"]))
	for r: Dictionary in def.results:
		ok = ok and inv.add(StringName(String(r["item_id"])), int(r["qty"])) == 0
	inv.restore(snap)
	return "" if ok else "inventory_full"


## Aplica a receita (JA aprovada por `preview`): remove ingredientes e adiciona os resultados.
static func apply_to(inv: Inventory, def: RecipeDef) -> void:
	for s: Dictionary in def.ingredients:
		inv.remove(StringName(String(s["item_id"])), int(s["qty"]))
	for r: Dictionary in def.results:
		inv.add(StringName(String(r["item_id"])), int(r["qty"]))


## Desfaz `apply_to`: tira os resultados e devolve os ingredientes. false = nao deu (ex.: resultado ja equipado/consumido).
static func undo_on(inv: Inventory, def: RecipeDef) -> bool:
	for r: Dictionary in def.results:
		if inv.count(StringName(String(r["item_id"]))) < int(r["qty"]):
			return false
	var snap: Array[ItemStack] = inv.snapshot()
	for r: Dictionary in def.results:
		inv.remove(StringName(String(r["item_id"])), int(r["qty"]))
	for s: Dictionary in def.ingredients:
		if inv.add(StringName(String(s["item_id"])), int(s["qty"])) > 0:
			inv.restore(snap)
			return false
	return true


# ------------------------------------------------------------------ backend

func _on_backend_done(r: Dictionary, entity_id: int, req_id: int, def: RecipeDef, character_id: String) -> void:
	var pc: PlayerCtx = _players.get(entity_id) as PlayerCtx
	if pc != null:
		pc.pending = false
		pc.pending_character = ""
	if bool(r["ok"]):
		if pc != null:
			_ok(pc, req_id, def)
		return
	var status: int = int(r.get("status", 0))
	var code: String = String(r.get("code", ""))
	var definitive: bool = status >= 400 and status < 500 and status != 429
	stats["rolled_back"] = int(stats["rolled_back"]) + 1
	if pc == null:
		return # jogador saiu: o checkpoint final ja foi capturado; nada a avisar
	var loadout: PlayerLoadout = loadout_of.call(entity_id) as PlayerLoadout
	var restored: bool = false
	if definitive and loadout != null:
		restored = undo_on(loadout.inventory, def)
	if not restored and sync != null:
		stats["reloaded"] = int(stats["reloaded"]) + 1
		sync.enqueue_reload(character_id) # banco = verdade: reaplica o estado dele na memoria
	var err_code: String = code if (definitive and code in ["insufficient_ingredients", "inventory_full", "unknown_recipe", "session_fenced"]) else "backend_error"
	_send(pc, Protocol.CRAFT_ERROR, {"req_id": req_id, "recipe_id": def.id, "code": err_code})


# ------------------------------------------------------------------ respostas

func _ok(pc: PlayerCtx, req_id: int, def: RecipeDef) -> Dictionary:
	stats["ok"] = int(stats["ok"]) + 1
	_send(pc, Protocol.CRAFT_OK, {"req_id": req_id, "recipe_id": def.id, "results": def.results_payload()})
	return {"ok": true, "code": ""}


func _fail(pc: PlayerCtx, req_id: int, recipe_id: String, code: String) -> Dictionary:
	stats["rejected"] = int(stats["rejected"]) + 1
	_send(pc, Protocol.CRAFT_ERROR, {"req_id": req_id, "recipe_id": recipe_id, "code": code})
	return {"ok": false, "code": code}


func _send(pc: PlayerCtx, kind: int, data: Dictionary) -> void:
	var peer: int = int(peer_of.call(pc.entity_id)) if peer_of.is_valid() else -1
	if peer >= 0 and transport != null:
		transport.send_craft_update(peer, kind, data)
