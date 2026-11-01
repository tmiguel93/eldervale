extends RefCounted
## E5.1: QuestTracker + QuestState (logica pura): progresso, estados invalidos, abandono, limites,
## recompensa unica, serializacao/restauracao.

var _cat: QuestCatalog


func run(ctx: Object) -> void:
	_cat = QuestCatalog.load_dir()
	_test_lifecycle(ctx)
	_test_invalid_states(ctx)
	_test_progress_events(ctx)
	_test_abandon(ctx)
	_test_limits(ctx)
	_test_state_roundtrip(ctx)
	_test_restore_lenient(ctx)
	_test_status_and_context(ctx)


func _tracker() -> QuestTracker:
	return QuestTracker.new(_cat)


func _finish_welcome(t: QuestTracker) -> void:
	t.accept("gw_welcome", 1)
	t.on_npc_talked("npc_hunter_brannoch")
	t.complete("gw_welcome")


func _test_lifecycle(ctx: Object) -> void:
	var t: QuestTracker = _tracker()
	var log: Array[String] = []
	t.quest_accepted.connect(func(q: String) -> void: log.append("acc:" + q))
	t.objective_progressed.connect(func(q: String, o: String, v: int, r: int) -> void: log.append("prog:%s:%s:%d/%d" % [q, o, v, r]))
	t.quest_ready.connect(func(q: String) -> void: log.append("ready:" + q))
	t.quest_completed.connect(func(q: String) -> void: log.append("done:" + q))
	ctx.check(t.status_of("gw_welcome", 1) == "available", "quest inicial disponivel")
	ctx.check(t.status_of("gw_clear_clearing", 1) == "unavailable", "quest com prerequisito pendente indisponivel")
	var a: Dictionary = t.accept("gw_welcome", 1)
	ctx.check(bool(a["ok"]) and t.status_of("gw_welcome", 1) == "active", "aceitar -> ativa")
	ctx.check(t.state.progress_of("gw_welcome", "talk_brannoch") == 0, "progresso inicial zerado")
	ctx.check(t.check_turn_in("gw_welcome")["code"] == "not_ready", "entregar antes de completar -> not_ready")
	ctx.check(t.on_npc_talked("npc_hunter_brannoch") == 1, "talk avanca o objetivo")
	ctx.check(t.status_of("gw_welcome", 1) == "ready", "objetivos completos -> ready")
	ctx.check(t.on_npc_talked("npc_hunter_brannoch") == 0, "talk repetido nao muda (ja completo)")
	var chk: Dictionary = t.check_turn_in("gw_welcome")
	ctx.check(bool(chk["ok"]) and int(chk["rewards"]["xp"]) == 60 and chk["rewards"]["items"][0]["item_id"] == "potion_minor", "check_turn_in devolve a recompensa da quest")
	ctx.check(t.status_of("gw_welcome", 1) == "ready", "check_turn_in nao altera o estado")
	var c: Dictionary = t.complete("gw_welcome")
	ctx.check(bool(c["ok"]) and t.status_of("gw_welcome", 1) == "completed" and not t.state.is_active("gw_welcome"), "complete -> concluida e fora das ativas")
	ctx.check(t.complete("gw_welcome")["code"] == "already_completed", "recompensa unica: segunda entrega recusada")
	ctx.check(t.accept("gw_welcome", 1)["code"] == "already_completed", "quest concluida nao pode ser aceita de novo")
	ctx.check(t.status_of("gw_clear_clearing", 1) == "available", "concluir libera a quest seguinte")
	ctx.check(log == ["acc:gw_welcome", "prog:gw_welcome:talk_brannoch:1/1", "ready:gw_welcome", "done:gw_welcome"], "sinais na ordem: accepted, progressed, ready, completed (%s)" % str(log))


