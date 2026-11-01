class_name TalentTree
extends RefCounted
## Arvore de talentos de UMA classe (E6.2), carregada de data/talents/<class_id>.json (mesma fonte do catalogo do backend:
## tools/gen_talents_catalog.mjs -> shared/content_schemas/talents.json). Dados puros + validacao; sem logica de jogo.
## No: {id, name, description, tier, spec, requires: Array[String], min_points_spent, min_level, cost, max_rank, effects: Array[Dictionary]}.
## `spec` vazio = no generico da classe (sempre disponivel); senao exige a especializacao escolhida. Efeitos:
##  - {type: "stat", stat, amount}           : soma `amount * rank` ao stat final (via StatCalculator);
##  - {type: "skill_mod", skill, mod, ...}   : modificador de habilidade aplicado em tempo de uso (SkillMods), tipos em MOD_KEYS.
## Espelha tools/gen_talents_catalog.mjs (mesmas faixas e regras); a paridade e conferida por teste.

const TIERS: Array[String] = ["small", "notable", "mastery"]
const STATS: Array[String] = ["max_health", "max_resource", "resource_regen", "attack_power", "defense", "resistance", "move_speed"]
const ELEMENTS: Array[String] = ["physical", "fire", "ice", "lightning"]
const WHEN: Array[String] = ["self_hp_below", "self_hp_above", "resource_above"]
const MOD_KEYS: Dictionary = {
	"damage": ["damage_pct"],
	"extra_projectiles": ["count", "spread_deg", "damage_scale"],
	"area": ["radius_pct"],
	"duration": ["i_frames_add"],
	"cost": ["cost_pct", "cooldown_pct"],
	"convert": ["to", "damage_pct"],
	"condition": ["when", "threshold", "damage_pct"],
	"synergy": ["after_skill", "window", "damage_pct"],
}
const MAX_NODES: int = 40
const MAX_RANK: int = 5
const MAX_COST: int = 10
const MAX_EFFECTS: int = 6
const MAX_REQUIRES: int = 4

var class_id: String = ""
var nodes: Dictionary = {} ## id -> Dictionary (no)
var order: Array[String] = [] ## ids na ordem do arquivo
var specs: Array[String] = [] ## especializacoes iniciais da classe (preenchido pelo catalogo)


