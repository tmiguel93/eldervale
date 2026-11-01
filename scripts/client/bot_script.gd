class_name BotScript
extends RefCounted
## Roteiros de bot (puros). step(name, t, tick) devolve os c_input a enviar neste tick de envio
## (30 Hz). Cada item: {move: Vector2, yaw: float, actions: int, seq_repeat: bool (opcional)}.
## Sem "seq" no item, a sessao atribui o proximo seq crescente; com seq_repeat reenvia o ultimo.

const NAMES: PackedStringArray = ["idle", "walk_square", "attack_loop", "cheat_speed", "invalid_flood", "bad_version", "kill_enemy", "replay_ticket", "bad_ticket", "world_tour", "adv_hub_wild", "adv_ruins", "adv_party", "adv_prep", "adv_zone_drop", "adv_check"]
const SQUARE_SIDE_S: float = 1.5  # s por lado
const KILL_MELEE_RANGE: float = 1.3  # distancia (m) em que o bot para de andar e so golpeia
const KILL_YAW: float = 0.0  # yaw de camera usado pelo bot: forward = -Z, right = +X


static func is_known(bot: String) -> bool:
	return NAMES.has(bot)


static func step(bot: String, t: float, tick: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	match bot:
		"walk_square":
			var side: int = int(floorf(t / SQUARE_SIDE_S)) % 4
			var dirs: Array[Vector2] = [Vector2(0, 1), Vector2(1, 0), Vector2(0, -1), Vector2(-1, 0)]
			out.append(_in(dirs[side], 0, 0.0))
		"attack_loop":
			var actions: int = 1 if (int(floorf(t * 2.0)) % 2 == 0) else 0
			out.append(_in(Vector2(0, 1) if t < 2.0 else Vector2.ZERO, actions, 0.0))
		"cheat_speed":
			if t < 2.0:
				out.append(_in(Vector2(10, 0), 0, 0.0))
			else:
				out.append(_in(Vector2(1, 0), 0, 0.0))
		"invalid_flood":
			if t < 1.0:
				out.append(_in(Vector2(0, 1), 0, 0.0))
			else:
				var phase: int = tick % 4
				match phase:
					0:
						out.append(_in(Vector2(NAN, 0.0), 0, 0.0))
					1:
						out.append(_in(Vector2(0, 1), 0xF0, 0.0))
					2:
						var rep: Dictionary = _in(Vector2(0, 1), 0, 0.0)
						rep["seq_repeat"] = true
						out.append(rep)
					_:
						for i: int in 10:  # rajada acima do limite de taxa
							out.append(_in(Vector2(0, 1), 0, INF if i == 0 else 0.0))
		_:
			pass  # idle, bad_version: sem inputs
	return out


## Roteiros que exigem credenciais/backend (ticket) para fazer sentido.
static func needs_backend(bot: String) -> bool:
	return bot == "replay_ticket" or bot == "bad_ticket"


## bad_ticket: adultera o ticket (ultimo caractere trocado) antes do hello. Puro e testavel.
static func tamper_ticket(ticket: String) -> String:
	if ticket.is_empty():
		return ticket
	var last: String = ticket.substr(ticket.length() - 1)
	return ticket.substr(0, ticket.length() - 1) + ("A" if last != "A" else "B")


## kill_enemy: anda ate o inimigo vivo mais proximo do snapshot e ataca ate ele morrer.
## `self_pos`: posicao autoritativa do jogador; `entities`: entidades do ultimo snapshot;
## `target_id`: alvo atual (-1 = escolher). Devolve {items: Array[Dictionary], target_id: int}.
static func kill_enemy_step(self_pos: Vector3, entities: Array, target_id: int) -> Dictionary:
	var target: Dictionary = {}
	var best: float = INF
	for e: Variant in entities:
		if not (e is Dictionary):
			continue
		var d: Dictionary = e
		if int(d.get("kind", 0)) != Protocol.KIND_ENEMY or float(d.get("hp", 0.0)) <= 0.0 or not (d.get("pos") is Vector3):
			continue
		if int(d.get("id", -1)) == target_id:
			target = d  # mantem o alvo enquanto vivo
			break
		var dist: float = self_pos.distance_squared_to(d["pos"])
		if dist < best:
			best = dist
			target = d
	var items: Array[Dictionary] = []
	if target.is_empty():
		return {"items": items, "target_id": -1}
	var delta: Vector3 = (target["pos"] as Vector3) - self_pos
	delta.y = 0.0
	var dist_flat: float = delta.length()
	var dir: Vector3 = delta / dist_flat if dist_flat > 0.001 else Vector3.ZERO
	# world_direction(move, yaw=0): right = +X (move.x), forward = -Z (move.y)
	var move: Vector2 = Vector2(dir.x, -dir.z)
	if dist_flat <= KILL_MELEE_RANGE:
		move *= 0.05  # quase parado, mas mantem a direcao do golpe
	items.append(_in(move.limit_length(1.0), Protocol.ACTION_ATTACK if dist_flat <= KILL_MELEE_RANGE + 0.8 else 0, KILL_YAW))
	return {"items": items, "target_id": int(target["id"])}


## world_tour (E5.3): percorre hub -> portal -> selvagem (trilha) -> portal -> ruinas (placas A e B, portao) ->
## salao do chefe. Dirigido pelos DADOS do mundo e pela posicao autoritativa; `memo` guarda o estagio do puzzle.
## Devolve {items, done}. `done` = chegou ao salao (depois do portao).
static func world_tour_step(pos: Vector3, memo: Dictionary) -> Dictionary:
	var def: WorldDef = WorldDef.shared()
	var zid: String = def.zone_id_at(pos)
	var zone: ZoneDef = def.get_zone(zid)
	var target: Vector3 = pos
	var done: bool = false
	if zone != null:
		if not zone.puzzle.is_empty():
			var plates: Array = zone.puzzle["plates"]
			var stage: int = int(memo.get("stage", 0))
			if stage < plates.size():
				target = (plates[stage] as Dictionary)["pos"]
				if _flat(pos, target) < 1.0:
					memo["stage"] = stage + 1
			else:
				# depois das placas: entra pela abertura do portao (nao ha caminho reto, a divisoria bloqueia) e segue ao salao
				var gate: Vector3 = zone.puzzle["gate_pos"]
				var hall: Vector3 = (zone.encounter["trigger_center"] as Vector3) + Vector3(5.0, 0.0, 0.0)
				if not bool(memo.get("through", false)):
					target = Vector3(gate.x - 4.0, 0.0, gate.z)
					if _flat(pos, target) < 1.5:
						memo["through"] = true
				else:
					target = hall
					done = _flat(pos, hall) < 2.0
		elif not zone.portals.is_empty():
			# hub: o unico portal; selvagem: o portal que leva para ALEM do hub (maior indice de zona)
			var best: Dictionary = zone.portals[0]
			for p: Dictionary in zone.portals:
				if def.zone_order.find(String(p["to_zone"])) > def.zone_order.find(String(best["to_zone"])):
					best = p
			target = best["pos"]
	var d: Vector3 = target - pos
	d.y = 0.0
	var move: Vector2 = Vector2.ZERO
	if d.length() > 0.3:
		var dir: Vector3 = d.normalized()
		move = Vector2(dir.x, -dir.z) # yaw 0: direita = +X, frente = -Z
	var items: Array[Dictionary] = [_in(move.limit_length(1.0), 0, KILL_YAW)]
	return {"items": items, "done": done}


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Versao enviada no hello pelo bot.
static func hello_version(bot: String, real_version: int) -> int:
	return real_version + 99 if bot == "bad_version" else real_version


static func _in(move: Vector2, actions: int, yaw: float) -> Dictionary:
	return {"move": move, "yaw": yaw, "actions": actions}
