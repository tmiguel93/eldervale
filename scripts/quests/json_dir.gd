class_name JsonDir
extends RefCounted
## Leitura de arquivos JSON de conteudo (data/**.json). Silencioso em JSON invalido (devolve erro).


## Le e parseia um arquivo. Retorna {"ok": bool, "data": Variant, "error": String}.
static func read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "data": null, "error": "%s: arquivo ausente" % path}
	var text: String = FileAccess.get_file_as_string(path)
	var json: JSON = JSON.new() # parse() nao imprime erro (parse_string imprimiria)
	if json.parse(text) != OK:
		return {"ok": false, "data": null, "error": "%s: JSON invalido (linha %d)" % [path, json.get_error_line()]}
	return {"ok": true, "data": json.data, "error": ""}


## Nomes dos *.json de um diretorio, em ordem alfabetica; ignora os que comecam com "_".
static func list_json(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return out
	for n: String in dir.get_files():
		var name: String = n.trim_suffix(".remap")
		if name.ends_with(".json") and not name.begins_with("_"):
			out.append(name)
	out.sort()
	return out
