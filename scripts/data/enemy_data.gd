class_name EnemyData
extends Resource
## Definicao estatica de inimigo (dados separados da logica/cena).

const BEHAVIOR_MELEE: StringName = &"melee"
const BEHAVIOR_RANGED: StringName = &"ranged"

@export var id: StringName = &""
@export var display_name: String = ""
@export var stats: StatBlock
@export var xp_reward: int = 0
@export var loot_table: LootTable
@export var behavior: StringName = BEHAVIOR_MELEE
@export var aggro_range: float = 10.0
@export var attack_range: float = 1.8
@export var attack_cooldown: float = 1.5
@export var attack_damage_multiplier: float = 1.0
@export var projectile_speed: float = 0.0 ## so usado por ranged
@export var placeholder: bool = false
