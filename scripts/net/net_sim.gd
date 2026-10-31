class_name NetSim
extends RefCounted
## Simulador de latencia/jitter/perda na camada de aplicacao. Tempo injetado, deterministico por seed.
## reliable: nunca perde, ordem preservada (so atrasa). unreliable: pode perder e reordenar por jitter.

var latency_ms: int = 0
var jitter_ms: int = 0
var loss_pct: float = 0.0
var dropped: int = 0
var delivered: int = 0

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _queue: Array[Dictionary] = []
var _counter: int = 0
var _last_reliable_due: int = 0


func configure(p_latency_ms: int, p_jitter_ms: int, p_loss_pct: float, p_seed: int) -> void:
	latency_ms = maxi(p_latency_ms, 0)
	jitter_ms = maxi(p_jitter_ms, 0)
	loss_pct = clampf(p_loss_pct, 0.0, 100.0)
	_rng.seed = p_seed
	_queue.clear()
	_counter = 0
	_last_reliable_due = 0
	dropped = 0
	delivered = 0


func pending() -> int:
	return _queue.size()


func submit(callable: Callable, reliable: bool, now_msec: int) -> void:
	var jitter: int = 0
	if jitter_ms > 0:
		jitter = _rng.randi_range(0, jitter_ms)
	if not reliable and loss_pct > 0.0 and _rng.randf() * 100.0 < loss_pct:
		dropped += 1
		return
	var due: int = now_msec + latency_ms + jitter
	if reliable:
		due = maxi(due, _last_reliable_due)
		_last_reliable_due = due
	_queue.append({"due": due, "n": _counter, "call": callable})
	_counter += 1


func pump(now_msec: int) -> void:
	if _queue.is_empty():
		return
	var ready: Array[Dictionary] = []
	var rest: Array[Dictionary] = []
	for item: Dictionary in _queue:
		if int(item["due"]) <= now_msec:
			ready.append(item)
		else:
			rest.append(item)
	_queue = rest
	ready.sort_custom(_by_due)
	for item: Dictionary in ready:
		var c: Callable = item["call"]
		if c.is_valid():
			delivered += 1
			c.call()


static func _by_due(a: Dictionary, b: Dictionary) -> bool:
	if int(a["due"]) != int(b["due"]):
		return int(a["due"]) < int(b["due"])
	return int(a["n"]) < int(b["n"])
