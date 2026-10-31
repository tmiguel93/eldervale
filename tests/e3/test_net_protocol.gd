extends RefCounted
## Protocol: hello, input, entidade.


func run(ctx: Object) -> void:
	# hello
	var h: Dictionary = Protocol.validate_hello(Protocol.VERSION, "dev-1", "Ana_01 x", "")
	ctx.check(h["ok"] and h["name"] == "Ana_01 x", "hello valido aceito")
	ctx.check(Protocol.validate_hello(Protocol.VERSION, "", " Bob ", "")["name"] == "Bob", "hello: nome com bordas aparadas")
	var hv: Dictionary = Protocol.validate_hello(Protocol.VERSION + 1, "b", "Ana", "")
	ctx.check(not hv["ok"] and hv["code"] == Protocol.REJECT_VERSION, "hello: versao errada -> REJECT_VERSION")
	ctx.check(Protocol.validate_hello(Protocol.VERSION, "b", "", "")["code"] == Protocol.REJECT_INVALID_PAYLOAD, "hello: nome vazio rejeitado")
	ctx.check(not Protocol.validate_hello(Protocol.VERSION, "b", "   ", "")["ok"], "hello: nome so espacos rejeitado")
	ctx.check(not Protocol.validate_hello(Protocol.VERSION, "b", "a".repeat(25), "")["ok"], "hello: nome > 24 rejeitado")
	ctx.check(Protocol.validate_hello(Protocol.VERSION, "b", "a".repeat(24), "")["ok"], "hello: nome de 24 aceito")
	ctx.check(not Protocol.validate_hello(Protocol.VERSION, "b", "Ana<script>", "")["ok"], "hello: caracteres invalidos rejeitados")
	ctx.check(not Protocol.validate_hello(Protocol.VERSION, "b", "A\nB", "")["ok"], "hello: newline interno rejeitado")
	ctx.check(not Protocol.validate_hello(Protocol.VERSION, "b".repeat(33), "Ana", "")["ok"], "hello: build > 32 rejeitado")
	ctx.check(not Protocol.validate_hello("1", "b", "Ana", "")["ok"], "hello: version String rejeitada")
	ctx.check(not Protocol.validate_hello(1.0, "b", "Ana", "")["ok"], "hello: version float rejeitada")
	ctx.check(not Protocol.validate_hello(Protocol.VERSION, 5, "Ana", "")["ok"], "hello: build nao-String rejeitado")
	ctx.check(not Protocol.validate_hello(Protocol.VERSION, "b", null, "")["ok"], "hello: nome null rejeitado")
	# v2: ticket
	var tk: String = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ4In0.sig-_09"
	var ht: Dictionary = Protocol.validate_hello(Protocol.VERSION, "b", "Ana", tk)
	ctx.check(ht["ok"] and ht["ticket"] == tk, "hello v2: ticket valido aceito")
	ctx.check(Protocol.validate_hello(Protocol.VERSION, "b", "Ana", "")["ok"], "hello v2: ticket vazio e valido para o validador")
	ctx.check(Protocol.validate_hello(Protocol.VERSION, "b", "Ana", "a".repeat(1024))["ok"], "hello v2: ticket de 1024 aceito")
	ctx.check(not Protocol.validate_hello(Protocol.VERSION, "b", "Ana", "a".repeat(1025))["ok"], "hello v2: ticket > 1024 rejeitado")
	ctx.check(not Protocol.validate_hello(Protocol.VERSION, "b", "Ana", "ab cd")["ok"], "hello v2: ticket com espaco rejeitado")
	ctx.check(not Protocol.validate_hello(Protocol.VERSION, "b", "Ana", "ab\ncd")["ok"], "hello v2: ticket com newline rejeitado")
	ctx.check(not Protocol.validate_hello(Protocol.VERSION, "b", "Ana", "ab/cd+=")["ok"], "hello v2: ticket com charset invalido rejeitado")
	ctx.check(not Protocol.validate_hello(Protocol.VERSION, "b", "Ana", 5)["ok"], "hello v2: ticket nao-String rejeitado")
	ctx.check(not Protocol.validate_hello(Protocol.VERSION, "b", "Ana", null)["ok"], "hello v2: ticket null rejeitado")
	ctx.check(not Protocol.validate_hello(1, "b", "Ana", tk)["ok"] and Protocol.validate_hello(1, "b", "Ana", tk)["code"] == Protocol.REJECT_VERSION, "hello v2: versao 1 -> REJECT_VERSION")
	ctx.check(not "bad" in str(Protocol.validate_hello(Protocol.VERSION, "b", "Ana", "bad ticket!")["message"]), "hello v2: mensagem de erro nao ecoa o ticket")

	# input
	var i: Dictionary = Protocol.validate_input(5, Vector2(0.5, 0.5), 1.0, 3, 4)
	ctx.check(i["ok"] and i["move"] == Vector2(0.5, 0.5) and is_equal_approx(i["yaw"], 1.0), "input valido aceito")
	var big: Dictionary = Protocol.validate_input(5, Vector2(10, 0), 0.0, 0, 0)
	ctx.check(big["ok"] and is_equal_approx((big["move"] as Vector2).length(), 1.0), "input: move clampado a 1")
	var wrap: Dictionary = Protocol.validate_input(5, Vector2.ZERO, 3.0 * PI, 0, 0)
	ctx.check(wrap["ok"] and absf(wrap["yaw"]) <= PI + 0.0001, "input: yaw normalizado")
	ctx.check(not Protocol.validate_input(5, Vector2(NAN, 0), 0.0, 0, 0)["ok"], "input: move NaN rejeitado")
	ctx.check(not Protocol.validate_input(5, Vector2(INF, 0), 0.0, 0, 0)["ok"], "input: move inf rejeitado")
	ctx.check(not Protocol.validate_input(5, Vector2.ZERO, NAN, 0, 0)["ok"], "input: yaw NaN rejeitado")
	ctx.check(not Protocol.validate_input(5, Vector2.ZERO, INF, 0, 0)["ok"], "input: yaw inf rejeitado")
	ctx.check(not Protocol.validate_input(5, Vector2.ZERO, 1e9, 0, 0)["ok"], "input: yaw absurdo rejeitado")
	ctx.check(not Protocol.validate_input(5, Vector2.ZERO, 0.0, 16, 0)["ok"], "input: bit desconhecido rejeitado")
	ctx.check(not Protocol.validate_input(5, Vector2.ZERO, 0.0, -1, 0)["ok"], "input: actions negativo rejeitado")
	ctx.check(Protocol.validate_input(5, Vector2.ZERO, 0.0, Protocol.ACTION_MASK, 0)["ok"], "input: mascara completa aceita")
	var stale: Dictionary = Protocol.validate_input(4, Vector2.ZERO, 0.0, 0, 4)
	ctx.check(not stale["ok"] and stale.get("stale", false), "input: seq repetido -> stale")
	ctx.check(not Protocol.validate_input(3, Vector2.ZERO, 0.0, 0, 4)["ok"], "input: seq menor descartado")
	ctx.check(not Protocol.validate_input("5", Vector2.ZERO, 0.0, 0, 0)["ok"], "input: seq String rejeitado")
	ctx.check(not Protocol.validate_input(5, Vector3.ZERO, 0.0, 0, 0)["ok"], "input: move Vector3 rejeitado")
	ctx.check(not Protocol.validate_input(5, Vector2.ZERO, "x", 0, 0)["ok"], "input: yaw String rejeitado")
	ctx.check(not Protocol.validate_input(5, Vector2.ZERO, 0.0, 1.0, 0)["ok"], "input: actions float rejeitado")
	ctx.check(not Protocol.validate_input(5, null, 0.0, 0, 0)["ok"], "input: move null rejeitado")

	# entidade
	var e: Dictionary = {"id": 1, "kind": Protocol.KIND_PLAYER, "pos": Vector3(1, 0, 2), "yaw": 0.5, "hp": 10.0, "max_hp": 20.0, "state": 0, "type": "player"}
	ctx.check(Protocol.validate_entity_dict(e), "entidade valida aceita")
	ctx.check(not Protocol.validate_entity_dict(null), "entidade null rejeitada")
	ctx.check(not Protocol.validate_entity_dict([]), "entidade Array rejeitada")
	var m: Dictionary = e.duplicate()
	m.erase("hp")
	ctx.check(not Protocol.validate_entity_dict(m), "entidade sem campo rejeitada")
	m = e.duplicate()
	m["kind"] = 9
	ctx.check(not Protocol.validate_entity_dict(m), "entidade kind invalido rejeitada")
	m = e.duplicate()
	m["pos"] = Vector3(NAN, 0, 0)
	ctx.check(not Protocol.validate_entity_dict(m), "entidade pos NaN rejeitada")
	m = e.duplicate()
	m["pos"] = Vector2(1, 1)
	ctx.check(not Protocol.validate_entity_dict(m), "entidade pos tipo errado rejeitada")
	m = e.duplicate()
	m["hp"] = "10"
	ctx.check(not Protocol.validate_entity_dict(m), "entidade hp String rejeitada")
	m = e.duplicate()
	m["hp"] = -1.0
	ctx.check(not Protocol.validate_entity_dict(m), "entidade hp negativo rejeitada")
	m = e.duplicate()
	m["type"] = "x".repeat(33)
	ctx.check(not Protocol.validate_entity_dict(m), "entidade type longo rejeitada")
	m = e.duplicate()
	m["id"] = 1.5
	ctx.check(not Protocol.validate_entity_dict(m), "entidade id float rejeitada")

	ctx.check(Protocol.VERSION == 2 and Protocol.DEFAULT_PORT == 24680 and Protocol.ACTION_MASK == 15, "constantes do contrato")
