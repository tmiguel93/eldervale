class_name ServerMetrics
extends RefCounted
## E6.5: telemetria essencial do servidor de jogo. Contadores SIMPLES em memoria (sem servico externo, sem custo, sem dados pessoais):
## a chave e (categoria, nome) com nomes vindos so de DADOS do jogo (class_id, skill_id, enemy_type, rarity, quest_id...), nunca de
## nome de jogador, e-mail, ticket, token, id de personagem ou de sessao. Saida: uma linha de log estruturada (JSON) a cada
## `interval_sec` (e uma final no shutdown): `[metrics] {"uptime_s":..,"counters":{"kills":{"melee_grunt":12},...}}`.
## Protecao de memoria: no maximo MAX_KEYS chaves distintas; as excedentes somam em `dropped_keys` (nao em novas chaves).
## Exemplo de uso para balanceamento: `skill_use.<classe>.<habilidade>`, `kills.<tipo>`, `drops_rarity.<raridade>`, `quests_completed.<quest>`.

const MAX_KEYS: int = 512
const MAX_NAME_LEN: int = 64
const CATEGORIES: Array[String] = ["joins", "skill_use", "kills", "xp_from_kills", "drops_rarity", "drops_unique", "drops_items", "quests_completed",
	"pois_discovered", "talents", "equips", "crafts",
	# E7.1 (operacional): rejeicoes por codigo de protocolo / limite de conexao, reconexoes e saidas de jogadores.
	"rejects", "reconnects", "disconnects"]
## E7.1: series de medicao (janela deslizante das ultimas SERIES_MAX amostras): p50/p95/max/media. Nomes fixos (sem dado livre).
const SERIES_NAMES: Array[String] = ["tick_ms", "tick_dt_ms", "snapshot_bytes"]
const SERIES_MAX: int = 600

var counters: Dictionary = {} ## "categoria|nome" -> int
var dropped_keys: int = 0
var interval_sec: float = 60.0
var _start_msec: int = 0
var _last_log_msec: int = 0
var lines_logged: int = 0
## E7.1: devolve gauges instantaneos ({players_online, peers, pending, ...}); definido pela sessao.
var gauge_provider: Callable = Callable()
var _series: Dictionary = {} ## nome -> Array[float] (anel)
var _series_pos: Dictionary = {} ## nome -> proxima posicao a sobrescrever


func _init(p_interval_sec: float = 60.0, now_msec: int = 0) -> void:
	interval_sec = p_interval_sec
	_start_msec = now_msec
	_last_log_msec = now_msec


## Nome seguro: so [a-z0-9_.], minusculo, truncado; vazio vira "unknown". Garante que nada livre (ex.: texto de jogador) vire chave.
static func sanitize(raw: String) -> String:
	var out: String = ""
	for i: int in mini(raw.length(), MAX_NAME_LEN):
		var c: String = raw.substr(i, 1).to_lower()
		out += c if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") or c == "_" or c == "." else "_"
	return out if not out.is_empty() else "unknown"


func inc(category: String, name: String, amount: int = 1) -> void:
	if amount <= 0 or not CATEGORIES.has(category):
		return
	var key: String = "%s|%s" % [category, sanitize(name)]
	if not counters.has(key):
		if counters.size() >= MAX_KEYS:
			dropped_keys += 1
			return
		counters[key] = 0
	counters[key] = int(counters[key]) + amount


func get_count(category: String, name: String) -> int:
	return int(counters.get("%s|%s" % [category, sanitize(name)], 0))


func total(category: String) -> int:
	var t: int = 0
	for key: Variant in counters:
		if String(key).begins_with(category + "|"):
			t += int(counters[key])
	return t


## E7.1: registra uma amostra de uma das SERIES_NAMES (ignora nome desconhecido, NaN e negativos).
func observe(series: String, value: float) -> void:
	if not SERIES_NAMES.has(series) or is_nan(value) or is_inf(value) or value < 0.0:
		return
	var ring: Array = _series.get(series, [])
	if ring.size() < SERIES_MAX:
		ring.append(value)
	else:
		var pos: int = int(_series_pos.get(series, 0))
		ring[pos] = value
		_series_pos[series] = (pos + 1) % SERIES_MAX
	_series[series] = ring


## {count, avg, p50, p95, max} da serie (zeros se vazia). Percentil por posto: indice floor(p * n) do vetor ordenado.
func series_stats(series: String) -> Dictionary:
	var ring: Array = _series.get(series, [])
	if ring.is_empty():
		return {"count": 0, "avg": 0.0, "p50": 0.0, "p95": 0.0, "max": 0.0}
	var sorted: Array = ring.duplicate()
	sorted.sort()
	var n: int = sorted.size()
	var sum: float = 0.0
	for v: Variant in sorted:
		sum += float(v)
	return {"count": n, "avg": snappedf(sum / float(n), 0.01), "p50": snappedf(float(sorted[mini(n - 1, int(0.5 * n))]), 0.01),
		"p95": snappedf(float(sorted[mini(n - 1, int(0.95 * n))]), 0.01), "max": snappedf(float(sorted[n - 1]), 0.01)}


## {uptime_s, counters: {categoria: {nome: n}}, dropped_keys}. Chaves ordenadas (saida estavel).
func snapshot(now_msec: int) -> Dictionary:
	var nested: Dictionary = {}
	var keys: Array = counters.keys()
	keys.sort()
	for key: Variant in keys:
		var parts: PackedStringArray = String(key).split("|", true, 1)
		if not nested.has(parts[0]):
			nested[parts[0]] = {}
		(nested[parts[0]] as Dictionary)[parts[1]] = int(counters[key])
	var timings: Dictionary = {}
	for name: String in SERIES_NAMES:
		timings[name] = series_stats(name)
	var gauges: Dictionary = {}
	if gauge_provider.is_valid():
		var g: Variant = gauge_provider.call()
		if typeof(g) == TYPE_DICTIONARY:
			gauges = g
	return {"uptime_s": snappedf(float(now_msec - _start_msec) / 1000.0, 0.1), "counters": nested, "dropped_keys": dropped_keys,
		"gauges": gauges, "timings": timings}


func line(now_msec: int) -> String:
	return "[metrics] " + JSON.stringify(snapshot(now_msec), "", true)


## Chamado a cada tick: emite a linha periodica quando o intervalo passou (interval_sec <= 0 desliga o periodico). true se logou.
func tick(now_msec: int) -> bool:
	if interval_sec <= 0.0 or float(now_msec - _last_log_msec) < interval_sec * 1000.0:
		return false
	_last_log_msec = now_msec
	emit(now_msec)
	return true


func emit(now_msec: int) -> void:
	lines_logged += 1
	ServerLog.info(line(now_msec))
