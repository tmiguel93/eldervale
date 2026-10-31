class_name PlayerLoadout
extends Node
## Inventario, equipamento e progressao do jogador (filho "Loadout" do Player, depois de "Combat").
## Recalcula os stats finais com StatCalculator (base + nivel + equipados) e os aplica em
## HealthComponent.stats e no ResourcePool de PlayerCombat. Como o dano do golpe e
## `health.stats.attack_power * multiplicador`, equipar uma arma muda o dano real.
##
## POLITICA DE VIDA/RECURSO ao mudar o maximo: preserva a PROPORCAO atual (current/max_antigo *
## max_novo). Assim equipar nao "enche" de graca e desequipar/reequipar nao cria vida (sem
## exploit de troca). Subir de nivel usa a mesma regra (vida sobe proporcionalmente ao novo maximo).
## Jogador morto: stats sao recalculados mas a vida permanece 0.
## Autoridade local (E2): nada aqui e validado por servidor (E3).

signal stats_changed(final_stats: StatBlock)
signal inventory_message(text: String)

@export var combat_path: NodePath = NodePath("../Combat")
@export var inventory_capacity: int = 20

var registry: ContentRegistry
var inventory: Inventory
var equipment: Equipment
var progress: CharacterProgress = CharacterProgress.new()
var final_stats: StatBlock

var combat: PlayerCombat
var health: HealthComponent
var base_stats: StatBlock


## Acha o Loadout do jogador a partir do Player (ou de qualquer no cujo filho seja "Loadout").
static func find_for(node: Node) -> PlayerLoadout:
	if node == null:
		return null
	return node.get_node_or_null("Loadout") as PlayerLoadout


func _ready() -> void:
	if registry == null:
		registry = ContentRegistry.new()
		registry.load_all()
	inventory = Inventory.new(registry, inventory_capacity)
	equipment = Equipment.new(registry, inventory)
	combat = get_node_or_null(combat_path) as PlayerCombat
	if combat == null or combat.health == null:
		push_error("PlayerLoadout: requer irmao Combat (PlayerCombat) pronto; coloque Loadout depois de Combat.")
		return
	health = combat.health
	base_stats = combat.base_stats.copy() if combat.base_stats != null else health.stats.copy()
	equipment.equipment_changed.connect(func(_slot: int) -> void: recalculate())
	progress.leveled_up.connect(func(_lvl: int, _gained: int) -> void: recalculate())
	recalculate()


## Recalcula e aplica os stats finais (ver politica de proporcao no cabecalho).
func recalculate() -> void:
	if health == null:
		return
	var old_hp_max: float = health.max_health()
	var pool: ResourcePool = combat.resource_pool
	var old_res_max: float = pool.max_value()
	var hp_ratio: float = health.current_health / old_hp_max if old_hp_max > 0.0 else 1.0
	var res_ratio: float = pool.current / old_res_max if old_res_max > 0.0 else 1.0
	final_stats = StatCalculator.compute(base_stats, equipment, progress)
	health.stats = final_stats
	if not health.is_dead:
		health.current_health = clampf(hp_ratio * final_stats.max_health, 0.0, final_stats.max_health)
	health.health_changed.emit(health.current_health, final_stats.max_health)
	pool.stats = final_stats
	pool.current = clampf(res_ratio * final_stats.max_resource, 0.0, final_stats.max_resource)
	pool.changed.emit(pool.current, final_stats.max_resource)
	stats_changed.emit(final_stats)


## Concede XP (apenas via inimigo/sistema local). Retorna niveis ganhos.
func grant_xp(amount: int) -> int:
	return progress.add_xp(amount)


## Equipa o item da pilha `index` (0-based, ordem de inventory.contents()). false se nao equipavel.
func equip_from_index(index: int) -> bool:
	var contents: Array[Dictionary] = inventory.contents()
	if index < 0 or index >= contents.size():
		return false
	var id: StringName = contents[index]["id"] as StringName
	if not equipment.equip(id):
		inventory_message.emit(equipment.last_error)
		return false
	return true


func unequip_slot(slot: int) -> bool:
	if not equipment.unequip(slot):
		inventory_message.emit(equipment.last_error)
		return false
	return true