static func _is_int(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or (typeof(v) == TYPE_FLOAT and Protocol.is_finite_number(v) and v == floorf(v))


static func _in_range(v: Variant, lo: float, hi: float) -> bool:
	return (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT) and Protocol.is_finite_number(v) and float(v) >= lo and float(v) <= hi


func get_node_def(node_id: String) -> Dictionary:
	return nodes.get(node_id, {}) as Dictionary


func has_node_id(node_id: Variant) -> bool:
	return typeof(node_id) == TYPE_STRING and nodes.has(String(node_id))


## Soma de cost*max_rank de todos os nos (quanto custaria pegar tudo). Opcional: so os genericos + uma especializacao.
func total_cost(only_spec: String = "*") -> int:
	var t: int = 0
	for id: String in order:
		var n: Dictionary = nodes[id]
		if only_spec == "*" or String(n["spec"]) == "" or String(n["spec"]) == only_spec:
			t += int(n["cost"]) * int(n["max_rank"])
	return t


## Profundidade do no no grafo de requisitos (raiz = 0). Arvore acliclica garantida pelo parse.
func depth(node_id: String) -> int:
	var n: Dictionary = get_node_def(node_id)
	if n.is_empty():
		return 0
	var d: int = 0
	for r: String in (n["requires"] as Array):
		d = maxi(d, depth(r) + 1)
	return d


## Converte o JSON (Variant) em TalentTree. Devolve {"tree": TalentTree|null, "errors": Array[String]}; a arvore so existe sem erros.
static func parse(data: Variant) -> Dictionary:
	var errors: Array[String] = []
	if typeof(data) != TYPE_DICTIONARY:
		return {"tree": null, "errors": ["raiz deve ser objeto"] as Array[String]}
	var d: Dictionary = data
	for k: Variant in d:
		if not ["schema_version", "class_id", "nodes"].has(String(k)):
			errors.append("campo desconhecido: " + String(k).left(40))
	if not _is_int(d.get("schema_version", null)) or int(d["schema_version"]) != 1:
		errors.append("schema_version deve ser 1")
	var tree: TalentTree = TalentTree.new()
	if not ClassDef.is_valid_id(d.get("class_id", null)):
		errors.append("class_id invalido")
	else:
		tree.class_id = String(d["class_id"])
	var raw_nodes: Variant = d.get("nodes", null)
	if typeof(raw_nodes) != TYPE_ARRAY or (raw_nodes as Array).is_empty() or (raw_nodes as Array).size() > MAX_NODES:
		errors.append("nodes deve ter 1..%d" % MAX_NODES)
		return {"tree": null, "errors": errors}
	for e: Variant in raw_nodes:
		var n: Dictionary = _parse_node(e, errors)
		if n.is_empty():
			continue
		if tree.nodes.has(n["id"]):
			errors.append("no '%s': id duplicado" % n["id"])
			continue
		tree.nodes[n["id"]] = n
		tree.order.append(String(n["id"]))
	_check_graph(tree, errors)
	var masteries: int = 0
	for id: String in tree.order:
		if String((tree.nodes[id] as Dictionary)["tier"]) == "mastery":
			masteries += 1
	if masteries != 1:
		errors.append("a arvore deve ter exatamente 1 maestria (tem %d)" % masteries)
	return {"tree": tree if errors.is_empty() else null, "errors": errors}


static func _parse_node(e: Variant, errors: Array[String]) -> Dictionary:
	if typeof(e) != TYPE_DICTIONARY:
		errors.append("no invalido")
		return {}
	var s: Dictionary = e
	var nid: String = str(s.get("id", ""))
	var w: String = "no '%s'" % nid.left(48)
	for k: Variant in s:
		if not ["id", "name", "description", "tier", "spec", "requires", "min_points_spent", "min_level", "cost", "max_rank", "effects"].has(String(k)):
			errors.append("%s: campo desconhecido %s" % [w, String(k).left(40)])
	if not ClassDef.is_valid_id(s.get("id", null)):
		errors.append("%s: id invalido" % w)
		return {}
	var before: int = errors.size()
	var nm: Variant = s.get("name", null)
	if typeof(nm) != TYPE_STRING or String(nm).strip_edges().is_empty() or String(nm).length() > 60:
		errors.append("%s: name invalido" % w)
	var desc: Variant = s.get("description", null)
	if typeof(desc) != TYPE_STRING or String(desc).length() > 300:
		errors.append("%s: description invalida" % w)
	if typeof(s.get("tier", null)) != TYPE_STRING or not TIERS.has(String(s["tier"])):
		errors.append("%s: tier invalido" % w)
	var spec: Variant = s.get("spec", null)
	if typeof(spec) != TYPE_STRING or (String(spec) != "" and not ClassDef.is_valid_id(spec)):
		errors.append("%s: spec invalida" % w)
	for kv: Array in [["cost", 1, MAX_COST], ["max_rank", 1, MAX_RANK], ["min_points_spent", 0, 100], ["min_level", 1, 50]]:
		var v: Variant = s.get(kv[0], null)
		if not _is_int(v) or int(v) < int(kv[1]) or int(v) > int(kv[2]):
			errors.append("%s: %s deve ser inteiro %d..%d" % [w, kv[0], kv[1], kv[2]])
	var req: Array[String] = []
	var rv: Variant = s.get("requires", null)
	if typeof(rv) != TYPE_ARRAY or (rv as Array).size() > MAX_REQUIRES:
		errors.append("%s: requires invalido" % w)
	else:
		for r: Variant in rv:
			if not ClassDef.is_valid_id(r) or req.has(String(r)):
				errors.append("%s: requires com id invalido/repetido" % w)
			else:
				req.append(String(r))
	var fx_list: Array[Dictionary] = []
	var ev: Variant = s.get("effects", null)
	if typeof(ev) != TYPE_ARRAY or (ev as Array).is_empty() or (ev as Array).size() > MAX_EFFECTS:
		errors.append("%s: effects deve ter 1..%d" % [w, MAX_EFFECTS])
	else:
		for fx: Variant in ev:
			var pe: Dictionary = _parse_effect(fx, w, errors)
			if not pe.is_empty():
				fx_list.append(pe)
	if errors.size() > before:
		return {}
	return {
		"id": nid, "name": String(nm), "description": String(desc), "tier": String(s["tier"]), "spec": String(spec), "requires": req,
		"min_points_spent": int(s["min_points_spent"]), "min_level": int(s["min_level"]), "cost": int(s["cost"]), "max_rank": int(s["max_rank"]),
		"effects": fx_list,
	}


static func _parse_effect(fx: Variant, w: String, errors: Array[String]) -> Dictionary:
	if typeof(fx) != TYPE_DICTIONARY:
		errors.append("%s: efeito deve ser objeto" % w)
		return {}
	var f: Dictionary = fx
	var n0: int = errors.size()
	var out: Dictionary = {}
	var t: String = str(f.get("type", ""))
	if t == "stat":
		for k: Variant in f:
			if not ["type", "stat", "amount"].has(String(k)):
				errors.append("%s: campo %s desconhecido no efeito stat" % [w, String(k).left(40)])
		var st: String = str(f.get("stat", ""))
		if not STATS.has(st):
			errors.append("%s: stat desconhecido" % w)
		elif not _in_range(f.get("amount", null), 0.0001, 0.1 if st == "resistance" else 1000.0):
			errors.append("%s: stat.amount fora de faixa" % w)
		else:
			out = {"type": "stat", "stat": st, "amount": float(f["amount"])}
	elif t == "skill_mod":
		var m: String = str(f.get("mod", ""))
		if not MOD_KEYS.has(m):
			errors.append("%s: mod desconhecido" % w)
			return {}
		var allowed: Array = ["type", "skill", "mod"] + (MOD_KEYS[m] as Array)
		for k: Variant in f:
			if not allowed.has(String(k)):
				errors.append("%s: campo %s desconhecido no modificador" % [w, String(k).left(40)])
		if not ClassDef.is_valid_id(f.get("skill", null)):
			errors.append("%s: skill invalida" % w)
		out = {"type": "skill_mod", "skill": str(f.get("skill", "")), "mod": m}
		match m:
			"damage":
				_num(f, out, "damage_pct", 0.01, 2.0, true, w, errors)
			"extra_projectiles":
				if not _is_int(f.get("count", null)) or int(f["count"]) < 1 or int(f["count"]) > 2:
					errors.append("%s: count deve ser inteiro 1..2" % w)
				else:
					out["count"] = int(f["count"])
				_num(f, out, "spread_deg", 1.0, 45.0, true, w, errors)
				_num(f, out, "damage_scale", 0.1, 1.0, true, w, errors)
			"area":
				_num(f, out, "radius_pct", 0.01, 1.0, true, w, errors)
			"duration":
				_num(f, out, "i_frames_add", 0.01, 0.5, true, w, errors)
			"cost":
				if not f.has("cost_pct") and not f.has("cooldown_pct"):
					errors.append("%s: cost exige cost_pct e/ou cooldown_pct" % w)
				_num(f, out, "cost_pct", -0.9, 0.0, false, w, errors)
				_num(f, out, "cooldown_pct", -0.9, 0.0, false, w, errors)
			"convert":
				if not ELEMENTS.has(str(f.get("to", ""))):
					errors.append("%s: convert.to invalido" % w)
				else:
					out["to"] = str(f["to"])
				_num(f, out, "damage_pct", 0.0, 1.0, false, w, errors)
			"condition":
				if not WHEN.has(str(f.get("when", ""))):
					errors.append("%s: condition.when invalido" % w)
				else:
					out["when"] = str(f["when"])
				_num(f, out, "threshold", 0.05, 0.95, true, w, errors)
				_num(f, out, "damage_pct", 0.01, 2.0, true, w, errors)
			"synergy":
				if not ClassDef.is_valid_id(f.get("after_skill", null)):
					errors.append("%s: after_skill invalido" % w)
				else:
					out["after_skill"] = str(f["after_skill"])
				_num(f, out, "window", 0.5, 10.0, true, w, errors)
				_num(f, out, "damage_pct", 0.01, 2.0, true, w, errors)
	else:
		errors.append("%s: type de efeito deve ser stat|skill_mod" % w)
	return out if errors.size() == n0 else {}


static func _num(f: Dictionary, out: Dictionary, key: String, lo: float, hi: float, required: bool, w: String, errors: Array[String]) -> void:
	if not f.has(key):
		if required:
			errors.append("%s: %s ausente" % [w, key])
		return
	if not _in_range(f[key], lo, hi):
		errors.append("%s: %s fora de %s..%s" % [w, key, str(lo), str(hi)])
		return
	out[key] = float(f[key])


static func _check_graph(tree: TalentTree, errors: Array[String]) -> void:
	for id: String in tree.order:
		var n: Dictionary = tree.nodes[id]
		for r: String in (n["requires"] as Array):
			if not tree.nodes.has(r):
				errors.append("no '%s': requisito '%s' inexistente" % [id, r])
			elif r == id:
				errors.append("no '%s': requisito de si mesmo" % id)
			else:
				var rn: Dictionary = tree.nodes[r]
				if String(n["spec"]) == "" and String(rn["spec"]) != "":
					errors.append("no '%s': no generico nao pode exigir no de especializacao ('%s')" % [id, r])
				elif String(n["spec"]) != "" and String(rn["spec"]) != "" and String(rn["spec"]) != String(n["spec"]):
					errors.append("no '%s': requisito de outra especializacao ('%s')" % [id, r])
	# ciclos (DFS iterativo por cor)
	var color: Dictionary = {}
	for start: String in tree.order:
		if color.get(start, 0) == 2:
			continue
		var stack: Array[Array] = [[start, 0]]
		color[start] = 1
		while not stack.is_empty():
			var top: Array = stack[stack.size() - 1]
			var cur: String = top[0]
			var reqs: Array = (tree.nodes[cur] as Dictionary)["requires"]
			if int(top[1]) >= reqs.size():
				color[cur] = 2
				stack.pop_back()
				continue
			var nxt: String = reqs[int(top[1])]
			top[1] = int(top[1]) + 1
			if not tree.nodes.has(nxt):
				continue
			if color.get(nxt, 0) == 1:
				errors.append("ciclo de requisitos envolvendo '%s'" % nxt)
				return
			if color.get(nxt, 0) == 0:
				color[nxt] = 1
				stack.append([nxt, 0])
