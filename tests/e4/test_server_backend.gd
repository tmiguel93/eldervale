extends RefCounted
## Servidor Godot <-> backend (E4) com backend FALSO: hello com ticket, estado carregado, autosave,
## checkpoint/disconnect, recompensas idempotentes, conflito de revision, encerramento, logs limpos.
## Sem rede real; transporte sincrono (ou retido com hold=true para provar serializacao).

const B = preload("res://tests/e4/backend_helpers.gd")
const Fake = preload("res://tests/e4/fake_backend.gd")

const SAVED_INV: Array = [{"slot": 0, "item_id": "potion_minor", "qty": 7}, {"slot": 1, "item_id": "sword_rare", "qty": 1}]
const SAVED_EQ: Dictionary = {"weapon": "sword_basic", "armor": "armor_heavy"}


func run(ctx: Object) -> void:
	var tree: SceneTree = ctx as SceneTree
	ServerLog.capturing = true
	ServerLog.reset_capture()
	_test_register(ctx, tree)
	_test_hello_valid_loads_state(ctx, tree)
	_test_hello_failures(ctx, tree)
	_test_no_ticket_and_dev_mode(ctx, tree)
	_test_pending_and_redeem_timeout(ctx, tree)
	_test_pending_limit(ctx, tree)
	_test_duplicate_character(ctx, tree)
	_test_autosave_and_serialization(ctx, tree)
	_test_disconnect_checkpoint(ctx, tree)
	_test_real_kill_reward(ctx, tree)
	await _test_reward_retry_same_key(ctx, tree)
	_test_reward_permanent_failure(ctx, tree)
	_test_revision_conflict(ctx, tree)
	_test_heartbeat_and_reregister(ctx, tree)
	_test_clean_shutdown(ctx, tree)
	_test_shutdown_timeout(ctx, tree)
	_test_logs_clean(ctx)
	ServerLog.capturing = false
	await tree.physics_frame


func _tk_rig(tree: SceneTree, hold: bool = false) -> B.BRig:
	var rig: B.BRig = B.make(tree, hold)
	rig.fake.add_character(B.CID1, 3, 700, SAVED_INV, SAVED_EQ, 5, "Sir_Hero")
	rig.fake.tickets[B.TICKET1] = B.CID1
	return rig


func _test_register(ctx: Object, tree: SceneTree) -> void:
	var path: String = "user://test_session_id.txt"
	var rig: B.BRig = B.make(tree)
	ctx.check(rig.sync.is_ready() and rig.sync.session_id == Fake.SESSION_ID, "boot: sessao registrada e session_id guardado")
	var reg: Dictionary = rig.fake.find_all("POST /internal/sessions")[0]["body"]
	ctx.check(reg["region"] == "local" and int(reg["capacity"]) == 4 and int(reg["protocol_version"]) == 2 and String(reg["endpoint"]).contains(":"), "boot: register com region/capacity/protocol_version=2/endpoint")
	ctx.check(rig.fake.last_auth == B.SECRET, "boot: Authorization Bearer com o segredo configurado")
	rig.free_all()
	# --session-id-file
	var rig2: B.BRig = B.make(tree)
	rig2.sync.session_id_file = path
	rig2.sync._write_session_file()
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	ctx.check(f != null and f.get_as_text() == Fake.SESSION_ID, "boot: --session-id-file grava o session_id")
	rig2.free_all()


