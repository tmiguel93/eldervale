class_name StatUtil
extends RefCounted
## Helpers para StatBlock. StatBlock tem defaults de personagem (vida 100 etc.);
## modificadores de item/nivel precisam partir de zero.


## Bloco com todos os campos em 0 (neutro para StatBlock.add).
static func zero() -> StatBlock:
	var b: StatBlock = StatBlock.new()
	b.max_health = 0.0
	b.max_resource = 0.0
	b.resource_regen = 0.0
	b.attack_power = 0.0
	b.defense = 0.0
	b.resistance = 0.0
	b.move_speed = 0.0
	return b


## Multiplica todos os campos por `factor` (nao muta o original).
static func scaled(src: StatBlock, factor: float) -> StatBlock:
	var b: StatBlock = StatBlock.new()
	b.max_health = src.max_health * factor
	b.max_resource = src.max_resource * factor
	b.resource_regen = src.resource_regen * factor
	b.attack_power = src.attack_power * factor
	b.defense = src.defense * factor
	b.resistance = src.resistance * factor
	b.move_speed = src.move_speed * factor
	return b


static func equals(a: StatBlock, b: StatBlock) -> bool:
	return is_equal_approx(a.max_health, b.max_health) \
		and is_equal_approx(a.max_resource, b.max_resource) \
		and is_equal_approx(a.resource_regen, b.resource_regen) \
		and is_equal_approx(a.attack_power, b.attack_power) \
		and is_equal_approx(a.defense, b.defense) \
		and is_equal_approx(a.resistance, b.resistance) \
		and is_equal_approx(a.move_speed, b.move_speed)
