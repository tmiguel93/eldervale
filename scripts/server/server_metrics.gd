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
	"pois_discovered", "talents", "equips", "crafts"]

var counters: Dictionary = {} ## "categoria|nome" -> int
var dropped_keys: int = 0
var interval_sec: float = 60.0
var _start_msec: int = 0
var _last_log_msec: int = 0
var lines_logged: int = 0


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
	return {"uptime_s": snappedf(float(now_msec - _start_msec) / 1000.0, 0.1), "counters": nested, "dropped_keys": dropped_keys}


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
