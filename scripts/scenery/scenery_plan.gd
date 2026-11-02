class_name SceneryPlan
extends RefCounted
## E8.2: espalhamento DETERMINISTICO do cenario de uma zona. Puro: nao carrega arte, nao cria nos, nao toca fisica, nao usa
## aleatoriedade global (RandomNumberGenerator com seed = FNV-1a de "zona|regra"). Mesma zona + mesma densidade = mesma lista.
## A densidade so FILTRA por `rank` (sorteado sempre): Baixa e subconjunto de Media, que e subconjunto de Alta.
## Cada colocacao: {rule, kind(scatter|perimeter|feature), asset, pos:Vector3, yaw:float(rad), height:float(m), cls(flat|low|tall),
##   shadow:bool, rank:float [0,1), elev:float, light:Dictionary(so feature)}.
## Regras de seguranca visual: nada ALTO e colocado onde ocluiria o jogador na camera isometrica (casts_view_shadow_on), e o
## miolo da zona so recebe cobertura baixa (a decoracao nao tem colisao; props de gameplay continuam sendo os do JSON).

const CAM_YAW_DEG: float = 45.0     ## = IsoCamera.yaw_deg (testado)
const CAM_PITCH_DEG: float = 50.0   ## = IsoCamera.pitch_deg (testado)
const MAX_TRIES_PER_ITEM: int = 14
const WALL_HALF: float = 0.5        ## WorldBuilder.WALL_THICKNESS / 2


# ------------------------------------------------------------------ seed

## FNV-1a 32 bits (estavel entre plataformas/versoes, ao contrario de String.hash()).
static func fnv1a(text: String) -> int:
	var h: int = 2166136261
	for b: int in text.to_utf8_buffer():
		h = ((h ^ b) * 16777619) & 0xFFFFFFFF
	return h


static func seed_for(zone_id: String, salt: String = "") -> int:
	return fnv1a("%s|%s" % [zone_id, salt])


static func _rng(zone_id: String, salt: String) -> RandomNumberGenerator:
	var r: RandomNumberGenerator = RandomNumberGenerator.new()
	r.seed = seed_for(zone_id, salt)
	return r


# ------------------------------------------------------------------ API

## Lista completa de colocacoes da zona na densidade dada (0..1). `npcs` (opcional) so serve para evitar os NPCs.
static func build(zone: ZoneDef, theme: Dictionary, density: float = 1.0, npcs: NpcDirectory = null) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if zone == null or theme.is_empty():
		return out
	var dens: float = clampf(density, 0.0, 1.0)
	var rect: Rect2 = zone_rect(zone)
	var ex: Dictionary = exclusions(zone, theme, npcs)
	for rule: Dictionary in theme.get("perimeter", []):
		out.append_array(_perimeter(zone, rect, rule))
	for rule: Dictionary in theme.get("scatter", []):
		for p: Dictionary in _scatter(zone, rect, theme, rule, ex):
			if float(p["rank"]) < dens:
				out.append(p)
	for f: Dictionary in theme.get("features", []):
		out.append({"rule": String(f["id"]), "kind": "feature", "asset": String(f["asset"]), "pos": f["pos"] as Vector3,
			"yaw": deg_to_rad(float(f.get("yaw", 0.0))), "height": float(f["height"]), "cls": "low", "shadow": bool(f.get("shadow", false)),
			"rank": 0.0, "elev": float(f.get("elev", 0.0)), "light": (f.get("light", {}) as Dictionary)})
	return out


## Resumo numerico para testes de determinismo (ordem e valores).
static func digest(list: Array[Dictionary]) -> int:
	var h: int = 2166136261
	for p: Dictionary in list:
		var v: Vector3 = p["pos"]
		var s: String = "%s|%s|%.3f|%.3f|%.3f|%.3f|%.3f" % [p["rule"], String(p["asset"]).get_file(), v.x, v.z, float(p["yaw"]), float(p["height"]), float(p["rank"])]
		h = ((h ^ fnv1a(s)) * 16777619) & 0xFFFFFFFF
	return h


