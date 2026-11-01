class_name TalentState
extends RefCounted
## Estado de talentos de UM personagem (E6.2): especializacao escolhida + niveis (ranks) por no + contagem de respecs.
## Persistido pelo BACKEND (characters.talents, jsonb) e alterado SO por comandos validados (alocar/escolher/respec); o checkpoint do
## servidor de jogo nunca o envia. As regras (`check_*`) sao puras e espelham backend/src/talents/rules.ts; o backend e a autoridade
## final. Codigos de erro (strings estaveis, iguais no backend): unknown_node, spec_not_chosen, wrong_spec, max_rank, level_too_low,
## prerequisite, no_points, unknown_spec, spec_already_chosen, nothing_to_reset.

const MAX_RESPECS: int = 1_000_000

var spec_id: String = ""
var ranks: Dictionary = {} ## node_id (String) -> rank (int >= 1)
var respecs: int = 0


func rank_of(node_id: String) -> int:
	return int(ranks.get(node_id, 0))


func is_empty() -> bool:
	return spec_id == "" and ranks.is_empty()


func copy() -> TalentState:
	var s: TalentState = TalentState.new()
	s.spec_id = spec_id
	s.ranks = ranks.duplicate()
	s.respecs = respecs
	return s


func to_dict() -> Dictionary:
	return {"spec": spec_id, "ranks": ranks.duplicate(), "respecs": respecs}


## Assinatura estavel (chaves ordenadas) para comparar estados.
func signature() -> String:
	return JSON.stringify(to_dict(), "", true)


## Pontos gastos nos nos CONHECIDOS da arvore.
func points_spent(tree: TalentTree) -> int:
	var t: int = 0
	for id: Variant in ranks:
		var n: Dictionary = tree.get_node_def(String(id))
		if not n.is_empty():
			t += int(n["cost"]) * int(ranks[id])
	return t


func points_available(tree: TalentTree, level: int, catalog: TalentCatalog) -> int:
	return maxi(0, catalog.points_for_level(level) - points_spent(tree))


## Forma do JSON vindo do backend (`characters.talents`). "" se valido. NAO confere ids contra a arvore (isso e do `restore`).
static func shape_error(raw: Variant) -> String:
	if typeof(raw) != TYPE_DICTIONARY:
		return "talents deve ser objeto"
	var d: Dictionary = raw
	for k: Variant in d:
		if not ["spec", "ranks", "respecs"].has(String(k)):
			return "talents: campo desconhecido"
	if d.has("spec") and (typeof(d["spec"]) != TYPE_STRING or (String(d["spec"]) != "" and not ClassDef.is_valid_id(d["spec"]))):
		return "talents.spec invalido"
	if d.has("respecs") and (not TalentTree._is_int(d["respecs"]) or int(d["respecs"]) < 0 or int(d["respecs"]) > MAX_RESPECS):
		return "talents.respecs invalido"
	if d.has("ranks"):
		if typeof(d["ranks"]) != TYPE_DICTIONARY or (d["ranks"] as Dictionary).size() > TalentTree.MAX_NODES:
			return "talents.ranks invalido"
		for id: Variant in (d["ranks"] as Dictionary):
			if not ClassDef.is_valid_id(id) or not TalentTree._is_int((d["ranks"] as Dictionary)[id]) \
					or int((d["ranks"] as Dictionary)[id]) < 1 or int((d["ranks"] as Dictionary)[id]) > TalentTree.MAX_RANK:
				return "talents.ranks: entrada invalida"
	return ""


## Restaura em-place a partir do JSON (ja com forma valida). Leniente: nos desconhecidos sao descartados, rank limitado ao max_rank,
## spec desconhecida vira "". Devolve avisos.
func restore(raw: Variant, tree: TalentTree) -> Array[String]:
	var warns: Array[String] = []
	spec_id = ""
	ranks = {}
	respecs = 0
	if typeof(raw) != TYPE_DICTIONARY:
		return warns
	var d: Dictionary = raw
	respecs = clampi(int(d.get("respecs", 0)), 0, MAX_RESPECS)
	var sp: String = String(d.get("spec", ""))
	if sp != "":
		if tree != null and tree.specs.has(sp):
			spec_id = sp
		else:
			warns.append("talentos: especializacao desconhecida descartada")
	if typeof(d.get("ranks", null)) == TYPE_DICTIONARY and tree != null:
		for id: Variant in (d["ranks"] as Dictionary):
			var n: Dictionary = tree.get_node_def(String(id))
			if n.is_empty():
				warns.append("talentos: no desconhecido '%s' descartado" % String(id).left(32))
				continue
			if String(n["spec"]) != "" and String(n["spec"]) != spec_id:
				warns.append("talentos: no '%s' de outra especializacao descartado" % String(id).left(32))
				continue
			ranks[String(id)] = clampi(int((d["ranks"] as Dictionary)[id]), 1, int(n["max_rank"]))
	return warns


# ------------------------------------------------------------------ regras (puras)

## "" se der para somar 1 rank em `node_id`; senao o codigo do primeiro impedimento (ordem fixa, igual ao backend).
static func check_allocate(tree: TalentTree, state: TalentState, level: int, node_id: String, catalog: TalentCatalog) -> String:
	var n: Dictionary = tree.get_node_def(node_id)
	if n.is_empty():
		return "unknown_node"
	var spec: String = String(n["spec"])
	if spec != "":
		if state.spec_id == "":
			return "spec_not_chosen"
		if state.spec_id != spec:
			return "wrong_spec"
	if state.rank_of(node_id) >= int(n["max_rank"]):
		return "max_rank"
	if level < int(n["min_level"]):
		return "level_too_low"
	for r: String in (n["requires"] as Array):
		if state.rank_of(r) < 1:
			return "prerequisite"
	if int(n["min_points_spent"]) > 0 and state.points_spent(tree) < int(n["min_points_spent"]):
		return "prerequisite"
	if state.points_available(tree, level, catalog) < int(n["cost"]):
		return "no_points"
	return ""


static func check_choose_spec(tree: TalentTree, state: TalentState, spec: String) -> String:
	if not tree.specs.has(spec):
		return "unknown_spec"
	if state.spec_id != "":
		return "spec_already_chosen"
	return ""


static func check_respec(state: TalentState) -> String:
	return "nothing_to_reset" if state.is_empty() else ""


func apply_allocate(node_id: String) -> void:
	ranks[node_id] = rank_of(node_id) + 1


func apply_choose_spec(spec: String) -> void:
	spec_id = spec


func apply_respec() -> void:
	spec_id = ""
	ranks = {}
	respecs += 1
