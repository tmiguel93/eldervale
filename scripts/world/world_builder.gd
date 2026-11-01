class_name WorldBuilder
extends RefCounted
## Monta a geometria de uma zona (ZoneDef) em primitivas: piso, muralha, props, portais, placas, portao.
## O servidor usa `with_visuals=false` (so StaticBody3D + colisao, mesmas formas do cliente); o cliente
## usa `true` (malhas placeholder, arte provisoria). Occluders (grupo `occluder`) tem um MeshInstance3D
## filho para o OcclusionFader do E1. Convencao de nomes: "Zone_<id>/Floor|Wall*|Prop_*|Portal_*|Plate_<i>|PuzzleGate|Npc_*".

const OCCLUDER_GROUP: StringName = &"occluder"
const WALL_HEIGHT: float = 4.0
const WALL_THICKNESS: float = 1.0
const GATE_META: StringName = &"gate_layer"
const PLATE_OFF: Color = Color(0.35, 0.33, 0.30)
const PLATE_ON: Color = Color(0.35, 0.85, 0.45)
const GATE_COLOR: Color = Color(0.55, 0.42, 0.28)


static func build_zone(parent: Node, zone: ZoneDef, with_visuals: bool, npcs: NpcDirectory = null) -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = "Zone_%s" % zone.id
	parent.add_child(root)
	var c: Vector3 = zone.center
	_box(root, with_visuals, "Floor", Vector3(zone.size.x, 1.0, zone.size.y), c + Vector3(0.0, -0.5, 0.0), zone.floor_color, false)
	var hx: float = zone.size.x * 0.5
	var hz: float = zone.size.y * 0.5
	var wy: float = WALL_HEIGHT * 0.5
	var t: float = WALL_THICKNESS
	_box(root, with_visuals, "WallN", Vector3(zone.size.x, WALL_HEIGHT, t), c + Vector3(0.0, wy, -hz + t * 0.5), zone.wall_color, true)
	_box(root, with_visuals, "WallS", Vector3(zone.size.x, WALL_HEIGHT, t), c + Vector3(0.0, wy, hz - t * 0.5), zone.wall_color, true)
	_box(root, with_visuals, "WallW", Vector3(t, WALL_HEIGHT, zone.size.y), c + Vector3(-hx + t * 0.5, wy, 0.0), zone.wall_color, true)
	_box(root, with_visuals, "WallE", Vector3(t, WALL_HEIGHT, zone.size.y), c + Vector3(hx - t * 0.5, wy, 0.0), zone.wall_color, true)
	for p: Dictionary in zone.props:
		_add_prop(root, with_visuals, p)
	if with_visuals:
		for portal: Dictionary in zone.portals:
			_add_portal_visual(root, portal)
	if not zone.puzzle.is_empty():
		_add_puzzle(root, with_visuals, zone.puzzle)
	if with_visuals and npcs != null:
		for npc_id: String in zone.npcs:
			if npcs.has_npc(npc_id):
				_add_npc_marker(root, npcs.get_npc(npc_id))
	return root


# ------------------------------------------------------------------ puzzle (estado visual/colisao)

static func gate_of(zone_root: Node) -> StaticBody3D:
	return zone_root.get_node_or_null("PuzzleGate") as StaticBody3D


## Abre/fecha o portao: colisao desligada (servidor e cliente) e malha escondida/abaixada (cliente).
static func set_gate_open(zone_root: Node, open: bool) -> void:
	var gate: StaticBody3D = gate_of(zone_root)
	if gate == null:
		return
	if not gate.has_meta(GATE_META):
		gate.set_meta(GATE_META, gate.collision_layer)
	gate.collision_layer = 0 if open else int(gate.get_meta(GATE_META))
	gate.collision_mask = 0
	var mesh: Node3D = gate.get_node_or_null("Mesh") as Node3D
	if mesh != null:
		mesh.visible = not open
	if open:
		gate.remove_from_group(OCCLUDER_GROUP)
	else:
		gate.add_to_group(OCCLUDER_GROUP)


static func set_plate_lit(zone_root: Node, index: int, lit: bool) -> void:
	var plate: MeshInstance3D = zone_root.get_node_or_null("Plate_%d" % index) as MeshInstance3D
	if plate == null:
		return
	var mat: StandardMaterial3D = plate.material_override as StandardMaterial3D
	if mat == null:
		return
	mat.albedo_color = PLATE_ON if lit else PLATE_OFF
	mat.emission_enabled = lit
	mat.emission = PLATE_ON
	mat.emission_energy_multiplier = 0.8


# ------------------------------------------------------------------ pecas

static func _add_prop(root: Node3D, with_visuals: bool, p: Dictionary) -> void:
	var pos: Vector3 = p["pos"]
	var color: Color = p["color"]
	var name: String = "Prop_%s" % String(p["name"])
	match String(p["kind"]):
		"box":
			var size: Vector3 = p["size"]
			if bool(p["collide"]):
				_box(root, with_visuals, name, size, pos, color, bool(p["occluder"]))
			elif with_visuals:
				_decal(root, name, size, pos, color)
		"cylinder":
			var radius: float = p["radius"]
			var height: float = p["height"]
			var body: StaticBody3D = _body(root, name, pos, bool(p["occluder"]))
			_collision(body, _cyl_shape(radius, height), Vector3.ZERO)
			if with_visuals:
				_mesh(body, "Mesh", _cyl_mesh(radius, height), color, Vector3.ZERO)
		"tree":
			var body2: StaticBody3D = _body(root, name, pos, bool(p["occluder"]))
			_collision(body2, _cyl_shape(0.45, 3.0), Vector3(0.0, 1.5, 0.0))
			if with_visuals:
				_mesh(body2, "Mesh", _cyl_mesh(0.35, 2.4), Color(0.4, 0.28, 0.16), Vector3(0.0, 1.2, 0.0))
				var sph: SphereMesh = SphereMesh.new()
				sph.radius = 1.9
				sph.height = 3.4
				_mesh(body2, "Canopy", sph, Color(0.2, 0.45, 0.2), Vector3(0.0, 3.3, 0.0))


