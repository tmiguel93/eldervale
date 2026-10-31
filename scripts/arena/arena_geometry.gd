class_name ArenaGeometry
extends RefCounted
## Geometria da arena E1 (1 unidade = 1 m), compartilhada pela arena local (com malhas) e pelo
## servidor dedicado (sem malhas: so StaticBody3D + CollisionShape3D, mesmas formas/posicoes).

const OCCLUDER_GROUP: StringName = &"occluder"
const FLOOR_SIZE: float = 60.0
const RAMP_ANGLE_DEG: float = 20.0  # <= 30
const RAMP_LENGTH: float = 8.0
const RAMP_WIDTH: float = 4.0
const STAIR_STEPS: int = 10
const STAIR_RISE: float = 0.2
const STAIR_DEPTH: float = 0.4
const STAIR_WIDTH: float = 3.0
const CORRIDOR_WIDTH: float = 2.5
const CORRIDOR_LENGTH: float = 14.0
const WALL_HEIGHT: float = 4.0


static func build(parent: Node3D, with_visuals: bool = true) -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = "Geometry"
	parent.add_child(root)

	var grey: Color = Color(0.45, 0.47, 0.5)
	var wall_col: Color = Color(0.55, 0.5, 0.45)
	var accent: Color = Color(0.8, 0.5, 0.2)
	var step_col: Color = Color(0.3, 0.55, 0.7)

	# Piso: topo em y=0.
	_add_box(root, with_visuals, "Floor", Vector3(FLOOR_SIZE, 1.0, FLOOR_SIZE), Vector3(0, -0.5, 0), Color(0.32, 0.36, 0.32), false)

	# Muralha externa (occluder).
	var half: float = FLOOR_SIZE * 0.5
	var wy: float = WALL_HEIGHT * 0.5
	_add_box(root, with_visuals, "WallN", Vector3(FLOOR_SIZE, WALL_HEIGHT, 1.0), Vector3(0, wy, -half + 0.5), wall_col, true)
	_add_box(root, with_visuals, "WallS", Vector3(FLOOR_SIZE, WALL_HEIGHT, 1.0), Vector3(0, wy, half - 0.5), wall_col, true)
	_add_box(root, with_visuals, "WallE", Vector3(1.0, WALL_HEIGHT, FLOOR_SIZE), Vector3(half - 0.5, wy, 0), wall_col, true)
	_add_box(root, with_visuals, "WallW", Vector3(1.0, WALL_HEIGHT, FLOOR_SIZE), Vector3(-half + 0.5, wy, 0), wall_col, true)

	# Area aberta central (x,z em -10..10): caixas baixas e pilares altos (occluder).
	_add_box(root, with_visuals, "Crate1", Vector3(1.5, 1.0, 1.5), Vector3(5, 0.5, 4), grey, false)
	_add_box(root, with_visuals, "Crate2", Vector3(2.0, 1.5, 1.0), Vector3(-5, 0.75, 3), grey, false)
	_add_box(root, with_visuals, "Crate3", Vector3(1.0, 1.0, 1.0), Vector3(3, 0.5, -4), grey, false)
	_add_box(root, with_visuals, "Pillar1", Vector3(1.0, 6.0, 1.0), Vector3(-4, 3.0, -4), wall_col, true)
	_add_box(root, with_visuals, "Pillar2", Vector3(1.0, 6.0, 1.0), Vector3(6, 3.0, -2), wall_col, true)
	_add_box(root, with_visuals, "Pillar3", Vector3(1.0, 6.0, 1.0), Vector3(2, 3.0, 7), wall_col, true)
	_add_box(root, with_visuals, "Pillar4", Vector3(1.2, 6.0, 1.2), Vector3(-7, 3.0, 8), wall_col, true)

	# Corredor estreito ao norte (z de -12 a -26), abre para x=0.
	var cz: float = -12.0 - CORRIDOR_LENGTH * 0.5
	var cx: float = CORRIDOR_WIDTH * 0.5 + 0.25
	_add_box(root, with_visuals, "CorridorWallL", Vector3(0.5, WALL_HEIGHT, CORRIDOR_LENGTH), Vector3(-cx, wy, cz), wall_col, true)
	_add_box(root, with_visuals, "CorridorWallR", Vector3(0.5, WALL_HEIGHT, CORRIDOR_LENGTH), Vector3(cx, wy, cz), wall_col, true)

	# Rampa a leste: sobe em +x, depois plataforma.
	var ang: float = deg_to_rad(RAMP_ANGLE_DEG)
	var rise: float = RAMP_LENGTH * sin(ang)
	var ramp_thick: float = 0.4
	var ramp_cx: float = 14.0
	var ramp_pos: Vector3 = Vector3(
		ramp_cx + (ramp_thick * 0.5) * sin(ang),
		rise * 0.5 - (ramp_thick * 0.5) * cos(ang),
		8.0)
	_add_box(root, with_visuals, "Ramp", Vector3(RAMP_LENGTH, ramp_thick, RAMP_WIDTH), ramp_pos, accent, false, Vector3(0, 0, RAMP_ANGLE_DEG))
	var plat_x0: float = ramp_cx + RAMP_LENGTH * 0.5 * cos(ang)
	_add_box(root, with_visuals, "RampPlatform", Vector3(4.0, rise, RAMP_WIDTH), Vector3(plat_x0 + 2.0, rise * 0.5, 8.0), grey, false)

	# Escada de teste a oeste: degraus de 0.2 m subindo em +z, depois plataforma.
	for i: int in range(STAIR_STEPS):
		var h: float = (i + 1) * STAIR_RISE
		_add_box(root, with_visuals, "Step%d" % i, Vector3(STAIR_WIDTH, h, STAIR_DEPTH),
			Vector3(-16.0, h * 0.5, 4.0 + i * STAIR_DEPTH + STAIR_DEPTH * 0.5), step_col, false)
	var top_h: float = STAIR_STEPS * STAIR_RISE
	_add_box(root, with_visuals, "StairPlatform", Vector3(STAIR_WIDTH, top_h, 4.0),
		Vector3(-16.0, top_h * 0.5, 4.0 + STAIR_STEPS * STAIR_DEPTH + 2.0), grey, false)
	return root


static func _add_box(parent: Node3D, with_visuals: bool, node_name: String, size: Vector3, pos: Vector3, color: Color,
		occluder: bool, rot_deg: Vector3 = Vector3.ZERO) -> StaticBody3D:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = node_name
	body.position = pos
	body.rotation_degrees = rot_deg
	if with_visuals:
		_add_mesh(body, size, color)
	var col: CollisionShape3D = CollisionShape3D.new()
	col.name = "Collision"
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	if occluder:
		body.add_to_group(OCCLUDER_GROUP)
	parent.add_child(body)
	return body


static func _add_mesh(body: StaticBody3D, size: Vector3, color: Color) -> void:
	var mesh_inst: MeshInstance3D = MeshInstance3D.new()
	mesh_inst.name = "Mesh"
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	var mat: StandardMaterial3D = StandardMaterial3D.new()  # placeholder
	mat.albedo_color = color
	mat.roughness = 0.9
	mesh.material = mat
	mesh_inst.mesh = mesh
	body.add_child(mesh_inst)
