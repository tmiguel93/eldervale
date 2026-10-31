class_name EnemyVisual
extends Node3D
## Apresentacao do inimigo (no "Visual"): malha PLACEHOLDER por comportamento, etiqueta com o nome
## e pulso de telegrafo durante o windup. Nenhuma regra de gameplay aqui.
##  melee  -> caixa vermelha larga; ranged -> cone roxo alto + esfera flutuante.

const MELEE_COLOR: Color = Color(0.75, 0.2, 0.15)
const RANGED_COLOR: Color = Color(0.5, 0.25, 0.8)

var _body: MeshInstance3D
var _telegraphing: bool = false
var _ai: EnemyAI
var _ambush: bool = false
var _scale: float = 1.0
var _telegraph: MeshInstance3D
var _telegraph_attack: EnemyAttack


func apply(data: EnemyData) -> void:
	_body = get_node_or_null("Body") as MeshInstance3D
	if _body == null:
		push_error("EnemyVisual: filho Body ausente.")
		return
	_ambush = data.ambush
	_scale = data.visual_scale
	var mat: StandardMaterial3D = StandardMaterial3D.new() # placeholder
	if data.visual_shape != &"":
		_apply_custom(data, mat)
	elif data.behavior == EnemyData.BEHAVIOR_RANGED:
		var cone: CylinderMesh = CylinderMesh.new()
		cone.top_radius = 0.05
		cone.bottom_radius = 0.5
		cone.height = 1.9
		mat.albedo_color = RANGED_COLOR
		cone.material = mat
		_body.mesh = cone
		_body.position = Vector3(0.0, 0.95, 0.0)
		var orb: MeshInstance3D = MeshInstance3D.new()
		orb.name = "Orb"
		var sph: SphereMesh = SphereMesh.new()
		sph.radius = 0.2
		sph.height = 0.4
		var omat: StandardMaterial3D = StandardMaterial3D.new()
		omat.albedo_color = Color(0.9, 0.5, 1.0)
		omat.emission_enabled = true
		omat.emission = Color(0.9, 0.5, 1.0)
		sph.material = omat
		orb.mesh = sph
		orb.position = Vector3(0.0, 2.2, 0.0)
		add_child(orb)
	else:
		var box: BoxMesh = BoxMesh.new()
		box.size = Vector3(0.95, 1.6, 0.95)
		mat.albedo_color = MELEE_COLOR
		box.material = mat
		_body.mesh = box
		_body.position = Vector3(0.0, 0.8, 0.0)
	var tag: Label3D = Label3D.new()
	tag.name = "NameTag"
	tag.text = data.display_name
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	tag.pixel_size = 0.006
	tag.font_size = 40
	tag.outline_size = 8
	tag.position = Vector3(0.0, 2.7 * maxf(_scale, 1.0), 0.0)
	add_child(tag)
	_refresh_body_scale()


## E5.2: forma/cor/escala por dados (box, cone, low, tall). Cor com alpha 0 = padrao do tipo.
func _apply_custom(data: EnemyData, mat: StandardMaterial3D) -> void:
	var color: Color = data.visual_color
	if color.a <= 0.0:
		color = RANGED_COLOR if data.behavior == EnemyData.BEHAVIOR_RANGED else MELEE_COLOR
	color.a = 1.0
	mat.albedo_color = color
	var s: float = data.visual_scale
	match data.visual_shape:
		&"cone":
			var cone: CylinderMesh = CylinderMesh.new()
			cone.top_radius = 0.05
			cone.bottom_radius = 0.5 * s
			cone.height = 1.9 * s
			cone.material = mat
			_body.mesh = cone
			_body.position = Vector3(0.0, 0.95 * s, 0.0)
		&"low":
			var low: BoxMesh = BoxMesh.new()
			low.size = Vector3(0.8, 0.9, 1.5) * s
			low.material = mat
			_body.mesh = low
			_body.position = Vector3(0.0, 0.45 * s, 0.0)
		&"tall":
			var tall: BoxMesh = BoxMesh.new()
			tall.size = Vector3(1.1, 2.4, 1.1) * s
			tall.material = mat
			_body.mesh = tall
			_body.position = Vector3(0.0, 1.2 * s, 0.0)
		_:
			var box: BoxMesh = BoxMesh.new()
			box.size = Vector3(0.95, 1.6, 0.95) * s
			box.material = mat
			_body.mesh = box
			_body.position = Vector3(0.0, 0.8 * s, 0.0)
	if data.behavior == EnemyData.BEHAVIOR_RANGED and data.visual_shape == &"cone":
		var orb: MeshInstance3D = MeshInstance3D.new()
		orb.name = "Orb"
		var sph: SphereMesh = SphereMesh.new()
		sph.radius = 0.2 * s
		sph.height = 0.4 * s
		var omat: StandardMaterial3D = StandardMaterial3D.new()
		omat.albedo_color = color.lightened(0.4)
		omat.emission_enabled = true
		omat.emission = color.lightened(0.4)
		sph.material = omat
		orb.mesh = sph
		orb.position = Vector3(0.0, 2.2 * s, 0.0)
		add_child(orb)


## Liga ao sinal de estado da IA para o pulso de telegrafo.
func bind(ai: EnemyAI) -> void:
	_ai = ai
	ai.state_changed.connect(_on_state_changed)
	_refresh_body_scale()


func _on_state_changed(_from: EnemyAI.State, to: EnemyAI.State) -> void:
	_telegraphing = to == EnemyAI.State.ATTACK
	_refresh_body_scale()
	if _telegraphing and _ai != null and _ai.current_attack != null:
		show_telegraph(_ai.current_attack)
	else:
		hide_telegraph()


func _refresh_body_scale() -> void:
	if _body == null:
		return
	var k: float = 1.25 if _telegraphing else 1.0
	var buried: bool = _ambush and _ai != null and (_ai.state == EnemyAI.State.IDLE or _ai.state == EnemyAI.State.RETURN)
	_body.scale = Vector3(k, 0.3 if buried else k, k)


## Mostra o indicador de chao do ataque (substitui o anterior).
func show_telegraph(attack: EnemyAttack) -> void:
	hide_telegraph()
	_telegraph_attack = attack
	_telegraph = EnemyTelegraph.build(attack)
	add_child(_telegraph)


func hide_telegraph() -> void:
	if _telegraph != null and is_instance_valid(_telegraph):
		_telegraph.queue_free()
	_telegraph = null
	_telegraph_attack = null


func has_telegraph() -> bool:
	return _telegraph != null and is_instance_valid(_telegraph)


func _process(_delta: float) -> void:
	if has_telegraph() and _ai != null:
		var mesh: PrimitiveMesh = _telegraph.mesh as PrimitiveMesh
		var mat: StandardMaterial3D = mesh.material as StandardMaterial3D if mesh != null else null
		if mat != null:
			var c: Color = _telegraph_attack.telegraph_color
			c.a = EnemyTelegraph.alpha_for(_ai.windup_progress())
			mat.albedo_color = c