static func zone_rect(zone: ZoneDef) -> Rect2:
	return Rect2(zone.center.x - zone.size.x * 0.5, zone.center.z - zone.size.y * 0.5, zone.size.x, zone.size.y)


## True se um objeto de `height` m em `pos` (plano XZ) esconderia, para a camera isometrica, algum ponto de `rect`.
## A sombra visual do objeto vai da base para o lado OPOSTO a camera, com comprimento height / tan(pitch) (+ raio).
static func casts_view_shadow_on(rect: Rect2, pos: Vector2, height: float, radius: float) -> bool:
	var yaw: float = deg_to_rad(CAM_YAW_DEG)
	var c: Vector2 = Vector2(sin(yaw), cos(yaw))        # do alvo para a camera (XZ)
	var side: Vector2 = Vector2(-c.y, c.x)
	var length: float = height / tan(deg_to_rad(CAM_PITCH_DEG)) + radius
	var t: float = 0.0
	while t <= length:
		for lat: float in [-radius * 0.7, 0.0, radius * 0.7]:
			if rect.has_point(pos - c * t + side * lat):
				return true
		t += 0.75
	return false


# ------------------------------------------------------------------ exclusoes

## {circles: Array[Vector3(x, z, r)], rects: Array[Rect2] (props que colidem), paths: Array[Rect2] (decais sem colisao)}.
static func exclusions(zone: ZoneDef, theme: Dictionary, npcs: NpcDirectory = null) -> Dictionary:
	var circles: Array[Vector3] = []
	var rects: Array[Rect2] = []
	var paths: Array[Rect2] = []
	for p: Dictionary in zone.props:
		var pos: Vector3 = p["pos"]
		match String(p["kind"]):
			"box":
				var s: Vector3 = p["size"]
				var r: Rect2 = Rect2(pos.x - s.x * 0.5, pos.z - s.z * 0.5, s.x, s.z)
				if bool(p["collide"]):
					rects.append(r.grow(0.8))
				else:
					paths.append(r)
			"cylinder":
				circles.append(Vector3(pos.x, pos.z, float(p["radius"]) + 0.9))
			"tree":
				circles.append(Vector3(pos.x, pos.z, 1.3))
	for portal: Dictionary in zone.portals:
		var pp: Vector3 = portal["pos"]
		circles.append(Vector3(pp.x, pp.z, float(portal["radius"]) + 1.8))
	for name: String in zone.spawns:
		for sp: Variant in zone.spawns[name]:
			circles.append(Vector3((sp as Vector3).x, (sp as Vector3).z, 2.2))
	for st: Dictionary in zone.stations:
		var sp2: Vector3 = st["pos"]
		circles.append(Vector3(sp2.x, sp2.z, float(st["radius"]) * 0.6))
	for e: Dictionary in zone.enemies:
		var ep: Vector3 = e["pos"]
		circles.append(Vector3(ep.x, ep.z, 1.6))
	if not zone.puzzle.is_empty():
		for pl: Dictionary in zone.puzzle["plates"]:
			var pv: Vector3 = pl["pos"]
			circles.append(Vector3(pv.x, pv.z, float(pl["radius"]) + 1.2))
		var gp: Vector3 = zone.puzzle["gate_pos"]
		var gs: Vector3 = zone.puzzle["gate_size"]
		rects.append(Rect2(gp.x - gs.x * 0.5, gp.z - gs.z * 0.5, gs.x, gs.z).grow(1.2))
	if not zone.encounter.is_empty():
		var bp: Vector3 = zone.encounter["spawn"]
		circles.append(Vector3(bp.x, bp.z, 3.5))
	if npcs != null:
		for nid: String in zone.npcs:
			if npcs.has_npc(nid):
				var np: Vector3 = npcs.get_npc(nid)["position"]
				circles.append(Vector3(np.x, np.z, 2.0))
	return {"circles": circles, "rects": rects, "paths": paths}


