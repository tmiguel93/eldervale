class_name AdventureBot
extends RefCounted
## E5.6: bot de AVENTURA (sem apresentacao). Executa um roteiro de passos sobre a API publica da ClientSession (dialogo,
## quests, crafting) e envia inputs como um jogador: anda ate NPCs/portais/estacao pelos DADOS do mundo, ataca inimigos
## por tipo, coleta os proprios pickups, abre o puzzle e luta com o chefe. NAO decide nada de gameplay: so pede; o
## servidor e a autoridade (quests, recompensas, loot, craft). Roteiros por nome de bot (BotScript.NAMES):
##   adv_hub_wild   hub + selvagem: falar com NPCs, aceitar/entregar quests, abater, coletar, craftar, replay de entrega
##   adv_ruins      hub -> selvagem (mini-chefe) -> ruinas (puzzle, conjuradores, chefe) [-> volta ao hub e entrega]
##   adv_party      igual ao ruins, enxuto, para 4 jogadores (cada um com o proprio personagem)
##   adv_prep       aceita/entrega quests no hub e fica parado (cenarios de falha: queda do servidor / do backend)
##   adv_zone_drop  anda ate o portal e DERRUBA a conexao no meio da transicao de zona
##   adv_check      so conecta, olha o estado sincronizado e fica parado (verifica o que foi persistido)
## Cada passo tem timeout; estourar registra "timeout:<passo>" e segue (o harness decide o que e falha).

const STOP_RANGE: float = 1.3
const ATTACK_RANGE: float = 2.1
const STUCK_WINDOW_S: float = 1.4
const DEFAULT_TIMEOUT_S: float = 45.0
const FINAL_HOLD_S: float = 3.0

var plan: String = ""
var steps: Array[Dictionary] = []
var idx: int = 0
var done: bool = false
var drop_requested: bool = false
var kills: Dictionary = {}          ## tipo -> abates observados (eventos death)
var quest_errors: Array[String] = [] ## codigos de QUEST_ERROR recebidos, em ordem
var craft_results: Array = []        ## [{ok, code}]
var timeouts: Array[String] = []

var _s: ClientSession
var _types: Dictionary = {}          ## id de entidade -> tipo (ultimo snapshot)
var _memo: Dictionary = {}
var _step_t0: float = 0.0
var _last_pos: Vector3 = Vector3.ZERO
var _last_move_t: float = 0.0
var _side: int = 1
var _side_until: float = -1.0
var _dialogue_end_seen: bool = false
var _world: WorldDef


static func is_adventure(bot: String) -> bool:
	return bot.begins_with("adv_")


static func create(bot: String, session: ClientSession) -> AdventureBot:
	var b: AdventureBot = AdventureBot.new()
	b.plan = bot
	b._s = session
	b._world = WorldDef.shared()
	b.steps = steps_for(bot)
	session.quest_log.quest_error.connect(func(_r: int, _o: int, _q: String, code: String) -> void: b.quest_errors.append(code))
	session.craft_finished.connect(func(ok: bool, data: Dictionary) -> void: b.craft_results.append({"ok": ok, "code": String(data.get("code", ""))}))
	return b


# ------------------------------------------------------------------ roteiros

static func _q(op: String, quest: String, npc: String, expect_error: bool = false) -> Dictionary:
	return {"type": "quest", "op": op, "quest": quest, "npc": npc, "expect_error": expect_error, "name": "%s:%s" % [op, quest]}


