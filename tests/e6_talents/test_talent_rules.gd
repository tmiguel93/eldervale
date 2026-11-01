extends RefCounted
## E6.2 - regras puras de talentos (TalentState): pontos por nivel, pre-requisitos, max_rank, especializacao, respec, restauracao
## leniente, forma do JSON do backend e validadores de protocolo. Sem fisica.


func run(ctx: Object) -> void:
	var tree: SceneTree = ctx as SceneTree
	await tree.physics_frame
	_test_allocation_rules(ctx)
	_test_spec_rules(ctx)
	_test_respec(ctx)
	_test_restore_and_shape(ctx)
	_test_protocol(ctx)
	_test_loadout_integration(ctx)


func _alloc(tr: TalentTree, st: TalentState, lvl: int, id: String, cat: TalentCatalog) -> String:
	var code: String = TalentState.check_allocate(tr, st, lvl, id, cat)
	if code.is_empty():
		st.apply_allocate(id)
	return code


func _test_allocation_rules(ctx: Object) -> void:
	var cat: TalentCatalog = TalentCatalog.shared()
	var tr: TalentTree = cat.get_tree("warrior")
	var st: TalentState = TalentState.new()
	ctx.check(TalentState.check_allocate(tr, st, 1, "w_vigor", cat) == "no_points", "nivel 1: sem pontos")
	ctx.check(TalentState.check_allocate(tr, st, 5, "nao_existe", cat) == "unknown_node", "no inexistente")
	ctx.check(TalentState.check_allocate(tr, st, 5, "w_iron_skin", cat) == "prerequisite", "pre-requisito (w_vigor) ausente")
	ctx.check(TalentState.check_allocate(tr, st, 5, "b_bloodlust", cat) == "spec_not_chosen", "no de especializacao sem escolher")
	ctx.check(_alloc(tr, st, 5, "w_vigor", cat) == "" and st.rank_of("w_vigor") == 1, "aloca w_vigor rank 1")
	ctx.check(_alloc(tr, st, 5, "w_vigor", cat) == "" and _alloc(tr, st, 5, "w_vigor", cat) == "" and st.rank_of("w_vigor") == 3, "ate o max_rank (3)")
	ctx.check(TalentState.check_allocate(tr, st, 50, "w_vigor", cat) == "max_rank", "alem do max_rank")
	ctx.check(st.points_spent(tr) == 3 and st.points_available(tr, 5, cat) == 1, "pontos: nivel 5 = 4, gastos 3, sobra 1")
	ctx.check(_alloc(tr, st, 5, "w_iron_skin", cat) == "" and st.points_available(tr, 5, cat) == 0, "pre-requisito cumprido: aloca e zera os pontos")
	ctx.check(TalentState.check_allocate(tr, st, 5, "w_might", cat) == "no_points", "sem pontos restantes")
	ctx.check(TalentState.check_allocate(tr, st, 6, "w_might", cat) == "", "subir de nivel libera 1 ponto")
	# custo > 1: precisa de pontos suficientes
	var s2: TalentState = TalentState.new()
	s2.ranks = {"w_might": 1}
	ctx.check(TalentState.check_allocate(tr, s2, 2, "w_heavy_focus", cat) == "no_points", "custo 2 com 1 ponto disponivel recusa")
	ctx.check(TalentState.check_allocate(tr, s2, 4, "w_heavy_focus", cat) == "", "custo 2 com 2 pontos disponiveis aceita")
	# estado nunca excede os pontos: simula todas as alocacoes possiveis no nivel 15 e confere
	var st3: TalentState = TalentState.new()
	st3.spec_id = "berserker"
	var progress: bool = true
	var guard: int = 0
	while progress and guard < 500:
		progress = false
		guard += 1
		for id: String in tr.order:
			if _alloc(tr, st3, 15, id, cat) == "":
				progress = true
	ctx.check(st3.points_spent(tr) <= cat.points_for_level(15) and st3.points_available(tr, 15, cat) >= 0, "guloso no nivel 15 nunca estoura (%d/%d)" % [st3.points_spent(tr), cat.points_for_level(15)])
	for id: String in st3.ranks:
		ctx.check(st3.rank_of(id) <= int(tr.nodes[id]["max_rank"]), "rank de %s <= max_rank" % id)
	# min_points_spent (mestria)
	var s4: TalentState = TalentState.new()
	s4.spec_id = "berserker"
	s4.ranks = {"b_rage": 2, "b_frenzy": 1, "w_might": 1, "b_cyclone": 1, "w_wide_swing": 1, "b_bloodlust": 1}
	ctx.check(s4.points_spent(tr) < 12 and TalentState.check_allocate(tr, s4, 40, "b_warlord", cat) == "prerequisite", "mestria exige min_points_spent (gastos %d < 12)" % s4.points_spent(tr))
	s4.ranks["w_wide_swing"] = 2
	s4.ranks["b_cyclone"] = 2
	ctx.check(s4.points_spent(tr) >= 12 and TalentState.check_allocate(tr, s4, 40, "b_warlord", cat) == "", "com 12+ pontos gastos a mestria libera")


