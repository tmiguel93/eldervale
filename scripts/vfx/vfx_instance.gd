class_name VfxInstance
extends Node3D
## E8.3: uma instancia de efeito (pool). Montada UMA vez a partir da definicao (camadas = nos filhos); `begin()` rearma sem
## criar nos; `step(delta)` so ajusta uniforms/transformacoes (sem alocar). Camadas: arc, ring, rune, pillar, orb, streak, burst
## (CPUParticles3D), light (OmniLight3D, sujeita ao orcamento do preset) e shake (pedido de tremor de camera ao VfxPlayer).
## Eixos locais: -Z = frente do efeito (yaw do chamador); offsets das camadas sao locais.

var effect_id: String = ""
var def: Dictionary = {}
var priority: int = 1
var looping: bool = false
var duration: float = 0.5
var fade_out: float = 0.35
var age: float = 0.0
var active: bool = false
var stopping: bool = false
var handle: int = 0
var scale_mul: float = 1.0
var velocity: Vector3 = Vector3.ZERO
var travel_left: float = 0.0
var end_effect: String = ""
var owner_id: int = -1
var pierce_left: int = 0
var quiet: bool = false   ## sem tremor de camera (efeito longe do jogador local)
var follow: Node3D = null
var follow_offset: Vector3 = Vector3.ZERO
var layer_count: int = 0

var _layers: Array[Dictionary] = []
var _player: Node = null
var _stop_age: float = 0.0
var _density: float = 1.0
var _tint: Color = Color(0, 0, 0, 0)


## Monta os nos. `density` escala a quantidade de particulas (preset de qualidade).
func build(p_id: String, p_def: Dictionary, density: float) -> void:
	effect_id = p_id
	def = p_def
	name = "Vfx_" + p_id
	_density = density
	priority = int(def.get("priority", 1))
	looping = bool(def.get("loop", false))
	fade_out = float(def.get("fade_out", 0.35))
	duration = 0.0
	for ld: Variant in (def.get("layers", []) as Array):
		var L: Dictionary = _build_layer(ld as Dictionary)
		if L.is_empty():
			continue
		_layers.append(L)
		duration = maxf(duration, float(L["start"]) + float(L["life"]))
	layer_count = _layers.size()
	visible = false


