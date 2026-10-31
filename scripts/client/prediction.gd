class_name Prediction
extends RefCounted
## Predicao do movimento do jogador local + reconciliacao por last_input_seq.
## LIMITACAO: sem colisao/gravidade/degraus no cliente. O replay re-aplica apenas o movimento
## plano (PlayerMotion.world_direction * velocidade * dt) dos inputs ainda nao confirmados sobre a
## posicao do servidor. Y vem sempre do servidor. Dodge/skills com deslocamento nao sao previstos.

const BASE_SPEED: float = 6.0
const DEADZONE: float = 0.05      # erro menor que isso e ignorado (m)
const SNAP_DISTANCE: float = 2.0  # erro maior que isso teleporta (m)
const SMOOTH_RATE: float = 10.0   # 1/s da correcao suave
const MAX_PENDING: int = 120

var speed: float = BASE_SPEED
var pos: Vector3 = Vector3.ZERO
var initialized: bool = false
var snaps: int = 0
var smooth_corrections: int = 0

var _pending: Array[Dictionary] = []  # {seq, step: Vector3}
var _correction: Vector3 = Vector3.ZERO


func init_at(p: Vector3) -> void:
	pos = p
	initialized = true
	_pending.clear()
	_correction = Vector3.ZERO


## Aplica um input predito (dt em s). move e a entrada local; yaw a base de movimento.
func apply_input(seq: int, move: Vector2, yaw: float, dt: float) -> void:
	if not initialized:
		return
	if not (is_finite(move.x) and is_finite(move.y) and is_finite(yaw)):
		return
	var step: Vector3 = PlayerMotion.world_direction(move, yaw) * speed * dt
	pos += step
	_pending.append({"seq": seq, "step": step})
	while _pending.size() > MAX_PENDING:
		_pending.remove_at(0)


func pending_count() -> int:
	return _pending.size()


## server_pos: posicao autoritativa do jogador local no snapshot; last_seq: ultimo input processado.
func reconcile(server_pos: Vector3, last_seq: int) -> void:
	if not initialized:
		init_at(server_pos)
		return
	while not _pending.is_empty() and int(_pending[0]["seq"]) <= last_seq:
		_pending.remove_at(0)
	var expected: Vector3 = server_pos
	for p: Dictionary in _pending:
		expected += p["step"] as Vector3
	var err: Vector3 = expected - (pos + _correction)
	err.y = 0.0
	var dist: float = err.length()
	if dist > SNAP_DISTANCE:
		pos = Vector3(expected.x, server_pos.y, expected.z)
		_correction = Vector3.ZERO
		snaps += 1
	elif dist > DEADZONE:
		_correction = err
		smooth_corrections += 1
	else:
		_correction = Vector3.ZERO
	pos.y = server_pos.y


## Aplica a correcao suave pendente (chamar todo frame).
func update(dt: float) -> void:
	if _correction.length_squared() < 0.0000001:
		return
	var w: float = 1.0 - exp(-SMOOTH_RATE * dt)
	var d: Vector3 = _correction * w
	pos += d
	_correction -= d
