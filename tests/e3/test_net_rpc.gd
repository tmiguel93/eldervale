extends RefCounted
## NetRpc: fumaca (sinais, senders, install idempotente) e RPC real em loopback (ENet/UDP em
## 127.0.0.1, dois MultiplayerAPI em subarvores da mesma SceneTree).

const TEST_PORT: int = 24791

var _got: Dictionary = {}


func _on(key: String, args: Array) -> void:
	_got[key] = args


func _wait_for(tree: SceneTree, key: String, timeout_msec: int) -> bool:
	var t0: int = Time.get_ticks_msec()
	while not _got.has(key) and Time.get_ticks_msec() - t0 < timeout_msec:
		await tree.process_frame
	return _got.has(key)


func run(ctx: Object) -> void:
	var tree: SceneTree = ctx as SceneTree
	# --- fumaca
	var n: NetRpc = NetRpc.new()
	for sig: String in ["hello_received", "input_received", "ping_received", "welcome_received", "reject_received", "snapshot_received", "event_received", "pong_received"]:
		ctx.check(n.has_signal(sig), "NetRpc tem sinal " + sig)
	for m: String in ["c_hello", "c_input", "c_ping", "s_welcome", "s_reject", "s_snapshot", "s_event", "s_pong",
			"send_hello", "send_input", "send_ping", "send_welcome", "send_reject", "send_snapshot", "send_event", "send_pong"]:
		ctx.check(n.has_method(m), "NetRpc tem metodo " + m)
	# envio sem conexao nao quebra nem enfileira
	n.sim = NetSim.new()
	n.sim.configure(0, 0, 0.0, 1)
	n.send_hello(1, "b", "Ana", "tk")
	ctx.check(n.sim.pending() == 0, "envio sem conexao e ignorado")
	n.free()

	# --- install idempotente
	var a: NetRpc = NetRpc.install(tree)
	var b: NetRpc = NetRpc.install(tree)
	ctx.check(a != null and a == b, "install idempotente (mesma instancia)")
	ctx.check(a.get_parent() == tree.root and a.name == "NetRpc", "install: no 'NetRpc' na raiz")
	var cnt: int = 0
	for c: Node in tree.root.get_children():
		if c is NetRpc:
			cnt += 1
	ctx.check(cnt == 1, "install: exatamente um NetRpc")
	ctx.check(NetRpc.get_instance(tree) == a, "get_instance devolve o no instalado")
	tree.root.remove_child(a)
	a.free()

	# --- loopback real
	var srv_root: Node = Node.new()
	srv_root.name = "SrvRoot"
	var cli_root: Node = Node.new()
	cli_root.name = "CliRoot"
	tree.root.add_child(srv_root)
	tree.root.add_child(cli_root)
	var srv: NetRpc = NetRpc.new()
	srv.name = "NetRpc"
	var cli: NetRpc = NetRpc.new()
	cli.name = "NetRpc"
	srv_root.add_child(srv)
	cli_root.add_child(cli)
	var sapi: SceneMultiplayer = SceneMultiplayer.new()
	var capi: SceneMultiplayer = SceneMultiplayer.new()
	tree.set_multiplayer(sapi, srv_root.get_path())
	tree.set_multiplayer(capi, cli_root.get_path())
	var sp: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var cp: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var err: int = sp.create_server(TEST_PORT, 2)
	if err != OK:
		ctx.check(false, "loopback: create_server falhou (%d)" % err)
		_cleanup(tree, srv_root, cli_root)
		return
	cp.create_client("127.0.0.1", TEST_PORT)
	sapi.multiplayer_peer = sp
	capi.multiplayer_peer = cp
	srv.hello_received.connect(func(p: int, v: int, bd: String, nm: String, tk: String) -> void: _on("hello", [p, v, bd, nm, tk]))
	srv.input_received.connect(func(p: int, s: int, mv: Vector2, y: float, ac: int, ct: int) -> void: _on("input", [p, s, mv, y, ac, ct]))
	srv.ping_received.connect(func(p: int, t: int) -> void: _on("ping", [p, t]))
	cli.welcome_received.connect(func(pid: int, tr: int, sd: int) -> void: _on("welcome", [pid, tr, sd]))
	cli.reject_received.connect(func(c2: int, m2: String) -> void: _on("reject", [c2, m2]))
	cli.snapshot_received.connect(func(st: int, ls: int, en: Array) -> void: _on("snap", [st, ls, en]))
	cli.event_received.connect(func(ei: int, k: int, d: Dictionary) -> void: _on("event", [ei, k, d]))
	cli.pong_received.connect(func(t: int) -> void: _on("pong", [t]))

	var t0: int = Time.get_ticks_msec()
	while cp.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED and Time.get_ticks_msec() - t0 < 5000:
		await tree.process_frame
	var connected: bool = cp.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED
	ctx.check(connected, "loopback: cliente conectou")
	if connected:
		var cid: int = capi.get_unique_id()
		cli.send_hello(Protocol.VERSION, "dev", "Ana", "tk.abc-1")
		ctx.check(await _wait_for(tree, "hello", 3000), "loopback: c_hello chegou")
		ctx.check(_got.get("hello", []) == [cid, Protocol.VERSION, "dev", "Ana", "tk.abc-1"], "loopback: hello com remetente correto")
		srv.send_welcome(cid, cid, 30, 12345)
		ctx.check(await _wait_for(tree, "welcome", 3000) and _got["welcome"] == [cid, 30, 12345], "loopback: s_welcome")
		cli.send_input(7, Vector2(0.5, -0.5), 1.25, 9, 33)
		ctx.check(await _wait_for(tree, "input", 3000), "loopback: c_input chegou")
		ctx.check(_got.get("input", []) == [cid, 7, Vector2(0.5, -0.5), 1.25, 9, 33], "loopback: input integro")
		cli.send_ping(555)
		ctx.check(await _wait_for(tree, "ping", 3000) and _got["ping"] == [cid, 555], "loopback: c_ping")
		srv.send_pong(cid, 555)
		ctx.check(await _wait_for(tree, "pong", 3000) and _got["pong"] == [555], "loopback: s_pong")
		var ents: Array = [{"id": 1, "kind": 1, "pos": Vector3(1, 2, 3), "yaw": 0.5, "hp": 10.0, "max_hp": 20.0, "state": 0, "type": "player"}]
		srv.send_snapshot(cid, 99, 7, ents)
		ctx.check(await _wait_for(tree, "snap", 3000), "loopback: s_snapshot chegou")
		var snap: Array = _got.get("snap", [0, 0, []])
		ctx.check(snap[0] == 99 and snap[1] == 7 and snap[2].size() == 1 and Protocol.validate_entity_dict(snap[2][0]) and snap[2][0]["pos"] == Vector3(1, 2, 3), "loopback: snapshot integro")
		srv.send_event(cid, 4, Protocol.EVENT_DAMAGE, {"source_id": 1, "target_id": 2, "amount": 5.0, "crit": false})
		ctx.check(await _wait_for(tree, "event", 3000) and _got["event"][0] == 4 and _got["event"][1] == 3 and _got["event"][2]["amount"] == 5.0, "loopback: s_event")
		srv.send_reject(cid, Protocol.REJECT_SERVER_FULL, "cheio")
		ctx.check(await _wait_for(tree, "reject", 3000) and _got["reject"] == [3, "cheio"], "loopback: s_reject")
		# com NetSim: latencia respeitada
		_got.erase("welcome")
		srv.sim = NetSim.new()
		srv.sim.configure(150, 0, 0.0, 1)
		var ts: int = Time.get_ticks_msec()
		srv.send_welcome(cid, cid, 30, 777)
		var arrived: bool = await _wait_for(tree, "welcome", 3000)
		var dt: int = Time.get_ticks_msec() - ts
		ctx.check(arrived and dt >= 150, "loopback: NetSim atrasa >= 150 ms via _process (arrived=%s dt=%d)" % [arrived, dt])
	_cleanup(tree, srv_root, cli_root)


func _cleanup(tree: SceneTree, srv_root: Node, cli_root: Node) -> void:
	for r: Node in [srv_root, cli_root]:
		var api: MultiplayerAPI = tree.get_multiplayer(r.get_path())
		if api.multiplayer_peer != null:
			api.multiplayer_peer.close()
			api.multiplayer_peer = null
		tree.set_multiplayer(MultiplayerAPI.create_default_interface(), r.get_path())
		tree.root.remove_child(r)
		r.free()
