class_name Inventory
extends RefCounted
## Inventario por slots (logica pura). So guarda pilhas nao vazias, compactadas;
## `capacity` limita o numero de pilhas. Itens desconhecidos pelo registry sao rejeitados.

signal changed

var capacity: int
var _registry: ContentRegistry
var _stacks: Array[ItemStack] = []


func _init(p_registry: ContentRegistry, p_capacity: int = 20) -> void:
	_registry = p_registry
	capacity = maxi(p_capacity, 0)


func stack_count() -> int:
	return _stacks.size()


func free_slots() -> int:
	return capacity - _stacks.size()


func count(item_id: StringName) -> int:
	var n: int = 0
	for s: ItemStack in _stacks:
		if s.item_id == item_id:
			n += s.quantity
	return n


func has_item(item_id: StringName, qty: int = 1) -> bool:
	return count(item_id) >= qty


## Pilhas como [{id, qty}] (copia, para UI/testes). E6.3: instancias rolada levam tambem `inst` (copia).
func contents() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s: ItemStack in _stacks:
		var e: Dictionary = {"id": s.item_id, "qty": s.quantity}
		if not s.inst.is_empty():
			e["inst"] = s.inst.duplicate(true)
		out.append(e)
	return out


## E6.3: quantas unidades SIMPLES (sem instancia) de `item_id`. Crafting e remove() so enxergam estas: um item com affixes
## nunca e consumido como ingrediente.
func count_plain(item_id: StringName) -> int:
	var n: int = 0
	for s: ItemStack in _stacks:
		if s.item_id == item_id and s.inst.is_empty():
			n += s.quantity
	return n


func stack_at(index: int) -> ItemStack:
	return _stacks[index] if index >= 0 and index < _stacks.size() else null


## Remove e devolve a pilha do indice (null se invalido). Usado por Equipment.
func take_at(index: int) -> ItemStack:
	if index < 0 or index >= _stacks.size():
		return null
	var s: ItemStack = _stacks[index]
	_stacks.remove_at(index)
	changed.emit()
	return s


func has_uid(uid: String) -> bool:
	for s: ItemStack in _stacks:
		if not s.inst.is_empty() and String(s.inst.get("uid", "")) == uid:
			return true
	return false


## E6.3: adiciona UMA instancia rolada (nao empilhavel). false se o item e desconhecido/nao equipavel, a instancia e vazia, o uid ja
## existe aqui ou nao ha slot livre (nada muda).
func add_instance(item_id: StringName, inst: Dictionary) -> bool:
	var item: ItemData = _registry.get_item(item_id)
	if item == null or inst.is_empty() or not item.is_equippable() or free_slots() < 1 or has_uid(String(inst.get("uid", ""))):
		return false
	_stacks.append(ItemStack.make(item_id, 1, inst))
	changed.emit()
	return true


## Quanto de `qty` cabe sem alterar nada.
func room_for(item_id: StringName, qty: int) -> int:
	var item: ItemData = _registry.get_item(item_id)
	if item == null or qty <= 0:
		return 0
	var cap: int = item.effective_max_stack()
	var fit: int = 0
	if item.stackable:
		for s: ItemStack in _stacks:
			if s.item_id == item_id:
				fit += cap - s.quantity
	fit += free_slots() * cap
	return mini(fit, qty)


## Adiciona e devolve o que NAO coube (0 = tudo coube). Item desconhecido/qty<=0: nada muda.
func add(item_id: StringName, qty: int) -> int:
	var item: ItemData = _registry.get_item(item_id)
	if item == null:
		return maxi(qty, 0)
	if qty <= 0:
		return 0
	var cap: int = item.effective_max_stack()
	var left: int = qty
	if item.stackable:
		for s: ItemStack in _stacks:
			if left == 0:
				break
			if s.item_id == item_id and s.inst.is_empty() and s.quantity < cap:
				var put: int = mini(cap - s.quantity, left)
				s.quantity += put
				left -= put
	while left > 0 and _stacks.size() < capacity:
		var put2: int = mini(cap, left)
		_stacks.append(ItemStack.make(item_id, put2))
		left -= put2
	if left < qty:
		changed.emit()
	return left


## Remove exatamente `qty` ou nada (atomico). Retorna true se removeu.
func remove(item_id: StringName, qty: int) -> bool:
	if qty <= 0 or count_plain(item_id) < qty: # E6.3: so unidades simples (instancias nunca sao consumidas aqui)
		return false
	var left: int = qty
	var i: int = _stacks.size() - 1
	while i >= 0 and left > 0:
		var s: ItemStack = _stacks[i]
		if s.item_id == item_id and s.inst.is_empty():
			var take: int = mini(s.quantity, left)
			s.quantity -= take
			left -= take
			if s.quantity == 0:
				_stacks.remove_at(i)
		i -= 1
	changed.emit()
	return true


## Copia do estado interno, para rollback atomico (usado por Equipment).
func snapshot() -> Array[ItemStack]:
	var out: Array[ItemStack] = []
	for s: ItemStack in _stacks:
		out.append(ItemStack.make(s.item_id, s.quantity, s.inst))
	return out


## Restaura um snapshot sem emitir `changed` (o chamador desfaz uma operacao falha).
func restore(snap: Array[ItemStack]) -> void:
	_stacks = []
	for s: ItemStack in snap:
		_stacks.append(ItemStack.make(s.item_id, s.quantity, s.inst))
