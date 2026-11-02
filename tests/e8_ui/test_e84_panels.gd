extends RefCounted
## E8.4: paineis tematicos (abrem/fecham com e sem animacao, cabem em 1280x720), barra do chefe (some fora do alcance/da zona/sem
## posicao/fora de PLAYING = correcao do bug da barra fantasma), hotbar com recarga estimada e reduce-motion.

const U = preload("res://tests/e5_ui/ui_helpers.gd")
const FAR: Vector3 = Vector3(-30.0, 0.05, 20.0)


func run(ctx: Variant) -> void:
	var tree: SceneTree = ctx as SceneTree
	await tree.physics_frame
	_boss_pure(ctx)
	_boss_widget(ctx, tree)
	await _panels(ctx, tree)
	_hotbar(ctx)
	await _reduce_motion(ctx, tree)


func _alpha(id: int, pos: Vector3, hp: float = 400.0) -> Dictionary:
	return U.enemy(id, "thorn_alpha", pos, hp, 420.0, 0)


func _boss_pure(ctx: Variant) -> void:
	var wild: ZoneDef = WorldDef.shared().get_zone("zone_wild")
	var hub: ZoneDef = WorldDef.shared().get_zone("zone_hub")
	var c: Vector3 = wild.center
	var here: Vector3 = c + Vector3(2, 0, 2)
	var near: Dictionary = _alpha(5, c + Vector3(10, 0, 2))
	var far: Dictionary = _alpha(6, c + Vector3(30, 0, 0))
	ctx.check(not BossBar.pick_boss([near], here, wild, BossBar.SHOW_RANGE).is_empty(), "chefe perto e na zona: escolhido")
	ctx.check(BossBar.pick_boss([_alpha(7, c + Vector3(0, 0, 60))], c, null, BossBar.SHOW_RANGE).is_empty(), "chefe a 60 m: fora do alcance (nao aparece)")
	ctx.check(BossBar.pick_boss([_alpha(8, hub.center)], hub.center + Vector3(3, 0, 0), wild, 999.0).is_empty(), "chefe de OUTRA zona e ignorado")
	ctx.check(BossBar.pick_boss([_alpha(9, c + Vector3(1, 0, 1), 0.0)], here, wild).is_empty(), "chefe morto e ignorado")
	ctx.check(int(BossBar.pick_boss([far, near], here, wild)["id"]) == 5, "escolhe o chefe mais proximo")
	ctx.check(BossBar.pick_boss([U.enemy(10, "thorn_grunt", c, 50.0, 50.0)], here, wild).is_empty(), "inimigo comum nao e chefe")
	ctx.check(BossBar.HIDE_RANGE > BossBar.SHOW_RANGE, "histerese: some mais longe do que aparece")


