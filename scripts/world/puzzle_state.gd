class_name PuzzleState
extends RefCounted
## Puzzle cooperativo de placas de pressao (logica PURA, servidor autoritativo). N placas; o portao abre
## quando TODAS estao acesas ao mesmo tempo. Cada placa fica acesa enquanto alguem a pisa e por mais
## `latch_time` s depois (trava temporizada): um jogador sozinho consegue correr de uma placa a outra
## dentro da janela; em grupo, dois jogadores podem ficar parados nas placas. O que NAO existe: reset
## por rede, fechar o portao com gente dentro. Depois de aberto o portao PERMANECE aberto ate `reset()`
## (feito pelo diretor quando a zona fica vazia / e descarregada) => sem softlock no salao do chefe.
## Estados: IDLE (nenhuma acesa), PARTIAL (algumas), OPEN (portao aberto).

enum State { IDLE, PARTIAL, OPEN }

const PLATE_HEIGHT_TOLERANCE: float = 2.0

var puzzle_id: String = ""
var plates: Array[Dictionary] = []   ## {pos:Vector3, radius:float}
var latch_time: float = 10.0
var open: bool = false
var open_count: int = 0              ## quantas vezes abriu desde a criacao (telemetria/teste)

var _latch_left: Array[float] = []
var _pressed: Array[bool] = []


static func from_zone(zone: ZoneDef) -> PuzzleState:
	if zone == null or zone.puzzle.is_empty():
		return null
	var s: PuzzleState = PuzzleState.new()
	s.puzzle_id = String(zone.puzzle["id"])
	s.latch_time = float(zone.puzzle["latch_time"])
	for p: Dictionary in zone.puzzle["plates"]:
		s.plates.append({"pos": p["pos"], "radius": p["radius"]})
	s.reset()
	return s


func reset() -> void:
	open = false
	_latch_left.clear()
	_pressed.clear()
	for i: int in plates.size():
		_latch_left.append(0.0)
		_pressed.append(false)


func plate_count() -> int:
	return plates.size()


func is_pressed(i: int) -> bool:
	return i >= 0 and i < _pressed.size() and _pressed[i]


## Placa acesa = pisada agora OU dentro da janela de trava.
func is_lit(i: int) -> bool:
	return i >= 0 and i < _latch_left.size() and (_pressed[i] or _latch_left[i] > 0.0)


func lit_flags() -> Array[bool]:
	var out: Array[bool] = []
	for i: int in plates.size():
		out.append(is_lit(i))
	return out


func lit_count() -> int:
	var n: int = 0
	for i: int in plates.size():
		if is_lit(i):
			n += 1
	return n


func state() -> State:
	if open:
		return State.OPEN
	return State.PARTIAL if lit_count() > 0 else State.IDLE


## Avanca `dt` s com as posicoes dos jogadores VIVOS da zona. Devolve true se o que e observavel
## (placas acesas ou portao) mudou.
func update(positions: Array[Vector3], dt: float) -> bool:
	var before: Array[bool] = lit_flags()
	var was_open: bool = open
	for i: int in plates.size():
		var c: Vector3 = plates[i]["pos"]
		var r: float = plates[i]["radius"]
		var on: bool = false
		for p: Vector3 in positions:
			if Vector2(p.x - c.x, p.z - c.z).length() <= r and absf(p.y - c.y) <= PLATE_HEIGHT_TOLERANCE:
				on = true
				break
		_pressed[i] = on
		if on:
			_latch_left[i] = latch_time
		else:
			_latch_left[i] = maxf(0.0, _latch_left[i] - dt)
	if not open and plates.size() > 0 and lit_count() == plates.size():
		open = true
		open_count += 1
	return open != was_open or before != lit_flags()


## Dados do evento de rede (ver Protocol.validate_puzzle_event).
func to_event(zone_id: String) -> Dictionary:
	return {"zone": zone_id, "puzzle": puzzle_id, "plates": lit_flags(), "open": open, "state": int(state())}
