class_name ClientInventory
extends RefCounted
## E5.5: espelho SOMENTE-LEITURA do inventario para a UI.
##
## E5.6: o servidor envia o inventario COMPLETO (`s_inventory`, ClientSession.inventory_synced) e `apply_full` o aplica
## (`complete = true`: esconde o aviso). Depois disso o servidor e a unica fonte: as estimativas por evento (pickup, craft,
## recompensa de quest) viram no-op para nao contar duas vezes. Antes do primeiro `s_inventory` (ou com servidor antigo, que
## nao envia) a classe guarda uma ESTIMATIVA da sessao (`complete == false`) e a UI avisa isso ao jogador.

signal changed()

const SLOT_COUNT: int = 25  ## grade da UI (5x5); o backend usa capacidade 24 (CharacterLimits), Inventory padrao 20
const EQUIP_SLOTS: Array[String] = ["weapon", "armor", "trinket"]

var complete: bool = false
var _qty: Dictionary = {}       ## item_id -> qty (estimativa ou estado completo)
var equipment: Dictionary = {}  ## slot -> item_id (so preenchido por apply_full)


func reset() -> void:
	_qty = {}
	equipment = {}
	complete = false
	changed.emit()


func add(item_id: String, qty: int) -> void:
	if complete or qty <= 0 or not Protocol.is_content_id(item_id):
		return
	_qty[item_id] = int(_qty.get(item_id, 0)) + qty
	changed.emit()


## Remove ate `qty` (nunca fica negativo: a estimativa pode nao conhecer o estoque anterior).
func remove(item_id: String, qty: int) -> void:
	if complete or qty <= 0 or not _qty.has(item_id):
		return
	var left: int = int(_qty[item_id]) - qty
	if left <= 0:
		_qty.erase(item_id)
	else:
		_qty[item_id] = left
	changed.emit()


func count(item_id: String) -> int:
	return int(_qty.get(item_id, 0))


## Entradas ordenadas por id: [{item_id, qty}].
func entries() -> Array[Dictionary]:
	var ids: Array = _qty.keys()
	ids.sort()
	var out: Array[Dictionary] = []
	for k: Variant in ids:
		out.append({"item_id": String(k), "qty": int(_qty[k])})
	return out


## Ganho de item vindo de evento do servidor.
func on_pickup(data: Dictionary) -> void:
	add(String(data.get("item_id", "")), int(data.get("qty", 0)))


## Craft concluido: soma resultados e subtrai os ingredientes da receita (dados locais, so para a estimativa).
func on_craft_ok(data: Dictionary) -> void:
	if complete:
		return # o servidor reenvia o inventario completo
	var def: RecipeDef = RecipeCatalog.shared().get_recipe(String(data.get("recipe_id", "")))
	if def != null:
		for i: Dictionary in def.ingredients:
			remove(String(i["item_id"]), int(i["qty"]))
	for r: Variant in data.get("results", []):
		if r is Dictionary:
			add(String((r as Dictionary).get("item_id", "")), int((r as Dictionary).get("qty", 0)))


func on_quest_reward(items: Array) -> void:
	for r: Variant in items:
		if r is Dictionary:
			add(String((r as Dictionary).get("item_id", "")), int((r as Dictionary).get("qty", 0)))


## Estado completo (uso futuro, quando houver mensagem do servidor): slots [{item_id, qty}] e equipamento {slot: item_id}.
func apply_full(slots: Array, equip: Dictionary) -> void:
	_qty = {}
	for s: Variant in slots:
		if s is Dictionary and Protocol.is_content_id((s as Dictionary).get("item_id", null)):
			var q: int = int((s as Dictionary).get("qty", 0))
			if q > 0:
				_qty[String(s["item_id"])] = int(_qty.get(String(s["item_id"]), 0)) + q
	equipment = {}
	for k: String in EQUIP_SLOTS:
		if equip.has(k) and Protocol.is_content_id(equip[k]):
			equipment[k] = String(equip[k])
	complete = true
	changed.emit()
