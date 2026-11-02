class_name QualitySettings
extends RefCounted
## Presets de qualidade grafica (E1). Sem autoload: apenas funcoes estaticas.
## Aplica em Viewport (MSAA/scaling 3D), Environment (SSAO/glow) e DirectionalLight3D (sombras).

enum Preset { LOW, MEDIUM, HIGH }

const PRESET_NAMES: Dictionary = {
	Preset.LOW: "Baixo",
	Preset.MEDIUM: "Medio",
	Preset.HIGH: "Alto",
}

## Parametros por preset. shadow_size = resolucao do atlas de sombra direcional.
## E8.2 (cenario): decor_density (fracao da decoracao do SceneryPlan; Baixa e subconjunto de Media e Alta), view_distance
## (m a partir da camera; props de cenario alem disso nao sao desenhados), max_lights (luzes de tocha/fogueira ativas ao
## mesmo tempo, as mais proximas do jogador), shadow_distance (m), volumetric_fog (so Forward+), ssil (so Forward+; fica
## desligado: custo alto para pouco ganho com a camera isometrica).
## E8.3 (VFX de combate): vfx_density (fator sobre a quantidade de particulas de cada efeito), vfx_max_active (efeitos
## simultaneos; o excedente e descartado por prioridade) e vfx_max_lights (luzes dinamicas curtas dos efeitos fortes).
const PRESET_DATA: Dictionary = {
	Preset.LOW: {"shadows": false, "shadow_size": 1024, "ssao": false, "glow": false,
		"msaa": Viewport.MSAA_DISABLED, "scale": 0.75,
		"decor_density": 0.35, "view_distance": 60.0, "max_lights": 4, "shadow_distance": 50.0,
		"volumetric_fog": false, "ssil": false,
		"vfx_density": 0.4, "vfx_max_active": 10, "vfx_max_lights": 0},
	Preset.MEDIUM: {"shadows": true, "shadow_size": 2048, "ssao": false, "glow": true,
		"msaa": Viewport.MSAA_2X, "scale": 1.0,
		"decor_density": 0.7, "view_distance": 90.0, "max_lights": 8, "shadow_distance": 55.0,
		"volumetric_fog": false, "ssil": false,
		"vfx_density": 0.75, "vfx_max_active": 20, "vfx_max_lights": 2},
	Preset.HIGH: {"shadows": true, "shadow_size": 4096, "ssao": true, "glow": true,
		"msaa": Viewport.MSAA_4X, "scale": 1.0,
		"decor_density": 1.0, "view_distance": 130.0, "max_lights": 14, "shadow_distance": 60.0,
		"volumetric_fog": true, "ssil": false,
		"vfx_density": 1.0, "vfx_max_active": 32, "vfx_max_lights": 4},
}

## E8.2: padrao seguro do cliente (sem configuracao salva nem --quality).
const DEFAULT_PRESET: int = Preset.MEDIUM
const CONFIG_PATH: String = "user://settings.cfg"
const CONFIG_SECTION: String = "graphics"
const CONFIG_KEY: String = "quality"
const KEY_NAMES: Dictionary = {Preset.LOW: "low", Preset.MEDIUM: "medium", Preset.HIGH: "high"}
const ALIASES: Dictionary = {
	"low": Preset.LOW, "baixo": Preset.LOW, "baixa": Preset.LOW, "l": Preset.LOW, "0": Preset.LOW,
	"medium": Preset.MEDIUM, "med": Preset.MEDIUM, "medio": Preset.MEDIUM, "media": Preset.MEDIUM, "m": Preset.MEDIUM, "1": Preset.MEDIUM,
	"high": Preset.HIGH, "alto": Preset.HIGH, "alta": Preset.HIGH, "h": Preset.HIGH, "2": Preset.HIGH,
}

## Preset em uso no cliente (resolvido uma vez em ClientMain; F9 alterna).
static var current: int = DEFAULT_PRESET


static func preset_name(preset: int) -> String:
	return str(PRESET_NAMES.get(preset, "?"))


static func next_preset(preset: int) -> int:
	return (preset + 1) % PRESET_DATA.size()