static func steps_for(bot: String) -> Array[Dictionary]:
	var orla: String = "npc_elder_orla"
	var brannoch: String = "npc_hunter_brannoch"
	var ilmar: String = "npc_scholar_ilmar"
	var s: Array[Dictionary] = []
	match bot:
		"adv_hub_wild":
			s.append(_q("accept", "gw_welcome", orla))
			s.append({"type": "talk", "npc": brannoch, "choose": [], "name": "talk:brannoch"})
			s.append(_q("turn_in", "gw_welcome", orla))
			s.append(_q("turn_in", "gw_welcome", orla, true)) # replay da entrega: o servidor tem de recusar
			s.append(_q("accept", "gw_scrap_for_orla", orla))
			s.append({"type": "talk", "npc": brannoch, "choose": [0], "name": "dialogue_accept:gw_clear_clearing"})
			s.append({"type": "zone", "to": "zone_wild", "name": "zone:wild"})
			s.append({"type": "kill", "enemy": "melee_grunt", "count": 6, "via": [Vector3(176, 0, 0), Vector3(184, 0, -14)], "timeout": 60.0, "name": "kill:melee_grunt"})
			s.append({"type": "loot", "name": "loot"})
			# a sucata sorteada pode nao bastar: caca outros comuns (sem chefes) ate o objetivo de coleta fechar
			s.append({"type": "kill", "enemy": ["forest_stalker", "bow_scout", "bark_brute", "ranged_caster", "grove_shaman"], "count": 99, "via": [Vector3(170, 0, 8), Vector3(172, 0, 22)],
				"until_quest": {"quest": "gw_scrap_for_orla", "obj": "collect_scrap", "required": 6}, "timeout": 60.0, "name": "farm:scrap"})
			s.append({"type": "loot", "name": "loot2"})
			s.append({"type": "zone", "to": "zone_hub", "name": "zone:hub"})
			s.append({"type": "craft", "recipe": "rcp_potion_minor", "name": "craft:potion"})
			s.append(_q("turn_in", "gw_scrap_for_orla", orla))
			s.append({"type": "talk", "npc": brannoch, "choose": [0], "name": "dialogue_turn_in:gw_clear_clearing"})
			s.append({"type": "wait", "secs": 1.0, "name": "settle"})
		"adv_ruins", "adv_party":
			if bot == "adv_ruins":
				s.append(_q("accept", "gw_ruins_expedition", ilmar))
			else:
				s.append(_q("accept", "gw_ruin_guardian", ilmar))
			s.append({"type": "zone", "to": "zone_wild", "name": "zone:wild"})
			if bot == "adv_ruins":
				s.append({"type": "kill", "enemy": "thorn_alpha", "count": 1, "via": [Vector3(200, 0, 0), Vector3(228, 0, -12)], "timeout": 45.0, "name": "kill:mini_boss"})
				s.append({"type": "loot", "name": "loot:mini_boss"})
			s.append({"type": "zone", "to": "zone_ruins", "name": "zone:ruins"})
			s.append({"type": "puzzle", "name": "puzzle"})
			if bot == "adv_party":
				s.insert(0, {"type": "wait", "secs": 0.0, "by_join": 12.0, "name": "wait_group"})
			else:
				s.append({"type": "kill", "enemy": "ranged_caster", "count": 1, "timeout": 20.0, "name": "kill:casters"})
			s.append({"type": "kill", "enemy": "blight_treant", "count": 1, "timeout": 60.0, "name": "kill:boss"})
			s.append({"type": "loot", "name": "loot:boss"})
			if bot == "adv_ruins":
				s.append({"type": "zone", "to": "zone_hub", "name": "zone:hub_return"})
				s.append(_q("turn_in", "gw_ruins_expedition", ilmar))
			s.append({"type": "wait", "secs": 1.0, "name": "settle"})
		"adv_prep":
			s.append(_q("accept", "gw_welcome", orla))
			s.append({"type": "talk", "npc": brannoch, "choose": [], "name": "talk:brannoch"})
			s.append({"type": "wait", "secs": 8.0, "name": "wait_before_turn_in"})
			s.append(_q("turn_in", "gw_welcome", orla))
			s.append(_q("accept", "gw_scrap_for_orla", orla))
			s.append({"type": "wait", "secs": 600.0, "name": "hold"})
		"adv_zone_drop":
			s.append({"type": "zone", "to": "zone_wild", "name": "zone:wild"})
			s.append({"type": "wait", "secs": 30.0, "name": "hold"})
		"adv_check":
			s.append(_q("turn_in", "gw_welcome", orla, true)) # tentativa de receber de novo: nunca pode pagar duas vezes
			s.append({"type": "wait", "secs": 600.0, "name": "hold"})
	return s


