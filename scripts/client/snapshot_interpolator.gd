class_name SnapshotInterpolator
extends RefCounted
## Interpolador de snapshots (puro, sem nos). Guarda uma janela de snapshots e responde
## `sample(now_ms)` com o estado de cada entidade em (agora - delay).
## Relogio: o tempo do servidor de cada snapshot e server_tick*1000/tick_rate. O offset
## local-servidor e estimado a partir do horario de chegada (cai rapido, sobe devagar), o que
## filtra jitter sem depender de relogios sincronizados.
## Entidades ausentes do snapshot mais recente somem assim que o tempo de render o alcanca.

const DEFAULT_DELAY_MS: float = 100.0
const DEFAULT_MAX_EXTRAPOLATION_MS: float = 150.0
const MAX_SNAPSHOTS: int = 64

var delay_ms: float = DEFAULT_DELAY_MS
var max_extrapolation_ms: float = DEFAULT_MAX_EXTRAPOLATION_MS
var tick_rate: int = 30

var last_tick: int = -1
var accepted: int = 0
var discarded: int = 0

var _snaps: Array[Dictionary] = []  # {t: float, tick: int, ents: Dictionary id -> Dictionary}
var _offset: float = 0.0
var _has_offset: bool = false


func configure(p_tick_rate: int, p_delay_ms: float = DEFAULT_DELAY_MS, p_max_extrap_ms: float = DEFAULT_MAX_EXTRAPOLATION_MS) -> void:
	tick_rate = maxi(p_tick_rate, 1)
	delay_ms = maxf(p_delay_ms, 0.0)
	max_extrapolation_ms = maxf(p_max_extrap_ms, 0.0)


func reset() -> void:
	_snaps.clear()
	last_tick = -1
	_has_offset = false


func snapshot_count() -> int:
	return _snaps.size()


## Retorna false (e descarta) se o tick for <= ao ultimo aceito (velho/duplicado/fora de ordem).
func push(server_tick: int, recv_ms: float, entities: Array) -> bool:
	if server_tick <= last_tick:
		discarded += 1
		return false
	var t: float = float(server_tick) * 1000.0 / float(tick_rate)
	var sample_offset: float = recv_ms - t
	if not _has_offset:
		_offset = sample_offset
		_has_offset = true
	elif sample_offset < _offset:
		_offset = sample_offset
	else:
		_offset += (sample_offset - _offset) * 0.05
	var ents: Dictionary = {}
	for e: Variant in entities:
		if e is Dictionary and (e as Dictionary).has("id"):
			ents[int((e as Dictionary)["id"])] = e
	_snaps.append({"t": t, "tick": server_tick, "ents": ents})
	last_tick = server_tick
	accepted += 1
	while _snaps.size() > MAX_SNAPSHOTS:
		_snaps.remove_at(0)
	return true


## Tempo de render no relogio do servidor (ms) para o instante local `now_ms`.
func render_time(now_ms: float) -> float:
	return now_ms - _offset - delay_ms


## Retorna id -> {pos, yaw, hp, max_hp, state, type, kind, extrapolated}.
func sample(now_ms: float) -> Dictionary:
	var out: Dictionary = {}
	if _snaps.is_empty() or not _has_offset:
		return out
	var rt: float = render_time(now_ms)
	# a = ultimo snapshot com t <= rt (ou o primeiro, se rt for anterior a todos)
	var ia: int = 0
	for i: int in _snaps.size():
		if (_snaps[i]["t"] as float) <= rt:
			ia = i
		else:
			break
	var a: Dictionary = _snaps[ia]
	var ents_a: Dictionary = a["ents"]
	if rt <= (a["t"] as float) and ia == 0:
		for id: Variant in ents_a:
			out[id] = _view(ents_a[id], (ents_a[id] as Dictionary)["pos"], false)
		return out
	if ia + 1 < _snaps.size():
		var b: Dictionary = _snaps[ia + 1]
		var span: float = (b["t"] as float) - (a["t"] as float)
		var f: float = clampf((rt - (a["t"] as float)) / span, 0.0, 1.0) if span > 0.0 else 1.0
		var ents_b: Dictionary = b["ents"]
		for id: Variant in ents_a:
			if not ents_b.has(id):
				# sumiu em b: mantem em a ate b ser alcancado (sempre, aqui, pois rt < b.t)
				out[id] = _view(ents_a[id], (ents_a[id] as Dictionary)["pos"], false)
				continue
			var ea: Dictionary = ents_a[id]
			var eb: Dictionary = ents_b[id]
			var pos: Vector3 = (ea["pos"] as Vector3).lerp(eb["pos"] as Vector3, f)
			var v: Dictionary = _view(eb, pos, false)
			v["yaw"] = lerp_angle(float(ea.get("yaw", 0.0)), float(eb.get("yaw", 0.0)), f)
			v["hp"] = lerpf(float(ea.get("hp", 0.0)), float(eb.get("hp", 0.0)), f)
			out[id] = v
		return out
	# rt alem do snapshot mais novo: extrapolacao limitada por velocidade do par anterior
	var ahead: float = rt - (a["t"] as float)
	var ext_ms: float = minf(ahead, max_extrapolation_ms)
	var prev: Dictionary = _snaps[ia - 1] if ia > 0 else {}
	for id: Variant in ents_a:
		var ea2: Dictionary = ents_a[id]
		var pos2: Vector3 = ea2["pos"] as Vector3
		var extrapolated: bool = false
		if ext_ms > 0.0 and not prev.is_empty() and (prev["ents"] as Dictionary).has(id):
			var ep: Dictionary = (prev["ents"] as Dictionary)[id]
			var dt: float = ((a["t"] as float) - (prev["t"] as float)) / 1000.0
			if dt > 0.0:
				var vel: Vector3 = ((ea2["pos"] as Vector3) - (ep["pos"] as Vector3)) / dt
				pos2 = pos2 + vel * (ext_ms / 1000.0)
				extrapolated = true
		out[id] = _view(ea2, pos2, extrapolated)
	return out


func _view(e: Dictionary, pos: Vector3, extrapolated: bool) -> Dictionary:
	return {
		"pos": pos,
		"yaw": float(e.get("yaw", 0.0)),
		"hp": float(e.get("hp", 0.0)),
		"max_hp": float(e.get("max_hp", 0.0)),
		"state": int(e.get("state", 0)),
		"type": String(e.get("type", "")),
		"kind": int(e.get("kind", 0)),
		"extrapolated": extrapolated,
	}