func _test_spec_rules(ctx: Object) -> void:
	var cat: TalentCatalog = TalentCatalog.shared()
	var tr: TalentTree = cat.get_tree("warrior")
	var st: TalentState = TalentState.new()
	ctx.check(TalentState.check_choose_spec(tr, st, "elementalist") == "unknown_spec", "spec de outra classe recusada")
	ctx.check(TalentState.check_choose_spec(tr, st, "berserker") == "", "berserker valida para guerreiro")
	st.apply_choose_spec("berserker")
	ctx.check(TalentState.check_choose_spec(tr, st, "berserker") == "spec_already_chosen", "nao escolhe duas vezes")
	var mage: TalentTree = cat.get_tree("mage")
	ctx.check(TalentState.check_allocate(mage, st, 20, "b_bloodlust", cat) == "unknown_node", "no de guerreiro na arvore de mago: desconhecido")
	var s2: TalentState = TalentState.new()
	s2.spec_id = "elementalist"
	ctx.check(TalentState.check_allocate(tr, s2, 20, "b_bloodlust", cat) == "wrong_spec", "spec escolhida diferente da do no: wrong_spec")
	ctx.check(TalentState.check_allocate(tr, s2, 20, "w_vigor", cat) == "", "no generico vale com qualquer spec")


func _test_respec(ctx: Object) -> void:
	var st: TalentState = TalentState.new()
	ctx.check(TalentState.check_respec(st) == "nothing_to_reset", "respec vazio recusado")
	st.apply_choose_spec("berserker")
	ctx.check(TalentState.check_respec(st) == "", "so com spec ja ha o que resetar")
	st.apply_allocate("w_vigor")
	st.apply_respec()
	ctx.check(st.is_empty() and st.respecs == 1, "respec zera spec e ranks e conta")
	st.apply_choose_spec("berserker")
	st.apply_respec()
	ctx.check(st.respecs == 2, "contador acumula")
	var c: TalentState = st.copy()
	c.apply_choose_spec("x")
	ctx.check(st.spec_id == "" and c.spec_id == "x", "copy() e independente")


func _test_restore_and_shape(ctx: Object) -> void:
	var cat: TalentCatalog = TalentCatalog.shared()
	var tr: TalentTree = cat.get_tree("warrior")
	var st: TalentState = TalentState.new()
	var warns: Array[String] = st.restore({"spec": "berserker", "ranks": {"w_vigor": 5, "fantasma": 1, "b_rage": 2}, "respecs": 3}, tr)
	ctx.check(st.spec_id == "berserker" and st.rank_of("w_vigor") == 3 and st.rank_of("fantasma") == 0 and st.rank_of("b_rage") == 2 and st.respecs == 3, "restore leniente: limita ao max_rank, descarta desconhecidos")
	ctx.check(warns.size() == 1, "um aviso para o no desconhecido (%s)" % str(warns))
	st.restore({"spec": "mago_louco", "ranks": {"b_rage": 1, "w_vigor": 1}}, tr)
	ctx.check(st.spec_id == "" and st.rank_of("b_rage") == 0 and st.rank_of("w_vigor") == 1, "spec desconhecida cai e leva os nos dela")
	st.restore("lixo", tr)
	ctx.check(st.is_empty() and st.respecs == 0, "entrada que nao e objeto vira vazio")
	var round: TalentState = TalentState.new()
	round.restore(st.to_dict(), tr)
	ctx.check(round.signature() == st.signature(), "to_dict/restore idempotente")
	ctx.check(TalentState.shape_error({"spec": "", "ranks": {}, "respecs": 0}).is_empty(), "forma valida")
	for bad: Variant in [[], "x", {"spec": 3}, {"spec": "Bad Id"}, {"ranks": []}, {"ranks": {"w_vigor": 0}}, {"ranks": {"w_vigor": 9}}, {"ranks": {"w_vigor": 1.5}}, {"ranks": {"X": 1}}, {"respecs": -1}, {"respecs": "a"}, {"extra": 1}]:
		ctx.check(not TalentState.shape_error(bad).is_empty(), "forma invalida recusada: %s" % str(bad))
	var many: Dictionary = {}
	for i: int in 41:
		many["n%d" % i] = 1
	ctx.check(not TalentState.shape_error({"ranks": many}).is_empty(), "mais de 40 nos recusado")