func _test_hello_valid_loads_state(ctx: Object, tree: SceneTree) -> void:
	var rig: B.BRig = _tk_rig(tree)
	B.hello(rig, 101, B.TICKET1)
	var st: ServerSession.PeerState = rig.session.get_peer_state(101)
	ctx.check(st != null and st.welcomed and st.entity_id > 0, "hello+ticket valido: jogador criado")
	ctx.check(rig.transport.welcomes.size() == 1 and rig.transport.rejects.is_empty(), "hello+ticket valido: welcome enviado, sem reject")
	var redeem: Dictionary = rig.fake.find_all("redeem")[0]["body"]
	ctx.check(redeem["ticket"] == B.TICKET1 and redeem["session_id"] == Fake.SESSION_ID, "redeem enviado com ticket e session_id")
	var lo: PlayerLoadout = B.loadout_of(rig, 101)
	ctx.check(lo != null and lo.progress.level == 3 and lo.progress.total_xp == 700, "estado carregado: nivel 3, xp 700")
	ctx.check(lo.inventory.count(&"potion_minor") == 7 and lo.inventory.count(&"sword_rare") == 1 and lo.inventory.count(&"sword_basic") == 0, "estado carregado: inventario do backend (sem kit inicial duplicado)")
	ctx.check(lo.equipment.get_equipped(ItemData.Slot.WEAPON) == &"sword_basic" and lo.equipment.get_equipped(ItemData.Slot.ARMOR) == &"armor_heavy", "estado carregado: equipamento do backend")
	ctx.check(lo.inventory.capacity == 24, "capacidade do inventario vem do backend (24)")
	ctx.check(lo.final_stats.attack_power > lo.base_stats.attack_power and lo.final_stats.max_health > 100.0, "stats finais recalculados (nivel + equipamento)")
	ctx.check(rig.sync.revision_of(B.CID1) == 5, "revision 5 guardada")
	ctx.check(rig.world.get_player_node(st.entity_id) != null and rig.session.snapshot_character(B.CID1)["level"] == 3, "snapshot do personagem reflete o estado")
	rig.free_all()


func _test_hello_failures(ctx: Object, tree: SceneTree) -> void:
	var rig: B.BRig = _tk_rig(tree)
	B.hello(rig, 1, "ticket-invalido-xyz")
	ctx.check(rig.transport.reject_codes(1) == [Protocol.REJECT_NOT_AUTHENTICATED] and rig.world.player_count() == 0, "ticket invalido (401) -> reject(5), sem jogador")
	ctx.check(not rig.transport.rejects[0]["message"].contains("ticket") and not rig.transport.rejects[0]["message"].contains("401"), "reject nao vaza detalhes")
	rig.fake.force("redeem", [Fake.err(409, "ticket_already_used")])
	B.hello(rig, 2, B.TICKET1)
	ctx.check(rig.transport.reject_codes(2) == [Protocol.REJECT_NOT_AUTHENTICATED] and rig.world.player_count() == 0, "redeem 409 -> reject(5)")
	rig.fake.force("redeem", [Fake.err(409, "character_locked")])
	B.hello(rig, 3, B.TICKET1)
	ctx.check(rig.transport.reject_codes(3) == [Protocol.REJECT_NOT_AUTHENTICATED], "redeem 409 character_locked -> reject(5)")
	ctx.check(rig.transport.disconnects.has(1) and rig.transport.disconnects.has(2), "peers rejeitados sao desconectados")
	# resgate ok mas a carga do personagem falha: lock liberado e reject(5)
	rig.fake.force("/internal/characters/" + B.CID1, [Fake.err(404, "not_found")])
	B.hello(rig, 4, B.TICKET1)
	ctx.check(rig.transport.reject_codes(4) == [Protocol.REJECT_NOT_AUTHENTICATED] and rig.world.player_count() == 0, "carga do personagem falhou -> reject(5)")
	ctx.check(rig.fake.count("POST /internal/characters/" + B.CID1 + "/release") == 1, "carga falhou: release enviado (lock nao fica preso)")
	# estado invalido do backend (item desconhecido)
	rig.fake.chars[B.CID1]["inventory"] = [{"slot": 0, "item_id": "item_inexistente", "qty": 1}]
	B.hello(rig, 5, B.TICKET1)
	ctx.check(rig.transport.reject_codes(5) == [Protocol.REJECT_NOT_AUTHENTICATED] and rig.world.player_count() == 0, "estado invalido do backend -> reject(5), nenhum jogador")
	# ticket malformado nunca chega ao backend
	var before: int = rig.fake.count("redeem")
	B.hello(rig, 6, "tem espaco e / simbolos")
	ctx.check(rig.transport.reject_codes(6) == [Protocol.REJECT_INVALID_PAYLOAD] and rig.fake.count("redeem") == before, "ticket malformado -> reject(2) sem chamar o backend")
	rig.free_all()


