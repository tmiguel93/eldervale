class_name UiSettings
extends RefCounted
## E8.4: configuracoes de interface/audio do cliente, gravadas em user://settings.cfg junto das de grafico (QualitySettings, [graphics]) e
## acessibilidade (VfxSettings, [accessibility]): [audio] master_volume (0..1) e [interface] ui_scale. Sem autoload: variaveis estaticas.
## Padrao seguro sem arquivo: volume 0.8, escala 1.0. So cliente (o servidor nunca toca aqui).

const SECTION_AUDIO: String = "audio"
const KEY_VOLUME: String = "master_volume"
const SECTION_UI: String = "interface"
const KEY_SCALE: String = "ui_scale"
const SCALES: Array[float] = [0.85, 1.0, 1.15, 1.3]
const BASE_SIZE: Vector2i = Vector2i(1280, 720)

static var master_volume: float = 0.8
static var ui_scale: float = 1.0


static func reset() -> void:
	master_volume = 0.8
	ui_scale = 1.0


static func clamp_volume(v: float) -> float:
	return clampf(v if is_finite(v) else 0.8, 0.0, 1.0)


## Escala valida mais proxima da lista (valor invalido => 1.0).
static func nearest_scale(v: float) -> float:
	if not is_finite(v):
		return 1.0
	var best: float = 1.0
	var best_d: float = INF
	for s: float in SCALES:
		if absf(s - v) < best_d:
			best_d = absf(s - v)
			best = s
	return best


static func load_saved(path: String = QualitySettings.CONFIG_PATH) -> void:
	var cf: ConfigFile = ConfigFile.new()
	if cf.load(path) != OK:
		return
	master_volume = clamp_volume(float(cf.get_value(SECTION_AUDIO, KEY_VOLUME, master_volume)))
	ui_scale = nearest_scale(float(cf.get_value(SECTION_UI, KEY_SCALE, ui_scale)))


static func save(path: String = QualitySettings.CONFIG_PATH) -> int:
	var cf: ConfigFile = ConfigFile.new()
	cf.load(path)
	cf.set_value(SECTION_AUDIO, KEY_VOLUME, master_volume)
	cf.set_value(SECTION_UI, KEY_SCALE, ui_scale)
	return cf.save(path)


static func resolve_startup(path: String = QualitySettings.CONFIG_PATH) -> void:
	reset()
	load_saved(path)


## Volume geral no barramento Master (0 = mudo). Seguro em headless.
static func apply_volume() -> void:
	var idx: int = AudioServer.get_bus_index("Master")
	if idx < 0:
		return
	AudioServer.set_bus_mute(idx, master_volume <= 0.001)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(master_volume, 0.0001)))


## Escala de conteudo da janela: base 1280x720 (canvas_items, expand) para a UI ficar legivel de 720p a 4K; `ui_scale` multiplica.
## Ignorado em headless/testes (nao mexe na janela do executor).
static func apply_scale(window: Window) -> void:
	if window == null or DisplayServer.get_name() == "headless":
		return
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	window.content_scale_size = BASE_SIZE
	window.content_scale_factor = ui_scale
