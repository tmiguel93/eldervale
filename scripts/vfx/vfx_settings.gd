class_name VfxSettings
extends RefCounted
## E8.3: acessibilidade/conforto dos efeitos de combate (SO cliente). `reduce_motion` desliga tremor de camera, hit-stop e
## brilhos fortes de uma vez; `camera_shake` e `hit_stop` liberam cada um separadamente. Sem autoload: variaveis estaticas.
## Precedencia no inicio: `--reduce-motion 1|0` (nao grava) > `user://settings.cfg` [accessibility] > padrao (tremor leve ligado).

const CONFIG_SECTION: String = "accessibility"
const KEY_REDUCE: String = "reduce_motion"
const KEY_SHAKE: String = "camera_shake"
const KEY_HITSTOP: String = "hit_stop"

static var reduce_motion: bool = false
static var camera_shake: bool = true
static var hit_stop: bool = true


static func shake_enabled() -> bool:
	return camera_shake and not reduce_motion


static func hit_stop_enabled() -> bool:
	return hit_stop and not reduce_motion


## Brilhos/pulsos fortes de tela (level up etc.): so sem reduce_motion.
static func strong_flash_enabled() -> bool:
	return not reduce_motion


static func reset() -> void:
	reduce_motion = false
	camera_shake = true
	hit_stop = true


static func _flag(text: String) -> int:
	match text.strip_edges().to_lower():
		"1", "true", "on", "yes", "sim":
			return 1
		"0", "false", "off", "no", "nao":
			return 0
	return -1


## `--reduce-motion 1|0` (ou --reduce-motion=1); -1 se ausente/invalido.
static func reduce_from_args(args: PackedStringArray) -> int:
	for i: int in args.size():
		if args[i] == "--reduce-motion" and i + 1 < args.size():
			return _flag(args[i + 1])
		if args[i].begins_with("--reduce-motion="):
			return _flag(args[i].substr(16))
	return -1


static func load_saved(path: String = QualitySettings.CONFIG_PATH) -> void:
	var cf: ConfigFile = ConfigFile.new()
	if cf.load(path) != OK:
		return
	reduce_motion = bool(cf.get_value(CONFIG_SECTION, KEY_REDUCE, reduce_motion))
	camera_shake = bool(cf.get_value(CONFIG_SECTION, KEY_SHAKE, camera_shake))
	hit_stop = bool(cf.get_value(CONFIG_SECTION, KEY_HITSTOP, hit_stop))


static func save(path: String = QualitySettings.CONFIG_PATH) -> int:
	var cf: ConfigFile = ConfigFile.new()
	cf.load(path)
	cf.set_value(CONFIG_SECTION, KEY_REDUCE, reduce_motion)
	cf.set_value(CONFIG_SECTION, KEY_SHAKE, camera_shake)
	cf.set_value(CONFIG_SECTION, KEY_HITSTOP, hit_stop)
	return cf.save(path)


static func resolve_startup(args: PackedStringArray, path: String = QualitySettings.CONFIG_PATH) -> void:
	reset()
	load_saved(path)
	var a: int = reduce_from_args(args)
	if a >= 0:
		reduce_motion = a == 1