func _test_no_ticket_and_dev_mode(ctx: Object, tree: SceneTree) -> void:
	var rig: B.BRig = _tk_rig(tree)
	B.hello(rig, 1, "")
	ctx.check(rig.transport.reject_codes(1) == [Protocol.REJECT_NOT_AUTHENTICATED] and rig.fake.count("redeem") == 0, "backend configurado + sem ticket -> reject(5), sem chamada")
	rig.free_all()
	# backend ainda nao registrado: ninguem entra
	var rig2: B.BRig = B.make(tree)
	rig2.fake.add_character(B.CID1)
	rig2.fake.tickets[B.TICKET1] = B.CID1
	rig2.sync._registered = false
	B.hello(rig2, 1, B.TICKET1)
	ctx.check(rig2.transport.reject_codes(1) == [Protocol.REJECT_NOT_AUTHENTICATED], "sessao nao registrada -> reject(5)")
	rig2.free_all()
	# modo dev (sem backend): ticket nao exigido, kit inicial como no E3
	var dev: Object = B.H.make_rig(tree)
	var id: int = B.H.join(dev, 7, "DevPlayer")
	ctx.check(id > 0 and dev.session.sync == null and dev.transport.rejects.is_empty(), "sem backend: modo dev aceita sem ticket")
	var dlo: PlayerLoadout = PlayerLoadout.find_for(dev.world.get_player_node(id))
	ctx.check(dlo.inventory.count(&"sword_basic") == 1, "modo dev mantem o kit inicial do E3")
	dev.free_all()


func _test_pending_and_redeem_timeout(ctx: Object, tree: SceneTree) -> void:
	var rig: B.BRig = _tk_rig(tree, true)
	B.hello(rig, 1, B.TICKET1)
	var st: ServerSession.PeerState = rig.session.get_peer_state(1)
	ctx.check(st.pending and not st.welcomed and rig.world.player_count() == 0 and rig.transport.welcomes.is_empty(), "pendente: sem jogador e sem welcome")
	rig.session.on_input(1, 1, Vector2(1, 0), 0.0, 0, 0)
	ctx.check(rig.transport.reject_codes(1) == [Protocol.REJECT_NOT_AUTHENTICATED] and rig.world.player_count() == 0, "pendente: input -> reject(5), sem simulacao")
	rig.free_all()
	# fluxo completo em duas etapas (redeem, depois carga) com respostas retidas
	var rig2: B.BRig = _tk_rig(tree, true)
	B.hello(rig2, 1, B.TICKET1)
	rig2.fake.flush(1) # redeem
	ctx.check(rig2.session.get_peer_state(1).pending and rig2.fake.count("GET /internal/characters/") == 1, "apos o redeem sai o GET do personagem")
	rig2.fake.flush(1) # carga
	ctx.check(rig2.session.get_peer_state(1).welcomed and rig2.transport.welcomes.size() == 1, "welcome so depois de resgate + carga")
	rig2.free_all()
	# timeout do resgate
	var rig3: B.BRig = _tk_rig(tree, true)
	B.hello(rig3, 1, B.TICKET1)
	rig3.session.test_now_msec = 1000 + int(rig3.settings.redeem_timeout_sec * 1000.0) + 1
	rig3.session.check_timeouts()
	ctx.check(rig3.transport.reject_codes(1) == [Protocol.REJECT_NOT_AUTHENTICATED] and not rig3.session.has_peer(1), "timeout do redeem -> reject(5) e peer descartado")
	rig3.fake.flush() # resposta tardia com sucesso: o lock precisa ser solto
	ctx.check(rig3.world.player_count() == 0 and rig3.transport.welcomes.is_empty(), "resposta tardia nao cria jogador")
	ctx.check(rig3.fake.count("/release") == 1 and rig3.fake.count("GET /internal/characters/") == 0, "resposta tardia: release do lock, sem carga")
	rig3.free_all()
	# peer sai enquanto pendente
	var rig4: B.BRig = _tk_rig(tree, true)
	B.hello(rig4, 1, B.TICKET1)
	rig4.session.on_peer_disconnected(1)
	rig4.fake.flush()
	ctx.check(rig4.world.player_count() == 0 and rig4.fake.count("/release") == 1, "peer saiu durante o redeem: sem jogador, lock liberado")
	rig4.free_all()


func _test_pending_limit(ctx: Object, tree: SceneTree) -> void:
	var rig: B.BRig = _tk_rig(tree, true)
	rig.settings.max_pending = 2
	B.hello(rig, 1, B.TICKET1)
	B.hello(rig, 2, B.TICKET1)
	B.hello(rig, 3, B.TICKET1)
	ctx.check(rig.transport.reject_codes(3) == [Protocol.REJECT_SERVER_FULL] and rig.fake.count("redeem") == 2, "limite de pendentes: 3o hello -> reject(3), sem chamar o backend")
	rig.free_all()