func _test_invalid_states(ctx: Object) -> void:
	var t: QuestTracker = _tracker()
	ctx.check(t.accept("nao_existe", 1)["code"] == "unknown_quest", "aceitar quest desconhecida")
	ctx.check(t.abandon("nao_existe")["code"] == "unknown_quest", "abandonar quest desconhecida")
	ctx.check(t.check_turn_in("nao_existe")["code"] == "unknown_quest", "entregar quest desconhecida")
	ctx.check(t.accept("gw_clear_clearing", 5)["code"] == "prereq_missing", "aceitar sem prerequisito")
	ctx.check(t.accept("gw_ruins_expedition", 1)["code"] == "level_too_low", "aceitar com nivel baixo")
	ctx.check(t.abandon("gw_welcome")["code"] == "not_active", "abandonar quest nao ativa")
	ctx.check(t.check_turn_in("gw_welcome")["code"] == "not_active", "entregar quest nao ativa")
	ctx.check(t.complete("gw_welcome")["code"] == "not_active", "complete sem estar ativa")
	t.accept("gw_welcome", 1)
	ctx.check(t.accept("gw_welcome", 1)["code"] == "already_active", "aceitar duas vezes")
	ctx.check(t.state.active.size() == 1, "aceite duplicado nao cria segunda entrada")
	ctx.check(t.complete("gw_welcome")["code"] == "not_ready", "complete com objetivos pendentes recusado")
	# eventos sem quest ativa que os use nao fazem nada
	ctx.check(t.on_enemy_killed("melee_grunt") == 0 and t.on_item_gained("scrap_material", 5) == 0 and t.on_area_entered("area_ruins_gate") == 0, "eventos sem quest ativa correspondente sao ignorados")
	ctx.check(t.on_npc_talked("npc_elder_orla") == 0, "talk com NPC errado ignorado")
	# pre-requisito de nivel exato
	var t2: QuestTracker = _tracker()
	_finish_welcome(t2)
	t2.accept("gw_clear_clearing", 1)
	for i: int in 5:
		t2.on_enemy_killed("melee_grunt")
	t2.complete("gw_clear_clearing")
	ctx.check(t2.accept("gw_ruins_expedition", 1)["code"] == "level_too_low" and bool(t2.accept("gw_ruins_expedition", 2)["ok"]), "min_level exato (1 recusa, 2 aceita)")


func _test_progress_events(ctx: Object) -> void:
	var t: QuestTracker = _tracker()
	_finish_welcome(t)
	t.accept("gw_clear_clearing", 1)
	for i: int in 4:
		t.on_enemy_killed("melee_grunt")
	ctx.check(t.state.progress_of("gw_clear_clearing", "kill_grunts") == 4 and t.status_of("gw_clear_clearing", 1) == "active", "4/5 kills: ainda ativa")
	t.on_enemy_killed("ranged_caster")
	ctx.check(t.state.progress_of("gw_clear_clearing", "kill_grunts") == 4, "inimigo de outro tipo nao conta")
	t.on_enemy_killed("melee_grunt")
	ctx.check(t.status_of("gw_clear_clearing", 1) == "ready", "5/5: ready")
	t.on_enemy_killed("melee_grunt")
	ctx.check(t.state.progress_of("gw_clear_clearing", "kill_grunts") == 5, "progresso nunca passa de required")
	# coleta: soma por quantidade, com teto
	var c: QuestTracker = _tracker()
	_finish_welcome(c)
	c.accept("gw_scrap_for_orla", 1)
	c.on_item_gained("scrap_material", 4)
	c.on_item_gained("scrap_material", 0)
	c.on_item_gained("scrap_material", -3)
	ctx.check(c.state.progress_of("gw_scrap_for_orla", "collect_scrap") == 4, "coleta soma quantidades positivas; 0/negativo ignorados")
	c.on_item_gained("potion_minor", 9)
	ctx.check(c.state.progress_of("gw_scrap_for_orla", "collect_scrap") == 4, "item diferente nao conta")
	c.on_item_gained("scrap_material", 1000000)
	ctx.check(c.state.progress_of("gw_scrap_for_orla", "collect_scrap") == 6 and c.status_of("gw_scrap_for_orla", 1) == "ready", "coleta grande satura em required")
	# areas, varios objetivos
	var r: QuestTracker = _tracker()
	_finish_welcome(r)
	r.accept("gw_clear_clearing", 2)
	for i: int in 5:
		r.on_enemy_killed("melee_grunt")
	r.complete("gw_clear_clearing")
	r.accept("gw_ruins_expedition", 2)
	var readies: Array[String] = []
	r.quest_ready.connect(func(q: String) -> void: readies.append(q))
	r.on_area_entered("area_ruins_hall")
	ctx.check(r.status_of("gw_ruins_expedition", 2) == "active" and readies.is_empty(), "um de dois objetivos: nao esta pronta (ordem livre)")
	r.on_area_entered("area_ruins_gate")
	ctx.check(r.status_of("gw_ruins_expedition", 2) == "ready" and readies == (["gw_ruins_expedition"] as Array[String]), "dois objetivos completos: ready (uma vez)")
	r.on_area_entered("area_ruins_gate")
	ctx.check(readies.size() == 1, "ready nao e reemitido")
	# chefe do salao (E5.3: blight_treant): o tracker conta o abate por id
	r.complete("gw_ruins_expedition")
	r.accept("gw_ruin_guardian", 3)
	r.on_enemy_killed("blight_treant")
	ctx.check(r.state.progress_of("gw_ruin_guardian", "kill_guardian") == 1, "kill do chefe blight_treant conta por string")
	# uma morte avanca todas as quests que a usam
	var m: QuestDef = QuestDef.parse({
		"schema_version": 1, "id": "extra_hunt", "type": "hunt", "region": "greenwood", "title": "t", "title_key": "k", "description": "d", "description_key": "k",
		"giver_npc": "npc_elder_orla", "turn_in_npc": "npc_elder_orla", "prerequisites": {"quests": [], "min_level": 1},
		"objectives": [{"id": "k", "type": "kill", "target": "melee_grunt", "required": 2, "text": "x", "text_key": "k"}],
		"rewards": {"xp": 5, "items": []}})["def"]
	var cat2: QuestCatalog = QuestCatalog.load_dir()
	cat2.add(m)
	var t3: QuestTracker = QuestTracker.new(cat2)
	t3.accept("gw_welcome", 1)
	t3.on_npc_talked("npc_hunter_brannoch")
	t3.complete("gw_welcome")
	t3.accept("gw_clear_clearing", 1)
	t3.accept("extra_hunt", 1)
	ctx.check(t3.on_enemy_killed("melee_grunt") == 2, "um kill avanca objetivos de 2 quests")


