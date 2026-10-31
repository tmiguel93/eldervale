class_name Pickup
extends Area3D
## Item no chao. Area3D que enxerga a Hurtbox do jogador (mascara player_hurt). A coleta e por
## POLLING a cada frame de fisica (sobreposicao), entao um pickup que nao coube (inventario cheio)
## continua no chao e e coletado depois, quando houver espaco. `collected` e emitido no maximo UMA
## vez (flag `_done`); coleta parcial reduz `quantity` e mantem o pickup.
## O destino e o `PlayerLoadout` encontrado no pai da Hurtbox (filho "Loadout").

signal collected(item_id: StringName, quantity: int)

const SCENE_PATH: String = "res://scenes/pickups/pickup.tscn"

var item_id: StringName = &""
var quantity: int = 1

var _done: bool = false


## Cria (sem adicionar a arvore) um pickup a partir da cena. Chamador define posicao e add_child.
static func create(p_item_id: StringName, p_quantity: int) -> Pickup:
	var scene: PackedScene = load(SCENE_PATH) as PackedScene
	if scene == null:
		push_error("Pickup: cena ausente %s" % SCENE_PATH)
		return null
	var p: Pickup = scene.instantiate() as Pickup
	p.item_id = p_item_id
	p.quantity = p_quantity
	return p


func _ready() -> void:
	collision_layer = 0
	collision_mask = CombatLayers.PLAYER_HURT
	monitoring = true
	monitorable = false
	var label: Label3D = get_node_or_null("Label") as Label3D
	if label != null:
		label.text = "%s x%d" % [item_id, quantity] if quantity > 1 else String(item_id)


func _physics_process(_delta: float) -> void:
	if _done:
		return
	for area: Area3D in get_overlapping_areas():
		var hurtbox: Hurtbox = area as Hurtbox
		if hurtbox == null or hurtbox.get_parent() == null:
			continue
		var loadout: PlayerLoadout = PlayerLoadout.find_for(hurtbox.get_parent())
		if loadout != null and try_collect(loadout):
			return


func _process(delta: float) -> void:
	var mesh: Node3D = get_node_or_null("Mesh") as Node3D
	if mesh != null:
		mesh.rotate_y(delta * 2.0) # apresentacao


func is_done() -> bool:
	return _done


## Tenta mover para o inventario. true = coletado por completo (pickup removido).
func try_collect(loadout: PlayerLoadout) -> bool:
	if _done or loadout == null or quantity <= 0:
		return false
	var left: int = loadout.inventory.add(item_id, quantity)
	var taken: int = quantity - left
	if taken > 0:
		collected.emit(item_id, taken)
	quantity = left
	if left > 0:
		_refresh_label()
		return false
	_done = true
	queue_free()
	return true


func _refresh_label() -> void:
	var label: Label3D = get_node_or_null("Label") as Label3D
	if label != null:
		label.text = "%s x%d" % [item_id, quantity] if quantity > 1 else String(item_id)
