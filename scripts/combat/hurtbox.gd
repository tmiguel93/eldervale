class_name Hurtbox
extends Area3D
## Area que RECEBE golpes e os repassa ao HealthComponent ligado em `health`.
## DEDUPE (autoritativo): cada par (source, hit_id) so causa dano UMA vez por Hurtbox, mesmo que
## o Hitbox continue sobreposto por varios frames ou entre/saia da area. O Hitbox tambem
## mantem seu proprio conjunto por golpe (otimizacao), mas a garantia vive aqui.

const MAX_HISTORY: int = 128

@export var health_path: NodePath = NodePath("../Health")
@export var team: CombatLayers.Team = CombatLayers.Team.PLAYER

var health: HealthComponent ## resolvido de health_path no _ready (ou atribuido por codigo)
var _seen: Dictionary = {} ## chave -> true
var _order: Array[String] = []


func _ready() -> void:
	if health == null:
		health = get_node_or_null(health_path) as HealthComponent
	collision_layer = CombatLayers.hurt_layer(team)
	collision_mask = 0
	monitoring = false
	monitorable = true


## Aplica o golpe. Retorna o dano final aplicado (0 se duplicado, sem vida ligada ou bloqueado).
func receive_hit(info: DamageInfo) -> float:
	if info == null or health == null:
		return 0.0
	var key: String = "%d:%d" % [info.source.get_instance_id() if info.source != null else 0, info.hit_id]
	if _seen.has(key):
		return 0.0
	_seen[key] = true
	_order.append(key)
	if _order.size() > MAX_HISTORY:
		_seen.erase(_order.pop_front())
	return health.apply_damage(info)


func clear_history() -> void:
	_seen.clear()
	_order.clear()
