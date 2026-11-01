class_name TalentService
extends RefCounted
## Talentos do servidor (E6.2), 100% autoritativo. O cliente so envia `c_talent_cmd(req_id, op, arg)`.
## Validacao local (a mesma do backend, em `TalentState.check_*`; ordem): jogador conhecido/vivo -> req_id estritamente crescente
## (`duplicate_request`, anti-replay) -> nenhum comando em andamento (`busy`) -> regra do comando. Respec ainda exige zona segura
## (`not_safe_zone`) e os itens do custo no INVENTARIO (`insufficient_items`).
##
## Consistencia memoria x banco (o BANCO e a verdade dos talentos, ver docs/E6_TALENTS.md):
##  - sem backend (modo dev): aplica na memoria e responde na hora;
##  - com backend: os talentos so mudam na memoria DEPOIS que o backend confirma (`POST /internal/characters/:id/talents`, fila
##    serializada do personagem, chave estavel `talent:<sessao>:<n>:<personagem>`); o estado devolvido pelo backend e o que vale
##    (inclusive em replay). O CUSTO do respec (itens) e removido do inventario em memoria ANTES de enfileirar (como o crafting), para
##    que nenhum autosave reponha os itens, e devolvido se o backend recusar de forma definitiva. Resultado desconhecido (rede/5xx)
##    -> recarrega o personagem do banco. Sem autosave do personagem enquanto um comando esta em voo.
## `send_state` manda `s_talents(TALENTS_STATE)` ao dono; `sync` o reenvia quando o estado ou o nivel mudam (assinatura).

var world: ServerWorld
var transport: ServerTransport
var sync_backend: BackendSync = null
var catalog: TalentCatalog
## Callable(entity_id) -> PlayerLoadout | null; Callable(entity_id) -> int peer_id | -1; Callable(entity_id) -> String character_id.
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
	var sig: String = ""


func _init(p_world: ServerWorld, p_transport: ServerTransport, p_catalog: TalentCatalog = null) -> void:
	world = p_world
	transport = p_transport
	catalog = p_catalog if p_catalog != null else TalentCatalog.shared()


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


## Payload de s_talents(TALENTS_STATE) do jogador ({} se sem classe/arvore).
func state_payload(entity_id: int, req_id: int = -1) -> Dictionary:
	var lo: PlayerLoadout = loadout_of.call(entity_id) as PlayerLoadout
	var tree: TalentTree = lo.talent_tree() if lo != null else null
	if tree == null:
		return {}
	var total: int = catalog.points_for_level(lo.progress.level)
	var spent: int = lo.talents.points_spent(tree)
	return {
		"spec": lo.talents.spec_id, "ranks": lo.talents.ranks.duplicate(), "respecs": lo.talents.respecs, "level": lo.progress.level,
		"points_total": total, "points_spent": spent, "points_available": maxi(0, total - spent), "req_id": req_id,
	}


## Envia o estado ao dono. Sem `force`, so se mudou desde o ultimo envio (cobre subida de nivel, recarga do banco e conflito de revision).
func send_state(entity_id: int, req_id: int = -1, force: bool = false) -> bool:
	var pc: PlayerCtx = _players.get(entity_id) as PlayerCtx
	if pc == null:
		return false
	var payload: Dictionary = state_payload(entity_id, req_id)
	if payload.is_empty():
		return false
	var sig_payload: Dictionary = payload.duplicate()
	sig_payload["req_id"] = 0
	var sig: String = JSON.stringify(sig_payload, "", true)
	if not force and sig == pc.sig:
		return false
	pc.sig = sig
	_send(pc, Protocol.TALENTS_STATE, payload)
	return true


## Reenvio periodico: so quando o estado/nivel mudou. Sem mensagem enquanto um comando esta em voo.
func sync_all() -> void:
	for pc: PlayerCtx in _players.values():
		if not pc.pending:
			send_state(pc.entity_id)


## Pedido JA validado por Protocol.validate_talent_cmd. Devolve {ok, code}. Responde ao cliente (TALENTS_STATE/TALENTS_ERROR).
func cmd_talent(entity_id: int, req_id: int, op: int, arg: String) -> Dictionary:
	var pc: PlayerCtx = _players.get(entity_id) as PlayerCtx
	if pc == null:
		return {"ok": false, "code": "not_ready"}
	var slot: ServerWorld.PlayerSlot = world.get_slot(entity_id)
	if slot == null or slot.health.is_dead or slot.transit_left > 0.0:
		return _fail(pc, req_id, op, "not_available")
	if req_id <= pc.last_req_id:
		return _fail(pc, req_id, op, "duplicate_request")
	pc.last_req_id = req_id
	if pc.pending:
		return _fail(pc, req_id, op, "busy")
	var lo: PlayerLoadout = loadout_of.call(entity_id) as PlayerLoadout
	var tree: TalentTree = lo.talent_tree() if lo != null else null
	if tree == null:
		return _fail(pc, req_id, op, "not_ready")
	var level: int = lo.progress.level
	var code: String = ""
	match op:
		Protocol.TALENT_OP_ALLOCATE:
			code = TalentState.check_allocate(tree, lo.talents, level, arg, catalog)
		Protocol.TALENT_OP_CHOOSE_SPEC:
			code = TalentState.check_choose_spec(tree, lo.talents, arg)
		Protocol.TALENT_OP_RESPEC:
			code = TalentState.check_respec(lo.talents)
			if code.is_empty() and catalog.respec_require_safe_zone and not world.is_safe_zone(entity_id):
				code = "not_safe_zone"
			if code.is_empty() and not _can_pay(lo.inventory):
				code = "insufficient_items"
		_:
			code = "unknown_op"
	if not code.is_empty():
		return _fail(pc, req_id, op, code)
	var paid: bool = false
	if op == Protocol.TALENT_OP_RESPEC:
		paid = _pay(lo.inventory)
	var character_id: String = String(character_of.call(entity_id)) if character_of.is_valid() else ""
	if sync_backend == null or character_id.is_empty():
		_apply_local(lo, op, arg)
		return _ok(pc, req_id)
	pc.pending = true
	pc.pending_character = character_id
	var key: String = "talent:%s:%d:%s" % [sync_backend.session_id, _next_n, character_id]
	_next_n += 1
	var op_name: String = "allocate" if op == Protocol.TALENT_OP_ALLOCATE else ("respec" if op == Protocol.TALENT_OP_RESPEC else "choose_spec")
	sync_backend.enqueue_talent(character_id, key, op_name, arg, _on_backend_done.bind(entity_id, req_id, op, paid, character_id))
	return {"ok": true, "code": ""}