func _build_layer(d: Dictionary) -> Dictionary:
	var ty: String = String(d.get("type", ""))
	var L: Dictionary = {"type": ty, "d": d, "start": float(d.get("start", 0.0)), "life": float(d.get("life", 0.5)), "started": false, "rot": 0.0, "tint": bool(d.get("tintable", false))}
	var off: Vector3 = VfxCatalog.vec3_of(d.get("offset", null))
	L["off"] = off
	var node: Node3D = null
	match ty:
		"arc":
			var half: float = deg_to_rad(float(d["angle"])) * 0.5
			var radius: float = float(d["radius"])
			var inner: float = clampf(1.0 - float(d["width"]) / radius, 0.0, 0.95)
			var mi: MeshInstance3D = MeshInstance3D.new()
			mi.mesh = VfxMeshes.annulus(inner, half if bool(d.get("mirror", false)) else -half, -half if bool(d.get("mirror", false)) else half, 36)
			var m: ShaderMaterial = VfxAssets.shader_material("arc")
			m.set_shader_parameter("intensity", float(d.get("intensity", 1.6)))
			m.set_shader_parameter("tail_len", float(d.get("tail", 0.6)))
			m.set_shader_parameter("sweep_end", float(d.get("sweep", 0.55)))
			mi.material_override = m
			L["mat"] = m
			node = mi
		"ring":
			var mi2: MeshInstance3D = MeshInstance3D.new()
			mi2.mesh = VfxMeshes.annulus(1.0 - float(d.get("width", 0.18)), 0.0, TAU, 48)
			var m2: ShaderMaterial = VfxAssets.shader_material("ring")
			m2.set_shader_parameter("intensity", float(d.get("intensity", 1.5)))
			m2.set_shader_parameter("dash", float(d.get("dash", 0.0)))
			mi2.material_override = m2
			L["mat"] = m2
			node = mi2
		"rune":
			var mi3: MeshInstance3D = MeshInstance3D.new()
			mi3.mesh = VfxMeshes.ground_quad(2.0, 2.0)
			var m3: ShaderMaterial = VfxAssets.shader_material("rune")
			m3.set_shader_parameter("intensity", float(d.get("intensity", 1.6)))
			m3.set_shader_parameter("appear", float(d.get("appear", 0.2)))
			m3.set_shader_parameter("vanish", float(d.get("vanish", 0.35)))
			m3.set_shader_parameter("fill", float(d.get("fill", 0.0)))
			m3.set_shader_parameter("glyphs", float(int(d.get("glyphs", 12))))
			m3.set_shader_parameter("style", ["circle", "valknut", "rings"].find(String(d.get("style", "circle"))))
			mi3.material_override = m3
			L["mat"] = m3
			node = mi3
		"pillar":
			var mi4: MeshInstance3D = MeshInstance3D.new()
			mi4.mesh = VfxMeshes.open_cylinder(20)
			var m4: ShaderMaterial = VfxAssets.shader_material("pillar")
			m4.set_shader_parameter("intensity", float(d.get("intensity", 1.6)))
			m4.set_shader_parameter("grow", float(d.get("grow", 0.25)))
			mi4.material_override = m4
			L["mat"] = m4
			node = mi4
		"orb":
			var holder: Node3D = Node3D.new()
			var core: MeshInstance3D = MeshInstance3D.new()
			core.mesh = VfxMeshes.sphere(float(d["radius"]))
			var m5: ShaderMaterial = VfxAssets.shader_material("orb")
			m5.set_shader_parameter("intensity", float(d.get("intensity", 1.8)))
			core.material_override = m5
			holder.add_child(core)
			L["mat"] = m5
			var gl: float = float(d.get("glow", 3.0))
			if gl > 0.0:
				var glow: MeshInstance3D = MeshInstance3D.new()
				glow.mesh = VfxMeshes.billboard_quad(float(d["radius"]) * 2.0 * gl)
				glow.material_override = VfxAssets.glow_material().duplicate() as Material
				holder.add_child(glow)
				L["glow"] = glow
			node = holder
		"streak":
			var mi6: MeshInstance3D = MeshInstance3D.new()
			mi6.mesh = VfxMeshes.streak(float(d["length"]), float(d["width"]))
			var m6: ShaderMaterial = VfxAssets.shader_material("streak")
			m6.set_shader_parameter("intensity", float(d.get("intensity", 1.6)))
			m6.set_shader_parameter("flash", 1.0 if String(d.get("mode", "trail")) == "flash" else 0.0)
			mi6.material_override = m6
			L["mat"] = m6
			node = mi6
		"burst":
			node = _build_burst(d, L)
		"light":
			if float(d.get("energy", 1.0)) > 0.0:
				var ol: OmniLight3D = OmniLight3D.new()
				ol.omni_range = float(d["range"])
				ol.shadow_enabled = false
				ol.light_energy = 0.0
				ol.visible = false
				node = ol
		"shake":
			node = null
	L["node"] = node
	if node != null:
		node.position = off
		node.visible = false
		add_child(node)
	return L


