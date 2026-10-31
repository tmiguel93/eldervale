extends RefCounted
## Sessao do servidor SEM rede real: handlers chamados diretamente (como se viessem do NetRpc),
## saida capturada por um transporte gravador. Tempo controlado por session.test_now_msec.
## Nenhum teste aqui depende de timing real, exceto onde marcado.

const H = preload("res://tests/e3/server_helpers.gd")


func run(ctx: Object) -> void:
	var tree: SceneTree = ctx as SceneTree
	_test_hello_ok(ctx, tree)
	_test_hello_rejects(ctx, tree)
	_test_hello_order(ctx, tree)
	_test_server_full(ctx, tree)
	_test_disconnect(ctx, tree)
	_test_input_validation(ctx, tree)
	_test_input_flood(ctx, tree)
	_test_invalid_recidivism(ctx, tree)
	_test_events_and_snapshots(ctx, tree)
	_test_ping(ctx, tree)
	await tree.physics_frame # deixa queue_free dos rigs acontecer


func _test_hello_ok(ctx: Object, tree: SceneTree) -> void:
	var rig: H.Rig = H.make_rig(tree)
	var id: int = H.join(rig, 101, "Alice_1")
	ctx.check(id > 0, "hello valido cria jogador (entity_id=%d)" % id)
	ctx.check(rig.world.player_count() == 1 and rig.world.get_player_node(id) != null, "jogador existe no mundo do servidor")
	ctx.check(rig.transport.welcomes.size() == 1 and int(rig.transport.welcomes[0]["player_id"]) == id, "welcome enviado com player_id")
	ctx.check(int(rig.transport.welcomes[0]["tick_rate"]) == 30 and int(rig.transport.welcomes[0]["seed"]) == 12345, "welcome carrega tick_rate e seed")
	ctx.check(rig.transport.rejects.is_empty(), "sem reject no hello valido")
	var p: Player = rig.world.get_player_node(id)
	ctx.check(p.use_external_input, "jogador em modo use_external_input")
	ctx.check(not (p.get_node("Combat") as PlayerCombat).read_input_actions, "combate NAO le Input (read_input_actions=false)")
	ctx.check(p.get_node_or_null("DamageNumbers") == null and p.get_node_or_null("HitFlash") == null, "nos cosmeticos removidos")
	ctx.check(rig.transport.events_of(101, Protocol.EVENT_PLAYER_JOINED).is_empty(), "quem entra sabe o proprio id pelo welcome (sem player_joined de si)")
	rig.free_all()


func _test_hello_rejects(ctx: Object, tree: SceneTree) -> void:
	var rig: H.Rig = H.make_rig(tree)
	rig.session.on_peer_connected(1)
	rig.session.on_hello(1, 2, "test", "Bob")
	ctx.check(rig.transport.reject_codes(1) == [Protocol.REJECT_VERSION], "versao errada -> reject(1)")
	ctx.check(rig.transport.disconnects.has(1) and not rig.session.has_peer(1), "versao errada desconecta e esquece o peer")
	ctx.check(rig.world.player_count() == 0, "nenhum jogador criado na versao errada")

	rig.session.on_peer_connected(2)
	rig.session.on_hello(2, 1, "test", "bad<name>")
	ctx.check(rig.transport.reject_codes(2) == [Protocol.REJECT_INVALID_PAYLOAD], "nome invalido -> reject(2)")
	rig.session.on_peer_connected(3)
	rig.session.on_hello(3, "1", 5, null)
	ctx.check(rig.transport.reject_codes(3) == [Protocol.REJECT_INVALID_PAYLOAD], "tipos errados no hello -> reject(2)")
	rig.session.on_peer_connected(4)
	rig.session.on_hello(4, 1, "x".repeat(40), "Ok")
	ctx.check(rig.transport.reject_codes(4) == [Protocol.REJECT_INVALID_PAYLOAD], "build longo -> reject(2)")
	# mensagens de peer ja fechado sao ignoradas (sem segundo reject)
	rig.session.on_hello(1, 1, "test", "Bob")
	rig.session.on_input(1, 1, Vector2.ZERO, 0.0, 0, 0)
	ctx.check(rig.transport.reject_codes(1).size() == 1, "peer fechado e ignorado")
	rig.free_all()