# ------------------------------------------------------------------ eventos

## Eventos validados da sessao (drenados pelo ClientMain).
func on_event(kind: int, data: Dictionary) -> void:
	if kind == Protocol.EVENT_DEATH:
		var t: String = String(_types.get(int(data.get("id", -1)), ""))
		if not t.is_empty():
			kills[t] = int(kills.get(t, 0)) + 1
	elif kind == Protocol.EVENT_ZONE and plan == "adv_zone_drop":
		if int(data.get("id", -1)) == _s.player_id and int(data.get("phase", -1)) == Protocol.ZONE_PHASE_LEAVING:
			drop_requested = true # transicao iniciada: derruba a conexao (o harness verifica reconexao/lock)


# ------------------------------------------------------------------ tick

func current_step_name() -> String:
	return String(steps[idx].get("name", "?")) if idx < steps.size() else "fim"


## Um tick de envio (30 Hz). Devolve os inputs (BotScript.step-like) e avanca o roteiro.
func tick(t: float) -> Array[Dictionary]:
	var none: Array[Dictionary] = []
	if done or _s.local_entity.is_empty() or not (_s.local_entity.get("pos") is Vector3):
		return none
	for e: Variant in _s.last_entities:
		if e is Dictionary and int((e as Dictionary).get("kind", 0)) == Protocol.KIND_ENEMY:
			_types[int((e as Dictionary)["id"])] = String((e as Dictionary).get("type", ""))
	var pos: Vector3 = _s.local_entity["pos"]
	if float(_s.local_entity.get("hp", 1.0)) <= 0.0:
		return [_in(Vector2.ZERO, 0)] # morto: espera o respawn do servidor
	if idx >= steps.size():
		done = true
		return none
	if _memo.is_empty():
		_memo = {"t0": t}
		_step_t0 = t
		print("[adv] passo %d/%d: %s" % [idx + 1, steps.size(), current_step_name()])
	var st: Dictionary = steps[idx]
	var out: Array[Dictionary] = []
	var finished: bool = _run(st, pos, t, out)
	if not finished and t - _step_t0 > float(st.get("timeout", DEFAULT_TIMEOUT_S)) and String(st["type"]) != "wait":
		timeouts.append(String(st.get("name", st["type"])))
		print("[adv] TIMEOUT no passo %s" % current_step_name())
		finished = true
	if finished:
		_s.result.mark_step(String(st.get("name", st["type"])), t)
		idx += 1
		_memo = {}
		out = [_in(Vector2.ZERO, 0)]
	return out


func _run(st: Dictionary, pos: Vector3, t: float, out: Array[Dictionary]) -> bool:
	match String(st["type"]):
		"wait":
			out.append(_in(Vector2.ZERO, 0))
			var secs: float = float(st["secs"])
			if st.has("by_join"): # espera proporcional a ordem de entrada (id 1 espera mais): o grupo chega junto ao chefe
				secs = float(maxi(0, 4 - _s.player_id)) * float(st["by_join"])
			return t - _step_t0 >= secs
		"quest":
			return _run_quest(st, pos, t, out)
		"talk":
			return _run_talk(st, pos, t, out)
		"zone":
			return _run_zone(st, pos, t, out)
		"kill":
			return _run_kill(st, pos, t, out)
		"loot":
			return _run_loot(pos, t, out)
		"craft":
			return _run_craft(st, pos, t, out)
		"puzzle":
			return _run_puzzle(pos, t, out)
	return true


# ------------------------------------------------------------------ passos

