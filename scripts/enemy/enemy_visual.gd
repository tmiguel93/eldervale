class_name EnemyVisual
extends Node3D
## Apresentacao do inimigo (no "Visual"): malha PLACEHOLDER por comportamento, etiqueta com o nome
## e pulso de telegrafo durante o windup. Nenhuma regra de gameplay aqui.
##  melee  -> caixa vermelha larga; ranged -> cone roxo alto + esfera flutuante.

const MELEE_COLOR: Color = Color(0.75, 0.2, 0.15)
const RANGED_COLOR: Color = Color(0.5, 0.25, 0.8)

var _body: MeshInstance3D
var _telegraphing: bool = false


func apply(data: EnemyData) -> void:
	_body = get_node_or_null("Body") as MeshInstance3D
	if _body == null:
		push_error("EnemyVisual: filho Body ausente.")
		return
	var mat: StandardMaterial3D = StandardMaterial3D.new() # placeholder
	if data.behavior == EnemyData.BEHAVIOR_RANGED:
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
	tag.position = Vector3(0.0, 2.7, 0.0)
	add_child(tag)


## Liga ao sinal de estado da IA para o pulso de telegrafo.
func bind(ai: EnemyAI) -> void:
	ai.state_changed.connect(_on_state_changed)


func _on_state_changed(_from: EnemyAI.State, to: EnemyAI.State) -> void:
	_telegraphing = to == EnemyAI.State.ATTACK
	if _body != null:
		_body.scale = Vector3(1.25, 1.25, 1.25) if _telegraphing else Vector3.ONE
