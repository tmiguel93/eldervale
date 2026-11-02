class_name SceneryBuilder
extends RefCounted
## E8.2: monta o cenario 3D de uma zona SOMENTE NO CLIENTE, por cima do que o WorldBuilder ja criou (colisao e nomes intactos).
## - "skins": troca as malhas primitivas dos props de gameplay (casa, poco, bancada, arvore, pilar...) por modelos CC0; o corpo
##   (StaticBody3D + colisao) nunca e tocado. O filho visual continua chamado "Mesh" (o portao do puzzle liga/desliga por ele).
## - decoracao: SceneryPlan -> MultiMeshInstance3D por (asset, celula de 40 m); pecas fixas (tochas, fogueiras) viram
##   instancias com OmniLight3D + chama procedural.
## - chao: ShaderMaterial procedural no piso, decais de caminho e anel externo; muralhas primitivas somem (o perimetro e baixo
##   perto da camera e alto so atras, ver SceneryPlan), entao nada oclui o jogador.
## Em headless/bot/teste (ModelRig.models_enabled() == false) NADA aqui roda: o fallback de primitivas segue intacto.

const GROUND_SHADER: Shader = preload("res://scripts/scenery/ground.gdshader")
const PATH_SHADER: Shader = preload("res://scripts/scenery/path.gdshader")
const FLAME_SHADER: Shader = preload("res://scripts/scenery/flame.gdshader")

const DECOR_NAME: String = "Scenery"
const LIGHT_GROUP: StringName = &"scenery_light"
const OCCLUDER_GROUP: StringName = &"occluder"
const CELL_SIZE: float = 40.0
const WALL_NAMES: PackedStringArray = ["WallN", "WallS", "WallE", "WallW"]

## Cache por caminho: {ok, parts:[{mesh, xf}], aabb}. `extract_count` = quantos GLB foram abertos para extrair malhas.
static var _info: Dictionary = {}
static var extract_count: int = 0


static func enabled() -> bool:
	return ModelRig.models_enabled()


static func clear_cache() -> void:
	_info = {}
	extract_count = 0


# ------------------------------------------------------------------ assets (cache de malhas)

## Malhas estaticas do modelo (sem malhas skinned/escondidas), com a transformacao relativa a raiz e o AABB unido.
static func asset_info(path: String) -> Dictionary:
	if _info.has(path):
		return _info[path] as Dictionary
	var info: Dictionary = {"ok": false, "parts": [], "aabb": AABB()}
	var ps: PackedScene = ModelRig.load_scene(path)
	if ps != null:
		var inst: Node = ps.instantiate()
		var parts: Array = []
		_collect_parts(inst, Transform3D.IDENTITY, parts)
		inst.free()
		extract_count += 1
		if not parts.is_empty():
			var box: AABB = AABB()
			var first: bool = true
			for part: Dictionary in parts:
				var bb: AABB = (part["xf"] as Transform3D) * (part["mesh"] as Mesh).get_aabb()
				box = bb if first else box.merge(bb)
				first = false
			info = {"ok": true, "parts": parts, "aabb": box}
	_info[path] = info
	return info


static func _collect_parts(node: Node, parent_xf: Transform3D, out: Array) -> void:
	var xf: Transform3D = parent_xf
	var n3: Node3D = node as Node3D
	if n3 != null:
		if not n3.visible:
			return
		xf = parent_xf * n3.transform
	var mi: MeshInstance3D = node as MeshInstance3D
	if mi != null and mi.mesh != null and mi.skin == null:
		out.append({"mesh": mi.mesh, "xf": xf})
	for c: Node in node.get_children():
		_collect_parts(c, xf, out)


## Transformacao que coloca o modelo com a BASE (min y) em `pos.y`, centrado em XZ, escala `scale` e giro `yaw` (rad).
static func placement_xf(info: Dictionary, pos: Vector3, yaw: float, scale: Vector3) -> Transform3D:
	var bb: AABB = info["aabb"]
	var c: Vector3 = bb.get_center()
	var local: Transform3D = Transform3D(Basis.from_scale(scale), Vector3(-c.x * scale.x, -bb.position.y * scale.y, -c.z * scale.z))
	return Transform3D(Basis(Vector3.UP, yaw), pos) * local


