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

# --- E8.1: apresentacao 3D (SO cliente; o servidor ignora estes campos e nunca carrega assets) ---
## Alias do manifest (assets/ASSET_MANIFEST.json > aliases / id de asset) ou caminho res://assets/third_party/...glb. "" = primitivas.
@export var visual_scene: String = ""
## Altura alvo em metros: o cliente mede o AABB do modelo e normaliza a escala (os pacotes nao compartilham escala).
@export var visual_height: float = 1.8
## Multiplicador de cor do albedo; alpha 0 = sem tintura.
@export var visual_tint: Color = Color(1.0, 1.0, 1.0, 0.0)
## Giro extra (graus) sobre a orientacao padrao dos modelos.
@export var visual_yaw_offset: float = 0.0
## Estado (idle|move|attack|skill|dodge|hit|death|spawn) -> nome do clip (sem prefixo `Armature|`). Ausente = padrao do ClipTable.
@export var visual_clips: Dictionary = {}
## Meshes de acessorio (hat, arma, escudo) que ficam visiveis; vazio = nao esconde nada.
@export var visual_equip: PackedStringArray = PackedStringArray()
## true = visual provisorio (asset reaproveitado, ex.: chefe = esqueleto grande).
@export var visual_placeholder: bool = false


func visual_spec() -> VisualSpec:
	return VisualSpec.from_enemy(self)


func is_boss() -> bool:
	return tier == TIER_BOSS or tier == TIER_MINI_BOSS


func all_attacks() -> Array[EnemyAttack]:
	var out: Array[EnemyAttack] = []
	out.append_array(attacks)
	for p: EnemyPhase in phases:
		if p != null:
			out.append_array(p.attacks)
	return out