func _test_protocol(ctx: Object) -> void:
	ctx.check(bool(Protocol.validate_talent_cmd(1, Protocol.TALENT_OP_ALLOCATE, "w_vigor")["ok"]), "alocar valido")
	ctx.check(bool(Protocol.validate_talent_cmd(2, Protocol.TALENT_OP_CHOOSE_SPEC, "berserker")["ok"]), "escolher valido")
	ctx.check(bool(Protocol.validate_talent_cmd(3, Protocol.TALENT_OP_RESPEC, "")["ok"]), "respec valido")
	var bad: Array = [
		[1, Protocol.TALENT_OP_RESPEC, "x"], [1, Protocol.TALENT_OP_ALLOCATE, ""], [1, Protocol.TALENT_OP_ALLOCATE, "Bad Id"],
		[1, Protocol.TALENT_OP_ALLOCATE, "a".repeat(80)], [1, 99, "w_vigor"], [1, "1", "w_vigor"], [1, 1, 5], [1.5, 1, "w_vigor"],
		["1", 1, "w_vigor"], [-1, 1, "w_vigor"], [null, 1, "w_vigor"], [1, 1, null], [1, 1, ["w_vigor"]], [1, 1, {"a": 1}], [1, 1.0, "w_vigor"],
	]
	for b: Array in bad:
		ctx.check(not bool(Protocol.validate_talent_cmd(b[0], b[1], b[2])["ok"]), "comando invalido recusado: %s" % str(b))
	var good: Dictionary = {"spec": "berserker", "ranks": {"w_vigor": 2}, "respecs": 0, "level": 5, "points_total": 4, "points_spent": 2, "points_available": 2, "req_id": 7}
	ctx.check(Protocol.validate_talents_update(Protocol.TALENTS_STATE, good), "s_talents/STATE valido")
	ctx.check(Protocol.validate_talents_update(Protocol.TALENTS_ERROR, {"req_id": 1, "op": 1, "code": "no_points"}), "s_talents/ERROR valido")
	var mut: Array = [
		func(d: Dictionary) -> void: d["extra"] = 1,
		func(d: Dictionary) -> void: d["level"] = "5",
		func(d: Dictionary) -> void: d["points_available"] = -1,
		func(d: Dictionary) -> void: d["spec"] = "Bad Id",
		func(d: Dictionary) -> void: d["ranks"] = {"w_vigor": 99},
		func(d: Dictionary) -> void: d["ranks"] = {"w_vigor": 1.5},
		func(d: Dictionary) -> void: d["ranks"] = []
	]
	for m: Callable in mut:
		var d: Dictionary = good.duplicate(true)
		m.call(d)
		ctx.check(not Protocol.validate_talents_update(Protocol.TALENTS_STATE, d), "s_talents/STATE malformado recusado")
	ctx.check(not Protocol.validate_talents_update(9, good) and not Protocol.validate_talents_update(Protocol.TALENTS_STATE, "x") and not Protocol.validate_talents_update(Protocol.TALENTS_ERROR, {"req_id": 1, "op": 1}), "kind desconhecido / tipo errado / erro incompleto")
	ctx.check(Protocol.VERSION == 2, "protocolo continua na versao 2 (mudanca aditiva)")


func _test_loadout_integration(ctx: Object) -> void:
	var lo: PlayerLoadout = PlayerLoadout.new()
	ctx.check(lo.talent_points_available() == 0 and lo.talent_tree() == null, "loadout sem classe: sem arvore / sem pontos")
	lo.free()