static func uniform_scale_for_height(info: Dictionary, height: float) -> float:
	var h: float = (info["aabb"] as AABB).size.y
	return height / h if h > 0.001 else 1.0


## Instancia visual (um MeshInstance3D por superficie-malha) sob um Node3D posicionado por `xf`.
static func make_node(info: Dictionary, xf: Transform3D, shadow: bool, node_name: String = "Model") -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = node_name
	root.transform = xf
	for part: Dictionary in info["parts"]:
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.mesh = part["mesh"] as Mesh
		mi.transform = part["xf"] as Transform3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	return root


# ------------------------------------------------------------------ entrada principal

## Decora `zone_root` (criado pelo WorldBuilder com visuais). Devolve {root, lights, stats} ou {} se a zona nao tem tema / modelos
## desligados. `quality` = QualitySettings.Preset.
static func decorate(zone_root: Node3D, zone: ZoneDef, quality: int, npcs: NpcDirectory = null) -> Dictionary:
	var theme: Dictionary = SceneryTheme.for_zone(zone.id)
	if theme.is_empty() or zone_root == null or not enabled():
		return {}
	var q: Dictionary = QualitySettings.data(quality)
	var decor: Node3D = Node3D.new()
	decor.name = DECOR_NAME
	zone_root.add_child(decor)
	var stats: Dictionary = {"skins": 0, "multimeshes": 0, "instances": 0, "features": 0, "lights": 0, "missing": 0}
	var lights: Array[OmniLight3D] = []
	_style_ground(zone_root, zone, theme, decor)
	if bool(theme.get("hide_walls", false)):
		_hide_walls(zone_root)
	_skin_props(zone_root, zone, theme, stats)
	_skin_portals(zone_root, zone, theme, lights, stats)
	var plan: Array[Dictionary] = SceneryPlan.build(zone, theme, float(q["decor_density"]), npcs)
	_build_decor(decor, plan, float(q["view_distance"]), lights, stats)
	for l: OmniLight3D in lights:
		l.add_to_group(LIGHT_GROUP)
	stats["lights"] = lights.size()
	return {"root": decor, "lights": lights, "stats": stats, "plan_size": plan.size()}


# ------------------------------------------------------------------ chao

static func _ground_material(style: Dictionary, scale: float, soft: float = 0.0, half: Vector2 = Vector2.ONE, paths: bool = false) -> ShaderMaterial:
	var m: ShaderMaterial = ShaderMaterial.new()
	m.shader = PATH_SHADER if paths else GROUND_SHADER
	m.set_shader_parameter("color_a", style["a"])
	m.set_shader_parameter("color_b", style["b"])
	m.set_shader_parameter("color_c", style["c"])
	m.set_shader_parameter("patch_amount", float(style.get("patch", 0.45)))
	m.set_shader_parameter("noise_scale", float(style.get("scale", scale)))
	m.set_shader_parameter("tile_size", float(style.get("tile", 0.0)))
	if style.has("grout"):
		m.set_shader_parameter("grout", style["grout"])
	if paths:
		m.set_shader_parameter("soft", soft)
		m.set_shader_parameter("half_size", half)
	return m