# ------------------------------------------------------------------ custo do respec (itens do INVENTARIO)

func _can_pay(inv: Inventory) -> bool:
	for c: Dictionary in catalog.respec_cost_items:
		if inv.count(StringName(String(c["item_id"]))) < int(c["qty"]):
			return false
	return true


func _pay(inv: Inventory) -> bool:
	for c: Dictionary in catalog.respec_cost_items:
		inv.remove(StringName(String(c["item_id"])), int(c["qty"]))
	return true


## Devolve os itens do custo (rollback). false = nao coube (o chamador recarrega o personagem do banco).
func _refund(inv: Inventory) -> bool:
	var ok: bool = true
	for c: Dictionary in catalog.respec_cost_items:
		ok = ok and inv.add(StringName(String(c["item_id"])), int(c["qty"])) == 0
	return ok


func _apply_local(lo: PlayerLoadout, op: int, arg: String) -> void:
	match op:
		Protocol.TALENT_OP_ALLOCATE: lo.talents.apply_allocate(arg)
		Protocol.TALENT_OP_CHOOSE_SPEC: lo.talents.apply_choose_spec(arg)
		Protocol.TALENT_OP_RESPEC: lo.talents.apply_respec()
	lo.apply_talents()


# ------------------------------------------------------------------ backend

func _on_backend_done(r: Dictionary, entity_id: int, req_id: int, op: int, paid: bool, character_id: String) -> void:
	var pc: PlayerCtx = _players.get(entity_id) as PlayerCtx
	if pc != null:
		pc.pending = false
		pc.pending_character = ""
	var lo: PlayerLoadout = loadout_of.call(entity_id) as PlayerLoadout
	if bool(r["ok"]):
		if pc == null or lo == null:
			return
		var ch: Dictionary = r.get("character", {}) as Dictionary
		var raw: Variant = ch.get("talents", null)
		if not ch.has("talents") or not TalentState.shape_error(raw).is_empty():
			stats["reloaded"] = int(stats["reloaded"]) + 1
			if sync_backend != null:
				sync_backend.enqueue_reload(character_id)
			_send(pc, Protocol.TALENTS_ERROR, {"req_id": req_id, "op": op, "code": "backend_error"})
			return
		lo.talents.restore(raw, lo.talent_tree()) # o estado do BANCO e o que vale (inclusive em replay)
		lo.apply_talents()
		_ok(pc, req_id)
		return
	var status: int = int(r.get("status", 0))
	var code: String = String(r.get("code", ""))
	var definitive: bool = status >= 400 and status < 500 and status != 429
	stats["rolled_back"] = int(stats["rolled_back"]) + 1
	if pc == null:
		return # jogador saiu: o checkpoint final ja foi capturado
	var restored: bool = true
	if paid and lo != null:
		restored = definitive and _refund(lo.inventory)
	if (not definitive or not restored) and sync_backend != null:
		stats["reloaded"] = int(stats["reloaded"]) + 1
		sync_backend.enqueue_reload(character_id) # banco = verdade: reaplica o estado dele na memoria
	var known: Array[String] = ["unknown_node", "spec_not_chosen", "wrong_spec", "max_rank", "level_too_low", "prerequisite", "no_points",
		"unknown_spec", "spec_already_chosen", "nothing_to_reset", "insufficient_items", "session_fenced", "revision_conflict"]
	_send(pc, Protocol.TALENTS_ERROR, {"req_id": req_id, "op": op, "code": code if (definitive and known.has(code)) else "backend_error"})


# ------------------------------------------------------------------ respostas

func _ok(pc: PlayerCtx, req_id: int) -> Dictionary:
	stats["ok"] = int(stats["ok"]) + 1
	send_state(pc.entity_id, req_id, true)
	return {"ok": true, "code": ""}


func _fail(pc: PlayerCtx, req_id: int, op: int, code: String) -> Dictionary:
	stats["rejected"] = int(stats["rejected"]) + 1
	_send(pc, Protocol.TALENTS_ERROR, {"req_id": req_id, "op": op, "code": code})
	return {"ok": false, "code": code}


func _send(pc: PlayerCtx, kind: int, data: Dictionary) -> void:
	var peer: int = int(peer_of.call(pc.entity_id)) if peer_of.is_valid() else -1
	if peer >= 0 and transport != null:
		transport.send_talents(peer, kind, data)
