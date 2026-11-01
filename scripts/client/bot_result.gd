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
# --- E4 (backend) ---
var login_ok: bool = false
var character_id: String = ""
var session_id: String = ""
var ticket_used_ok: bool = false     # o servidor aceitou (welcome) uma conexao com ticket
var flow_error: String = ""          # codigo do erro do fluxo de backend (sem dados sensiveis)
var attempts: Array = []             # replay_ticket: resultado de cada conexao [{connected, rejected}]
var kills: int = 0                   # mortes de inimigo observadas (kill_enemy)
var character_final: Dictionary = {} # GET /v1/characters/:id apos sair: {level, xp, revision, items}
var elapsed_s: float = 0.0
# --- E5.3 (mundo em zonas) ---
var zones_seen: Array[String] = []   # zonas em que o servidor confirmou a chegada (evento zone), em ordem
var puzzle_open_seen: bool = false   # recebeu puzzle_state com o portao aberto
var respawns: int = 0                # eventos respawn do proprio jogador
var boss_states: Array[int] = []     # estados de chefe recebidos (0 armado, 1 ativo, 2 derrotado)
var tour_done: bool = false          # world_tour: chegou ao salao do chefe

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


## E5.3: acumula o que o bot viu do mundo (so eventos validados pela sessao).
func on_world_event(kind: int, data: Dictionary, my_id: int) -> void:
	match kind:
		Protocol.EVENT_ZONE:
			if int(data.get("id", -1)) == my_id and int(data.get("phase", -1)) == Protocol.ZONE_PHASE_ARRIVED:
				var z: String = String(data.get("zone", ""))
				if zones_seen.is_empty() or zones_seen[zones_seen.size() - 1] != z:
					zones_seen.append(z)
		Protocol.EVENT_PUZZLE:
			if bool(data.get("open", false)):
				puzzle_open_seen = true
		Protocol.EVENT_RESPAWN:
			if int(data.get("id", -1)) == my_id:
				respawns += 1
		Protocol.EVENT_BOSS:
			boss_states.append(int(data.get("state", -1)))


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


func _events_total() -> int:
	var n: int = 0
	for k: String in events_by_kind:
		n += int(events_by_kind[k])
	return n


## Resumo seguro do personagem (GET /v1/characters/:id) para o relatorio.
func set_character_final(c: Dictionary) -> void:
	var items: int = 0
	if c.get("inventory") is Array:
		for it: Variant in c["inventory"]:
			if it is Dictionary:
				items += int((it as Dictionary).get("qty", 0))
	character_final = {"level": int(c.get("level", 0)), "xp": int(c.get("xp", 0)), "revision": int(c.get("revision", 0)), "inventory_qty": items}


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
		"login_ok": login_ok,
		"character_id": character_id,
		"session_id": session_id,
		"ticket_used_ok": ticket_used_ok,
		"flow_error": flow_error,
		"attempts": attempts,
		"kills": kills,
		"events_total": _events_total(),
		"character_final": character_final,
		"xp": int(character_final.get("xp", -1)),
		"level": int(character_final.get("level", -1)),
		"elapsed_s": elapsed_s,
		"world": {"zones": zones_seen, "puzzle_open": puzzle_open_seen, "respawns": respawns, "boss_states": boss_states, "tour_done": tour_done},
	}


func to_json() -> String:
	return JSON.stringify(to_dict(), "  ")
