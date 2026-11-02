class_name SceneryEnv
extends Node3D
## E8.2: iluminacao e atmosfera do cliente. Dono de UM WorldEnvironment (ceu procedural, ambiente, tonemap, nevoa, glow, ajustes;
## SSAO e nevoa volumetrica so em Forward+) e de UM DirectionalLight3D (sol com sombras). Cada zona do SceneryTheme define o
## humor; regioes dentro da zona (ruinas: salao do chefe) misturam suavemente conforme a posicao do jogador. Tambem pisca as
## luzes de tocha/fogueira e mantem acesas so as `max_lights` mais proximas (preset de qualidade).
## So apresentacao: nao conhece servidor, fisica nem protocolo.

const BLEND_RATE: float = 2.2          ## 1/s: velocidade da mistura de humor dentro da zona
const ZONE_BLEND_RATE: float = 1.6     ## ao trocar de zona o humor atravessa em ~1,5 s
const LIGHT_PICK_INTERVAL: float = 0.25

var world_env: WorldEnvironment
var env: Environment
var sun: DirectionalLight3D
var sky_material: ProceduralSkyMaterial
var quality: int = QualitySettings.DEFAULT_PRESET
var zone_id: String = ""
var theme: Dictionary = {}
var region_id: String = ""
var lights: Array[OmniLight3D] = []
var caps: Dictionary = {}

var _cur: Dictionary = {}
var _target: Dictionary = {}
var _blend_rate: float = BLEND_RATE
var _time: float = 0.0
var _pick_timer: float = 0.0
var _player: Vector3 = Vector3.ZERO
var _has_player: bool = false


func _init() -> void:
	name = "SceneryEnv"
	caps = QualitySettings.renderer_caps()
	_build()


func _build() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	sky_material = ProceduralSkyMaterial.new()
	sky_material.sun_angle_max = 25.0
	sky_material.sky_curve = 0.18
	sky_material.ground_curve = 0.05
	var sky: Sky = Sky.new()
	sky.sky_material = sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_sky_affect = 1.0
	env.glow_enabled = true
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.glow_hdr_threshold = 1.0
	env.glow_hdr_scale = 1.5
	env.adjustment_enabled = true
	# so Forward+ (QualitySettings.apply liga/desliga conforme o preset e o renderer)
	env.ssao_radius = 1.4
	env.ssao_intensity = 2.0
	env.ssao_power = 1.6
	env.ssao_detail = 0.6
	env.ssil_radius = 4.0
	env.ssil_intensity = 0.8
	env.volumetric_fog_gi_inject = 0.0
	env.volumetric_fog_length = 80.0
	env.volumetric_fog_anisotropy = 0.35
	world_env = WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = env
	add_child(world_env)
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.4
	sun.shadow_blur = 1.2
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_fade_start = 0.9
	add_child(sun)


# ------------------------------------------------------------------ zona / qualidade

## Aplica o tema da zona. Sem tema devolve false (quem chama mantem a luz de reserva).
func set_zone(p_zone_id: String, instant: bool = true) -> bool:
	var t: Dictionary = SceneryTheme.for_zone(p_zone_id)
	if t.is_empty():
		return false
	zone_id = p_zone_id
	theme = t
	region_id = ""
	var base: Dictionary = (t["mood"] as Dictionary).duplicate()
	_target = base
	if instant or _cur.is_empty():
		_cur = base.duplicate()
	_blend_rate = ZONE_BLEND_RATE
	_apply_sky(base)
	_apply_mood(_cur)
	return true


func set_quality(preset: int) -> void:
	quality = preset
	QualitySettings.apply(preset, get_viewport() if is_inside_tree() else null, env, sun)
	_apply_capabilities()
	_pick_lights()


func _apply_capabilities() -> void:
	# SSAO/SSIL/nevoa volumetrica nao existem em Compatibility/Mobile: nunca ligar o que o renderer nao tem
	var d: Dictionary = QualitySettings.data(quality)
	env.ssao_enabled = bool(d["ssao"]) and bool(caps["ssao"])
	env.ssil_enabled = bool(d["ssil"]) and bool(caps["ssil"])
	env.volumetric_fog_enabled = bool(d["volumetric_fog"]) and bool(caps["volumetric_fog"])


func set_lights(list: Array[OmniLight3D]) -> void:
	lights = list
	_pick_timer = 0.0
	_pick_lights()


## Humor efetivo: base da zona + regiao em que o jogador esta (se houver).
func mood_for(player_pos: Vector3) -> Dictionary:
	var m: Dictionary = (theme["mood"] as Dictionary).duplicate()
	for r: Dictionary in theme.get("regions", []):
		if (r["rect"] as Rect2).has_point(Vector2(player_pos.x, player_pos.z)):
			m.merge(r["mood"] as Dictionary, true)
			return m
	return m