func _test_hello_order(ctx: Object, tree: SceneTree) -> void:
	var rig: H.Rig = H.make_rig(tree)
	var id: int = H.join(rig, 10)
	rig.session.on_hello(10, 1, "test", "Again")
	ctx.check(rig.transport.reject_codes(10) == [Protocol.REJECT_NOT_AUTHENTICATED], "hello repetido -> reject(5)")
	ctx.check(rig.world.player_count() == 0 and not rig.session.has_peer(10) and id > 0, "hello repetido remove o jogador e o peer")
	# input antes do hello/welcome
	rig.session.on_peer_connected(11)
	rig.session.on_input(11, 1, Vector2(1, 0), 0.0, 0, 0)
	ctx.check(rig.transport.reject_codes(11) == [Protocol.REJECT_NOT_AUTHENTICATED], "input antes do welcome -> reject(5)")
	ctx.check(rig.world.player_count() == 0, "input sem hello nao cria jogador")
	# peer desconhecido (sem on_peer_connected): ignorado
	rig.session.on_hello(99, 1, "test", "Ghost")
	ctx.check(rig.world.player_count() == 0 and rig.transport.reject_codes(99).is_empty(), "hello de peer desconhecido ignorado")
	# timeout de hello (relogio injetado)
	rig.session.test_now_msec = 2000
	rig.session.on_peer_connected(12)
	rig.session.test_now_msec = 2000 + 4999
	rig.session.check_timeouts()
	ctx.check(rig.transport.reject_codes(12).is_empty(), "antes do prazo nao desconecta")
	rig.session.test_now_msec = 2000 + 5000
	rig.session.check_timeouts()
	ctx.check(rig.transport.reject_codes(12) == [Protocol.REJECT_NOT_AUTHENTICATED] and rig.transport.disconnects.has(12), "timeout de hello -> reject(5) + disconnect")
	var id2: int = H.join(rig, 13)
	rig.session.test_now_msec += 60000
	rig.session.check_timeouts()
	ctx.check(id2 > 0 and rig.session.has_peer(13), "peer com welcome nao sofre timeout de hello")
	rig.free_all()


func _test_server_full(ctx: Object, tree: SceneTree) -> void:
	var rig: H.Rig = H.make_rig(tree, false, 2)
	var a: int = H.join(rig, 1)
	var b: int = H.join(rig, 2)
	var c: int = H.join(rig, 3)
	ctx.check(a > 0 and b > 0 and c == 0, "terceiro jogador nao entra com max_players=2")
	ctx.check(rig.transport.reject_codes(3) == [Protocol.REJECT_SERVER_FULL], "servidor cheio -> reject(3)")
	ctx.check(rig.transport.disconnects.has(3) and rig.world.player_count() == 2, "cheio: desconecta so o excedente")
	rig.session.on_peer_disconnected(1)
	var d: int = H.join(rig, 4)
	ctx.check(d > 0, "vaga liberada pode ser ocupada")
	rig.free_all()


func _test_disconnect(ctx: Object, tree: SceneTree) -> void:
	var rig: H.Rig = H.make_rig(tree)
	var a: int = H.join(rig, 1, "A")
	var b: int = H.join(rig, 2, "B")
	var node_a: Player = rig.world.get_player_node(a)
	rig.session.on_peer_disconnected(1)
	ctx.check(rig.world.player_count() == 1 and rig.world.get_player_node(a) == null, "desconexao remove o jogador")
	ctx.check(not is_instance_valid(node_a) or not node_a.is_inside_tree(), "no do jogador sai da arvore")
	ctx.check(not rig.session.has_peer(1) and rig.session.has_peer(2), "peer removido da sessao")
	var left: Array[Dictionary] = rig.transport.events_of(2, Protocol.EVENT_PLAYER_LEFT)
	ctx.check(left.size() == 1 and int((left[0]["data"] as Dictionary)["id"]) == a, "player_left replicado aos demais")
	ctx.check(rig.transport.events_of(1, Protocol.EVENT_PLAYER_LEFT).is_empty(), "quem saiu nao recebe player_left")
	rig.session.on_peer_disconnected(1) # idempotente
	ctx.check(rig.world.player_count() == 1 and b > 0, "desconectar de novo e inofensivo")
	rig.free_all()


