class_name BotResult
extends RefCounted
## Acumulador do relatorio de um bot/cliente. to_dict() e JSON-seguro.

var bot: String = ""
var connected: bool = false
var welcome: Dictionary = {}          # {player_id, tick_rate}
var rejected: Dictionary = {}         # {code, message}
var disconnected: bool = false
var snapshots_received: int = 0
var last_server_tick: int = -1
var max_snapshot_gap_ms: float = 0.0
var positions: Array = []             # [{t, x, y, z}] amostradas
var entities_seen: Dictionary = {}    # "id" -> {kind, type}
var events_by_kind: Dictionary = {}   # "kind" -> contagem
var rtt_samples: Array[float] = []
var inputs_sent: int = 0
var errors: Array[String] = []
var elapsed_s: float = 0.0

var _last_snapshot_ms: float = -1.0
var _last_pos_sample_s: float = -1.0e9


func on_welcome(player_id: int, tick_rate: int) -> void:
	connected = true
	welcome = {"player_id": player_id, "tick_rate": tick_rate}


func on_reject(code: int, message: String) -> void:
	rejected = {"code": code, "message": message}


func on_snapshot(now_ms: float, server_tick: int, entities: Array) -> void:
	snapshots_received += 1
	last_server_tick = maxi(last_server_tick, server_tick)
	if _last_snapshot_ms >= 0.0:
		max_snapshot_gap_ms = maxf(max_snapshot_gap_ms, now_ms - _last_snapshot_ms)
	_last_snapshot_ms = now_ms
	for e: Variant in entities:
		if e is Dictionary and (e as Dictionary).has("id"):
			var d: Dictionary = e
			entities_seen[str(int(d["id"]))] = {"kind": int(d.get("kind", 0)), "type": String(d.get("type", ""))}


func on_event(kind: int) -> void:
	var k: String = str(kind)
	events_by_kind[k] = int(events_by_kind.get(k, 0)) + 1


func on_rtt(ms: float) -> void:
	rtt_samples.append(ms)


## Amostra posicao local no maximo a cada `every_s` segundos.
func sample_position(t_s: float, p: Vector3, every_s: float = 0.5) -> void:
	if t_s - _last_pos_sample_s >= every_s:
		_last_pos_sample_s = t_s
		positions.append({"t": snappedf(t_s, 0.001), "x": p.x, "y": p.y, "z": p.z})


func rtt_avg_ms() -> float:
	if rtt_samples.is_empty():
		return -1.0
	var s: float = 0.0
	for v: float in rtt_samples:
		s += v
	return s / float(rtt_samples.size())


func to_dict() -> Dictionary:
	return {
		"bot": bot,
		"connected": connected,
		"welcome": welcome,
		"rejected": rejected,
		"disconnected": disconnected,
		"snapshots_received": snapshots_received,
		"last_server_tick": last_server_tick,
		"max_snapshot_gap_ms": max_snapshot_gap_ms,
		"positions": positions,
		"entities_seen": entities_seen,
		"events_by_kind": events_by_kind,
		"rtt_avg_ms": rtt_avg_ms(),
		"rtt_samples": rtt_samples.size(),
		"inputs_sent": inputs_sent,
		"errors": errors,
		"elapsed_s": elapsed_s,
	}


func to_json() -> String:
	return JSON.stringify(to_dict(), "  ")