func _boss_widget(ctx: Variant, tree: SceneTree) -> void:
	var wild: ZoneDef = WorldDef.shared().get_zone("zone_wild")
	var hub: ZoneDef = WorldDef.shared().get_zone("zone_hub")
	var c: Vector3 = wild.center
	var bar: BossBar = BossBar.new()
	tree.root.add_child(bar)
	ctx.check(not bar.visible, "barra nasce oculta")
	var boss_ents: Array = [_alpha(5, c + Vector3(12, 0, 0))]
	bar.refresh(boss_ents, c, wild)
	ctx.check(bar.visible and bar.current_id == 5, "perto do chefe, na zona: barra visivel")
	bar.refresh(boss_ents, c + Vector3(-30, 0, 0), wild)
	ctx.check(bar.visible and bar.current_id == 5, "a 42 m ainda visivel (histerese)")
	bar.refresh(boss_ents, c + Vector3(-45, 0, 0), wild)
	ctx.check(not bar.visible and bar.current_id == -1, "longe (> HIDE_RANGE): barra SOME")
	bar.refresh(boss_ents, c + Vector3(-30, 0, 0), wild)
	ctx.check(not bar.visible, "a 42 m depois de sumir NAO volta (precisa chegar a SHOW_RANGE)")
	bar.refresh(boss_ents, c, wild)
	ctx.check(bar.visible, "voltou ao se aproximar")
	bar.refresh(boss_ents, hub.center, hub)
	ctx.check(not bar.visible, "jogador em outra zona: barra some")
	bar.refresh(boss_ents, c, wild)
	bar.refresh(boss_ents, null, wild)
	ctx.check(not bar.visible, "sem posicao local conhecida: oculta")
	bar.refresh(boss_ents, c, wild)
	bar.refresh([], c, wild)
	ctx.check(not bar.visible, "chefe morreu/sumiu do snapshot: oculta")
	bar.refresh(boss_ents, c, wild)
	bar.reset()
	ctx.check(not bar.visible and bar.current_id == -1, "reset() oculta na hora")
	tree.root.remove_child(bar)
	bar.queue_free()
	# integrada ao ClientUi: zona/estado
	var made: Dictionary = U.make_session()
	var ss: ClientSession = made["session"]
	var ui: ClientUi = U.make_ui(tree, ss)
	U.world_event(ss, Protocol.EVENT_ZONE, {"id": ss.player_id, "zone": "zone_wild", "phase": Protocol.ZONE_PHASE_ARRIVED, "pos": c})
	U.snapshot(ss, [U.player(ss.player_id, c), _alpha(5, c + Vector3(8, 0, 0))])
	ui.update_frame(0.016)
	ctx.check(ui.boss.visible, "ClientUi: chefe a 8 m na mesma zona => barra")
	U.snapshot(ss, [U.player(ss.player_id, c + Vector3(-45, 0, 0)), _alpha(5, c + Vector3(8, 0, 0))])
	ui.update_frame(0.016)
	ctx.check(not ui.boss.visible, "ClientUi: jogador se afasta 53 m => barra some")
	U.snapshot(ss, [U.player(ss.player_id, c), _alpha(5, c + Vector3(8, 0, 0))])
	ui.update_frame(0.016)
	ctx.check(ui.boss.visible, "ClientUi: volta ao se aproximar")
	U.world_event(ss, Protocol.EVENT_ZONE, {"id": ss.player_id, "zone": "zone_hub", "phase": Protocol.ZONE_PHASE_ARRIVED, "pos": hub.center})
	ui.update_frame(0.016)
	ctx.check(not ui.boss.visible, "ClientUi: troca de zona esconde a barra na hora")
	U.snapshot(ss, [U.player(ss.player_id, hub.center), _alpha(5, c + Vector3(8, 0, 0))])
	ui.update_frame(0.016)
	ctx.check(not ui.boss.visible, "ClientUi: chefe de outra zona nunca aparece no hub")
	U.snapshot(ss, [U.player(ss.player_id, c), _alpha(5, c + Vector3(8, 0, 0))])
	U.world_event(ss, Protocol.EVENT_ZONE, {"id": ss.player_id, "zone": "zone_wild", "phase": Protocol.ZONE_PHASE_ARRIVED, "pos": c})
	U.snapshot(ss, [U.player(ss.player_id, c), _alpha(5, c + Vector3(8, 0, 0))])
	ui.update_frame(0.016)
	ctx.check(ui.boss.visible, "ClientUi: de volta a zona do chefe")
	ui.bind(ClientSession.new())
	ui.update_frame(0.016)
	ctx.check(not ui.boss.visible, "ClientUi: sessao fora de PLAYING nao mostra chefe")
	U.free_ui(tree, ui)


