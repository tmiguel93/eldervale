extends RefCounted
## Hello v2 (ticket), argumentos do cliente, roteiros kill_enemy/replay_ticket, JSON dos bots.

const TICKET: String = "aaa.bbb.TICKET_SECRET_ccc"


func _enemy(id: int, pos: Vector3, hp: float = 10.0) -> Dictionary:
	return {"id": id, "kind": 2, "pos": pos, "yaw": 0.0, "hp": hp, "max_hp": 10.0, "state": 0, "type": "melee_grunt"}


func run(ctx: Object) -> void:
	# ---- hello v2
	ctx.check(Protocol.VERSION == 2, "hello: Protocol.VERSION == 2")
	var sent: Array = []
	var ss: ClientSession = ClientSession.new()
	ss.send_hello = func(v: int, b: String, n: String, t: String) -> void: sent.append([v, b, n, t])
	ss.begin(Protocol.VERSION, "dev-e4", "Ana", TICKET)
	ctx.check(sent.size() == 1 and sent[0][0] == 2 and sent[0][3] == TICKET, "hello: monta c_hello(version, build, name, ticket)")
	ss.on_welcome(5, 30, 1)
	ctx.check(ss.result.ticket_used_ok, "hello: welcome apos ticket => ticket_used_ok")
	ctx.check(not ss.message.contains(TICKET) and not ss.result.to_json().contains(TICKET), "hello: ticket fora de mensagem e do JSON")
	var ss2: ClientSession = ClientSession.new()
	var sent2: Array = []
	ss2.send_hello = func(v: int, b: String, n: String, t: String) -> void: sent2.append(t)
	ss2.begin(Protocol.VERSION, "dev", "Ana")
	ss2.on_welcome(5, 30, 1)
	ctx.check(sent2 == [""] and not ss2.result.ticket_used_ok, "hello: sem ticket => string vazia e ticket_used_ok=false")
	var ss3: ClientSession = ClientSession.new()
	ss3.send_hello = func(_v: int, _b: String, _n: String, _t: String) -> void: pass
	ss3.begin(Protocol.VERSION, "dev", "Ana", TICKET)
	ss3.on_reject(5, "ticket invalido")
	ctx.check(ss3.state == ClientSession.State.REJECTED and ss3.result.rejected["code"] == 5 and not ss3.result.ticket_used_ok, "hello: reject 5 registrado, ticket_used_ok=false")
	ctx.check(ClientSession.reject_text(5, "").length() > 0, "hello: texto do reject 5")

	# ---- argumentos
	var a: ClientArgs = ClientArgs.parse(PackedStringArray(["--backend-url", "http://127.0.0.1:8787", "--email", "a@b.com", "--password", "pw-secreta-1", "--character=Ana", "--session-id", "sid", "--port", "1234"]))
	ctx.check(a.uses_backend() and a.backend_url == "http://127.0.0.1:8787" and a.email == "a@b.com" and a.password == "pw-secreta-1" and a.character == "Ana" and a.session_id == "sid", "args: parse de argumentos")
	ctx.check(a.errors.is_empty() and a.bot_problems().is_empty(), "args: validos")
	var e: ClientArgs = ClientArgs.parse(PackedStringArray(["--backend-url", "https://x", "--email"]), {"ELDERVALE_PASSWORD": "from-env", "ELDERVALE_CHARACTER": "Zed"})
	ctx.check(e.password == "from-env" and e.character == "Zed" and e.errors.size() == 1 and not (e.errors[0] + "").contains("from-env"), "args: senha via ambiente; erro sem valores")
	ctx.check(e.bot_problems().size() == 1, "args: --email ausente reportado")
	ctx.check(not ClientArgs.parse(PackedStringArray()).uses_backend() and ClientArgs.parse(PackedStringArray()).bot_problems().is_empty(), "args: sem backend = modo direto")
	ctx.check(ClientArgs.is_own_warning("chave desconhecida: --password") and ClientArgs.is_own_warning("chave desconhecida: --session-id") and not ClientArgs.is_own_warning("port: inteiro invalido"), "args: avisos do NetConfig filtrados so para chaves proprias")
	var nc: NetConfig = NetConfig.parse(PackedStringArray(["--password", "pw-secreta-1", "--email", "a@b.com"]))
	var leaked: bool = false
	for m: String in nc.errors:
		leaked = leaked or m.contains("pw-secreta-1")
	ctx.check(not leaked, "args: NetConfig nao copia o valor da senha para seus erros")

	# ---- roteiros
	ctx.check(BotScript.is_known("kill_enemy") and BotScript.is_known("replay_ticket") and BotScript.is_known("walk_square"), "bots: novos roteiros conhecidos")
	var tt: String = BotScript.tamper_ticket(TICKET)
	ctx.check(BotScript.is_known("bad_ticket") and BotScript.needs_backend("bad_ticket") and tt != TICKET and tt.length() == TICKET.length() and BotScript.tamper_ticket("") == "" and BotScript.tamper_ticket("abA") == "abB", "bots: bad_ticket adultera o ticket")
	ctx.check(ClientArgs.parse(PackedStringArray(["--kill-grace", "30"])).kill_grace_s == 30.0 and ClientArgs.parse(PackedStringArray()).kill_grace_s < 0.0, "args: --kill-grace")
	ctx.check(BotScript.needs_backend("replay_ticket") and not BotScript.needs_backend("kill_enemy") and not BotScript.needs_backend("idle"), "bots: replay_ticket exige backend")
	ctx.check(BotScript.step("replay_ticket", 1.0, 1).is_empty() and BotScript.step("kill_enemy", 1.0, 1).is_empty(), "bots: step puro vazio para roteiros com contexto")
	var origin: Vector3 = Vector3(0, 0, 0)
	var r0: Dictionary = BotScript.kill_enemy_step(origin, [], -1)
	ctx.check(r0["items"].is_empty() and r0["target_id"] == -1, "kill: sem inimigos nao envia")
	var r1: Dictionary = BotScript.kill_enemy_step(origin, [_enemy(10, Vector3(8, 0, 0)), _enemy(11, Vector3(0, 0, -3)), _enemy(12, Vector3(0, 0, 1), 0.0), {"id": 1, "kind": 1, "pos": Vector3(0, 0, 0.5), "hp": 5.0}], -1)
	ctx.check(r1["target_id"] == 11, "kill: escolhe o inimigo VIVO mais proximo (ignora morto e jogador)")
	var it: Dictionary = r1["items"][0]
	var wd: Vector3 = PlayerMotion.world_direction(it["move"], it["yaw"])
	ctx.check(wd.dot(Vector3(0, 0, -1)) > 0.99 and (it["move"] as Vector2).length() > 0.99 and it["actions"] == 0, "kill: anda na direcao do alvo (world_direction) sem atacar longe")
	var r2: Dictionary = BotScript.kill_enemy_step(origin, [_enemy(10, Vector3(5, 0, 5)), _enemy(11, Vector3(1.0, 0, 0))], 10)
	ctx.check(r2["target_id"] == 10, "kill: mantem o alvo atual enquanto vivo")
	var r3: Dictionary = BotScript.kill_enemy_step(origin, [_enemy(11, Vector3(1.0, 0, 0))], 10)
	ctx.check(r3["target_id"] == 11 and int(r3["items"][0]["actions"]) == Protocol.ACTION_ATTACK, "kill: alvo morto -> troca; perto -> ataca")
	var wd3: Vector3 = PlayerMotion.world_direction(r3["items"][0]["move"], r3["items"][0]["yaw"]).normalized()
	ctx.check(wd3.dot(Vector3(1, 0, 0)) > 0.99, "kill: perto continua virado ao alvo")
	var valid: bool = Protocol.validate_input(1, r1["items"][0]["move"], r1["items"][0]["yaw"], r1["items"][0]["actions"], 0)["ok"]
	ctx.check(valid, "kill: input gerado passa em Protocol.validate_input")
	ctx.check(BotScript.kill_enemy_step(Vector3(1, 0, 1), [_enemy(5, Vector3(1, 0, 1))], -1)["items"].size() == 1, "kill: alvo exatamente na mesma posicao nao quebra")

	# ---- JSON do bot
	var br: BotResult = BotResult.new()
	br.login_ok = true
	br.character_id = "c1"
	br.session_id = "s1"
	br.kills = 1
	br.on_event(4)
	br.on_event(3)
	br.attempts = [{"connected": true}, {"connected": false, "rejected": {"code": 5}}]
	br.set_character_final({"level": 2, "xp": 120, "revision": 3, "inventory": [{"slot": 0, "item_id": "x", "qty": 2}, {"slot": 1, "item_id": "y", "qty": 1}]})
	var d: Dictionary = JSON.parse_string(br.to_json())
	ctx.check(d["login_ok"] == true and d["character_id"] == "c1" and d["session_id"] == "s1" and d["kills"] == 1 and d["events_total"] == 2, "json: campos E4")
	ctx.check(d["xp"] == 120 and d["level"] == 2 and d["character_final"]["revision"] == 3 and d["character_final"]["inventory_qty"] == 3, "json: xp/nivel/revision/itens do GET final")
	ctx.check(d["attempts"].size() == 2 and d.has("rejected") and d.has("ticket_used_ok") and d.has("events_by_kind"), "json: attempts/rejected/ticket_used_ok/eventos")
	ctx.check(BotResult.new().to_dict()["xp"] == -1, "json: sem GET final => xp -1")
