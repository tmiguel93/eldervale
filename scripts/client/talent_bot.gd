class_name TalentBot
extends RefCounted
## E6.2: roteiro do bot `talents` (so harness/testes). O ClientMain abate inimigos ate o servidor informar ponto de talento
## (s_talents.points_available >= 1); entao PARA de atacar, mede a vida maxima, pede `choose_spec` (Berserker) e `allocate` (w_vigor:
## +10 vida maxima por nivel do talento), mede a vida maxima de novo (o efeito vem do servidor via snapshot) e por fim pede um
## `allocate` sem pontos (deve voltar `no_points`). Tudo e PEDIDO; o servidor decide. O resultado vai em `session.result.talent_bot`.

const FINAL_HOLD_S: float = 2.0
const SETTLE_S: float = 1.0
const SPEC: String = "berserker"
const NODE: String = "w_vigor"
const EXTRA_NODE: String = "w_might"

var session: ClientSession
var done: bool = false
var holding: bool = false ## true = para de atacar
var stage: int = 0
var _t0: float = 0.0
var _info: Dictionary = {"max_hp_before": -1.0, "max_hp_after": -1.0, "spec_after": "", "ranks_after": {}, "points_before": -1, "points_after": -1,
	"level_before": -1, "error_code": "", "stage": 0}


func _init(p_session: ClientSession) -> void:
	session = p_session
	session.result.talent_bot = _info


func _max_hp() -> float:
	return float(session.local_entity.get("max_hp", -1.0))


func tick(t: float) -> void:
	if done or session.talents_state.is_empty() or session.local_entity.is_empty():
		return
	var st: Dictionary = session.talents_state
	match stage:
		0:
			if int(st["points_available"]) >= 1:
				holding = true
				_t0 = t
				stage = 1
		1: # espera os snapshots assentarem, mede e pede a especializacao
			if t - _t0 >= SETTLE_S:
				_info["max_hp_before"] = _max_hp()
				_info["points_before"] = int(st["points_available"])
				_info["level_before"] = int(st["level"])
				session.talent_choose_spec(SPEC)
				stage = 2
		2:
			if String(st["spec"]) == SPEC:
				session.talent_allocate(NODE)
				stage = 3
		3:
			if int((st["ranks"] as Dictionary).get(NODE, 0)) >= 1:
				_t0 = t
				stage = 4
		4:
			if t - _t0 >= SETTLE_S:
				_info["max_hp_after"] = _max_hp()
				_info["spec_after"] = String(st["spec"])
				_info["ranks_after"] = (st["ranks"] as Dictionary).duplicate()
				_info["points_after"] = int(st["points_available"])
				if int(st["points_available"]) == 0:
					session.talent_allocate(EXTRA_NODE) # sem pontos: o servidor deve recusar (no_points)
					stage = 5
				else:
					stage = 6
		5:
			if not session.result.talents_errors.is_empty():
				_info["error_code"] = String((session.result.talents_errors[0] as Dictionary).get("code", ""))
				stage = 6
		6:
			done = true
	_info["stage"] = stage