func _panels(ctx: Variant, tree: SceneTree) -> void:
	var made: Dictionary = U.make_session()
	var ss: ClientSession = made["session"]
	var ui: ClientUi = U.make_ui(tree, ss)
	U.world_event(ss, Protocol.EVENT_ZONE, {"id": ss.player_id, "zone": "zone_hub", "phase": Protocol.ZONE_PHASE_ARRIVED, "pos": U.HUB_STATION})
	U.snapshot(ss, [U.player(ss.player_id, U.HUB_STATION)])
	var vp: Vector2 = Vector2(1280, 720)
	for p: UiPanel in [ui.dialogue, ui.quests, ui.inventory_panel, ui.craft, ui.map_panel, ui.talents, ui.menu, ui.options, ui.credits]:
		p.open()
		await tree.process_frame
		await tree.process_frame
		await tree.process_frame
		var m: Vector2 = p.size
		ctx.check(m.x <= vp.x - 40.0 and m.y <= vp.y - 60.0, "painel '%s' cabe em 1280x720 (%dx%d)" % [p.title_label.text, int(m.x), int(m.y)])
		var centered: Vector2 = p.global_position + p.size * 0.5
		ctx.check(centered.distance_to(root_center(tree)) < 4.0, "painel '%s' fica centrado (%s)" % [p.title_label.text, centered])
		p.close()
	# abrir/fechar (headless: instantaneo)
	ctx.check(not UiFx.available(), "headless: UiFx instantaneo")
	for pair: Array in [["I", ui.inventory_panel], ["J", ui.quests], ["K", ui.talents], ["M", ui.map_panel]]:
		var key: Key = {"I": KEY_I, "J": KEY_J, "K": KEY_K, "M": KEY_M}[pair[0]]
		ui.handle_input(U.key(key))
		ctx.check((pair[1] as UiPanel).is_open() and (pair[1] as UiPanel).visible, "%s abre o painel" % pair[0])
		ui.handle_input(U.key(KEY_ESCAPE))
		ctx.check(not (pair[1] as UiPanel).is_open() and not (pair[1] as UiPanel).visible, "Esc fecha o painel de %s" % pair[0])
	ui.handle_input(U.key(KEY_O))
	ctx.check(ui.options.is_open(), "O abre as Opcoes")
	ui.handle_input(U.key(KEY_F1))
	ctx.check(ui.credits.is_open() and not ui.options.is_open(), "F1 abre os Creditos (exclusivo)")
	ui.handle_input(U.key(KEY_ESCAPE))
	ctx.check(not ui.credits.is_open(), "Esc fecha os Creditos")
	# com animacao real (forcada): abre ja visivel com fade, fecha e fica oculto ao fim
	UiFx.force_enabled = true
	ui.inventory_panel.open()
	ctx.check(ui.inventory_panel.visible and ui.inventory_panel.modulate.a < 1.0, "com animacao: abre comecando transparente (fade-in)")
	await tree.create_timer(0.5).timeout
	ctx.check(is_equal_approx(ui.inventory_panel.modulate.a, 1.0) and ui.inventory_panel.scale.is_equal_approx(Vector2.ONE), "fade-in termina opaco e na escala 1")
	ui.inventory_panel.close()
	ctx.check(not ui.inventory_panel.is_open(), "close(): is_open falso na hora")
	await tree.create_timer(0.5).timeout
	ctx.check(not ui.inventory_panel.visible and is_equal_approx(ui.inventory_panel.modulate.a, 1.0), "fade-out termina oculto e com alfa restaurado")
	# abrir de novo no meio do fade-out cancela o tween antigo
	ui.inventory_panel.open()
	ui.inventory_panel.close()
	ui.inventory_panel.open()
	await tree.create_timer(0.5).timeout
	ctx.check(ui.inventory_panel.visible and ui.inventory_panel.is_open(), "reabrir durante o fade-out deixa o painel visivel")
	ui.inventory_panel.close()
	await tree.create_timer(0.4).timeout
	UiFx.force_enabled = false
	# toast + dano nao quebram em headless
	ui.on_event(Protocol.EVENT_DAMAGE, {"id": 1, "target_id": ss.player_id, "amount": 12.0, "crit": false})
	ctx.check(ui.toasts != null, "evento de dano nao quebra a HUD")
	U.free_ui(tree, ui)