static func _blocked(p: Vector2, ex: Dictionary, include_paths: bool) -> bool:
	for c: Vector3 in ex["circles"]:
		if p.distance_squared_to(Vector2(c.x, c.y)) < c.z * c.z:
			return true
	for r: Rect2 in ex["rects"]:
		if r.has_point(p):
			return true
	if include_paths:
		for r2: Rect2 in ex["paths"]:
			if r2.grow(0.3).has_point(p):
				return true
	return false


# ------------------------------------------------------------------ grade de distancia minima

class SpatialGrid:
	extends RefCounted
	var cell: float
	var cells: Dictionary = {}

	func _init(p_cell: float) -> void:
		cell = maxf(p_cell, 0.1)

	func _key(p: Vector2) -> Vector2i:
		return Vector2i(int(floor(p.x / cell)), int(floor(p.y / cell)))

	func too_close(p: Vector2, min_dist: float) -> bool:
		var k: Vector2i = _key(p)
		var md2: float = min_dist * min_dist
		for dx: int in [-1, 0, 1]:
			for dz: int in [-1, 0, 1]:
				var arr: Variant = cells.get(Vector2i(k.x + dx, k.y + dz))
				if arr == null:
					continue
				for q: Vector2 in arr:
					if q.distance_squared_to(p) < md2:
						return true
		return false

	func add(p: Vector2) -> void:
		var k: Vector2i = _key(p)
		if not cells.has(k):
			cells[k] = []
		(cells[k] as Array).append(p)


# ------------------------------------------------------------------ perimetro (visual das muralhas da zona)