func _build_burst(d: Dictionary, L: Dictionary) -> CPUParticles3D:
	var p: CPUParticles3D = CPUParticles3D.new()
	var continuous: bool = bool(d.get("continuous", false))
	p.emitting = false
	p.one_shot = not continuous
	p.amount = maxi(1, roundi(float(d["count"]) * _density))
	p.lifetime = float(d.get("life", 0.5))
	p.explosiveness = 0.0 if continuous else float(d.get("explosiveness", 0.9))
	p.randomness = 0.6
	p.local_coords = bool(d.get("local", false))
	var q: QuadMesh = QuadMesh.new()
	q.size = Vector2.ONE
	q.material = VfxAssets.particle_material(String(d.get("sprite", "particle_soft")), String(d.get("blend", "add")))
	p.mesh = q
	var shape: String = String(d.get("shape", "point"))
	var sr: float = float(d.get("shape_radius", 0.0))
	match shape:
		"sphere":
			p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
			p.emission_sphere_radius = maxf(sr, 0.01)
		"ring", "disc":
			p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
			p.emission_ring_axis = Vector3.UP
			p.emission_ring_height = 0.0
			p.emission_ring_radius = maxf(sr, 0.05)
			p.emission_ring_inner_radius = maxf(sr, 0.05) * (0.85 if shape == "ring" else 0.0)
		_:
			p.emission_shape = CPUParticles3D.EMISSION_SHAPE_POINT
	p.direction = VfxCatalog.vec3_of(d.get("direction", null), Vector3.UP)
	p.spread = float(d.get("spread", 45.0))
	p.gravity = Vector3(0.0, float(d.get("gravity", 0.0)), 0.0)
	var sp: Array = d.get("speed", [1.0, 3.0]) as Array
	p.initial_velocity_min = float(sp[0])
	p.initial_velocity_max = float(sp[1])
	var dm: float = float(d.get("damping", 0.0))
	p.damping_min = dm * 0.8
	p.damping_max = dm
	var sz: Array = d.get("size", [0.1, 0.2]) as Array
	p.scale_amount_min = float(sz[0])
	p.scale_amount_max = float(sz[1])
	p.scale_amount_curve = VfxAssets.size_curve(String(d.get("size_curve", "shrink")))
	var spn: Array = d.get("spin", [0.0, 0.0]) as Array
	p.angle_min = float(spn[0])
	p.angle_max = float(spn[1])
	p.particle_flag_align_y = bool(d.get("align", false))
	var g: Gradient = Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	g.colors = PackedColorArray([Color.WHITE, Color.WHITE, Color(1, 1, 1, 0)])
	p.color_ramp = g
	L["grad"] = g
	L["base_speed"] = [float(sp[0]), float(sp[1])]
	L["base_size"] = [float(sz[0]), float(sz[1])]
	L["base_radius"] = sr
	return p


## Rearma para uma nova reproducao. `p_scale` multiplica tamanhos; `tint` (alpha > 0) recolore camadas `tintable`.
func begin(player: Node, p_scale: float, tint: Color) -> void:
	_player = player
	age = 0.0
	stopping = false
	_stop_age = 0.0
	scale_mul = p_scale
	_tint = tint
	velocity = Vector3.ZERO
	travel_left = 0.0
	end_effect = ""
	owner_id = -1
	pierce_left = 0
	quiet = false
	follow = null
	follow_offset = Vector3.ZERO
	active = true
	visible = true
	for L: Dictionary in _layers:
		L["started"] = false
		L["rot"] = 0.0
		var node: Node3D = L["node"] as Node3D
		if node != null:
			node.visible = false
		_apply_colors(L)
		_apply_scale(L)


func _apply_colors(L: Dictionary) -> void:
	var d: Dictionary = L["d"] as Dictionary
	var ca: Color = VfxCatalog.color_of(d.get("color_a", d.get("color", null)), Color(1, 1, 1, 1))
	var cb: Color = VfxCatalog.color_of(d.get("color_b", null), ca.darkened(0.4))
	if bool(L["tint"]) and _tint.a > 0.0:
		ca = Color(_tint.r, _tint.g, _tint.b, 1.0)
		cb = ca.darkened(0.45)
	var mat: ShaderMaterial = L.get("mat") as ShaderMaterial
	var vc: Vector3 = Vector3(ca.r, ca.g, ca.b)
	var vb: Vector3 = Vector3(cb.r, cb.g, cb.b)
	match String(L["type"]):
		"arc":
			mat.set_shader_parameter("color_head", vc)
			mat.set_shader_parameter("color_tail", vb)
		"ring":
			mat.set_shader_parameter("color", vc)
		"rune", "pillar", "orb", "streak":
			mat.set_shader_parameter("color_a", vc)
			mat.set_shader_parameter("color_b", vb)
			var glow: MeshInstance3D = L.get("glow") as MeshInstance3D
			if glow != null:
				(glow.material_override as StandardMaterial3D).albedo_color = Color(cb.r, cb.g, cb.b, 0.9)
		"burst":
			var g: Gradient = L["grad"] as Gradient
			g.set_color(0, ca)
			g.set_color(1, cb)
			g.set_color(2, Color(cb.r, cb.g, cb.b, 0.0))
		"light":
			var ol: OmniLight3D = L.get("node") as OmniLight3D
			if ol != null:
				ol.light_color = VfxCatalog.color_of(d.get("color", null), Color(1, 0.8, 0.5)) if not (bool(L["tint"]) and _tint.a > 0.0) else ca


