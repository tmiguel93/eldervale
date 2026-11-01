class_name RecipeCatalog
extends RefCounted
## Catalogo de receitas carregado de data/recipes/*.json (arquivos que comecam com "_" sao ignorados).
## `validate` confere as referencias cruzadas: itens do registry e estacoes do mundo.

const RECIPES_DIR: String = "res://data/recipes"

static var _shared: RecipeCatalog = null

var recipes: Dictionary = {} ## id -> RecipeDef
var load_errors: Array[String] = []


static func shared() -> RecipeCatalog:
	if _shared == null:
		_shared = load_dir(RECIPES_DIR)
	return _shared


static func load_dir(dir_path: String = RECIPES_DIR) -> RecipeCatalog:
	var c: RecipeCatalog = RecipeCatalog.new()
	for n: String in JsonDir.list_json(dir_path):
		var r: Dictionary = JsonDir.read_json(dir_path + "/" + n)
		if not bool(r["ok"]):
			c.load_errors.append(String(r["error"]))
			continue
		var p: Dictionary = RecipeDef.parse(r["data"])
		if p["def"] == null:
			for e: String in (p["errors"] as Array):
				c.load_errors.append("%s: %s" % [n, e])
			continue
		var def: RecipeDef = p["def"]
		if n.trim_suffix(".json") != def.id:
			c.load_errors.append("%s: nome do arquivo difere do id '%s'" % [n, def.id])
			continue
		c.add(def)
	return c


func add(def: RecipeDef) -> void:
	if recipes.has(def.id):
		load_errors.append("receita id duplicado: " + def.id)
		return
	recipes[def.id] = def


func get_recipe(recipe_id: String) -> RecipeDef:
	return recipes.get(recipe_id) as RecipeDef


func ids() -> Array[String]:
	var out: Array[String] = []
	for k: Variant in recipes:
		out.append(String(k))
	out.sort()
	return out


## Erros de referencia (lista vazia = ok). `world` pode ser null (so confere os itens).
func validate(registry: ContentRegistry, world: WorldDef) -> Array[String]:
	var errs: Array[String] = load_errors.duplicate()
	var stations: Array[String] = world.station_ids() if world != null else ([] as Array[String])
	for id: String in ids():
		var def: RecipeDef = recipes[id]
		if world != null and not stations.has(def.station):
			errs.append("%s: estacao '%s' nao existe no mundo" % [id, def.station])
		for s: Dictionary in def.ingredients + def.results:
			if registry.get_item(StringName(String(s["item_id"]))) == null:
				errs.append("%s: item '%s' nao existe no registry" % [id, String(s["item_id"])])
	return errs