static func _perimeter(zone: ZoneDef, rect: Rect2, rule: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var rng: RandomNumberGenerator = _rng(zone.id, "perimeter:" + String(rule["id"]))
	var assets: Array = rule["assets"]
	var step: float = float(rule["step"])
	var inset: float = float(rule.get("inset", WALL_HALF))
	var jitter: float = float(rule.get("jitter", 0.0))
	var h_target: float = float(rule["height"])
	var cls: String = String(rule.get("cls", "low"))
	var x0: float = rect.position.x
	var x1: float = rect.end.x
	var z0: float = rect.position.y
	var z1: float = rect.end.y
	for side: String in rule["sides"]:
		var count: int = 0
		var len: float = (x1 - x0) if (side == "N" or side == "S") else (z1 - z0)
		count = int(floor(len / step))
		var start: float = ((x0 if (side == "N" or side == "S") else z0) + (len - float(count) * step) * 0.5) + step * 0.5
		for i: int in count:
			var along: float = start + float(i) * step
			var asset: String = String(assets[rng.randi() % assets.size()])
			var j: Vector2 = Vector2(rng.randf_range(-jitter, jitter), rng.randf_range(-jitter, jitter))
			var pos: Vector3
			var yaw: float
			match side:
				"N":
					pos = Vector3(along, 0.0, z0 + inset)
					yaw = 0.0
				"S":
					pos = Vector3(along, 0.0, z1 - inset)
					yaw = PI
				"W":
					pos = Vector3(x0 + inset, 0.0, along)
					yaw = PI * 0.5
				_:
					pos = Vector3(x1 - inset, 0.0, along)
					yaw = -PI * 0.5
			pos += Vector3(j.x, 0.0, j.y)
			if jitter > 0.0:
				yaw = rng.randf() * TAU
			var h: float = h_target * (rng.randf_range(0.85, 1.15) if jitter > 0.0 else 1.0)
			out.append({"rule": String(rule["id"]), "kind": "perimeter", "asset": asset, "pos": pos, "yaw": yaw, "height": h,
				"cls": cls, "shadow": bool(rule.get("shadow", true)), "rank": 0.0, "elev": 0.0, "side": side})
	return out


# ------------------------------------------------------------------ espalhamento

static func _scatter(zone: ZoneDef, rect: Rect2, theme: Dictionary, rule: Dictionary, ex: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var rng: RandomNumberGenerator = _rng(zone.id, "scatter:" + String(rule["id"]))
	var assets: Array = rule["assets"]
	var want: int = int(rule["count"])
	var region: String = String(rule.get("region", "inside"))
	var cls: String = String(rule.get("cls", "flat"))
	var hr: Array = rule["height"]
	var min_dist: float = float(rule.get("min_dist", 1.0))
	var grid: SpatialGrid = SpatialGrid.new(maxf(min_dist, 1.0))
	var outer: Dictionary = theme.get("outer", {})
	var margin: float = float(rule.get("outer_margin", float(outer.get("margin", 36.0))))
	var near: float = float(rule.get("outer_near", 1.0))
	var inset: float = float(rule.get("inset", 1.0))
	var face: bool = bool(rule.get("face_center", false))
	var center: Vector2 = rect.get_center()
	var paths: Array[Rect2] = ex["paths"] as Array[Rect2]
	var den: Dictionary = theme.get("den", {})
	var tries: int = want * MAX_TRIES_PER_ITEM
	while out.size() < want and tries > 0:
		tries -= 1
		var p: Vector2 = Vector2.ZERO
		var ok: bool = true
		match region:
			"outer":
				var big: Rect2 = rect.grow(margin)
				p = Vector2(rng.randf_range(big.position.x, big.end.x), rng.randf_range(big.position.y, big.end.y))
				if rect.grow(near).has_point(p):
					ok = false
			"path_edge":
				if paths.is_empty():
					return out
				var pr: Rect2 = paths[rng.randi() % paths.size()]
				var along: float = rng.randf()
				var off: float = rng.randf_range(0.15, 0.9)
				var long_x: bool = pr.size.x >= pr.size.y
				var sgn: float = -1.0 if rng.randf() < 0.5 else 1.0
				if long_x:
					p = Vector2(pr.position.x + along * pr.size.x, pr.get_center().y + sgn * (pr.size.y * 0.5 + off))
				else:
					p = Vector2(pr.get_center().x + sgn * (pr.size.x * 0.5 + off), pr.position.y + along * pr.size.y)
				if not rect.grow(-inset).has_point(p) or _blocked(p, ex, false) or _on_any_path(p, paths):
					ok = false
			"den":
				var dc: Vector2 = den.get("center", center) as Vector2
				var dr: float = float(den.get("radius", 8.0))
				var ang: float = rng.randf() * TAU
				p = dc + Vector2(cos(ang), sin(ang)) * dr * sqrt(rng.randf())
				if not rect.grow(-inset).has_point(p) or _blocked(p, ex, true):
					ok = false
			_:
				var inner: Rect2 = rect.grow(-inset)
				p = Vector2(rng.randf_range(inner.position.x, inner.end.x), rng.randf_range(inner.position.y, inner.end.y))
				if _blocked(p, ex, true):
					ok = false
		# sorteios sempre consumidos na mesma ordem, aceitando ou nao (estabilidade ao mudar regras vizinhas nao importa; ao mudar densidade nada muda)
		var asset: String = String(assets[rng.randi() % assets.size()])
		var h: float = rng.randf_range(float(hr[0]), float(hr[1]))
		var yaw: float = rng.randf() * TAU
		var rank: float = rng.randf()
		if not ok:
			continue
		if region == "outer" and cls != "flat" and casts_view_shadow_on(rect, p, h, h * 0.18):
			continue
		if grid.too_close(p, min_dist):
			continue
		if face:
			var d: Vector2 = center - p
			yaw = atan2(d.x, d.y)
		grid.add(p)
		out.append({"rule": String(rule["id"]), "kind": "scatter", "asset": asset, "pos": Vector3(p.x, 0.0, p.y), "yaw": yaw, "height": h,
			"cls": cls, "shadow": bool(rule.get("shadow", true)), "rank": rank, "elev": 0.0, "flat_tile": bool(rule.get("flat_tile", false))})
	return out


static func _on_any_path(p: Vector2, paths: Array[Rect2]) -> bool:
	for r: Rect2 in paths:
		if r.grow(0.1).has_point(p):
			return true
	return false