## Parametros do preset (copia). Preset invalido cai no padrao.
static func data(preset: int) -> Dictionary:
	return (PRESET_DATA[preset] if PRESET_DATA.has(preset) else PRESET_DATA[DEFAULT_PRESET]).duplicate()


## "low"/"baixa"/"medio"/"alto"... -> Preset; -1 se nao reconhecido.
static func preset_from_name(text: String) -> int:
	var key: String = text.strip_edges().to_lower()
	return int(ALIASES.get(key, -1))


static func key_name(preset: int) -> String:
	return String(KEY_NAMES.get(preset, "medium"))


## `--quality low|medium|high` (ou --quality=...) nos argumentos de usuario; -1 se ausente/invalido.
static func preset_from_args(args: PackedStringArray) -> int:
	for i: int in args.size():
		var a: String = args[i]
		if a == "--quality" and i + 1 < args.size():
			return preset_from_name(args[i + 1])
		if a.begins_with("--quality="):
			return preset_from_name(a.substr(10))
	return -1


## Preset salvo em ConfigFile; -1 se nao existe/invalido.
static func load_saved(path: String = CONFIG_PATH) -> int:
	var cf: ConfigFile = ConfigFile.new()
	if cf.load(path) != OK:
		return -1
	return preset_from_name(str(cf.get_value(CONFIG_SECTION, CONFIG_KEY, "")))


## Grava o preset no ConfigFile preservando as outras chaves. Devolve OK ou o erro.
static func save(preset: int, path: String = CONFIG_PATH) -> int:
	var cf: ConfigFile = ConfigFile.new()
	cf.load(path) # arquivo ausente e normal
	cf.set_value(CONFIG_SECTION, CONFIG_KEY, key_name(preset))
	return cf.save(path)


## Ordem: --quality (nao grava) > configuracao salva > DEFAULT_PRESET.
static func resolve_startup(args: PackedStringArray, path: String = CONFIG_PATH) -> int:
	var from_args: int = preset_from_args(args)
	if from_args >= 0:
		return from_args
	var saved: int = load_saved(path)
	return saved if saved >= 0 else DEFAULT_PRESET


## O que o renderer atual suporta. Compatibility (opengl3): sem SSAO/SSIL/nevoa volumetrica; Mobile: sem SSAO/SSIL/volumetrica.
static func renderer_caps(method: String = "") -> Dictionary:
	var m: String = method if not method.is_empty() else str(RenderingServer.get_current_rendering_method())
	var forward_plus: bool = m == "forward_plus"
	return {"method": m, "ssao": forward_plus, "ssil": forward_plus, "volumetric_fog": forward_plus}


## Aplica o preset. Qualquer alvo nulo e ignorado com push_warning.
static func apply(preset: int, viewport: Viewport, environment: Environment, light: DirectionalLight3D) -> void:
	if not PRESET_DATA.has(preset):
		push_error("QualitySettings: preset invalido: %d" % preset)
		return
	var data: Dictionary = PRESET_DATA[preset]
	if viewport != null:
		viewport.msaa_3d = data["msaa"] as Viewport.MSAA
		viewport.scaling_3d_scale = data["scale"] as float
	else:
		push_warning("QualitySettings: viewport nulo.")
	if environment != null:
		var caps: Dictionary = renderer_caps()
		environment.ssao_enabled = (data["ssao"] as bool) and bool(caps["ssao"])
		environment.ssil_enabled = (data["ssil"] as bool) and bool(caps["ssil"])
		environment.volumetric_fog_enabled = (data["volumetric_fog"] as bool) and bool(caps["volumetric_fog"])
		environment.glow_enabled = data["glow"] as bool
	else:
		push_warning("QualitySettings: environment nulo.")
	if light != null:
		light.shadow_enabled = data["shadows"] as bool
		light.directional_shadow_max_distance = float(data["shadow_distance"])
		RenderingServer.directional_shadow_atlas_set_size(data["shadow_size"] as int, true)
	else:
		push_warning("QualitySettings: light nulo.")