static func _add_portal_visual(root: Node3D, portal: Dictionary) -> void:
	var pos: Vector3 = portal["pos"]
	var r: float = portal["radius"]
	var holder: Node3D = Node3D.new()
	holder.name = "Portal_%s" % String(portal["id"])
	holder.position = pos
	root.add_child(holder)
	var ring: MeshInstance3D = MeshInstance3D.new()
	ring.name = "Ring"
	ring.mesh = _cyl_mesh(r, 0.12)
	ring.position = Vector3(0.0, 0.06, 0.0)
	ring.material_override = _emissive(Color(0.3, 0.8, 1.0))
	holder.add_child(ring)
	for sx: float in [-1.0, 1.0]:
		var post: MeshInstance3D = MeshInstance3D.new()
		post.name = "Post"
		post.mesh = _cyl_mesh(0.3, 3.2)
		post.position = Vector3(0.0, 1.6, sx * r)
		post.material_override = _plain(Color(0.55, 0.55, 0.62))
		holder.add_child(post)
	if not String(portal["label"]).is_empty():
		var label: Label3D = Label3D.new()
		label.name = "Label"
		label.text = String(portal["label"])
		label.position = Vector3(0.0, 3.8, 0.0)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.pixel_size = 0.012
		holder.add_child(label)


static func _add_puzzle(root: Node3D, with_visuals: bool, puzzle: Dictionary) -> void:
	var plates: Array = puzzle["plates"]
	if with_visuals:
		for i: int in plates.size():
			var pl: Dictionary = plates[i]
			var m: MeshInstance3D = MeshInstance3D.new()
			m.name = "Plate_%d" % i
			m.mesh = _cyl_mesh(float(pl["radius"]), 0.1)
			m.position = (pl["pos"] as Vector3) + Vector3(0.0, 0.05, 0.0)
			m.material_override = _plain(PLATE_OFF)
			root.add_child(m)
	var gate: StaticBody3D = _box(root, with_visuals, "PuzzleGate", puzzle["gate_size"], puzzle["gate_pos"], GATE_COLOR, true)
	gate.set_meta(GATE_META, gate.collision_layer)


static func _add_npc_marker(root: Node3D, npc: Dictionary) -> void:
	var holder: Node3D = Node3D.new()
	holder.name = "Npc_%s" % String(npc["id"])
	holder.position = npc["position"]
	root.add_child(holder)
	var body: MeshInstance3D = MeshInstance3D.new()
	body.name = "Body"
	var cap: CapsuleMesh = CapsuleMesh.new()
	cap.radius = 0.4
	cap.height = 1.8
	body.mesh = cap
	body.position = Vector3(0.0, 0.9, 0.0)
	body.material_override = _plain(Color(0.95, 0.8, 0.3))
	holder.add_child(body)
	var label: Label3D = Label3D.new()
	label.name = "Label"
	label.text = String(npc["display_name"])
	label.position = Vector3(0.0, 2.4, 0.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.pixel_size = 0.01
	holder.add_child(label)


# ------------------------------------------------------------------ primitivas

static func _body(parent: Node3D, node_name: String, pos: Vector3, occluder: bool) -> StaticBody3D:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = node_name
	body.position = pos
	if occluder:
		body.add_to_group(OCCLUDER_GROUP)
	parent.add_child(body)
	return body


static func _box(parent: Node3D, with_visuals: bool, node_name: String, size: Vector3, pos: Vector3, color: Color, occluder: bool) -> StaticBody3D:
	var body: StaticBody3D = _body(parent, node_name, pos, occluder)
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = size
	_collision(body, shape, Vector3.ZERO)
	if with_visuals:
		var bm: BoxMesh = BoxMesh.new()
		bm.size = size
		_mesh(body, "Mesh", bm, color, Vector3.ZERO)
	return body


## Marca de chao sem colisao (trilhas, praca): so malha, nunca no grupo occluder.
static func _decal(parent: Node3D, node_name: String, size: Vector3, pos: Vector3, color: Color) -> void:
	var m: MeshInstance3D = MeshInstance3D.new()
	m.name = node_name
	var bm: BoxMesh = BoxMesh.new()
	bm.size = size
	m.mesh = bm
	m.position = pos
	m.material_override = _plain(color)
	parent.add_child(m)


static func _collision(body: StaticBody3D, shape: Shape3D, offset: Vector3) -> void:
	var col: CollisionShape3D = CollisionShape3D.new()
	col.name = "Collision"
	col.shape = shape
	col.position = offset
	body.add_child(col)


static func _mesh(body: Node3D, node_name: String, mesh: Mesh, color: Color, offset: Vector3) -> void:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.position = offset
	mi.material_override = _plain(color)
	body.add_child(mi)


static func _cyl_shape(radius: float, height: float) -> CylinderShape3D:
	var s: CylinderShape3D = CylinderShape3D.new()
	s.radius = radius
	s.height = height
	return s


static func _cyl_mesh(radius: float, height: float) -> CylinderMesh:
	var m: CylinderMesh = CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius
	m.height = height
	return m


static func _plain(color: Color) -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	return mat


static func _emissive(color: Color) -> StandardMaterial3D:
	var mat: StandardMaterial3D = _plain(color)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.9
	return mat