func _npc_pos(npc: String) -> Vector3:
	return NpcDirectory.shared().get_npc(npc).get("position", Vector3.ZERO)


## Anda ate `target` (plano XZ). Devolve true ao chegar a `tol`. Desvia de obstaculos quando travado.
func _walk(pos: Vector3, target: Vector3, tol: float, t: float, out: Array[Dictionary], actions: int = 0) -> bool:
	var d: Vector3 = target - pos
	d.y = 0.0
	if d.length() <= tol:
		out.append(_in(Vector2.ZERO, 0))
		return true
	var dir: Vector3 = d.normalized()
	# travado? (quase sem sair do lugar por STUCK_WINDOW_S enquanto tenta andar): contorna de lado por 1 s
	if Vector2(pos.x - _last_pos.x, pos.z - _last_pos.z).length() > 0.35:
		_last_pos = pos
		_last_move_t = t
	elif t - _last_move_t > STUCK_WINDOW_S and _side_until < t:
		_side = -_side
		_side_until = t + 1.0
		_last_move_t = t
		_last_pos = pos
	if _side_until > t:
		dir = (dir + Vector3(-dir.z, 0.0, dir.x) * float(_side) * 1.6).normalized()
	out.append(_in(Vector2(dir.x, -dir.z).limit_length(1.0), actions))
	return false


func _run_quest(st: Dictionary, pos: Vector3, t: float, out: Array[Dictionary]) -> bool:
	var npc: String = String(st["npc"])
	var npc_pos: Vector3 = _npc_pos(npc)
	var radius: float = float(NpcDirectory.shared().get_npc(npc).get("radius", 3.0))
	if not bool(_memo.get("near", false)):
		if _walk(pos, npc_pos, radius * 0.6, t, out):
			_memo["near"] = true
			_memo["near_t"] = t
		return false
	out.append(_in(Vector2.ZERO, 0))
	var qid: String = String(st["quest"])
	var expect_err: bool = bool(st["expect_error"])
	if not _memo.has("sent"):
		if t - float(_memo["near_t"]) < 0.4:
			return false # deixa o servidor ver a posicao parada
		_memo["sent"] = t
		_memo["errors0"] = quest_errors.size()
		if String(st["op"]) == "accept":
			_s.quest_accept(qid)
		else:
			_s.quest_turn_in(qid)
		return false
	var got_error: bool = quest_errors.size() > int(_memo["errors0"])
	if expect_err:
		return got_error or t - float(_memo["sent"]) > 2.0
	var status: String = _s.quest_log.status_of(qid)
	var ok: bool = (String(st["op"]) == "accept" and (status == "active" or status == "ready")) or (String(st["op"]) == "turn_in" and status == "completed")
	if ok:
		return true
	if got_error or t - float(_memo["sent"]) > 2.5:
		print("[adv] pedido %s falhou (erros=%s, status=%s)" % [current_step_name(), str(quest_errors), status])
		return true
	return false


func _run_talk(st: Dictionary, pos: Vector3, t: float, out: Array[Dictionary]) -> bool:
	var npc: String = String(st["npc"])
	var radius: float = float(NpcDirectory.shared().get_npc(npc).get("radius", 3.0))
	if not bool(_memo.get("near", false)):
		if _walk(pos, _npc_pos(npc), radius * 0.6, t, out):
			_memo["near"] = true
			_memo["near_t"] = t
		return false
	out.append(_in(Vector2.ZERO, 0))
	if not _memo.has("opened"):
		if t - float(_memo["near_t"]) < 0.4:
			return false
		_memo["opened"] = t
		_s.dialogue_open(npc)
		return false
	var choices: Array = st["choose"]
	var n: int = int(_memo.get("n", 0))
	var view: Dictionary = _s.dialogue_view
	if view.is_empty() and t - float(_memo["opened"]) < 3.0 and n == 0:
		return false # ainda esperando a fala
	if n < choices.size():
		if t - float(_memo.get("last", -1.0e9)) < 0.5:
			return false
		if view.is_empty():
			return true
		_memo["last"] = t
		_memo["n"] = n + 1
		_s.dialogue_choose(int(choices[n]))
		return false
	if t - float(_memo.get("last", -1.0e9)) < 0.7 and n > 0:
		return false
	if not view.is_empty():
		_s.dialogue_close()
	return true