func _test_input_validation(ctx: Object, tree: SceneTree) -> void:
	var rig: H.Rig = H.make_rig(tree)
	var id: int = H.join(rig, 1)
	var st: ServerSession.PeerState = rig.session.get_peer_state(1)
	rig.session.on_input(1, 5, Vector2(1, 0), 0.5, 1, 0)
	ctx.check(st.last_seq == 5 and st.accepted_inputs == 1, "input valido aceito (seq 5)")
	rig.session.on_input(1, 5, Vector2(0, 1), 0.5, 0, 0)
	rig.session.on_input(1, 4, Vector2(0, 1), 0.5, 0, 0)
	ctx.check(st.last_seq == 5 and st.accepted_inputs == 1 and st.dropped_stale == 2, "seq repetido/antigo descartado")
	rig.session.on_input(1, 6, Vector2(0, 1), 0.0, 16, 0)
	rig.session.on_input(1, 7, Vector2(0, 1), 0.0, -1, 0)
	rig.session.on_input(1, 8, Vector2(0, 1), 0.0, 1 << 20, 0)
	ctx.check(st.dropped_invalid == 3 and st.last_seq == 5, "bits de acao invalidos descartados + contados")
	rig.session.on_input(1, 9, Vector2(INF, 0), 0.0, 0, 0)
	rig.session.on_input(1, 10, Vector2(NAN, 0), 0.0, 0, 0)
	rig.session.on_input(1, 11, Vector2(1, 0), NAN, 0, 0)
	rig.session.on_input(1, 12, Vector2(1, 0), INF, 0, 0)
	rig.session.on_input(1, "13", Vector2(1, 0), 0.0, 0, 0)
	rig.session.on_input(1, 14, [1, 2], 0.0, 0, 0)
	ctx.check(st.dropped_invalid == 9 and st.last_seq == 5, "move/yaw nao finitos e tipos errados descartados")
	ctx.check(rig.session.has_peer(1) and rig.transport.rejects.is_empty(), "abaixo do limite o peer continua conectado")
	# clamp do vetor de movimento e normalizacao do yaw
	rig.session.on_input(1, 20, Vector2(10, 0), 7.0, 0, 0)
	ctx.check(st.last_seq == 20, "move 10x aceito (clampado)")
	var slot: ServerWorld.PlayerSlot = rig.world._players[id] as ServerWorld.PlayerSlot
	ctx.check(slot.move.length() <= 1.0001, "move clampado a comprimento <= 1 (%.4f)" % slot.move.length())
	ctx.check(absf(slot.yaw) <= PI + 0.0001, "yaw normalizado em [-pi, pi] (%.3f)" % slot.yaw)
	rig.free_all()


func _test_input_flood(ctx: Object, tree: SceneTree) -> void:
	var rig: H.Rig = H.make_rig(tree)
	H.join(rig, 1)
	var st: ServerSession.PeerState = rig.session.get_peer_state(1)
	# Relogio parado: so o burst (120) passa; o excedente e descartado e conta como abuso.
	var seq: int = 1
	for i: int in 120:
		rig.session.on_input(1, seq, Vector2(0, 1), 0.0, 0, 0)
		seq += 1
	ctx.check(st.accepted_inputs == 120 and st.dropped_rate == 0, "burst de 120 inputs aceito")
	for i: int in 30:
		rig.session.on_input(1, seq, Vector2(0, 1), 0.0, 0, 0)
		seq += 1
	ctx.check(st.dropped_rate == 30 and st.accepted_inputs == 120, "excedente do rate limit descartado (30)")
	ctx.check(rig.session.has_peer(1), "ainda no limite configurado: segue conectado")
	rig.session.on_input(1, seq, Vector2(0, 1), 0.0, 0, 0)
	ctx.check(rig.transport.reject_codes(1) == [Protocol.REJECT_RATE_LIMIT] and rig.transport.disconnects.has(1), "acima do limite -> reject(4) + disconnect")
	ctx.check(rig.world.player_count() == 0, "flood: jogador removido")
	# tokens voltam com o tempo
	var rig2: H.Rig = H.make_rig(tree)
	H.join(rig2, 1)
	var st2: ServerSession.PeerState = rig2.session.get_peer_state(1)
	for i: int in 121:
		rig2.session.on_input(1, i + 1, Vector2.ZERO, 0.0, 0, 0)
	ctx.check(st2.dropped_rate == 1, "121o input no mesmo ms e descartado")
	rig2.session.test_now_msec += 1000
	rig2.session.on_input(1, 500, Vector2.ZERO, 0.0, 0, 0)
	ctx.check(st2.last_seq == 500, "apos 1 s o limiter volta a aceitar")
	rig.free_all()
	rig2.free_all()