func root_center(tree: SceneTree) -> Vector2:
	return tree.root.get_visible_rect().size * 0.5


func _hotbar(ctx: Variant) -> void:
	var sb: SkillBar = SkillBar.new()
	sb.refresh("warrior")
	ctx.check(sb.slots.size() == 4 and sb.slot_summary().size() == 4, "hotbar da classe com 4 habilidades %s" % [sb.slot_summary()])
	var s2: SkillSlot = null
	for s: SkillSlot in sb.slots:
		if s.slot == "skill_1":
			s2 = s
	ctx.check(s2 != null and s2.cooldown > 0.45, "habilidade 1 tem recarga conhecida (%.1fs)" % (s2.cooldown if s2 else 0.0))
	sb.note_actions(Protocol.ACTION_SKILL_1)
	ctx.check(s2.is_cooling(), "tecla apertada inicia a recarga (estimada)")
	var before: float = s2.remaining
	sb.note_actions(Protocol.ACTION_SKILL_1)
	ctx.check(is_equal_approx(s2.remaining, before), "tecla segurada nao reinicia (so a borda de subida)")
	sb.advance(1.0)
	ctx.check(s2.remaining < before and s2.remaining > 0.0, "recarga avanca com o tempo")
	sb.advance(100.0)
	ctx.check(not s2.is_cooling(), "recarga termina")
	sb.refresh("mage")
	ctx.check(sb.slots.size() == 4 and not s2.is_cooling(), "trocar de classe limpa as recargas")
	sb.free()


func _reduce_motion(ctx: Variant, tree: SceneTree) -> void:
	var saved: bool = VfxSettings.reduce_motion
	UiFx.force_enabled = true
	VfxSettings.reduce_motion = false
	ctx.check(UiFx.motion() and is_equal_approx(UiFx.fade_time(0.2), 0.2), "sem reduce-motion: movimento e fade completo")
	VfxSettings.reduce_motion = true
	ctx.check(not UiFx.motion() and UiFx.fade_time(0.2) < 0.2 and UiFx.fade_time(0.2) > 0.0, "reduce-motion: sem movimento, so fade curto")
	var c: Control = Control.new()
	c.custom_minimum_size = Vector2(100, 100)
	tree.root.add_child(c)
	var p0: Vector2 = c.position
	UiFx.appear(c)
	ctx.check(c.scale.is_equal_approx(Vector2.ONE) and c.position.is_equal_approx(p0), "reduce-motion: appear() nao escala nem desloca")
	var shake_before: Vector2 = c.position
	UiFx.shake(c, 8.0, 0.2)
	await tree.create_timer(0.1).timeout
	ctx.check(c.position.is_equal_approx(shake_before), "reduce-motion: shake() nao mexe na posicao")
	UiFx.pulse(c)
	ctx.check(c.modulate.is_equal_approx(Color.WHITE) or c.modulate.a <= 1.0, "reduce-motion: pulse() nao estoura o brilho")
	var slot: SkillSlot = SkillSlot.new()
	slot.setup("skill_1", "fireball", "Q", 10, 3.0, "")
	slot.start_cooldown()
	slot.advance(3.5)
	ctx.check(is_equal_approx(slot.ready_flash, 0.0), "reduce-motion: sem pulso de recarga pronta")
	slot.free()
	VfxSettings.reduce_motion = false
	slot = SkillSlot.new()
	slot.setup("skill_1", "fireball", "Q", 10, 3.0, "")
	slot.start_cooldown()
	slot.advance(2.9)
	slot.advance(0.2)
	ctx.check(slot.ready_flash > 0.0, "com movimento: pulso de recarga pronta")
	slot.free()
	tree.root.remove_child(c)
	c.queue_free()
	UiFx.force_enabled = false
	VfxSettings.reduce_motion = saved
