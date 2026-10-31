class_name Hitbox
extends Area3D
## Area que CAUSA dano. Fica desligada ate begin_strike(); cada golpe recebe um hit_id NOVO
## (contador estatico global, unico entre todos os Hitbox). Enquanto ativo, a cada frame de
## fisica entrega o golpe as Hurtbox sobrepostas (polling, independente de area_entered).
## Dedupe: ver Hurtbox (autoritativo) + conjunto por golpe aqui.

signal hit_landed(hurtbox: Hurtbox, applied: float)

var source: Node
var damage_type: StringName = &"physical"
var active: bool = false
var current_hit_id: int = 0

static var _hit_counter: int = 0

var _damage: float = 0.0
var _targets: Dictionary = {}
var _shape_node: CollisionShape3D


static func new_hit_id() -> int:
	_hit_counter += 1
	return _hit_counter


func _ready() -> void:
	monitoring = false
	monitorable = false


func setup_team(team: CombatLayers.Team) -> void:
	collision_layer = CombatLayers.hit_layer(team)
	collision_mask = CombatLayers.hit_mask(team)


func configure_shape(skill: SkillData) -> void:
	if _shape_node == null:
		_shape_node = get_node_or_null("Shape") as CollisionShape3D
	if _shape_node == null:
		_shape_node = CollisionShape3D.new()
		_shape_node.name = "Shape"
		add_child(_shape_node)
	if skill.hitbox_shape == SkillData.HitboxShape.SPHERE:
		var sphere: SphereShape3D = SphereShape3D.new()
		sphere.radius = skill.hitbox_size.x
		_shape_node.shape = sphere
	else:
		var box: BoxShape3D = BoxShape3D.new()
		box.size = skill.hitbox_size
		_shape_node.shape = box


## Liga o golpe e devolve o hit_id novo. `amount` e o dano bruto (antes de defesa/resistencia).
func begin_strike(amount: float, p_source: Node = null) -> int:
	current_hit_id = new_hit_id()
	_damage = amount
	source = p_source
	_targets.clear()
	active = true
	monitoring = true
	return current_hit_id


func end_strike() -> void:
	active = false
	monitoring = false
	_targets.clear()


func _physics_process(_delta: float) -> void:
	if not active:
		return
	for area: Area3D in get_overlapping_areas():
		var hurtbox: Hurtbox = area as Hurtbox
		if hurtbox == null or _targets.has(hurtbox):
			continue
		if source != null and hurtbox.health != null and source.is_ancestor_of(hurtbox.health):
			continue # nunca acerta o proprio atacante
		_targets[hurtbox] = true
		var info: DamageInfo = DamageInfo.make(_damage, source, current_hit_id, damage_type)
		var applied: float = hurtbox.receive_hit(info)
		hit_landed.emit(hurtbox, applied)
