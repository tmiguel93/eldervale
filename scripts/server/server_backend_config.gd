class_name ServerBackendConfig
extends RefCounted
## Configuracao do servidor para falar com o backend (E4). Origem: argumentos extras do server_main
## (apos `--`) e ambiente ELDERVALE_*. O SEGREDO so vem do ambiente (ELDERVALE_INTERNAL_SECRET):
## nao existe argumento de CLI para ele e ele nunca e impresso.
## Backend habilitado <=> backend_url nao vazia. Sem backend EXIGE-SE modo dev explicito (M6): URL
## ausente por typo/ambiente vazio nao pode abrir o servidor sem ticket nem persistencia.

const ARG_KEYS: Array[String] = [
	"backend-url", "public-endpoint", "region", "session-id-file",
	"heartbeat-interval", "autosave-interval", "redeem-timeout", "max-pending", "shutdown-timeout", "dev-mode",
]
const ENV_KEYS: Dictionary = {
	"backend-url": "ELDERVALE_BACKEND_URL", "public-endpoint": "ELDERVALE_PUBLIC_ENDPOINT",
	"region": "ELDERVALE_REGION", "session-id-file": "ELDERVALE_SESSION_ID_FILE",
	"heartbeat-interval": "ELDERVALE_HEARTBEAT_INTERVAL", "autosave-interval": "ELDERVALE_AUTOSAVE_INTERVAL",
	"redeem-timeout": "ELDERVALE_REDEEM_TIMEOUT", "max-pending": "ELDERVALE_MAX_PENDING",
	"shutdown-timeout": "ELDERVALE_SHUTDOWN_TIMEOUT", "dev-mode": "ELDERVALE_DEV_MODE",
}
const SECRET_ENV: String = "ELDERVALE_INTERNAL_SECRET"

var backend_url: String = ""
var public_endpoint: String = ""
var region: String = "local"
var session_id_file: String = ""
var heartbeat_interval_sec: float = 10.0
var autosave_interval_sec: float = 30.0
var redeem_timeout_sec: float = 8.0
var max_pending: int = 8
var shutdown_timeout_sec: float = 8.0
var dev_mode: bool = false ## modo dev EXPLICITO: sem backend, sem ticket, nada persiste
var secret: String = "" ## NUNCA imprimir
var errors: PackedStringArray = PackedStringArray()


func enabled() -> bool:
	return not backend_url.is_empty()


## `values`: chave (sem `--`) -> String vindos da CLI; `env`: nome de variavel -> String.
## `port`/`max_players` servem para o endpoint padrao e a capacidade.
static func parse(values: Dictionary, env: Dictionary, port: int) -> ServerBackendConfig:
	var c: ServerBackendConfig = ServerBackendConfig.new()
	var v: Dictionary = {}
	for k: String in ENV_KEYS:
		if env.has(ENV_KEYS[k]):
			v[k] = str(env[ENV_KEYS[k]])
	for k: String in values:
		if ARG_KEYS.has(k):
			v[k] = str(values[k])
	c.secret = str(env.get(SECRET_ENV, ""))
	c.backend_url = str(v.get("backend-url", "")).strip_edges()
	var dm: String = str(v.get("dev-mode", "")).strip_edges().to_lower()
	c.dev_mode = dm == "1" or dm == "true"
	if not c.enabled() and not c.dev_mode:
		c.errors.append("backend-url ausente: informe ELDERVALE_BACKEND_URL (producao) ou habilite o modo dev explicitamente (--dev-mode 1 / ELDERVALE_DEV_MODE=1)")
	if c.enabled() and c.dev_mode:
		c.errors.append("dev-mode e backend-url sao mutuamente exclusivos")
	if c.enabled():
		var err: String = BackendClient.validate_url(c.backend_url)
		if not err.is_empty():
			c.errors.append(err)
		if c.secret.strip_edges().is_empty():
			c.errors.append("%s ausente (o segredo so e aceito por variavel de ambiente)" % SECRET_ENV)
	c.public_endpoint = str(v.get("public-endpoint", "127.0.0.1:%d" % port)).strip_edges()
	if not _valid_endpoint(c.public_endpoint):
		c.errors.append("public-endpoint invalido (use host:porta)")
		c.public_endpoint = "127.0.0.1:%d" % port
	c.region = str(v.get("region", c.region)).strip_edges().to_lower()
	if not _valid_region(c.region):
		c.errors.append("region invalida ([a-z0-9-]{2,32})")
		c.region = "local"
	if v.has("session-id-file"):
		var p: String = str(v["session-id-file"])
		var bad: bool = p.is_empty() or p.length() > 260
		for i: int in p.length():
			if p.unicode_at(i) < 32:
				bad = true
		if bad:
			c.errors.append("session-id-file: caminho invalido")
		else:
			c.session_id_file = p
	c.heartbeat_interval_sec = _num(v, "heartbeat-interval", 1.0, 300.0, c.heartbeat_interval_sec, c.errors)
	c.autosave_interval_sec = _num(v, "autosave-interval", 1.0, 3600.0, c.autosave_interval_sec, c.errors)
	c.redeem_timeout_sec = _num(v, "redeem-timeout", 1.0, 60.0, c.redeem_timeout_sec, c.errors)
	c.shutdown_timeout_sec = _num(v, "shutdown-timeout", 1.0, 60.0, c.shutdown_timeout_sec, c.errors)
	c.max_pending = int(_num(v, "max-pending", 1.0, 64.0, float(c.max_pending), c.errors))
	return c


static func _num(v: Dictionary, key: String, lo: float, hi: float, default_value: float, errors: PackedStringArray) -> float:
	if not v.has(key):
		return default_value
	var s: String = str(v[key]).strip_edges()
	if not s.is_valid_float() or s.to_float() < lo or s.to_float() > hi:
		errors.append("%s: fora da faixa %s..%s" % [key, lo, hi])
		return default_value
	return s.to_float()


static func _valid_region(r: String) -> bool:
	if r.length() < 2 or r.length() > 32:
		return false
	for i: int in r.length():
		var ch: int = r.unicode_at(i)
		if not ((ch >= 48 and ch <= 57) or (ch >= 97 and ch <= 122) or ch == 45):
			return false
	return true


static func _valid_endpoint(e: String) -> bool:
	var idx: int = e.rfind(":")
	if idx <= 0 or idx == e.length() - 1:
		return false
	var host: String = e.substr(0, idx)
	var port: String = e.substr(idx + 1)
	if not port.is_valid_int() or port.to_int() < 1 or port.to_int() > 65535:
		return false
	for i: int in host.length():
		var ch: int = host.unicode_at(i)
		if not ((ch >= 48 and ch <= 57) or (ch >= 65 and ch <= 90) or (ch >= 97 and ch <= 122) or ch == 46 or ch == 45 or ch == 95):
			return false
	return true
