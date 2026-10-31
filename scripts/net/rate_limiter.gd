class_name RateLimiter
extends RefCounted
## Token bucket. Um por peer e por tipo de mensagem. Tempo injetado (deterministico).

var rate_per_sec: float
var burst: int
var _tokens: float
var _last_msec: int = -1


func _init(p_rate_per_sec: float = 1.0, p_burst: int = 1) -> void:
	rate_per_sec = maxf(p_rate_per_sec, 0.0)
	burst = maxi(p_burst, 1)
	_tokens = float(burst)


func allow(now_msec: int) -> bool:
	if _last_msec >= 0 and now_msec > _last_msec:
		_tokens = minf(float(burst), _tokens + float(now_msec - _last_msec) * 0.001 * rate_per_sec)
	if _last_msec < 0 or now_msec > _last_msec:
		_last_msec = now_msec
	if _tokens >= 1.0:
		_tokens -= 1.0
		return true
	return false
