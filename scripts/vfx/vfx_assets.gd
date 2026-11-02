class_name VfxAssets
extends RefCounted
## E8.3: recursos compartilhados dos efeitos (shaders, texturas de sprite, materiais de particula). Tudo em cache estatico:
## cada arquivo/material e criado uma vez por processo. So o cliente com display chama isto (VfxPlayer.enabled()).
## Sprites: Kenney (CC0) via aliases do manifest (vfx.particle_soft/smoke/burst/hit); "glow" e um gradiente radial procedural.

const SHADER_DIR: String = "res://scripts/vfx/"
const SPRITE_ALIASES: Dictionary = {"particle_soft": "vfx.particle_soft", "smoke": "vfx.smoke", "burst": "vfx.burst", "hit": "vfx.hit"}

static var load_count: int = 0          ## quantos recursos foram realmente carregados/criados (testes: headless = 0)
static var _shaders: Dictionary = {}
static var _textures: Dictionary = {}
static var _particle_mats: Dictionary = {}
static var _curves: Dictionary = {}
static var _glow_mat: StandardMaterial3D = null


static func clear() -> void:
	_shaders = {}
	_textures = {}
	_particle_mats = {}
	_curves = {}
	_glow_mat = null
	load_count = 0


static func shader(name: String) -> Shader:
	if _shaders.has(name):
		return _shaders[name] as Shader
	var sh: Shader = load(SHADER_DIR + "vfx_%s.gdshader" % name) as Shader
	load_count += 1
	_shaders[name] = sh
	return sh


## Material novo (por instancia: os uniforms mudam a cada quadro) do shader `name`.
static func shader_material(name: String) -> ShaderMaterial:
	var m: ShaderMaterial = ShaderMaterial.new()
	m.shader = shader(name)
	return m


static func sprite(name: String) -> Texture2D:
	if _textures.has(name):
		return _textures[name] as Texture2D
	var tex: Texture2D = null
	if name == "glow":
		var g: Gradient = Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.4), Color(1, 1, 1, 0.0)])
		var gt: GradientTexture2D = GradientTexture2D.new()
		gt.gradient = g
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5)
		gt.fill_to = Vector2(1.0, 0.5)
		gt.width = 128
		gt.height = 128
		tex = gt
	else:
		var path: String = AssetAliases.resolve(String(SPRITE_ALIASES.get(name, "")))
		if not path.is_empty() and ResourceLoader.exists(path):
			tex = load(path) as Texture2D
	load_count += 1
	_textures[name] = tex
	return tex


## Material de particula billboard: sprite + mistura (add/mix), cor por particula (color_ramp).
static func particle_material(sprite_name: String, blend: String) -> StandardMaterial3D:
	var key: String = sprite_name + "|" + blend
	if _particle_mats.has(key):
		return _particle_mats[key] as StandardMaterial3D
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if blend == "add" else BaseMaterial3D.BLEND_MODE_MIX
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = sprite(sprite_name)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.disable_receive_shadows = true
	m.no_depth_test = false
	_particle_mats[key] = m
	return m


## Material do brilho billboard do nucleo (orb), aditivo.
static func glow_material() -> StandardMaterial3D:
	if _glow_mat != null:
		return _glow_mat
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_texture = sprite("glow")
	m.albedo_color = Color(1, 1, 1, 1)
	m.vertex_color_use_as_albedo = false
	m.disable_receive_shadows = true
	_glow_mat = m
	return m


## Curva de escala por nome: shrink (1 -> 0), grow (0.2 -> 1 -> 0), pop (0 -> 1.2 -> 0.8 -> 0), flat (1).
static func size_curve(name: String) -> Curve:
	if _curves.has(name):
		return _curves[name] as Curve
	var c: Curve = Curve.new()
	match name:
		"shrink":
			c.add_point(Vector2(0, 1.0))
			c.add_point(Vector2(1, 0.0))
		"grow":
			c.add_point(Vector2(0, 0.25))
			c.add_point(Vector2(0.6, 1.0))
			c.add_point(Vector2(1, 0.0))
		"pop":
			c.add_point(Vector2(0, 0.0))
			c.add_point(Vector2(0.12, 1.2))
			c.add_point(Vector2(0.5, 0.8))
			c.add_point(Vector2(1, 0.0))
		_:
			c.add_point(Vector2(0, 1.0))
			c.add_point(Vector2(1, 1.0))
	_curves[name] = c
	return c
