class_name BotScript
extends RefCounted
## Roteiros de bot (puros). step(name, t, tick) devolve os c_input a enviar neste tick de envio
## (30 Hz). Cada item: {move: Vector2, yaw: float, actions: int, seq_repeat: bool (opcional)}.
## Sem "seq" no item, a sessao atribui o proximo seq crescente; com seq_repeat reenvia o ultimo.

const NAMES: PackedStringArray = ["idle", "walk_square", "attack_loop", "cheat_speed", "invalid_flood", "bad_version"]
const SQUARE_SIDE_S: float = 1.5  # s por lado


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


## Versao enviada no hello pelo bot.
static func hello_version(bot: String, real_version: int) -> int:
	return real_version + 99 if bot == "bad_version" else real_version


static func _in(move: Vector2, actions: int, yaw: float) -> Dictionary:
	return {"move": move, "yaw": yaw, "actions": actions}
