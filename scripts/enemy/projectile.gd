class_name Projectile
extends Area3D
## Projetil inimigo. Area3D na camada 5 (enemy_hit); mascara = player_hurt (areas) + mundo (corpos).
## Dano UNICO: o primeiro Hurtbox do jogador atingido (ou o primeiro StaticBody do mundo) consome
## o projetil (queue_free). Expira apos `lifetime` s. Corpos nao-estaticos (CharacterBody3D) sao
## atravessados: o jogador so e atingido pela Hurtbox (permite que a esquiva funcione).
## Movimento em step(delta) (chamado pelo physics_process; testes podem chamar manualmente).

signal hit_target(hurtbox: Hurtbox, applied: float)
signal expired

var direction: Vector3 = Vector3.FORWARD
var speed: float = 12.0
var damage: float = 8.0
var lifetime: float = 4.0
var source: Node
var consumed: bool = false
var radius: float = 0.25

var _age: float = 0.0


func _ready() -> void:
	collision_layer = CombatLayers.ENEMY_HIT
	collision_mask = CombatLayers.PLAYER_HURT
	monitoring = true
	monitorable = false
	if get_node_or_null("Shape") == null:
		var shape_node: CollisionShape3D = CollisionShape3D.new()
		shape_node.name = "Shape"
		var s: SphereShape3D = SphereShape3D.new()
		s.radius = radius
		shape_node.shape = s
		add_child(shape_node)
		var mesh_inst: MeshInstance3D = MeshInstance3D.new()
		mesh_inst.name = "Mesh"
		var m: SphereMesh = SphereMesh.new()
		m.radius = radius
		m.height = radius * 2.0
		var mat: StandardMaterial3D = StandardMaterial3D.new() # placeholder
		mat.albedo_color = Color(0.8, 0.3, 1.0)
		mat.emission_enabled = true
		mat.emission = Color(0.8, 0.3, 1.0)
		m.material = mat
		mesh_inst.mesh = m
		add_child(mesh_inst)
	area_entered.connect(_on_area_entered)


func _physics_process(delta: float) -> void:
	step(delta)


func step(delta: float) -> void:
	if consumed:
		return
	var from: Vector3 = global_position
	var to: Vector3 = from + direction * speed * delta
	if _world_blocked(from, to):
		consumed = true
		queue_free()
		return
	global_position = to
	_age += delta
	if _age >= lifetime:
		consumed = true
		expired.emit()
		queue_free()


func _on_area_entered(area: Area3D) -> void:
	if consumed:
		return
	var hurtbox: Hurtbox = area as Hurtbox
	if hurtbox == null:
		return
	consumed = true
	var info: DamageInfo = DamageInfo.make(damage, source, Hitbox.new_hit_id())
	var applied: float = hurtbox.receive_hit(info)
	hit_target.emit(hurtbox, applied)
	queue_free()


func _world_blocked(from: Vector3, to: Vector3) -> bool:
	if not is_inside_tree():
		return false
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to, CombatLayers.WORLD)
	query.collide_with_areas = false
	query.hit_from_inside = true
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return false
	return hit["collider"] is StaticBody3D
