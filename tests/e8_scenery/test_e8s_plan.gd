extends RefCounted
## E8.2: SceneryPlan e deterministico por seed de zona, aninha por densidade, respeita exclusoes e e seguro para a camera.

const H = preload("res://tests/e8_scenery/e8s_helpers.gd")


func run(ctx: Variant) -> void:
	_fnv(ctx)
	_camera_constants(ctx)
	_determinism(ctx)
	_nesting(ctx)
	_safety(ctx)


func _fnv(ctx: Variant) -> void:
	ctx.check(SceneryPlan.fnv1a("") == 2166136261, "FNV-1a de vazio")
	ctx.check(SceneryPlan.fnv1a("a") == 3826002220, "FNV-1a de 'a' (vetor conhecido)")
	ctx.check(SceneryPlan.seed_for("zone_hub") != SceneryPlan.seed_for("zone_wild"), "seeds por zona diferem")
	ctx.check(SceneryPlan.seed_for("zone_hub", "a") != SceneryPlan.seed_for("zone_hub", "b"), "sal muda a seed")
	ctx.check(SceneryPlan.seed_for("zone_hub", "a") == SceneryPlan.seed_for("zone_hub", "a"), "seed estavel")


func _camera_constants(ctx: Variant) -> void:
	var cam: IsoCamera = (load("res://scenes/camera/iso_camera.tscn") as PackedScene).instantiate() as IsoCamera
	ctx.check(is_equal_approx(cam.yaw_deg, SceneryPlan.CAM_YAW_DEG), "CAM_YAW_DEG = IsoCamera.yaw_deg")
	ctx.check(is_equal_approx(cam.pitch_deg, SceneryPlan.CAM_PITCH_DEG), "CAM_PITCH_DEG = IsoCamera.pitch_deg")
	cam.free()


func _determinism(ctx: Variant) -> void:
	for zid: String in SceneryTheme.zone_ids():
		var z: ZoneDef = H.zone(zid)
		ctx.check(z != null, "zona existe: " + zid)
		var th: Dictionary = SceneryTheme.for_zone(zid)
		var a: Array[Dictionary] = SceneryPlan.build(z, th, 1.0)
		var b: Array[Dictionary] = SceneryPlan.build(z, th, 1.0)
		ctx.check(a.size() > 50, "%s: plano nao vazio (%d)" % [zid, a.size()])
		ctx.check(a.size() == b.size() and SceneryPlan.digest(a) == SceneryPlan.digest(b), "%s: mesma seed, mesmo plano" % zid)
	var hub: Array[Dictionary] = SceneryPlan.build(H.zone("zone_hub"), SceneryTheme.for_zone("zone_hub"), 1.0)
	var wild: Array[Dictionary] = SceneryPlan.build(H.zone("zone_wild"), SceneryTheme.for_zone("zone_wild"), 1.0)
	ctx.check(SceneryPlan.digest(hub) != SceneryPlan.digest(wild), "zonas diferentes, planos diferentes")


func _nesting(ctx: Variant) -> void:
	for zid: String in SceneryTheme.zone_ids():
		var z: ZoneDef = H.zone(zid)
		var th: Dictionary = SceneryTheme.for_zone(zid)
		var low: Array[Dictionary] = SceneryPlan.build(z, th, 0.35)
		var med: Array[Dictionary] = SceneryPlan.build(z, th, 0.7)
		var high: Array[Dictionary] = SceneryPlan.build(z, th, 1.0)
		ctx.check(low.size() <= med.size() and med.size() <= high.size() and low.size() < high.size(), "%s: densidade cresce (%d/%d/%d)" % [zid, low.size(), med.size(), high.size()])
		var keys: Dictionary = {}
		for p: Dictionary in high:
			keys["%s|%.3f|%.3f" % [p["rule"], (p["pos"] as Vector3).x, (p["pos"] as Vector3).z]] = true
		var ok: bool = true
		for p: Dictionary in low:
			ok = ok and keys.has("%s|%.3f|%.3f" % [p["rule"], (p["pos"] as Vector3).x, (p["pos"] as Vector3).z])
		ctx.check(ok, "%s: Baixa e subconjunto de Alta" % zid)


func _safety(ctx: Variant) -> void:
	for zid: String in SceneryTheme.zone_ids():
		var z: ZoneDef = H.zone(zid)
		var th: Dictionary = SceneryTheme.for_zone(zid)
		var rect: Rect2 = SceneryPlan.zone_rect(z)
		var plan: Array[Dictionary] = SceneryPlan.build(z, th, 1.0)
		var bad_exclusion: int = 0
		var bad_nan: int = 0
		var bad_shadow: int = 0
		var ex: Dictionary = SceneryPlan.exclusions(z, th)
		for p: Dictionary in plan:
			var v: Vector3 = p["pos"]
			if not (is_finite(v.x) and is_finite(v.z)):
				bad_nan += 1
			if p["kind"] == "feature":
				continue
			var p2: Vector2 = Vector2(v.x, v.z)
			var perimeter: bool = p["kind"] == "perimeter"   # pecas de parede: ficam na borda por definicao (colisao de 1 m ja ocupa)
			if not perimeter:
				for r: Rect2 in ex["rects"]:
					if r.has_point(p2):
						bad_exclusion += 1
			# area jogavel = zona sem a espessura da parede; objeto alto so e aceito se o que fica ATRAS dele (visto da camera) nao e jogavel
			var play: Rect2 = rect.grow(-1.5)
			if p["cls"] == "tall" and SceneryPlan.casts_view_shadow_on(play, p2, float(p["height"]), 1.0):
				bad_shadow += 1
		ctx.check(bad_nan == 0, "%s: posicoes finitas" % zid)
		ctx.check(bad_exclusion == 0, "%s: nada dentro de colisores de props (%d)" % [zid, bad_exclusion])
		ctx.check(bad_shadow == 0, "%s: nenhum objeto alto interno ocluiria o jogador (%d)" % [zid, bad_shadow])
		ctx.check(not SceneryPlan.casts_view_shadow_on(rect, Vector2(1e5, 1e5), 5.0, 1.0), "%s: objeto distante nunca ocluiu" % zid)