func _test_invalid_recidivism(ctx: Object, tree: SceneTree) -> void:
	var rig: H.Rig = H.make_rig(tree)
	rig.settings.max_invalid_inputs = 5
	H.join(rig, 1)
	for i: int in 5:
		rig.session.on_input(1, i + 1, Vector2.ZERO, 0.0, 99, 0)
	ctx.check(rig.session.has_peer(1), "5 invalidos (== limite) ainda tolerados")
	rig.session.on_input(1, 6, Vector2.ZERO, 0.0, 99, 0)
	ctx.check(rig.transport.reject_codes(1) == [Protocol.REJECT_RATE_LIMIT] and not rig.session.has_peer(1), "6o invalido -> reject(4) + desconecta")
	# janela deslizante: invalidos espacados no tempo nao acumulam
	var rig2: H.Rig = H.make_rig(tree)
	rig2.settings.max_invalid_inputs = 5
	H.join(rig2, 1)
	for i: int in 20:
		rig2.session.test_now_msec += 3000
		rig2.session.on_input(1, i + 1, Vector2.ZERO, 0.0, 99, 0)
	ctx.check(rig2.session.has_peer(1), "invalidos esparsos (janela de 10 s) nao derrubam o peer")
	rig.free_all()
	rig2.free_all()


func _test_events_and_snapshots(ctx: Object, tree: SceneTree) -> void:
	var rig: H.Rig = H.make_rig(tree, true)
	var a: int = H.join(rig, 1, "A")
	var enemies: int = rig.world.enemy_count()
	ctx.check(enemies == 5, "arena do servidor tem os 5 inimigos da arena local (%d)" % enemies)
	var b: int = H.join(rig, 2, "B")
	var spawns: Array[Dictionary] = rig.transport.events_of(2, Protocol.EVENT_ENEMY_SPAWN)
	ctx.check(spawns.size() == 5, "quem entra recebe enemy_spawn dos inimigos vivos")
	var joined_b: Array[Dictionary] = rig.transport.events_of(2, Protocol.EVENT_PLAYER_JOINED)
	var ids_seen: Array[int] = []
	for e: Dictionary in joined_b:
		ids_seen.append(int((e["data"] as Dictionary)["id"]))
	ctx.check(ids_seen == [a], "novo peer recebe player_joined de quem ja estava (e so dele)")
	var joined_a: Array[Dictionary] = rig.transport.events_of(1, Protocol.EVENT_PLAYER_JOINED)
	ctx.check(joined_a.size() == 1 and int((joined_a[0]["data"] as Dictionary)["id"]) == b, "peer antigo recebe player_joined do novo")
	var monotonic: bool = true
	var last: int = 0
	for e: Dictionary in rig.transport.events:
		if int(e["peer"]) == 2:
			if int(e["id"]) <= last:
				monotonic = false
			last = int(e["id"])
	ctx.check(monotonic, "event_id estritamente crescente por peer")

	# snapshots: divisor 2 (30/15), so para welcomed, last_input_seq por peer
	rig.session.on_peer_connected(3) # sem hello: nao recebe snapshot
	rig.session.on_input(1, 42, Vector2.ZERO, 0.0, 0, 0)
	rig.session.step_tick()
	ctx.check(rig.transport.snapshots.is_empty(), "tick 1: ainda sem snapshot (divisor 2)")
	rig.session.step_tick()
	ctx.check(rig.transport.snapshots.size() == 2, "tick 2: 1 snapshot por peer com welcome")
	var snap1: Dictionary = {}
	var snap2: Dictionary = {}
	for s: Dictionary in rig.transport.snapshots:
		if int(s["peer"]) == 1:
			snap1 = s
		elif int(s["peer"]) == 2:
			snap2 = s
	ctx.check(int(snap1["last_seq"]) == 42 and int(snap2["last_seq"]) == -1, "last_input_seq e por peer")
	ctx.check(int(snap1["tick"]) == 2, "server_tick no snapshot")
	var ents: Array = snap1["entities"] as Array
	var all_valid: bool = true
	var players: int = 0
	var foes: int = 0
	for e: Variant in ents:
		if not Protocol.validate_entity_dict(e):
			all_valid = false
		elif int((e as Dictionary)["kind"]) == Protocol.KIND_PLAYER:
			players += 1
		else:
			foes += 1
	ctx.check(all_valid and players == 2 and foes == 5, "snapshot: 2 players + 5 inimigos, todos validos no contrato")
	rig.free_all()


func _test_ping(ctx: Object, tree: SceneTree) -> void:
	var rig: H.Rig = H.make_rig(tree)
	H.join(rig, 1)
	rig.session.on_ping(1, 777)
	ctx.check(rig.transport.pongs.size() == 1 and int(rig.transport.pongs[0]["t"]) == 777, "ping -> pong com eco do valor")
	for i: int in 20:
		rig.session.on_ping(1, i)
	ctx.check(rig.transport.pongs.size() == 1 + 5, "ping limitado por token bucket (burst 6)")
	rig.session.on_ping(1, "texto")
	ctx.check(rig.transport.pongs.size() == 6, "ping com tipo errado ignorado")
	rig.free_all()