static func _style_ground(zone_root: Node3D, zone: ZoneDef, theme: Dictionary, decor: Node3D) -> void:
	var ground: Dictionary = theme["ground"]
	var floor_mesh: MeshInstance3D = zone_root.get_node_or_null("Floor/Mesh") as MeshInstance3D
	if floor_mesh != null:
		floor_mesh.material_override = _ground_material(ground, 0.16)
	# anel externo: plano largo logo abaixo do piso (a floresta/ruinas de fundo ficam sobre ele)
	var outer: Dictionary = theme.get("outer", ground)
	var margin: float = float(outer.get("margin", 40.0)) + 24.0
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(zone.size.x + margin * 2.0, zone.size.y + margin * 2.0)
	var og: MeshInstance3D = MeshInstance3D.new()
	og.name = "OuterGround"
	og.mesh = plane
	og.position = Vector3(zone.center.x, -0.04, zone.center.z)
	og.material_override = _ground_material(outer, 0.1)
	og.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	decor.add_child(og)
	# decais de caminho/praca/piso (props sem colisao nomeados no tema)
	var styles: Dictionary = theme.get("path_styles", {})
	var order: int = 0
	for p: Dictionary in zone.props:
		if String(p["kind"]) != "box" or bool(p["collide"]) or not styles.has(String(p["name"])):
			continue
		var node: MeshInstance3D = zone_root.get_node_or_null("Prop_%s" % String(p["name"])) as MeshInstance3D
		if node == null:
			continue
		var st: Dictionary = styles[String(p["name"])]
		var s: Vector3 = p["size"]
		node.material_override = _ground_material(st, 0.3, float(st.get("soft", 0.0)), Vector2(s.x * 0.5, s.z * 0.5), true)
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# decais que se sobrepoem (praca x estrada) brigavam por profundidade: cada um sobe 1,2 cm em relacao ao anterior
		node.position.y += 0.012 * float(order)
		order += 1
	_style_stations(zone_root, zone)


## Marcador de bancada/crafting: o disco ambar opaco do E5.4 vira um halo translucido (so cosmetico; sem colisao).
static func _style_stations(zone_root: Node3D, zone: ZoneDef) -> void:
	for st: Dictionary in zone.stations:
		var ring: MeshInstance3D = zone_root.get_node_or_null("Station_%s/Ring" % String(st["id"])) as MeshInstance3D
		if ring == null:
			continue
		var m: StandardMaterial3D = StandardMaterial3D.new()
		m.albedo_color = Color(1.0, 0.72, 0.28, 0.16)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		ring.material_override = m
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


static func _hide_walls(zone_root: Node3D) -> void:
	for wn: String in WALL_NAMES:
		var wall: Node = zone_root.get_node_or_null(wn)
		if wall == null:
			continue
		var m: Node = wall.get_node_or_null("Mesh")
		if m != null:
			wall.remove_child(m)
			m.free()
		wall.remove_from_group(OCCLUDER_GROUP)


# ------------------------------------------------------------------ skins dos props de gameplay

static func skin_spec_for(skins: Dictionary, prop_name: String) -> Dictionary:
	if skins.has(prop_name):
		return skins[prop_name] as Dictionary
	var base: String = prop_name
	while base.length() > 0 and base[base.length() - 1] >= "0" and base[base.length() - 1] <= "9":
		base = base.substr(0, base.length() - 1)
	return (skins[base] as Dictionary) if skins.has(base) else {}


static func _skin_props(zone_root: Node3D, zone: ZoneDef, theme: Dictionary, stats: Dictionary) -> void:
	var skins: Dictionary = theme.get("skins", {})
	var tree_skin: Dictionary = theme.get("tree_skin", {})
	var tree_i: int = 0
	for p: Dictionary in zone.props:
		var body: StaticBody3D = zone_root.get_node_or_null("Prop_%s" % String(p["name"])) as StaticBody3D
		if body == null:
			continue
		var kind: String = String(p["kind"])
		if kind == "tree":
			if not tree_skin.is_empty():
				var arr: Array = tree_skin["assets"]
				var hr: Array = tree_skin["height"]
				var rr: RandomNumberGenerator = SceneryPlan._rng(zone.id, "tree:" + String(p["name"]))
				var spec: Dictionary = {"asset": String(arr[rr.randi() % arr.size()]), "fit": "tree", "height": rr.randf_range(float(hr[0]), float(hr[1])), "yaw": rr.randf() * 360.0}
				if _skin_body(body, p, spec):
					stats["skins"] = int(stats["skins"]) + 1
				else:
					stats["missing"] = int(stats["missing"]) + 1
			tree_i += 1
			continue
		var s: Dictionary = skin_spec_for(skins, String(p["name"]))
		if s.is_empty() or bool(p["collide"]) == false:
			continue
		if _skin_body(body, p, s):
			stats["skins"] = int(stats["skins"]) + 1
		else:
			stats["missing"] = int(stats["missing"]) + 1
	# portao do puzzle (no `PuzzleGate`, fora de zone.props)
	if not zone.puzzle.is_empty() and skins.has("PuzzleGate"):
		var gate: StaticBody3D = zone_root.get_node_or_null("PuzzleGate") as StaticBody3D
		if gate != null:
			var gp: Dictionary = {"kind": "box", "size": zone.puzzle["gate_size"], "name": "PuzzleGate"}
			if _skin_body(gate, gp, skins["PuzzleGate"] as Dictionary):
				stats["skins"] = int(stats["skins"]) + 1