func _test_abandon(ctx: Object) -> void:
	var t: QuestTracker = _tracker()
	_finish_welcome(t)
	t.accept("gw_clear_clearing", 1)
	t.on_enemy_killed("melee_grunt")
	t.on_enemy_killed("melee_grunt")
	var gone: Array[String] = []
	t.quest_abandoned.connect(func(q: String) -> void: gone.append(q))
	var r: Dictionary = t.abandon("gw_clear_clearing")
	ctx.check(bool(r["ok"]) and gone == (["gw_clear_clearing"] as Array[String]) and not t.state.is_active("gw_clear_clearing"), "abandonar remove das ativas")
	ctx.check(t.status_of("gw_clear_clearing", 1) == "available", "abandonada volta a disponivel")
	ctx.check(t.on_enemy_killed("melee_grunt") == 0, "kills apos abandonar nao contam")
	t.accept("gw_clear_clearing", 1)
	ctx.check(t.state.progress_of("gw_clear_clearing", "kill_grunts") == 0, "reaceitar comeca do zero (progresso nao e aproveitado)")
	ctx.check(t.abandon("gw_welcome")["code"] == "not_active", "nao abandona quest concluida")
	var def: QuestDef = _cat.get_quest("gw_scrap_for_orla")
	def.abandonable = false
	t.accept("gw_scrap_for_orla", 1)
	ctx.check(t.abandon("gw_scrap_for_orla")["code"] == "not_abandonable" and t.state.is_active("gw_scrap_for_orla"), "quest nao abandonavel e respeitada")
	def.abandonable = true


func _test_limits(ctx: Object) -> void:
	var cat: QuestCatalog = QuestCatalog.new()
	for i: int in QuestTracker.MAX_ACTIVE + 2:
		var d: Dictionary = {
			"schema_version": 1, "id": "lim_%02d" % i, "type": "side", "region": "greenwood", "title": "t", "title_key": "k", "description": "d", "description_key": "k",
			"giver_npc": "npc_elder_orla", "turn_in_npc": "npc_elder_orla", "prerequisites": {"quests": [], "min_level": 1},
			"objectives": [{"id": "k", "type": "kill", "target": "melee_grunt", "required": 1, "text": "x", "text_key": "k"}],
			"rewards": {"xp": 5, "items": []}}
		cat.add(QuestDef.parse(d)["def"])
	var t: QuestTracker = QuestTracker.new(cat)
	for i: int in QuestTracker.MAX_ACTIVE:
		t.accept("lim_%02d" % i, 1)
	ctx.check(t.state.active.size() == QuestTracker.MAX_ACTIVE, "ate MAX_ACTIVE quests ativas")
	ctx.check(t.accept("lim_%02d" % QuestTracker.MAX_ACTIVE, 1)["code"] == "quest_log_full", "alem do limite: quest_log_full")
	t.abandon("lim_00")
	ctx.check(bool(t.accept("lim_%02d" % QuestTracker.MAX_ACTIVE, 1)["ok"]), "abandonar libera espaco no diario")


