class_name VfxMeshes
extends RefCounted
## E8.3: malhas procedurais dos efeitos (cache estatico por chave: uma malha por forma, compartilhada entre instancias).

static var _cache: Dictionary = {}


static func clear() -> void:
	_cache = {}


## Setor de anulo plano (XZ) de raio unitario: UV.x ao longo do arco (a0 -> a1, rad; 0 = frente -Z), UV.y de dentro (0) a fora (1).
static func annulus(inner: float, a0: float, a1: float, segs: int = 40) -> ArrayMesh:
	var key: String = "ann:%.3f:%.3f:%.3f:%d" % [inner, a0, a1, segs]
	if _cache.has(key):
		return _cache[key] as ArrayMesh
	var verts: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var idx: PackedInt32Array = PackedInt32Array()
	for i: int in segs + 1:
		var t: float = float(i) / float(segs)
		var a: float = lerpf(a0, a1, t)
		var dir: Vector3 = Vector3(sin(a), 0.0, -cos(a))
		verts.append(dir * inner)
		uvs.append(Vector2(t, 0.0))
		verts.append(dir)
		uvs.append(Vector2(t, 1.0))
	for i: int in segs:
		var b: int = i * 2
		idx.append_array(PackedInt32Array([b, b + 1, b + 2, b + 1, b + 3, b + 2]))
	var m: ArrayMesh = _mesh(verts, uvs, idx)
	_cache[key] = m
	return m


## Quad plano no chao (XZ), lado `size`, UV 0..1 (UV.y = 0 em -Z).
static func ground_quad(size_x: float, size_z: float) -> ArrayMesh:
	var key: String = "gq:%.3f:%.3f" % [size_x, size_z]
	if _cache.has(key):
		return _cache[key] as ArrayMesh
	var hx: float = size_x * 0.5
	var hz: float = size_z * 0.5
	var verts: PackedVector3Array = PackedVector3Array([Vector3(-hx, 0, -hz), Vector3(hx, 0, -hz), Vector3(hx, 0, hz), Vector3(-hx, 0, hz)])
	var uvs: PackedVector2Array = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	var m: ArrayMesh = _mesh(verts, uvs, PackedInt32Array([0, 1, 2, 0, 2, 3]))
	_cache[key] = m
	return m


## Cilindro aberto de raio 1 e altura 1 (base em y=0). UV.x = volta, UV.y = base 0 -> topo 1.
static func open_cylinder(segs: int = 20) -> ArrayMesh:
	var key: String = "cyl:%d" % segs
	if _cache.has(key):
		return _cache[key] as ArrayMesh
	var verts: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var norms: PackedVector3Array = PackedVector3Array()
	var idx: PackedInt32Array = PackedInt32Array()
	for i: int in segs + 1:
		var t: float = float(i) / float(segs)
		var a: float = t * TAU
		var d: Vector3 = Vector3(cos(a), 0.0, sin(a))
		verts.append(d)
		uvs.append(Vector2(t, 0.0))
		norms.append(d)
		verts.append(d + Vector3.UP)
		uvs.append(Vector2(t, 1.0))
		norms.append(d)
	for i: int in segs:
		var b: int = i * 2
		idx.append_array(PackedInt32Array([b, b + 2, b + 1, b + 1, b + 2, b + 3]))
	var m: ArrayMesh = _mesh(verts, uvs, idx, norms)
	_cache[key] = m
	return m


## Faixa ao longo de -Z: largura em X (-w/2..w/2), cabeca em z=0 e cauda em z=+length. UV.x = largura, UV.y = 0 (cabeca) -> 1 (cauda).
static func streak(length: float, width: float) -> ArrayMesh:
	var key: String = "str:%.3f:%.3f" % [length, width]
	if _cache.has(key):
		return _cache[key] as ArrayMesh
	var hw: float = width * 0.5
	var verts: PackedVector3Array = PackedVector3Array([Vector3(-hw, 0, 0), Vector3(hw, 0, 0), Vector3(hw, 0, length), Vector3(-hw, 0, length)])
	var uvs: PackedVector2Array = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	var m: ArrayMesh = _mesh(verts, uvs, PackedInt32Array([0, 1, 2, 0, 2, 3]))
	_cache[key] = m
	return m


static func sphere(radius: float) -> SphereMesh:
	var key: String = "sph:%.3f" % radius
	if _cache.has(key):
		return _cache[key] as SphereMesh
	var s: SphereMesh = SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = 14
	s.rings = 8
	_cache[key] = s
	return s


static func billboard_quad(size: float) -> QuadMesh:
	var key: String = "bq:%.3f" % size
	if _cache.has(key):
		return _cache[key] as QuadMesh
	var q: QuadMesh = QuadMesh.new()
	q.size = Vector2(size, size)
	_cache[key] = q
	return q


static func _mesh(verts: PackedVector3Array, uvs: PackedVector2Array, idx: PackedInt32Array, norms: PackedVector3Array = PackedVector3Array()) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	if norms.is_empty():
		norms = PackedVector3Array()
		norms.resize(verts.size())
		norms.fill(Vector3.UP)
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = idx
	var m: ArrayMesh = ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	m.custom_aabb = AABB(Vector3(-30, -30, -30), Vector3(60, 60, 60))
	return m
