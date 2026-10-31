class_name BotScript
extends RefCounted
## Roteiros de bot (puros). step(name, t, tick) devolve os c_input a enviar neste tick de envio
## (30 Hz). Cada item: {move: Vector2, yaw: float, actions: int, seq_repeat: bool (opcional)}.
## Sem "seq" no item, a sessao atribui o proximo seq crescente; com seq_repeat reenvia o ultimo.

const NAMES: PackedStringArray = ["idle", "walk_square", "attack_loop", "cheat_speed", "invalid_flood", "bad_version", "kill_enemy", "replay_ticket", "bad_ticket"]
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


## Versao enviada no hello pelo bot.
static func hello_version(bot: String, real_version: int) -> int:
	return real_version + 99 if bot == "bad_version" else real_version


static func _in(move: Vector2, actions: int, yaw: float) -> Dictionary:
	return {"move": move, "yaw": yaw, "actions": actions}
