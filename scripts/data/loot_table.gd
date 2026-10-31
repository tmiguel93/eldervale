class_name LootTable
extends Resource
## Tabela de loot ponderada. Cada roll sorteia UMA entrada por peso, ou "nada"
## com peso `nothing_weight`. `rolls` sorteios independentes por chamada.
## Determinismo: o resultado depende apenas do estado do `rng` recebido.

@export var id: StringName = &""
@export var entries: Array[LootEntry] = []
@export var rolls: int = 1
@export var nothing_weight: float = 0.0
@export var placeholder: bool = false


func total_weight() -> float:
	var t: float = 0.0
	for e: LootEntry in entries:
		if e != null and e.weight > 0.0:
			t += e.weight
	return t


## Sorteia drops. Drops do mesmo item sao somados numa unica LootDrop (ordem de 1o aparecimento).
func roll(rng: RandomNumberGenerator) -> Array[LootDrop]:
	var result: Array[LootDrop] = []
	var total: float = total_weight()
	var pool: float = total + maxf(nothing_weight, 0.0)
	if pool <= 0.0:
		return result
	for _i: int in maxi(rolls, 0):
		var pick: float = rng.randf() * pool
		if pick >= total:
			continue  # "nada"
		var acc: float = 0.0
		var chosen: LootEntry = null
		for e: LootEntry in entries:
			if e == null or e.weight <= 0.0:
				continue
			acc += e.weight
			chosen = e  # fallback robusto contra erro de ponto flutuante
			if pick < acc:
				break
		if chosen == null:
			continue
		var lo: int = maxi(chosen.min_qty, 1)
		var hi: int = maxi(chosen.max_qty, lo)
		_merge(result, chosen.item_id, rng.randi_range(lo, hi))
	return result


static func _merge(into: Array[LootDrop], item_id: StringName, qty: int) -> void:
	for d: LootDrop in into:
		if d.item_id == item_id:
			d.quantity += qty
			return
	into.append(LootDrop.make(item_id, qty))
