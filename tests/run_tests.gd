extends SceneTree
## Runner simples. Uso: $G --headless --path . --script res://tests/run_tests.gd
## Sai com codigo 1 se algum check falhar. Cada teste e um RefCounted com run(ctx),
## podendo ser corrotina (o runner aguarda; so ha await de sinais do proprio SceneTree).

const TESTS_ROOT: String = "res://tests"

var passed: int = 0
var failed: int = 0


func _initialize() -> void:
	_run_all()


func _run_all() -> void:
	# Filtro opcional (E5.1): `-- --only=tests/e5` (prefixo/trecho do caminho) roda so uma parte da suite.
	var only: String = ""
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.substr(7)
	for path: String in _discover(TESTS_ROOT):
		if not only.is_empty() and not path.contains(only):
			continue
		print("== ", path)
		var script: GDScript = load(path) as GDScript
		if script == null:
			check(false, "carregar " + path)
			continue
		var test: RefCounted = script.new() as RefCounted
		await test.run(self)
	print("RESULTADO: %d passaram, %d falharam" % [passed, failed])
	quit(1 if failed > 0 else 0)


## Descobre recursivamente tests/**/test_*.gd, em ordem alfabetica (estavel).
func _discover(dir_path: String) -> Array[String]:
	var found: Array[String] = []
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return found
	var names: PackedStringArray = dir.get_directories()
	for n: String in names:
		found.append_array(_discover(dir_path + "/" + n))
	for f: String in dir.get_files():
		if f.begins_with("test_") and f.ends_with(".gd"):
			found.append(dir_path + "/" + f)
	found.sort()
	return found


func check(condition: bool, message: String) -> void:
	if condition:
		passed += 1
		print("  PASS  ", message)
	else:
		failed += 1
		print("  FAIL  ", message)