## Troca o visual primitivo de `body` pelo modelo de `spec`. false se o asset nao existe (o visual primitivo fica).
static func _skin_body(body: StaticBody3D, prop: Dictionary, spec: Dictionary) -> bool:
	var kind: String = String(prop["kind"])
	var size: Vector3 = Vector3.ONE
	var bottom: float = 0.0
	match kind:
		"box":
			size = prop["size"]
			bottom = -size.y * 0.5
		"cylinder":
			size = Vector3(float(prop["radius"]) * 2.0, float(prop["height"]), float(prop["radius"]) * 2.0)
			bottom = -size.y * 0.5
		_:
			size = Vector3(1.0, float(spec.get("height", 6.0)), 1.0)
	var info: Dictionary = asset_info(String(spec["asset"]))
	if not bool(info["ok"]):
		return false
	var yaw_deg: float = float(spec.get("yaw", 0.0))
	var yaw: float = deg_to_rad(yaw_deg)
	var swapped: bool = is_equal_approx(fposmod(yaw_deg, 180.0), 90.0)
	var bb: AABB = info["aabb"]
	var holder: Node3D = Node3D.new()
	holder.name = "SkinHolder"
	holder.position = Vector3(0.0, bottom, 0.0)
	var shadow: bool = true
	match String(spec.get("fit", "stretch")):
		"tree":
			var s_t: float = uniform_scale_for_height(info, float(spec["height"]))
			holder.add_child(make_node(info, placement_xf(info, Vector3.ZERO, yaw, Vector3.ONE * s_t), shadow))
		"footprint":
			var ex: float = bb.size.z if swapped else bb.size.x
			var ez: float = bb.size.x if swapped else bb.size.z
			var fill: float = float(spec.get("fill", 0.95))
			var s_f: float = minf(size.x * fill / maxf(ex, 0.01), size.z * fill / maxf(ez, 0.01))
			if spec.has("max_h"):
				s_f = minf(s_f, float(spec["max_h"]) * size.y / maxf(bb.size.y, 0.01))
			holder.add_child(make_node(info, placement_xf(info, Vector3.ZERO, yaw, Vector3.ONE * s_f), shadow))
		"width":
			var s_w: float = float(spec["width"]) / maxf(maxf(bb.size.x, bb.size.z), 0.01)
			holder.add_child(make_node(info, placement_xf(info, Vector3.ZERO, yaw, Vector3.ONE * s_w), shadow))
		"wall_run":
			# trecho de muro: pecas de ~4 m lado a lado ao longo do eixo longo do prop (eixo local x do modelo -> comprimento)
			var length: float = size.z if swapped else size.x
			var thick: float = size.x if swapped else size.z
			var pieces: Array = spec["pieces"]
			var n: int = maxi(1, int(round(length / 4.0)))
			var piece_len: float = length / float(n)
			var any: bool = false
			for i: int in n:
				var pinfo: Dictionary = asset_info(String(pieces[i % pieces.size()]))
				if not bool(pinfo["ok"]):
					continue
				any = true
				var pb: AABB = pinfo["aabb"]
				var sc: Vector3 = Vector3(piece_len / maxf(pb.size.x, 0.01), size.y / maxf(pb.size.y, 0.01), thick / maxf(pb.size.z, 0.01))
				var along: float = -length * 0.5 + (float(i) + 0.5) * piece_len
				var pos: Vector3 = Vector3(0.0, 0.0, along) if swapped else Vector3(along, 0.0, 0.0)
				holder.add_child(make_node(pinfo, placement_xf(pinfo, pos, yaw, sc), shadow))
			if not any:
				holder.free()
				return false
		_:
			var tx: float = size.z if swapped else size.x
			var tz: float = size.x if swapped else size.z
			var sc2: Vector3 = Vector3(tx / maxf(bb.size.x, 0.01), size.y / maxf(bb.size.y, 0.01), tz / maxf(bb.size.z, 0.01))
			holder.add_child(make_node(info, placement_xf(info, Vector3.ZERO, yaw, sc2), shadow))
	# remove o visual primitivo e instala o modelo com o nome "Mesh" (WorldBuilder.set_gate_open usa esse nome)
	for old: String in ["Mesh", "Canopy"]:
		var n: Node = body.get_node_or_null(old)
		if n != null:
			body.remove_child(n)
			n.free()
	holder.name = "Mesh"
	body.add_child(holder)
	return true


