class_name EnemyTelegraph
extends RefCounted
## Indicador de chao do telegrafo de um EnemyAttack (apresentacao). Devolve um MeshInstance3D plano e
## translucido no referencial do inimigo (-Z = frente) para ser filho de `Visual`. Servidor e cliente
## usam o mesmo desenho; nada aqui decide gameplay.

const GROUND_Y: float = 0.06


static func build(attack: EnemyAttack) -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = "Telegraph"
	var mesh: Mesh = null
	match attack.kind:
		EnemyAttack.Kind.AOE:
			var cyl: CylinderMesh = CylinderMesh.new()
			cyl.top_radius = attack.radius
			cyl.bottom_radius = attack.radius
			cyl.height = 0.04
			mesh = cyl
			node.position = Vector3(0.0, GROUND_Y, -attack.aoe_offset)
		EnemyAttack.Kind.SUMMON:
			var ring: CylinderMesh = CylinderMesh.new()
			ring.top_radius = 2.6
			ring.bottom_radius = 2.6
			ring.height = 0.04
			mesh = ring
			node.position = Vector3(0.0, GROUND_Y, 0.0)
		EnemyAttack.Kind.CHARGE:
			var cbox: BoxMesh = BoxMesh.new()
			cbox.size = Vector3(attack.width, 0.04, attack.charge_distance)
			mesh = cbox
			node.position = Vector3(0.0, GROUND_Y, -attack.charge_distance * 0.5)
		EnemyAttack.Kind.PROJECTILE:
			var pbox: BoxMesh = BoxMesh.new()
			pbox.size = Vector3(0.3, 0.04, attack.max_range)
			mesh = pbox
			node.position = Vector3(0.0, GROUND_Y, -attack.max_range * 0.5)
		_:
			var mbox: BoxMesh = BoxMesh.new()
			mbox.size = Vector3(attack.width, 0.04, attack.max_range)
			mesh = mbox
			node.position = Vector3(0.0, GROUND_Y, -attack.max_range * 0.5)
	var mat: StandardMaterial3D = StandardMaterial3D.new() # placeholder
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = attack.telegraph_color
	mesh.material = mat
	node.mesh = mesh
	return node


## Alpha do indicador conforme o progresso do windup (0..1): comeca fraco e termina forte.
static func alpha_for(progress: float) -> float:
	return lerpf(0.18, 0.75, clampf(progress, 0.0, 1.0))