func _test_duplicate_character(ctx: Object, tree: SceneTree) -> void:
	var rig: B.BRig = _tk_rig(tree)
	rig.fake.tickets[B.TICKET2] = B.CID1 # outro ticket para o MESMO personagem (backend falho/permissivo)
	B.hello(rig, 1, B.TICKET1)
	B.hello(rig, 2, B.TICKET2)
	ctx.check(rig.session.get_peer_state(1).welcomed and rig.transport.reject_codes(2) == [Protocol.REJECT_NOT_AUTHENTICATED], "mesmo personagem em 2 peers: o segundo e recusado")
	ctx.check(rig.world.player_count() == 1 and rig.fake.count("/release") == 0, "o primeiro segue jogando e o lock dele nao e liberado")
	rig.free_all()


func _join_one(rig: B.BRig, peer_id: int = 1) -> PlayerLoadout:
	B.hello(rig, peer_id, B.TICKET1)
	return B.loadout_of(rig, peer_id)


func _test_autosave_and_serialization(ctx: Object, tree: SceneTree) -> void:
	var rig: B.BRig = _tk_rig(tree)
	var lo: PlayerLoadout = _join_one(rig)
	lo.grant_xp(100)
	rig.sync.tick(30.0)
	var cps: Array[Dictionary] = rig.fake.find_all("/checkpoint")
	ctx.check(cps.size() == 1 and int(cps[0]["body"]["expected_revision"]) == 5, "autosave: checkpoint com expected_revision=5")
	var state: Dictionary = cps[0]["body"]["state"]
	ctx.check(int(state["xp"]) == 800 and int(state["level"]) == 3 and int(state["schema_version"]) == 1, "autosave: estado COMPLETO do servidor (xp 800)")
	ctx.check(state["equipment"]["armor"] == "armor_heavy" and state["inventory"].size() == 2 and state["stats"].size() == 7, "autosave: inventario/equipamento/stats completos")
	ctx.check(rig.sync.revision_of(B.CID1) == 6, "autosave: revision adotada do backend (6)")
	rig.sync.tick(30.0)
	ctx.check(int(rig.fake.find_all("/checkpoint")[1]["body"]["expected_revision"]) == 6, "2o autosave usa expected_revision=6")
	rig.free_all()
	# serializacao: respostas retidas -> uma operacao por vez por personagem, coalescencia de autosave
	var rs: B.BRig = _tk_rig(tree)
	var lo2: PlayerLoadout = _join_one(rs)
	rs.fake.hold = true
	var cid: String = B.CID1
	rs.sync.enqueue_reward(cid, "kill:%s:9:%s" % [Fake.SESSION_ID, cid], 10, [])
	var a1: bool = rs.sync.enqueue_checkpoint(cid, CharacterCodec.capture(lo2), true)
	var a2: bool = rs.sync.enqueue_checkpoint(cid, CharacterCodec.capture(lo2), true)
	var base_req: int = rs.fake.requests.size()
	ctx.check(rs.fake.count("/rewards") == 1 and rs.fake.count("/checkpoint") == 0, "serializado: reward em voo, checkpoint aguarda")
	ctx.check(a1 and not a2, "autosave coalescido (nao empilha 2 checkpoints)")
	rs.fake.flush(1) # reward conclui -> checkpoint sai
	ctx.check(rs.fake.count("/checkpoint") == 1 and rs.fake.requests.size() == base_req + 1, "checkpoint so sai depois da recompensa terminar")
	var cp_rev: int = int(rs.fake.find_all("/checkpoint")[0]["body"]["expected_revision"])
	ctx.check(cp_rev == 6, "checkpoint usa a revision devolvida pela recompensa (6)")
	rs.fake.flush()
	ctx.check(rs.sync.revision_of(cid) == 7, "revision final 7 apos reward + checkpoint")
	rs.free_all()