## Portais: troca os dois postes cilindricos por pilares de pedra e acende um brilho no anel.
static func _skin_portals(zone_root: Node3D, zone: ZoneDef, theme: Dictionary, lights: Array[OmniLight3D], stats: Dictionary) -> void:
	var pt: Dictionary = theme.get("portal", {})
	if pt.is_empty():
		return
	var info: Dictionary = asset_info(String(pt["post_asset"]))
	for portal: Dictionary in zone.portals:
		var holder: Node3D = zone_root.get_node_or_null("Portal_%s" % String(portal["id"])) as Node3D
		if holder == null:
			continue
		if bool(info["ok"]):
			var posts: Array[Node] = []
			for c: Node in holder.get_children():
				if c.name.begins_with("Post"):
					posts.append(c)
			for c2: Node in posts:
				var pos: Vector3 = (c2 as Node3D).position
				holder.remove_child(c2)
				c2.free()
				var s: float = uniform_scale_for_height(info, float(pt["post_height"]))
				holder.add_child(make_node(info, placement_xf(info, Vector3(pos.x, 0.0, pos.z), 0.0, Vector3.ONE * s), true, "PostModel"))
		var ring: MeshInstance3D = holder.get_node_or_null("Ring") as MeshInstance3D
		if ring != null:
			# disco opaco do E5.3 -> energia translucida (so cosmetico; sem colisao)
			var rm: StandardMaterial3D = StandardMaterial3D.new()
			rm.albedo_color = Color((pt["light"] as Color).r, (pt["light"] as Color).g, (pt["light"] as Color).b, 0.32)
			rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			rm.emission_enabled = true
			rm.emission = pt["light"] as Color
			rm.emission_energy_multiplier = 1.6
			rm.cull_mode = BaseMaterial3D.CULL_DISABLED
			ring.material_override = rm
			ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var l: OmniLight3D = OmniLight3D.new()
		l.name = "PortalGlow"
		l.light_color = pt["light"] as Color
		l.light_energy = float(pt["light_energy"])
		l.omni_range = float(pt["light_range"])
		l.omni_attenuation = 1.3
		l.position = Vector3(0.0, 1.4, 0.0)
		l.set_meta("base_energy", l.light_energy)
		l.set_meta("flicker", 0.05)
		l.set_meta("phase", float(stats["skins"]))
		holder.add_child(l)
		lights.append(l)


# ------------------------------------------------------------------ decoracao (MultiMesh) e pecas fixas

