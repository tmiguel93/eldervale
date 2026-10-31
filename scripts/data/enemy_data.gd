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

# --- E5.2: campos adicionais (todos com padrao neutro: inimigos antigos nao mudam) ---
const TIER_NORMAL: StringName = &"normal"
const TIER_MINI_BOSS: StringName = &"mini_boss"
const TIER_BOSS: StringName = &"boss"

## normal | mini_boss | boss (escala de dificuldade e HUD).
@export var tier: StringName = TIER_NORMAL
## Papel de design (documentacao/telemetria): melee_basic, fast, ranged, brute, summoner, ambusher...
@export var role: StringName = &""
## Telegrafo (windup) do ataque legado quando `attacks` e vazio.
@export var windup: float = 0.45
## 0 = 2 x aggro_range.
@export var leash_range: float = 0.0
## Ataques do inimigo comum. Vazio = ataque unico legado (behavior/attack_range/attack_cooldown).
@export var attacks: Array[EnemyAttack] = []
## Fases (chefe/mini-chefe). Se houver, substituem `attacks`; a fase 0 tem limiar 1.0.
@export var phases: Array[EnemyPhase] = []
## Emboscador: fica "enterrado" (visual baixo) ate ser acionado.
@export var ambush: bool = false
## Adds invocados somem (sem drop/XP) quando o invocador morre ou o encontro reinicia.
@export var dismiss_adds_on_death: bool = true
## Placeholder visual: "" = por behavior (caixa/cone); box, cone, low, tall.
@export var visual_shape: StringName = &""
@export var visual_color: Color = Color(0.0, 0.0, 0.0, 0.0) ## alpha 0 = cor padrao
@export var visual_scale: float = 1.0


func is_boss() -> bool:
	return tier == TIER_BOSS or tier == TIER_MINI_BOSS


func all_attacks() -> Array[EnemyAttack]:
	var out: Array[EnemyAttack] = []
	out.append_array(attacks)
	for p: EnemyPhase in phases:
		if p != null:
			out.append_array(p.attacks)
	return out