func _test_disconnect_checkpoint(ctx: Object, tree: SceneTree) -> void:
	var rig: B.BRig = _tk_rig(tree)
	var lo: PlayerLoadout = _join_one(rig)
	lo.grant_xp(50)
	rig.session.on_peer_disconnected(1)
	var order: Array[String] = rig.fake.order()
	var tail: Array[String] = order.slice(order.size() - 2)
	ctx.check(tail == ["POST /internal/characters/%s/checkpoint" % B.CID1, "POST /internal/characters/%s/disconnect" % B.CID1], "desconexao: checkpoint e DEPOIS disconnect")
	var cp: Dictionary = rig.fake.find_all("/checkpoint")[0]["body"]
	ctx.check(int(cp["state"]["xp"]) == 750 and int(cp["expected_revision"]) == 5, "checkpoint final com o xp em memoria (750)")
	ctx.check(rig.fake.find_all("/disconnect")[0]["body"]["session_id"] == Fake.SESSION_ID and rig.world.player_count() == 0, "disconnect com session_id; jogador removido")
	ctx.check(rig.sync.char_sync(B.CID1) == null, "fila do personagem descartada apos drenar")
	# reconexao: novo ticket, mesmo personagem
	rig.fake.tickets[B.TICKET2] = B.CID1
	B.hello(rig, 2, B.TICKET2)
	var lo2: PlayerLoadout = B.loadout_of(rig, 2)
	ctx.check(lo2 != null and lo2.progress.total_xp == 750, "reconexao: personagem volta com o xp persistido")
	rig.free_all()


func _test_real_kill_reward(ctx: Object, tree: SceneTree) -> void:
	var rig: B.BRig = _tk_rig(tree)
	var lo: PlayerLoadout = _join_one(rig)
	var st: ServerSession.PeerState = rig.session.get_peer_state(1)
	var pnode: Player = rig.world.get_player_node(st.entity_id)
	var eid: int = rig.world.spawn_enemy(B.H.GRUNT_SCENE, Vector3(30, 0.05, 30))
	var enemy: Enemy = rig.world.get_enemy_node(eid)
	var xp_before: int = lo.progress.total_xp
	var stacks_before: int = lo.inventory.count(&"potion_minor") + lo.inventory.count(&"scrap_material") + lo.inventory.count(&"sword_rare") + lo.inventory.count(&"amulet_vigor")
	var reward_xp: int = enemy.data.xp_reward
	enemy.health.apply_damage(DamageInfo.make(99999.0, pnode, Hitbox.new_hit_id()))
	var rw: Array[Dictionary] = rig.fake.find_all("/rewards")
	ctx.check(rw.size() == 1, "morte de inimigo: 1 recompensa enviada ao backend")
	var body: Dictionary = rw[0]["body"] if not rw.is_empty() else {}
	ctx.check(body.get("idempotency_key", "") == "kill:%s:%d:%s" % [Fake.SESSION_ID, eid, B.CID1], "chave estavel kill:<session>:<enemy>:<character>")
	ctx.check(int(body.get("xp", -1)) == reward_xp and reward_xp > 0, "xp da recompensa = xp decidido pelo servidor (%d)" % reward_xp)
	ctx.check(lo.progress.total_xp >= xp_before + reward_xp, "xp tambem aplicado em memoria")
	var sent_qty: int = 0
	for it: Variant in body.get("items", []):
		sent_qty += int((it as Dictionary)["qty"])
	var stacks_after: int = lo.inventory.count(&"potion_minor") + lo.inventory.count(&"scrap_material") + lo.inventory.count(&"sword_rare") + lo.inventory.count(&"amulet_vigor")
	ctx.check(stacks_after - stacks_before == sent_qty, "drops persistidos = drops adicionados ao inventario em memoria (%d)" % sent_qty)
	# o cliente nunca decide: nenhum caminho de rede aceita recompensa; so o mundo emite enemy_killed
	ctx.check(rig.sync.revision_of(B.CID1) == 6, "revision adotada da resposta da recompensa")
	rig.free_all()


