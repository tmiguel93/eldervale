extends RefCounted
## Ajudantes dos testes do E8.2 (sem prefixo test_: o runner nao o executa).

static func zone(zid: String) -> ZoneDef:
	return WorldDef.shared().get_zone(zid)


## Assinatura fisica de uma zona: para cada corpo/colisor, camada, mascara, posicao global e forma.
static func physics_signature(root: Node) -> Array:
	var out: Array = []
	_walk(root, out)
	out.sort()
	return out


static func _walk(n: Node, out: Array) -> void:
	if n.name == "Scenery":
		return
	if n is CollisionObject3D:
		var co: CollisionObject3D = n as CollisionObject3D
		var shapes: Array = []
		for c: Node in co.get_children():
			if c is CollisionShape3D and (c as CollisionShape3D).shape != null:
				var cs: CollisionShape3D = c as CollisionShape3D
				shapes.append("%s@%s:%s" % [cs.shape.get_class(), str(cs.position), _shape_dims(cs.shape)])
		shapes.sort()
		out.append("%s|L%d|M%d|%s|%s" % [n.name, co.collision_layer, co.collision_mask, str((n as Node3D).position), str(shapes)])
	for c: Node in n.get_children():
		_walk(c, out)


static func _shape_dims(s: Shape3D) -> String:
	if s is BoxShape3D:
		return str((s as BoxShape3D).size)
	if s is CylinderShape3D:
		return "%s/%s" % [(s as CylinderShape3D).radius, (s as CylinderShape3D).height]
	return ""


static func count_collision_objects(n: Node) -> int:
	var c: int = 1 if n is CollisionObject3D else 0
	for ch: Node in n.get_children():
		c += count_collision_objects(ch)
	return c