func _test_state_roundtrip(ctx: Object) -> void:
	var t: QuestTracker = _tracker()
	_finish_welcome(t)
	t.accept("gw_clear_clearing", 1)
	t.on_enemy_killed("melee_grunt")
	t.on_enemy_killed("melee_grunt")
	var d: Dictionary = t.state.to_dict()
	ctx.check(d["completed"] == ["gw_welcome"] and d["active"]["gw_clear_clearing"]["objectives"]["kill_grunts"] == 2, "to_dict: active/completed")
	ctx.check(QuestState.shape_error(d) == "", "to_dict passa no shape_error")
	# via JSON (numeros viram float)
	var via_json: Variant = JSON.parse_string(JSON.stringify(d))
	var s2: QuestState = QuestState.new()
	var warns: Array[String] = s2.restore(via_json, _cat)
	ctx.check(warns.is_empty() and s2.to_dict() == d, "roundtrip via JSON identico (floats -> int)")
	ctx.check(s2.progress_of("gw_clear_clearing", "kill_grunts") == 2 and typeof(s2.progress_of("gw_clear_clearing", "kill_grunts")) == TYPE_INT, "progresso restaurado como int")
	# restore em-place preserva a referencia usada pelo tracker
	var t2: QuestTracker = QuestTracker.new(_cat, s2)
	s2.restore({"active": {}, "completed": []}, _cat)
	ctx.check(t2.state == s2 and not t2.state.is_active("gw_clear_clearing"), "restore e em-place (tracker enxerga o novo estado)")
	ctx.check(QuestState.shape_error({}) == "" and QuestState.shape_error(null) != "" and QuestState.shape_error("x") != "", "shape_error: vazio ok, nao-objeto invalido")


func _test_restore_lenient(ctx: Object) -> void:
	var s: QuestState = QuestState.new()
	var w: Array[String] = s.restore({
		"active": {
			"gw_clear_clearing": {"objectives": {"kill_grunts": 99, "obj_fantasma": 3}},
			"quest_removida": {"objectives": {"x": 1}},
			"gw_welcome": {"objectives": {"talk_brannoch": 1}},
		},
		"completed": ["gw_welcome", "outra_removida", "gw_welcome"],
	}, _cat)
	ctx.check(s.completed == (["gw_welcome"] as Array[String]), "completed: desconhecida descartada e duplicata removida")
	ctx.check(not s.active.has("quest_removida") and not s.active.has("gw_welcome"), "ativa desconhecida descartada; concluida nunca fica ativa")
	ctx.check(s.progress_of("gw_clear_clearing", "kill_grunts") == 5 and not (s.active["gw_clear_clearing"] as Dictionary).has("obj_fantasma"), "progresso limitado a required; objetivo desconhecido descartado")
	ctx.check(w.size() >= 2, "avisos emitidos (%d)" % w.size())
	var bad: QuestState = QuestState.new()
	bad.active["x"] = {}
	var w2: Array[String] = bad.restore({"active": "oops", "completed": 5}, _cat)
	ctx.check(bad.active.is_empty() and bad.completed.is_empty() and not w2.is_empty(), "forma invalida -> estado vazio com aviso")
	var neg: QuestState = QuestState.new()
	neg.restore({"active": {"gw_clear_clearing": {"objectives": {"kill_grunts": -7}}}, "completed": []}, _cat)
	ctx.check(neg.progress_of("gw_clear_clearing", "kill_grunts") == 0, "progresso negativo vira 0")
	var missing: QuestState = QuestState.new()
	missing.restore({"active": {"gw_ruins_expedition": {"objectives": {"reach_gate": 1}}}, "completed": []}, _cat)
	ctx.check(missing.progress_of("gw_ruins_expedition", "reach_hall") == 0 and (missing.active["gw_ruins_expedition"] as Dictionary).has("reach_hall"), "objetivo ausente no save vira 0")


func _test_status_and_context(ctx: Object) -> void:
	var t: QuestTracker = _tracker()
	var c: Dictionary = t.dialogue_context(1)
	ctx.check(c["level"] == 1 and c["quests"]["gw_welcome"] == "available" and c["quests"]["gw_ruin_guardian"] == "unavailable", "dialogue_context: status de todas as quests")
	ctx.check(QuestTracker.reward_key("gw_welcome", "abc12345") == "quest:gw_welcome:abc12345", "reward_key estavel: quest:<quest_id>:<character_id>")
	ctx.check(QuestTracker.reward_key("gw_welcome", "abc12345") == QuestTracker.reward_key("gw_welcome", "abc12345"), "reward_key deterministica")