func _test_reward_retry_same_key(ctx: Object, tree: SceneTree) -> void:
	var rig: B.BRig = _tk_rig(tree)
	_join_one(rig)
	var key: String = "kill:%s:7:%s" % [Fake.SESSION_ID, B.CID1]
	rig.fake.force("/rewards", [Fake.NET_ERR, Fake.TIMEOUT_ERR])
	rig.sync.enqueue_reward(B.CID1, key, 25, [{"item_id": "potion_minor", "qty": 2}])
	var t0: int = Time.get_ticks_msec()
	while rig.fake.find_all("/rewards").size() < 3 and Time.get_ticks_msec() - t0 < 3000:
		await tree.process_frame
	for i: int in 5:
		await tree.process_frame
	var rw: Array[Dictionary] = rig.fake.find_all("/rewards")
	ctx.check(rw.size() == 3, "recompensa: retry em erro de rede/timeout (3 tentativas)")
	var same: bool = rw.size() == 3 and rw[0]["raw"] == rw[1]["raw"] and rw[1]["raw"] == rw[2]["raw"]
	ctx.check(same and rw[2]["body"]["idempotency_key"] == key, "retry reutiliza a MESMA idempotency_key e o mesmo corpo")
	ctx.check(rig.fake.claims.has(key) and int(rig.fake.chars[B.CID1]["xp"]) == 725, "backend aplicou a recompensa uma unica vez")
	ctx.check(rig.sync.revision_of(B.CID1) == 6, "revision adotada apos o retry")
	# replay explicito (resposta perdida apos aplicar): a mesma chave nao reaplica
	rig.sync.enqueue_reward(B.CID1, key, 25, [{"item_id": "potion_minor", "qty": 2}])
	ctx.check(int(rig.fake.chars[B.CID1]["xp"]) == 725, "replay da mesma chave nao duplica xp")
	rig.free_all()


func _test_reward_permanent_failure(ctx: Object, tree: SceneTree) -> void:
	var rig: B.BRig = _tk_rig(tree)
	var lo: PlayerLoadout = _join_one(rig)
	lo.grant_xp(40)
	rig.fake.force("/rewards", [Fake.err(409, "inventory_full")])
	ServerLog.reset_capture()
	rig.sync.enqueue_reward(B.CID1, "kill:%s:8:%s" % [Fake.SESSION_ID, B.CID1], 40, [{"item_id": "potion_minor", "qty": 1}])
	ctx.check(rig.fake.count("/rewards") == 1, "falha permanente (409) nao e repetida")
	ctx.check(ServerLog.joined().contains("falhou de forma permanente") and lo.progress.total_xp == 740, "falha permanente logada; estado em memoria preservado (xp 740)")
	rig.sync.tick(30.0)
	ctx.check(int(rig.fake.find_all("/checkpoint")[0]["body"]["state"]["xp"]) == 740, "proximo checkpoint reconcilia o estado (xp 740)")
	rig.free_all()


func _test_revision_conflict(ctx: Object, tree: SceneTree) -> void:
	var rig: B.BRig = _tk_rig(tree)
	var lo: PlayerLoadout = _join_one(rig)
	# algo externo mexeu no personagem: revision 9 e xp 1500
	rig.fake.chars[B.CID1]["revision"] = 9
	rig.fake.chars[B.CID1]["xp"] = 1500
	rig.fake.chars[B.CID1]["level"] = 4
	ServerLog.reset_capture()
	rig.sync.tick(30.0)
	ctx.check(rig.fake.count("/checkpoint") == 1 and rig.fake.count("GET /internal/characters/") == 2, "409 de revision: recarrega o personagem (GET)")
	ctx.check(rig.sync.revision_of(B.CID1) == 9, "revision adotada do backend (9)")
	ctx.check(lo.progress.total_xp == 1500 and lo.progress.level == 4, "estado do backend reaplicado ao jogador vivo")
	ctx.check(rig.session.has_peer(1) and rig.session.get_peer_state(1).welcomed and rig.transport.rejects.is_empty(), "conflito nao derruba o jogador")
	ctx.check(ServerLog.joined().contains("conflito de revision"), "conflito registrado no log")
	rig.sync.tick(30.0)
	ctx.check(int(rig.fake.find_all("/checkpoint")[1]["body"]["expected_revision"]) == 9, "proximo checkpoint usa a revision recarregada")
	rig.free_all()