func region_at(player_pos: Vector3) -> String:
	for r: Dictionary in theme.get("regions", []):
		if (r["rect"] as Rect2).has_point(Vector2(player_pos.x, player_pos.z)):
			return String(r["id"])
	return ""


func update(delta: float, player_pos: Vector3) -> void:
	_player = player_pos
	_has_player = true
	_time += delta
	if not theme.is_empty():
		var rid: String = region_at(player_pos)
		if rid != region_id:
			region_id = rid
			_blend_rate = BLEND_RATE
		_target = mood_for(player_pos)
		var w: float = 1.0 - exp(-_blend_rate * delta)
		var changed: bool = false
		for k: Variant in _target:
			var a: Variant = _cur.get(k)
			var b: Variant = _target[k]
			if typeof(b) == TYPE_COLOR and typeof(a) == TYPE_COLOR:
				if not (a as Color).is_equal_approx(b as Color):
					_cur[k] = (a as Color).lerp(b as Color, w)
					changed = true
			elif typeof(b) == TYPE_FLOAT and typeof(a) == TYPE_FLOAT:
				if absf(float(a) - float(b)) > 0.00001:
					_cur[k] = lerpf(float(a), float(b), w)
					changed = true
			else:
				_cur[k] = b
		if changed:
			_apply_mood(_cur)
	_pick_timer -= delta
	if _pick_timer <= 0.0:
		_pick_timer = LIGHT_PICK_INTERVAL
		_pick_lights()
	_flicker()


# ------------------------------------------------------------------ humor

func _apply_sky(m: Dictionary) -> void:
	sky_material.sky_top_color = m["sky_top"] as Color
	sky_material.sky_horizon_color = m["sky_horizon"] as Color
	sky_material.ground_horizon_color = m["sky_horizon"] as Color
	sky_material.ground_bottom_color = m["sky_ground"] as Color
	sky_material.sun_curve = 0.15
	env.background_color = m["sky_horizon"] as Color


func _apply_mood(m: Dictionary) -> void:
	sun.light_color = m["sun_color"] as Color
	sun.light_energy = float(m["sun_energy"])
	sun.rotation_degrees = Vector3(float(m["sun_pitch"]), float(m["sun_yaw"]), 0.0)
	env.ambient_light_color = m["ambient_color"] as Color
	env.ambient_light_energy = float(m["ambient_energy"])
	env.fog_light_color = m["fog_color"] as Color
	env.fog_density = float(m["fog_density"])
	env.fog_sun_scatter = float(m.get("fog_sun_scatter", 0.0))
	env.tonemap_exposure = float(m["exposure"])
	env.tonemap_white = float(m["white"])
	env.glow_intensity = float(m["glow_intensity"])
	env.glow_bloom = float(m["glow_bloom"])
	env.glow_hdr_threshold = float(m["glow_threshold"])
	env.adjustment_saturation = float(m["saturation"])
	env.adjustment_contrast = float(m["contrast"])
	env.volumetric_fog_density = float(m.get("vol_fog_density", 0.02))
	env.volumetric_fog_albedo = (m["fog_color"] as Color).lightened(0.15)
	env.volumetric_fog_emission = (m["fog_color"] as Color).darkened(0.6)
	env.volumetric_fog_emission_energy = 0.4


# ------------------------------------------------------------------ luzes de tocha

## Acende so as `max_lights` mais proximas do jogador (sem jogador ainda: as primeiras).
func _pick_lights() -> void:
	var limit: int = int(QualitySettings.data(quality)["max_lights"])
	var valid: Array[OmniLight3D] = []
	for l: OmniLight3D in lights:
		if is_instance_valid(l):
			valid.append(l)
	lights = valid
	if _has_player:
		var p: Vector3 = _player
		valid.sort_custom(func(a: OmniLight3D, b: OmniLight3D) -> bool:
			return a.global_position.distance_squared_to(p) < b.global_position.distance_squared_to(p))
	for i: int in valid.size():
		valid[i].visible = i < limit


func _flicker() -> void:
	for l: OmniLight3D in lights:
		if not is_instance_valid(l) or not l.visible:
			continue
		var base: float = float(l.get_meta("base_energy", 1.0))
		var amount: float = float(l.get_meta("flicker", 0.0))
		var ph: float = float(l.get_meta("phase", 0.0))
		var n: float = sin(_time * 11.0 + ph) * 0.5 + sin(_time * 5.3 + ph * 1.7) * 0.3 + sin(_time * 23.0 + ph * 0.6) * 0.2
		l.light_energy = base * (1.0 + amount * n)
		if l.has_meta("flame"):
			var fl: Variant = l.get_meta("flame")
			if fl is MeshInstance3D and is_instance_valid(fl):
				(fl as MeshInstance3D).scale = Vector3(1.0 + 0.08 * n, 1.0 + 0.18 * n, 1.0)
