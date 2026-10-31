extends SceneTree
## Runner simples. Uso: $G --headless --path . --script res://tests/run_tests.gd
## Sai com codigo 1 se algum check falhar. Cada teste e um RefCounted com run(ctx),
## podendo ser corrotina (o runner aguarda; so ha await de sinais do proprio SceneTree).

const TESTS: Array[String] = [
	"res://tests/e1/test_player_motion.gd",
	"res://tests/e1/test_collision.gd",
	"res://tests/e1/test_occlusion.gd",
]

var passed: int = 0
var failed: int = 0


func _initialize() -> void:
	_run_all()


func _run_all() -> void:
	for path: String in TESTS:
		print("== ", path)
		var script: GDScript = load(path) as GDScript
		if script == null:
			check(false, "carregar " + path)
			continue
		var test: RefCounted = script.new() as RefCounted
		await test.run(self)
	print("RESULTADO: %d passaram, %d falharam" % [passed, failed])
	quit(1 if failed > 0 else 0)


func check(condition: bool, message: String) -> void:
	if condition:
		passed += 1
		print("  PASS  ", message)
	else:
		failed += 1
		print("  FAIL  ", message)
