class_name SkillProjectile
extends Area3D
## E6.1: projetil de habilidade do JOGADOR (flecha, bola de fogo...). So existe no servidor/jogo local; o cliente remoto
## nao o simula (so ve o efeito: hp do inimigo, numeros de dano). Movimento VARRIDO: a cada passo avanca em sub-passos de no
## maximo `radius` e consulta as Hurtbox (camada ENEMY_HURT) com intersect_shape, entao nao atravessa alvos mesmo a 30 Hz
## (servidor) e o resultado nao depende de a fisica ja ter processado o frame. Um StaticBody do mundo (raio) consome o projetil.
## Dano: `damage` (bruto, antes de defesa) por alvo; cada Hurtbox recebe no maximo UM golpe (dedupe por golpe, como Hitbox).
## `pierce` = alvos ADICIONAIS que atravessa: pierce 0 some no primeiro alvo; ao consumir os acertos o projetil e liberado.
## Se varios alvos estao sobrepostos no mesmo passo, os acertos alem do limite sao ignorados (ordem de sobreposicao).
## Movimento/sondagem em step(delta) (chamado pelo physics_process; testes chamam manualmente).

signal hit_target(hurtbox: Hurtbox, applied: float)
signal expired

var direction: Vector3 = Vector3.FORWARD
var speed: float = 12.0
var damage: float = 1.0
var max_range: float = 10.0
var pierce: int = 0
var radius: float = 0.4
var source: Node
var damage_type: StringName = &"physical"
var consumed: bool = false
var traveled: float = 0.0
var hits: int = 0
var hit_id: int = 0

var _targets: Dictionary = {}
var _shape: SphereShape3D


## Cria o projetil a partir da skill (nao entra na arvore). `origin` e a posicao global de disparo.
static func from_skill(skill: SkillData, p_source: Node, origin: Vector3, dir: Vector3, p_damage: float) -> SkillProjectile:
	var p: SkillProjectile = SkillProjectile.new()
	p.direction = Vector3(dir.x, 0.0, dir.z).normalized() if dir.length_squared() > 0.0001 else Vector3.FORWARD
	p.speed = skill.projectile_speed
	p.max_range = skill.projectile_range
	p.pierce = skill.projectile_pierce
	p.radius = skill.hitbox_size.x
	p.damage = p_damage
	p.source = p_source
	p.position = origin
	return p


func _ready() -> void:
	monitoring = false
	monitorable = false
	hit_id = Hitbox.new_hit_id()
	_shape = SphereShape3D.new()
	_shape.radius = radius


func _physics_process(delta: float) -> void:
	step(delta)


func step(delta: float) -> void:
	if consumed:
		return
	if source == null or not is_instance_valid(source):
		_finish(false) # atacante saiu do jogo: nao ha a quem atribuir o dano
		return
	if _shape == null:
		_shape = SphereShape3D.new()
		_shape.radius = radius
	if traveled == 0.0 and hits == 0:
		_poll_hits(global_position) # alvo ja dentro do raio no disparo
		if consumed:
			return
	var dist: float = minf(speed * delta, max_range - traveled)
	var substeps: int = maxi(1, int(ceil(dist / maxf(radius, 0.1))))
	var stride: float = dist / float(substeps)
	for i: int in substeps:
		var from: Vector3 = global_position
		var to: Vector3 = from + direction * stride
		if _world_blocked(from, to):
			_finish(false)
			return
		global_position = to
		traveled += stride
		_poll_hits(to)
		if consumed:
			return
	if traveled >= max_range - 0.0001:
		_finish(true)


func _poll_hits(at: Vector3) -> void:
	if not is_inside_tree():
		return
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = _shape
	query.transform = Transform3D(Basis.IDENTITY, at)
	query.collision_mask = CombatLayers.ENEMY_HURT
	query.collide_with_areas = true
	query.collide_with_bodies = false
	for r: Dictionary in get_world_3d().direct_space_state.intersect_shape(query, 16):
		var hurtbox: Hurtbox = r.get("collider") as Hurtbox
		if hurtbox == null or _targets.has(hurtbox):
			continue
		if hurtbox.health != null and source.is_ancestor_of(hurtbox.health):
			continue # nunca acerta o proprio atacante
		_targets[hurtbox] = true
		var info: DamageInfo = DamageInfo.make(damage, source, hit_id, damage_type)
		var applied: float = hurtbox.receive_hit(info)
		hits += 1
		hit_target.emit(hurtbox, applied)
		if hits > pierce:
			_finish(false)
			return


func _finish(emit_expired: bool) -> void:
	consumed = true
	if emit_expired:
		expired.emit()
	if is_inside_tree():
		queue_free()


func _world_blocked(from: Vector3, to: Vector3) -> bool:
	if not is_inside_tree() or from.is_equal_approx(to):
		return false
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to, CombatLayers.WORLD)
	query.collide_with_areas = false
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return false
	return hit["collider"] is StaticBody3D