func _test_heartbeat_and_reregister(ctx: Object, tree: SceneTree) -> void:
	var rig: B.BRig = B.make(tree)
	rig.sync.tick(5.0)
	ctx.check(rig.fake.count("/heartbeat") == 0, "heartbeat so no intervalo")
	rig.sync.tick(5.0)
	ctx.check(rig.fake.count("/heartbeat") == 1, "heartbeat periodico enviado")
	rig.fake.force("/heartbeat", [Fake.err(409, "session_closed")])
	rig.sync.tick(10.0)
	ctx.check(not rig.sync.is_ready(), "heartbeat 409 session_closed: sessao marcada como perdida")
	rig.sync.tick(6.0)
	ctx.check(rig.sync.is_ready() and rig.fake.count_path("/internal/sessions") == 2, "re-registro automatico depois de perder a sessao")
	rig.free_all()
	# registro com backend fora do ar: tenta de novo com espera
	var rn: B.BRig = _register_down(tree)
	ctx.check(not rn.sync.is_ready(), "backend fora do ar no boot: nao pronto (hellos recusados)")
	rn.fake.forced.clear()
	rn.sync.tick(5.1) # 1 falha -> espera = register_retry_sec (5 s)
	ctx.check(rn.sync.is_ready(), "backend volta: registro na proxima tentativa")
	rn.free_all()


func _register_down(tree: SceneTree) -> B.BRig:
	var r: B.BRig = B.BRig.new()
	r.base = B.H.make_rig(tree, false, 4, false)
	r.world = r.base.world
	r.session = r.base.session
	r.transport = r.base.transport
	r.settings = r.base.settings
	r.fake = Fake.new()
	r.fake.force("POST /internal/sessions", [Fake.NET_ERR, Fake.NET_ERR, Fake.NET_ERR, Fake.NET_ERR])
	r.client = BackendClient.new()
	tree.root.add_child(r.client)
	r.client.transport = r.fake
	r.client.configure("http://127.0.0.1:8787", B.SECRET)
	r.sync = BackendSync.new()
	r.sync.client = r.client
	tree.root.add_child(r.sync)
	r.sync.set_process(false)
	r.session.attach_backend(r.sync)
	r.sync.start()
	return r


func _test_clean_shutdown(ctx: Object, tree: SceneTree) -> void:
	var rig: B.BRig = _tk_rig(tree)
	var lo: PlayerLoadout = _join_one(rig)
	lo.grant_xp(10)
	rig.session.shutdown()
	rig.sync.begin_shutdown()
	rig.sync.tick(0.1)
	var order: Array[String] = rig.fake.order()
	var tail: Array[String] = order.slice(order.size() - 3)
	ctx.check(tail == ["POST /internal/characters/%s/checkpoint" % B.CID1, "POST /internal/characters/%s/release" % B.CID1, "POST /internal/sessions/%s/close" % Fake.SESSION_ID], "encerramento: checkpoint + release de cada jogador e DEPOIS close")
	ctx.check(rig.sync.is_shutdown_complete() and rig.fake.count("/disconnect") == 0, "encerramento concluido sem disconnect")
	ctx.check(int(rig.fake.find_all("/checkpoint")[0]["body"]["state"]["xp"]) == 710, "checkpoint final com o xp em memoria")
	rig.free_all()


func _test_shutdown_timeout(ctx: Object, tree: SceneTree) -> void:
	var rig: B.BRig = _tk_rig(tree)
	_join_one(rig)
	rig.fake.hold = true
	rig.session.shutdown()
	rig.sync.begin_shutdown()
	rig.sync.tick(1.0)
	ctx.check(not rig.sync.is_shutdown_complete(), "encerramento aguarda operacoes pendentes")
	rig.sync.tick(rig.sync.shutdown_timeout_sec)
	ctx.check(rig.sync.is_shutdown_complete() and rig.fake.cancelled == 1, "encerramento com prazo: abandona o que ficou pendente e cancela o transporte")
	rig.free_all()


func _test_logs_clean(ctx: Object) -> void:
	var log: String = ServerLog.joined()
	ctx.check(log.length() > 100, "logs capturados durante os testes (%d bytes)" % log.length())
	ctx.check(not log.contains(B.SECRET), "log nao contem o segredo interno")
	ctx.check(not log.contains(B.TICKET1) and not log.contains(B.TICKET2) and not log.contains("ticket-one") and not log.contains("ticket-two"), "log nao contem tickets")
	ctx.check(not log.contains("Bearer"), "log nao contem cabecalho Authorization")
	ServerLog.add_secret("marker-secret-123")
	ctx.check(ServerLog.scrub("x marker-secret-123 y") == "x [redacted] y", "ServerLog.scrub mascara segredos registrados")
	ServerLog.clear_secrets()
