class_name NetConfig
extends RefCounted
## Configuracao de rede a partir de argumentos (`--chave valor` ou `--chave=valor`) e ELDERVALE_*.
## Argumentos tem precedencia sobre ambiente. Invalido -> default + entrada em `errors`. Sem segredos.

const ROLE_SERVER: String = "server"
const ROLE_CLIENT: String = "client"

var role: String = ROLE_CLIENT
var host: String = "127.0.0.1"
var port: int = Protocol.DEFAULT_PORT
var max_players: int = 4
var tick_rate: int = 30
var snapshot_rate: int = 15
var sim_latency_ms: int = 0
var sim_jitter_ms: int = 0
var sim_loss_pct: float = 0.0
var name: String = "Player"
var bot_script: String = ""
var out_path: String = ""
var errors: PackedStringArray = PackedStringArray()

const _ENV_KEYS: Dictionary = {
	"role": "ELDERVALE_ROLE", "host": "ELDERVALE_HOST", "port": "ELDERVALE_PORT",
	"max-players": "ELDERVALE_MAX_PLAYERS", "tick-rate": "ELDERVALE_TICK_RATE",
	"snapshot-rate": "ELDERVALE_SNAPSHOT_RATE", "sim-latency-ms": "ELDERVALE_SIM_LATENCY_MS",
	"sim-jitter-ms": "ELDERVALE_SIM_JITTER_MS", "sim-loss-pct": "ELDERVALE_SIM_LOSS_PCT",
	"name": "ELDERVALE_NAME", "bot": "ELDERVALE_BOT", "out": "ELDERVALE_OUT",
}


## Le OS.get_cmdline_user_args() (argumentos apos `--`) e o ambiente real.
static func from_environment() -> NetConfig:
	var env: Dictionary = {}
	for k: String in _ENV_KEYS:
		var ev: String = _ENV_KEYS[k]
		if OS.has_environment(ev):
			env[ev] = OS.get_environment(ev)
	return parse(OS.get_cmdline_user_args(), env)


static func parse(args: PackedStringArray, env: Dictionary = {}) -> NetConfig:
	var cfg: NetConfig = NetConfig.new()
	var values: Dictionary = {}  # chave -> String
	for k: String in _ENV_KEYS:
		var ev: String = _ENV_KEYS[k]
		if env.has(ev):
			values[k] = str(env[ev])
	var i: int = 0
	while i < args.size():
		var a: String = args[i]
		i += 1
		if not a.begins_with("--"):
			cfg.errors.append("argumento ignorado: " + a)
			continue
		var key: String = a.substr(2)
		var val: String = ""
		var eq: int = key.find("=")
		if eq >= 0:
			val = key.substr(eq + 1)
			key = key.substr(0, eq)
		elif i < args.size() and not args[i].begins_with("--"):
			val = args[i]
			i += 1
		else:
			cfg.errors.append("--%s sem valor" % key)
			continue
		key = key.replace("_", "-")
		if not _ENV_KEYS.has(key):
			cfg.errors.append("chave desconhecida: --" + key)
			continue
		values[key] = val
	cfg._apply(values)
	return cfg


func _int_in(values: Dictionary, key: String, lo: int, hi: int, default_value: int) -> int:
	if not values.has(key):
		return default_value
	var s: String = str(values[key]).strip_edges()
	if not s.is_valid_int():
		errors.append("%s: inteiro invalido" % key)
		return default_value
	var v: int = s.to_int()
	if v < lo or v > hi:
		errors.append("%s: fora da faixa %d..%d" % [key, lo, hi])
		return default_value
	return v


func _apply(values: Dictionary) -> void:
	if values.has("role"):
		var r: String = str(values["role"]).strip_edges().to_lower()
		if r == ROLE_SERVER or r == ROLE_CLIENT:
			role = r
		else:
			errors.append("role: use server ou client")
	if values.has("host"):
		var h: String = str(values["host"]).strip_edges()
		if _valid_host(h):
			host = h
		else:
			errors.append("host: invalido")
	port = _int_in(values, "port", 1024, 65535, port)
	max_players = _int_in(values, "max-players", 1, 32, max_players)
	tick_rate = _int_in(values, "tick-rate", 10, 120, tick_rate)
	snapshot_rate = _int_in(values, "snapshot-rate", 1, 120, snapshot_rate)
	if snapshot_rate > tick_rate:
		errors.append("snapshot-rate: maior que tick-rate")
		snapshot_rate = mini(15, tick_rate)
	sim_latency_ms = _int_in(values, "sim-latency-ms", 0, 2000, sim_latency_ms)
	sim_jitter_ms = _int_in(values, "sim-jitter-ms", 0, 1000, sim_jitter_ms)
	if values.has("sim-loss-pct"):
		var s: String = str(values["sim-loss-pct"]).strip_edges()
		if s.is_valid_float() and Protocol.is_finite_number(s.to_float()) and s.to_float() >= 0.0 and s.to_float() <= 100.0:
			sim_loss_pct = s.to_float()
		else:
			errors.append("sim-loss-pct: fora da faixa 0..100")
	if values.has("name"):
		var n: Dictionary = Protocol.validate_name(values["name"])
		if bool(n["ok"]):
			name = n["name"]
		else:
			errors.append("name: invalido")
	if values.has("bot"):
		bot_script = _path_or_error(str(values["bot"]), "bot", bot_script)
	if values.has("out"):
		out_path = _path_or_error(str(values["out"]), "out", out_path)


func _path_or_error(p: String, key: String, default_value: String) -> String:
	var bad: bool = p.length() > 260
	for i: int in p.length():
		if p.unicode_at(i) < 32:
			bad = true
	if bad:
		errors.append("%s: caminho invalido" % key)
		return default_value
	return p


static func _valid_host(h: String) -> bool:
	if h.is_empty() or h.length() > 253:
		return false
	for i: int in h.length():
		var c: int = h.unicode_at(i)
		var okc: bool = (c >= 48 and c <= 58) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c == 46 or c == 45 or c == 95
		if not okc:
			return false
	return true
