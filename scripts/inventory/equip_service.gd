class_name EquipService
extends RefCounted
## E6.3: equipar/desequipar no SERVIDOR (autoridade). O cliente so envia `c_equip_cmd(req_id, op, index, item_id)`.
## Validacoes (ordem): jogador vivo e fora de transicao -> pedido repetido -> nenhum craft/talento em voo (`busy`: o backend ainda pode
## desfazer o inventario) -> indice/item (anti-corrida: a base esperada tem de ser a da pilha) -> equipavel -> instancia valida ->
## espaco para devolver o item anterior. Em qualquer falha nada muda (Equipment e atomico). O sucesso recalcula stats e habilidades
## (PlayerLoadout) e enfileira um checkpoint coalescido; nao ha duplicacao: o item sai do inventario e entra no slot na MESMA operacao.

var world: ServerWorld
var transport: ServerTransport
var sync: BackendSync = null
var loadout_of: Callable
var peer_of: Callable
var character_of: Callable
var crafting: CraftingService
var talents: TalentService
var _last_req: Dictionary = {} ## entity_id -> ultimo req_id
var stats: Dictionary = {"ok": 0, "rejected": 0}


func _init(p_world: ServerWorld, p_transport: ServerTransport) -> void:
	world = p_world
	transport = p_transport


func detach(entity_id: int) -> void:
	_last_req.erase(entity_id)


## Pedido JA validado por Protocol.validate_equip_cmd. Devolve {ok, code}; responde ao cliente (EQUIP_OK/EQUIP_ERROR).
func cmd_equip(entity_id: int, req_id: int, op: int, index: int, item_id: String) -> Dictionary:
	var slot: ServerWorld.PlayerSlot = world.get_slot(entity_id)
	if slot == null or slot.health.is_dead or slot.transit_left > 0.0:
		return _fail(entity_id, req_id, op, "not_available")
	if _last_req.get(entity_id, -1) == req_id:
		return _fail(entity_id, req_id, op, "duplicate_request")
	_last_req[entity_id] = req_id
	if (crafting != null and crafting.is_pending(entity_id)) or (talents != null and talents.is_pending(entity_id)):
		return _fail(entity_id, req_id, op, "busy")
	var loadout: PlayerLoadout = loadout_of.call(entity_id) as PlayerLoadout
	if loadout == null or loadout.equipment == null:
		return _fail(entity_id, req_id, op, "not_available")
	var eq: Equipment = loadout.equipment
	if op == Protocol.EQUIP_OP_EQUIP:
		var st: ItemStack = loadout.inventory.stack_at(index)
		if st == null:
			return _fail(entity_id, req_id, op, "bad_index")
		if String(st.item_id) != item_id:
			return _fail(entity_id, req_id, op, "item_mismatch")
		if not eq.equip_index(index):
			return _fail(entity_id, req_id, op, _code_for(eq.last_error))
	else:
		var slot_value: int = Equipment.SLOTS[index]
		var cur: StringName = eq.get_equipped(slot_value)
		if cur == &"":
			return _fail(entity_id, req_id, op, "empty_slot")
		if not item_id.is_empty() and String(cur) != item_id:
			return _fail(entity_id, req_id, op, "item_mismatch")
		if not eq.unequip(slot_value):
			return _fail(entity_id, req_id, op, _code_for(eq.last_error))
	stats["ok"] = int(stats["ok"]) + 1
	_send(entity_id, Protocol.EQUIP_OK, {"req_id": req_id, "op": op})
	var cid: String = String(character_of.call(entity_id)) if character_of.is_valid() else ""
	if sync != null and not cid.is_empty():
		sync.enqueue_checkpoint(cid, CharacterCodec.capture(loadout), true)
	return {"ok": true, "code": ""}


static func _code_for(err: String) -> String:
	if err.begins_with("inventario cheio"):
		return "inventory_full"
	if err.begins_with("instancia invalida"):
		return "invalid_instance"
	if err.begins_with("indice"):
		return "bad_index"
	return "not_equippable"


func _fail(entity_id: int, req_id: int, op: int, code: String) -> Dictionary:
	stats["rejected"] = int(stats["rejected"]) + 1
	_send(entity_id, Protocol.EQUIP_ERROR, {"req_id": req_id, "op": op, "code": code})
	return {"ok": false, "code": code}


func _send(entity_id: int, kind: int, data: Dictionary) -> void:
	var peer: int = int(peer_of.call(entity_id)) if peer_of.is_valid() else -1
	if peer >= 0 and transport != null:
		transport.send_equip_update(peer, kind, data)
