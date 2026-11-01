class_name RecipeDef
extends RefCounted
## Receita de crafting (E5.4), lida de data/recipes/<id>.json (esquema: shared/content_schemas/recipe.schema.json;
## catalogo do backend derivado por tools/gen_recipes_catalog.mjs). Dados puros. Espelha as regras do gerador.

const MAX_INGREDIENTS: int = 4
const MAX_RESULTS: int = 2
const MAX_QTY: int = 99

var id: String = ""
var station: String = ""
var display_name: String = ""
var name_key: String = ""
var ingredients: Array[Dictionary] = [] ## [{item_id: String, qty: int}]
var results: Array[Dictionary] = []


## Devolve {"def": RecipeDef | null, "errors": Array[String]}.
static func parse(raw: Variant) -> Dictionary:
	var errs: Array[String] = []
	if typeof(raw) != TYPE_DICTIONARY:
		return {"def": null, "errors": ["raiz deve ser objeto"] as Array[String]}
	var d: Dictionary = raw
	var def: RecipeDef = RecipeDef.new()
	if not Protocol.is_content_id(d.get("id", null)):
		errs.append("id invalido")
	else:
		def.id = String(d["id"])
	if int(d.get("schema_version", 0)) != 1 or typeof(d.get("schema_version", null)) == TYPE_STRING:
		errs.append("schema_version deve ser 1")
	if not Protocol.is_content_id(d.get("station", null)):
		errs.append("station invalida")
	else:
		def.station = String(d["station"])
	for k: String in ["name", "name_key"]:
		if typeof(d.get(k, null)) != TYPE_STRING or (d[k] as String).strip_edges().is_empty() or (d[k] as String).length() > 96:
			errs.append("'%s' ausente/vazio/longo demais" % k)
	def.display_name = String(d.get("name", ""))
	def.name_key = String(d.get("name_key", ""))
	def.ingredients = _stacks(d.get("ingredients", null), "ingredients", MAX_INGREDIENTS, errs)
	def.results = _stacks(d.get("results", null), "results", MAX_RESULTS, errs)
	for r: Dictionary in def.results:
		for i: Dictionary in def.ingredients:
			if String(i["item_id"]) == String(r["item_id"]):
				errs.append("resultado '%s' tambem e ingrediente (receita circular)" % String(r["item_id"]))
	return {"def": def if errs.is_empty() else null, "errors": errs}


static func _stacks(raw: Variant, label: String, max_n: int, errs: Array[String]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if typeof(raw) != TYPE_ARRAY or (raw as Array).is_empty() or (raw as Array).size() > max_n:
		errs.append("%s deve ter 1..%d entradas" % [label, max_n])
		return out
	var seen: Dictionary = {}
	for s: Variant in raw:
		if typeof(s) != TYPE_DICTIONARY or not Protocol.is_content_id((s as Dictionary).get("item_id", null)):
			errs.append("%s com entrada invalida" % label)
			continue
		var q: Variant = (s as Dictionary).get("qty", null)
		var qty_ok: bool = Protocol.is_finite_number(q) and float(q) == floorf(float(q)) and int(q) >= 1 and int(q) <= MAX_QTY
		if not qty_ok:
			errs.append("%s.qty fora de 1..%d" % [label, MAX_QTY])
			continue
		var iid: String = String((s as Dictionary)["item_id"])
		if seen.has(iid):
			errs.append("%s repete '%s'" % [label, iid])
			continue
		seen[iid] = true
		out.append({"item_id": iid, "qty": int(q)})
	return out


## Resultados no formato de mensagem: [{item_id, qty}] (copia).
func results_payload() -> Array:
	var out: Array = []
	for r: Dictionary in results:
		out.append({"item_id": String(r["item_id"]), "qty": int(r["qty"])})
	return out