func _next_zone_toward(cur: String, target: String) -> String:
	var order: Array[String] = _world.zone_order
	var ci: int = order.find(cur)
	var ti: int = order.find(target)
	if ci < 0 or ti < 0 or ci == ti:
		return ""
	return order[ci + (1 if ti > ci else -1)]


func _run_zone(st: Dictionary, pos: Vector3, t: float, out: Array[Dictionary]) -> bool:
	var cur: String = _s.zone_id if not _s.zone_id.is_empty() else _world.zone_id_at(pos)
	var target: String = String(st["to"])
	if cur == target:
		out.append(_in(Vector2.ZERO, 0))
		if not _memo.has("arrived"):
			_memo["arrived"] = t
		return t - float(_memo["arrived"]) >= 0.8 # deixa a transicao e o catch-up assentarem
	var nxt: String = _next_zone_toward(cur, target)
	var zone: ZoneDef = _world.get_zone(cur)
	if zone == null or nxt.is_empty():
		return true
	for p: Dictionary in zone.portals:
		if String(p["to_zone"]) == nxt:
			_walk(pos, p["pos"], 0.2, t, out) # pisar no portal dispara a transicao (raio dos dados)
			return false
	return true


func _alive_of(type_ids: Array, pos: Vector3, max_dist: float = 1.0e9) -> Dictionary:
	var best: Dictionary = {}
	var best_d: float = INF
	for e: Variant in _s.last_entities:
		if not (e is Dictionary):
			continue
		var d: Dictionary = e
		if int(d.get("kind", 0)) != Protocol.KIND_ENEMY or not type_ids.has(String(d.get("type", ""))) or float(d.get("hp", 0.0)) <= 0.0 or not (d.get("pos") is Vector3):
			continue
		var dist: float = Vector2(pos.x - (d["pos"] as Vector3).x, pos.z - (d["pos"] as Vector3).z).length()
		if dist < best_d and dist <= max_dist:
			best_d = dist
			best = d
	return best


## Passo `kill`: `enemy` = tipo (String) ou lista de tipos; termina apos `count` abates desses tipos OU, com `until_quest`
## ({quest, obj, required}), quando o objetivo da quest atinge o valor (ex.: coletar sucata de qualquer inimigo).
func _run_kill(st: Dictionary, pos: Vector3, t: float, out: Array[Dictionary]) -> bool:
	var type_ids: Array = st["enemy"] if st["enemy"] is Array else [String(st["enemy"])]
	var total: int = 0
	for tid: Variant in type_ids:
		total += int(kills.get(String(tid), 0))
	var base: int = int(_memo.get("base", -1))
	if base < 0:
		base = total
		_memo["base"] = base
	var finished: bool = total - base >= int(st.get("count", 1))
	if st.has("until_quest"):
		var uq: Dictionary = st["until_quest"]
		var qid: String = String(uq["quest"])
		var prog: int = int((_s.quest_log.active.get(qid, {}) as Dictionary).get(String(uq["obj"]), 0))
		finished = _s.quest_log.completed.has(qid) or _s.quest_log.ready.has(qid) or prog >= int(uq["required"])
	if finished:
		out.append(_in(Vector2.ZERO, 0))
		return true
	var target: Dictionary = _alive_of(type_ids, pos)
	var vias: Array = st.get("via", [])
	var vi: int = int(_memo.get("vi", 0))
	# sem alvo a vista (ou longe demais para o servidor ter replicado): percorre os pontos de passagem
	if target.is_empty() or (vi < vias.size() and Vector2(pos.x - (target["pos"] as Vector3).x, pos.z - (target["pos"] as Vector3).z).length() > 40.0):
		if vi < vias.size():
			if _walk(pos, vias[vi], 2.0, t, out):
				_memo["vi"] = vi + 1
			return false
		out.append(_in(Vector2.ZERO, 0))
		return false
	var tp: Vector3 = target["pos"]
	var dist: float = Vector2(pos.x - tp.x, pos.z - tp.z).length()
	if dist <= ATTACK_RANGE:
		var dir: Vector3 = (tp - pos)
		dir.y = 0.0
		dir = dir.normalized() if dir.length() > 0.001 else Vector3.ZERO
		var mv: Vector2 = Vector2(dir.x, -dir.z) * (0.05 if dist <= STOP_RANGE else 1.0)
		out.append(_in(mv.limit_length(1.0), Protocol.ACTION_ATTACK))
		return false
	_walk(pos, tp, STOP_RANGE, t, out)
	return false


