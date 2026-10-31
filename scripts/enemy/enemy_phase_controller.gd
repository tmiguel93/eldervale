class_name EnemyPhaseController
extends RefCounted
## Controle PURO das fases de um chefe (sem nos). `advance(fracao_de_vida)` devolve os indices de
## fase recem-ENTRADOS, em ordem (um golpe que cruza dois limiares entra nas duas, nunca pula uma).
## Monotonico: a vida subir de novo nao volta de fase; so `reset()` volta a fase 0.

var phases: Array[EnemyPhase] = []
var index: int = 0


func setup(p_phases: Array[EnemyPhase]) -> void:
	phases = p_phases
	index = 0


func is_active() -> bool:
	return not phases.is_empty()


func current() -> EnemyPhase:
	return phases[index] if index < phases.size() else null


func reset() -> void:
	index = 0


## Fase que corresponde a `fraction` (sem considerar monotonia): a de maior indice cujo limiar
## ainda e >= fraction. Exige limiares em ordem decrescente (validado em `validate_order`).
static func index_for_fraction(p_phases: Array[EnemyPhase], fraction: float) -> int:
	var found: int = 0
	for i: int in p_phases.size():
		if fraction <= p_phases[i].health_threshold + 0.000001:
			found = i
	return found


func advance(fraction: float) -> Array[int]:
	var entered: Array[int] = []
	var target: int = index_for_fraction(phases, fraction)
	while index < target:
		index += 1
		entered.append(index)
	return entered


## Erros se os limiares nao forem estritamente decrescentes ou a fase 0 nao for 1.0.
static func validate_order(p_phases: Array[EnemyPhase]) -> Array[String]:
	var errs: Array[String] = []
	if p_phases.is_empty():
		return errs
	if p_phases[0] == null or not is_equal_approx(p_phases[0].health_threshold, 1.0):
		errs.append("fases: a fase 0 deve ter health_threshold 1.0")
	for i: int in range(1, p_phases.size()):
		if p_phases[i] == null or p_phases[i - 1] == null:
			errs.append("fases: fase nula")
			continue
		if p_phases[i].health_threshold >= p_phases[i - 1].health_threshold:
			errs.append("fases: limiares devem ser estritamente decrescentes (fase %d)" % i)
	return errs