static func _build_decor(decor: Node3D, plan: Array[Dictionary], view_distance: float, lights: Array[OmniLight3D], stats: Dictionary) -> void:
	var groups: Dictionary = {}   # chave -> {asset, shadow, cell, items:[Transform3D]}
	var features: Node3D = Node3D.new()
	features.name = "Features"
	decor.add_child(features)
	for p: Dictionary in plan:
		var info: Dictionary = asset_info(String(p["asset"]))
		if not bool(info["ok"]):
			stats["missing"] = int(stats["missing"]) + 1
			continue
		var pos: Vector3 = p["pos"]
		var s: float = uniform_scale_for_height(info, float(p["height"]))
		if String(p["kind"]) == "feature":
			_add_feature(features, info, p, s, lights)
			stats["features"] = int(stats["features"]) + 1
			continue
		var xf: Transform3D = placement_xf(info, pos, float(p["yaw"]), Vector3.ONE * s)
		var cell: Vector2i = Vector2i(int(floor(pos.x / CELL_SIZE)), int(floor(pos.z / CELL_SIZE)))
		var key: String = "%s|%d|%d|%d" % [String(p["asset"]), cell.x, cell.y, 1 if bool(p["shadow"]) else 0]
		if not groups.has(key):
			groups[key] = {"asset": String(p["asset"]), "shadow": bool(p["shadow"]), "cell": cell, "items": []}
		(groups[key] as Dictionary)["items"].append(xf)
	var keys: Array = groups.keys()
	keys.sort()
	for key: Variant in keys:
		var g: Dictionary = groups[key]
		var info2: Dictionary = asset_info(String(g["asset"]))
		var items: Array = g["items"]
		var part_i: int = 0
		for part: Dictionary in info2["parts"]:
			var mm: MultiMesh = MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = part["mesh"] as Mesh
			mm.instance_count = items.size()
			for i: int in items.size():
				mm.set_instance_transform(i, (items[i] as Transform3D) * (part["xf"] as Transform3D))
			var mmi: MultiMeshInstance3D = MultiMeshInstance3D.new()
			mmi.name = "MM_%s_%d_%d_%d" % [String(g["asset"]).get_file().get_basename(), (g["cell"] as Vector2i).x, (g["cell"] as Vector2i).y, part_i]
			mmi.multimesh = mm
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if bool(g["shadow"]) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if view_distance > 0.0:
				mmi.visibility_range_end = view_distance
			decor.add_child(mmi)
			stats["multimeshes"] = int(stats["multimeshes"]) + 1
			stats["instances"] = int(stats["instances"]) + items.size()
			part_i += 1


static func _add_feature(parent: Node3D, info: Dictionary, p: Dictionary, s: float, lights: Array[OmniLight3D]) -> void:
	var pos: Vector3 = p["pos"]
	var elev: float = float(p.get("elev", 0.0))
	var base: Vector3 = Vector3(pos.x, pos.y + elev, pos.z)
	var node: Node3D = make_node(info, placement_xf(info, base, float(p["yaw"]), Vector3.ONE * s), bool(p["shadow"]), "F_%s" % String(p["rule"]))
	parent.add_child(node)
	var lt: Dictionary = p.get("light", {})
	if lt.is_empty():
		return
	var top: Vector3 = Vector3(base.x, base.y + float(lt["flame_y"]), base.z)
	var l: OmniLight3D = OmniLight3D.new()
	l.name = "L_%s" % String(p["rule"])
	l.light_color = lt["color"] as Color
	l.light_energy = float(lt["energy"])
	l.omni_range = float(lt["range"])
	l.omni_attenuation = 1.25
	l.shadow_enabled = false
	l.position = top
	var phase: float = float(SceneryPlan.fnv1a(String(p["rule"])) % 628) / 100.0
	l.set_meta("base_energy", l.light_energy)
	l.set_meta("flicker", float(lt.get("flicker", 0.2)))
	l.set_meta("phase", phase)
	parent.add_child(l)
	lights.append(l)
	var flame: MeshInstance3D = _flame(lt, phase)
	flame.position = top
	parent.add_child(flame)
	l.set_meta("flame", flame)


static func _flame(lt: Dictionary, phase: float) -> MeshInstance3D:
	var q: QuadMesh = QuadMesh.new()
	var size: float = float(lt.get("flame_size", 1.0))
	q.size = Vector2(size * 0.55, size * 0.85)
	q.center_offset = Vector3(0.0, size * 0.28, 0.0)
	var m: ShaderMaterial = ShaderMaterial.new()
	m.shader = FLAME_SHADER
	m.set_shader_parameter("flame_color", lt["color"])
	m.set_shader_parameter("phase", phase)
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = "Flame"
	mi.mesh = q
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