func _run_loot(pos: Vector3, t: float, out: Array[Dictionary]) -> bool:
	var best: Vector3 = Vector3.ZERO
	var best_d: float = INF
	for e: Variant in _s.last_entities:
		if e is Dictionary and int((e as Dictionary).get("kind", 0)) == Protocol.KIND_PICKUP and (e as Dictionary).get("pos") is Vector3:
			var p: Vector3 = (e as Dictionary)["pos"]
			var d: float = Vector2(pos.x - p.x, pos.z - p.z).length()
			if d < best_d:
				best_d = d
				best = p
	if best_d == INF:
		out.append(_in(Vector2.ZERO, 0))
		if not _memo.has("empty_since"):
			_memo["empty_since"] = t
		return t - float(_memo["empty_since"]) >= 1.2 or t - _step_t0 > 14.0
	_memo.erase("empty_since")
	_walk(pos, best, 0.5, t, out)
	return t - _step_t0 > 14.0


func _run_craft(st: Dictionary, pos: Vector3, t: float, out: Array[Dictionary]) -> bool:
	var hub: ZoneDef = _world.get_zone("zone_hub")
	var station: Vector3 = (hub.stations[0] as Dictionary)["pos"]
	var radius: float = float((hub.stations[0] as Dictionary)["radius"])
	if not bool(_memo.get("near", false)):
		if _walk(pos, station, radius * 0.5, t, out):
			_memo["near"] = true
			_memo["near_t"] = t
		return false
	out.append(_in(Vector2.ZERO, 0))
	if not _memo.has("sent"):
		if t - float(_memo["near_t"]) < 0.4:
			return false
		_memo["sent"] = t
		_memo["n0"] = craft_results.size()
		var inv: Dictionary = _s.result.inventory
		if int(inv.get("scrap_material", 0)) < 3:
			print("[adv] craft: sucata insuficiente (%s); pulando" % str(inv))
			return true
		_s.craft(String(st["recipe"]))
		return false
	return craft_results.size() > int(_memo["n0"]) or t - float(_memo["sent"]) > 6.0


func _run_puzzle(pos: Vector3, _t: float, out: Array[Dictionary]) -> bool:
	var r: Dictionary = BotScript.world_tour_step(pos, _memo)
	for it: Dictionary in r["items"]:
		out.append(it)
	return bool(r["done"])


static func _in(move: Vector2, actions: int) -> Dictionary:
	return {"move": move, "yaw": 0.0, "actions": actions}


## Resumo do diario para o relatorio do bot.
func quest_summary() -> Dictionary:
	var log: ClientQuestLog = _s.quest_log
	return {"active": log.active.duplicate(true), "completed": log.completed.duplicate(), "ready": log.ready.keys(), "errors": quest_errors.duplicate(),
		"kills": kills.duplicate(), "timeouts": timeouts.duplicate(), "crafts": craft_results.duplicate(true), "step": current_step_name(), "plan_done": done}
