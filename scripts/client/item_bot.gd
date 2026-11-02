class_name ItemBot
extends RefCounted
## E6.3: roteiro do bot `items` (so harness/testes). O ClientMain abate inimigos ate o servidor entregar um item ROLADO (entrada com `inst`
## em s_inventory); entao PARA de atacar, mede a vida maxima, PEDE para equipar a pilha, espera o s_inventory novo (instancia em
## `equipment_inst`), mede a vida maxima de novo e testa duas recusas (indice/item errado e slot vazio). Tudo e PEDIDO; o servidor decide.
## O resultado vai em `session.result.item_bot`.

const FINAL_HOLD_S: float = 2.0
const SETTLE_S: float = 1.0
const HP_WAIT_S: float = 60.0

var session: ClientSession
var done: bool = false
var holding: bool = false
var stage: int = 0
var _t0: float = 0.0
var _info: Dictionary = {"max_hp_before": -1.0, "max_hp_after": -1.0, "inst": {}, "base": "", "slot": "", "equipped_uid": "", "bad_index_code": "",
	"mismatch_code": "", "inst_in_bag_after": true, "stage": 0, "rolled_events": 0}


func _init(p_session: ClientSession) -> void:
	session = p_session
	session.result.item_bot = _info


func _max_hp() -> float:
	return float(session.local_entity.get("max_hp", -1.0))


## Indice da primeira pilha com instancia. `prefer_hp`: so aceita instancia com affix de VIDA maxima (a unica medida visivel no snapshot),
## para a conferencia "stats mudam exatamente" ser significativa; depois de HP_WAIT_S aceita qualquer uma.
func _find_rolled(prefer_hp: bool = false) -> int:
	var slots: Array = session.inventory_data.get("slots", []) as Array
	for i: int in slots.size():
		if not (slots[i] as Dictionary).has("inst"):
			continue
		if not prefer_hp or _has_hp_affix((slots[i] as Dictionary)["inst"] as Dictionary):
			return i
	return -1


func _has_hp_affix(inst: Dictionary) -> bool:
	var rules: ItemRules = ItemRules.shared()
	for a: Variant in inst.get("affixes", []):
		var def: Dictionary = rules.affixes.get(String((a as Dictionary).get("id", "")), {})
		if not def.is_empty() and String((def["effect"] as Dictionary).get("stat", "")) == "max_health":
			return true
	return false


func tick(t: float) -> void:
	if done or session.local_entity.is_empty() or session.inventory_data.is_empty():
		return
	var slots: Array = session.inventory_data.get("slots", []) as Array
	match stage:
		0:
			var idx: int = _find_rolled(t < HP_WAIT_S)
			if idx >= 0:
				holding = true
				_t0 = t
				_info["inst"] = (slots[idx] as Dictionary)["inst"]
				_info["base"] = String((slots[idx] as Dictionary)["item_id"])
				stage = 1
		1: # estabiliza (parou de atacar) e mede
			if t - _t0 >= SETTLE_S:
				_info["max_hp_before"] = _max_hp()
				var idx2: int = _find_rolled_uid(String((_info["inst"] as Dictionary).get("uid", "")))
				if idx2 < 0:
					return
				session.equip(idx2, String((slots[idx2] as Dictionary)["item_id"]))
				stage = 2
		2:
			var eqi: Dictionary = session.inventory_data.get("equipment_inst", {}) as Dictionary
			for k: Variant in eqi:
				if String((eqi[k] as Dictionary).get("uid", "")) == String((_info["inst"] as Dictionary).get("uid", "")):
					_info["slot"] = String(k)
					_info["equipped_uid"] = String((eqi[k] as Dictionary)["uid"])
					_info["inst_in_bag_after"] = _find_rolled_uid(String(_info["equipped_uid"])) >= 0
					_t0 = t
					stage = 3
		3:
			if t - _t0 >= SETTLE_S:
				_info["max_hp_after"] = _max_hp()
				session.equip(199, "sword_basic") # indice inexistente
				stage = 4
		4:
			if not session.result.equip_results.is_empty() and session.result.equip_results.size() >= 2:
				_info["bad_index_code"] = String((session.result.equip_results[1] as Dictionary).get("code", ""))
				session.equip(0, "scrap_material" if String((slots[0] as Dictionary)["item_id"]) != "scrap_material" else "potion_minor") # base errada
				stage = 5
		5:
			if session.result.equip_results.size() >= 3:
				_info["mismatch_code"] = String((session.result.equip_results[2] as Dictionary).get("code", ""))
				stage = 6
		6:
			done = true
	_info["stage"] = stage


func _find_rolled_uid(uid: String) -> int:
	var slots: Array = session.inventory_data.get("slots", []) as Array
	for i: int in slots.size():
		if (slots[i] as Dictionary).has("inst") and String(((slots[i] as Dictionary)["inst"] as Dictionary).get("uid", "")) == uid:
			return i
	return -1