func _apply_scale(L: Dictionary) -> void:
	var d: Dictionary = L["d"] as Dictionary
	var node: Node3D = L["node"] as Node3D
	if node == null:
		return
	var s: float = scale_mul
	node.position = (L["off"] as Vector3) * s
	match String(L["type"]):
		"arc":
			var r: float = float(d["radius"]) * s
			node.scale = Vector3(r, 1.0, r)
			node.position.y = float(d.get("height", 0.9)) * s
			node.rotation = Vector3(0.0, 0.0, deg_to_rad(float(d.get("tilt", 0.0))))
		"ring":
			node.position.y = float(d.get("height", 0.05))
		"rune":
			var rr: float = float(d["radius"]) * s
			node.scale = Vector3(rr, 1.0, rr)
			node.position.y = float(d.get("height", 0.05))
		"pillar":
			var pr: float = float(d["radius"]) * s
			node.scale = Vector3(pr, float(d["height"]) * s, pr)
		"orb":
			node.scale = Vector3.ONE * s
		"streak":
			node.scale = Vector3(s, 1.0, s)
		"burst":
			var p: CPUParticles3D = node as CPUParticles3D
			var bs: Array = L["base_speed"] as Array
			var bz: Array = L["base_size"] as Array
			p.initial_velocity_min = float(bs[0]) * s
			p.initial_velocity_max = float(bs[1]) * s
			p.scale_amount_min = float(bz[0]) * s
			p.scale_amount_max = float(bz[1]) * s
			if p.emission_shape == CPUParticles3D.EMISSION_SHAPE_SPHERE:
				p.emission_sphere_radius = maxf(float(L["base_radius"]) * s, 0.01)
			elif p.emission_shape == CPUParticles3D.EMISSION_SHAPE_RING:
				var rad: float = maxf(float(L["base_radius"]) * s, 0.05)
				p.emission_ring_radius = rad
				p.emission_ring_inner_radius = rad * (0.85 if String(d.get("shape", "")) == "ring" else 0.0)


## Pede parada suave (efeitos em loop; one-shots simplesmente terminam).
func stop() -> void:
	if active and not stopping:
		stopping = true
		_stop_age = 0.0
		for L: Dictionary in _layers:
			if String(L["type"]) == "burst" and L["node"] != null:
				(L["node"] as CPUParticles3D).emitting = false


## Avanca `delta`. Devolve true quando terminou (o VfxPlayer devolve ao pool).
func step(delta: float) -> bool:
	age += delta
	if stopping:
		_stop_age += delta
	var end_time: float = duration
	if looping:
		end_time = INF
	if stopping:
		var fo: float = maxf(fade_out, _max_particle_life())
		if _stop_age >= fo:
			return true
	elif age >= end_time:
		return true
	for L: Dictionary in _layers:
		var t: float = age - float(L["start"])
		if t < 0.0:
			continue
		var node: Node3D = L["node"] as Node3D
		var ty: String = String(L["type"])
		if not bool(L["started"]):
			L["started"] = true
			if ty == "shake":
				if not quiet and _player != null and _player.has_method("request_shake"):
					_player.request_shake(float((L["d"] as Dictionary)["strength"]) * minf(scale_mul, 1.6), float(L["life"]))
			elif ty == "light":
				var ol: OmniLight3D = node as OmniLight3D
				if ol != null and _player != null and _player.has_method("acquire_light") and bool(_player.acquire_light()):
					L["lit"] = true
					ol.visible = true
			elif node != null:
				node.visible = true
				if ty == "burst":
					var p: CPUParticles3D = node as CPUParticles3D
					p.restart()
					p.emitting = true
		var life: float = float(L["life"])
		var k: float = t / life
		if looping:
			if ty == "arc" or ty == "ring":
				k = fposmod(k, 1.0)
			else:
				k = minf(k, 0.45)
		if stopping:
			k = 0.45 + 0.55 * clampf(_stop_age / maxf(fade_out, 0.05), 0.0, 1.0) if ty != "arc" and ty != "ring" else 0.5 + 0.5 * clampf(_stop_age / maxf(fade_out, 0.05), 0.0, 1.0)
		_update_layer(L, ty, k, delta)
	if follow != null:
		if is_instance_valid(follow):
			global_position = follow.global_position + follow_offset
		else:
			follow = null
	return false


