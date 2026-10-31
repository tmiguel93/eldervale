class_name StatBlock
extends Resource
## Atributos numericos de uma entidade (contrato compartilhado E2).
## Dados puros: sem logica de gameplay. Somar blocos = base + equipamentos.

@export var max_health: float = 100.0
@export var max_resource: float = 50.0
@export var resource_regen: float = 5.0 ## por segundo
@export var attack_power: float = 10.0
@export var defense: float = 0.0 ## reducao plana de dano
@export var resistance: float = 0.0 ## 0.0..0.75, reducao percentual
@export var move_speed: float = 5.0


func add(other: StatBlock) -> void:
	max_health += other.max_health
	max_resource += other.max_resource
	resource_regen += other.resource_regen
	attack_power += other.attack_power
	defense += other.defense
	resistance = clampf(resistance + other.resistance, 0.0, 0.75)
	move_speed += other.move_speed


func copy() -> StatBlock:
	var b: StatBlock = StatBlock.new()
	b.max_health = max_health
	b.max_resource = max_resource
	b.resource_regen = resource_regen
	b.attack_power = attack_power
	b.defense = defense
	b.resistance = resistance
	b.move_speed = move_speed
	return b


## Soma `base` com cada bloco de `modifiers` sem alterar os originais.
static func combine(base: StatBlock, modifiers: Array[StatBlock]) -> StatBlock:
	var result: StatBlock = base.copy()
	for m: StatBlock in modifiers:
		result.add(m)
	return result
