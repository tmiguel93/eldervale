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
const PRESET_DATA: Dictionary = {
	Preset.LOW: {"shadows": false, "shadow_size": 1024, "ssao": false, "glow": false,
		"msaa": Viewport.MSAA_DISABLED, "scale": 0.75},
	Preset.MEDIUM: {"shadows": true, "shadow_size": 2048, "ssao": false, "glow": true,
		"msaa": Viewport.MSAA_2X, "scale": 1.0},
	Preset.HIGH: {"shadows": true, "shadow_size": 4096, "ssao": true, "glow": true,
		"msaa": Viewport.MSAA_4X, "scale": 1.0},
}


static func preset_name(preset: int) -> String:
	return str(PRESET_NAMES.get(preset, "?"))


static func next_preset(preset: int) -> int:
	return (preset + 1) % PRESET_DATA.size()


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
		environment.ssao_enabled = data["ssao"] as bool
		environment.glow_enabled = data["glow"] as bool
	else:
		push_warning("QualitySettings: environment nulo.")
	if light != null:
		light.shadow_enabled = data["shadows"] as bool
		RenderingServer.directional_shadow_atlas_set_size(data["shadow_size"] as int, true)
	else:
		push_warning("QualitySettings: light nulo.")