func _max_particle_life() -> float:
	var m: float = 0.0
	for L: Dictionary in _layers:
		if String(L["type"]) == "burst":
			m = maxf(m, float(L["life"]))
	return m


func _update_layer(L: Dictionary, ty: String, k: float, delta: float) -> void:
	var d: Dictionary = L["d"] as Dictionary
	var mat: ShaderMaterial = L.get("mat") as ShaderMaterial
	var node: Node3D = L["node"] as Node3D
	match ty:
		"arc":
			mat.set_shader_parameter("progress", clampf(k, 0.0, 1.0))
			var spin: float = float(d.get("spin", 0.0))
			if spin != 0.0 and node != null:
				L["rot"] = float(L["rot"]) + deg_to_rad(spin) * delta
				node.rotation.y = float(L["rot"])
			if k > 1.0 and not looping:
				node.visible = false
		"ring":
			var kk: float = clampf(k, 0.0, 1.0)
			var e: float = kk
			match String(d.get("ease", "out")):
				"out":
					e = 1.0 - (1.0 - kk) * (1.0 - kk)
				"in_out":
					e = kk * kk * (3.0 - 2.0 * kk)
			var r: float = lerpf(float(d["r0"]), float(d["r1"]), e) * scale_mul
			node.scale = Vector3(maxf(r, 0.01), 1.0, maxf(r, 0.01))
			mat.set_shader_parameter("progress", kk)
			if k > 1.0 and not looping:
				node.visible = false
		"rune":
			L["rot"] = float(L["rot"]) + float(d.get("spin", 0.4)) * delta
			mat.set_shader_parameter("rot", float(L["rot"]))
			mat.set_shader_parameter("pulse", 0.5 + 0.5 * sin(age * float(d.get("pulse", 3.0))))
			mat.set_shader_parameter("progress", clampf(k, 0.0, 1.0))
			if k > 1.0 and not looping:
				node.visible = false
		"pillar", "streak":
			mat.set_shader_parameter("progress", clampf(k, 0.0, 1.0))
			if k > 1.0 and not looping:
				node.visible = false
		"orb":
			mat.set_shader_parameter("progress", clampf(k, 0.0, 1.0))
			mat.set_shader_parameter("pulse", 0.5 + 0.5 * sin(age * float(d.get("pulse", 10.0))))
			var glow: MeshInstance3D = L.get("glow") as MeshInstance3D
			if glow != null:
				var fa: float = 1.0 - smoothstep(0.7, 1.0, clampf(k, 0.0, 1.0))
				var gm: StandardMaterial3D = glow.material_override as StandardMaterial3D
				gm.albedo_color.a = fa * (0.7 + 0.3 * sin(age * float(d.get("pulse", 10.0))))
			if k > 1.0 and not looping:
				node.visible = false
		"light":
			var ol: OmniLight3D = node as OmniLight3D
			if ol != null and bool(L.get("lit", false)):
				var peak: float = float(d.get("peak", 0.15))
				var kk2: float = clampf(k, 0.0, 1.0)
				var env: float = kk2 / maxf(peak, 0.001) if kk2 < peak else 1.0 - (kk2 - peak) / maxf(1.0 - peak, 0.001)
				ol.light_energy = float(d["energy"]) * clampf(env, 0.0, 1.0)
				if k > 1.0 and not looping:
					ol.visible = false


## Devolve recursos ocupados (luzes) e esconde. Chamado pelo VfxPlayer antes de reciclar.
func finish() -> void:
	active = false
	stopping = false
	visible = false
	follow = null
	for L: Dictionary in _layers:
		var node: Node3D = L["node"] as Node3D
		if node != null:
			node.visible = false
		if String(L["type"]) == "burst" and node != null:
			(node as CPUParticles3D).emitting = false
		if bool(L.get("lit", false)):
			L["lit"] = false
			if _player != null and _player.has_method("release_light"):
				_player.release_light()
