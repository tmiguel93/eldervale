extends RefCounted
## E8.3: VfxPlayer: pool reaproveita instancias, limite de efeitos simultaneos (descarta/evicta por prioridade), fila com
## atraso, escala por qualidade e headless sem carregar nada.


func run(ctx: Variant) -> void:
	var tree: SceneTree = ctx as SceneTree
	await tree.physics_frame
	await _headless(ctx, tree)
	await _pool(ctx, tree)
	await _limit(ctx, tree)
	await _quality(ctx, tree)
	await _settings(ctx)


func _player(tree: SceneTree, preset: int) -> VfxPlayer:
	var p: VfxPlayer = VfxPlayer.new()
	tree.root.add_child(p)
	p.set_quality(preset)
	return p


func _headless(ctx: Variant, tree: SceneTree) -> void:
	ModelRig.force_enabled = -1
	ModelRig.clear_cache()
	VfxAssets.clear()
	if DisplayServer.get_name() != "headless":
		ctx.check(true, "com display: checagem headless nao se aplica")
		return
	ctx.check(not VfxPlayer.enabled(), "headless: VfxPlayer.enabled() = false")
	ctx.check(not ClientVfx.enabled(), "headless: ClientVfx.enabled() = false")
	var w: ClientWorld = ClientWorld.new()
	tree.root.add_child(w)
	w.show_zone("zone_hub")
	w.update_frame({1: {"pos": Vector3.ZERO, "yaw": 0.0, "hp": 10.0, "max_hp": 10.0, "state": 0, "type": "player:mage", "kind": Protocol.KIND_PLAYER, "phase": 0, "atk": "", "qty": 0, "extrapolated": false}}, 1, null, 0.016)
	ctx.check(w.vfx == null, "headless: ClientWorld sem VFX")
	ctx.check(VfxAssets.load_count == 0, "headless: nenhum recurso de VFX carregado (%d)" % VfxAssets.load_count)
	ctx.check(ModelRig.load_count == 0, "headless: nenhum GLB carregado")
	w.queue_free()
	await tree.physics_frame


func _pool(ctx: Variant, tree: SceneTree) -> void:
	var p: VfxPlayer = _player(tree, QualitySettings.Preset.HIGH)
	var h: int = p.play("fx_hit_physical", Vector3.ZERO)
	ctx.check(h > 0 and p.active_count() == 1, "play devolve handle e ativa 1 efeito")
	ctx.check(p.play("fx_nao_existe", Vector3.ZERO) == -1 and int(p.stats["missing"]) == 1, "efeito inexistente: -1 e contado")
	for i: int in 60: # ~1.2 s: o efeito acaba e a instancia volta ao pool
		p.step(0.02)
	ctx.check(p.active_count() == 0 and p.pooled_count("fx_hit_physical") == 1, "efeito termina e volta ao pool")
	var built: int = int(p.stats["built"])
	for i: int in 5:
		p.play("fx_hit_physical", Vector3(i, 0, 0))
		for k: int in 60:
			p.step(0.02)
	ctx.check(int(p.stats["built"]) == built, "tocar 5x seguidas reaproveita a instancia (sem novas construcoes)")
	# atraso: fica na fila e toca depois
	p.play("fx_hit_crit", Vector3.ZERO, 0.0, {"delay": 0.3})
	ctx.check(p.active_count() == 0, "delay: ainda nao tocou")
	for k: int in 20:
		p.step(0.02)
	ctx.check(p.active_count() == 1, "delay: tocou apos o atraso")
	p.clear_all()
	ctx.check(p.active_count() == 0, "clear_all limpa")
	p.queue_free()
	await tree.physics_frame


func _limit(ctx: Variant, tree: SceneTree) -> void:
	var p: VfxPlayer = _player(tree, QualitySettings.Preset.LOW)
	ctx.check(p.max_active == 10, "LOW: max_active = 10")
	for i: int in 40:
		p.play("fx_hit_physical", Vector3(i, 0, 0))
	ctx.check(p.active_count() <= p.max_active, "limite respeitado: %d <= %d" % [p.active_count(), p.max_active])
	ctx.check(int(p.stats["dropped"]) + int(p.stats["evicted"]) > 0, "excedente descartado/evictado")
	# efeito critico (prioridade 2) ainda entra com o limite cheio
	var crit: int = p.play("fx_levelup", Vector3.ZERO)
	ctx.check(crit > 0 and p.active_count() <= p.max_active, "prioridade alta entra com o limite cheio")
	# fila de atrasos limitada
	var q: VfxPlayer = _player(tree, QualitySettings.Preset.HIGH)
	for i: int in VfxPlayer.MAX_PENDING + 30:
		q.play("fx_hit_physical", Vector3.ZERO, 0.0, {"delay": 5.0})
	ctx.check(int(q.stats["dropped"]) >= 30, "fila de atraso limitada (MAX_PENDING)")
	p.queue_free()
	q.queue_free()
	await tree.physics_frame


func _quality(ctx: Variant, tree: SceneTree) -> void:
	var lo: Dictionary = QualitySettings.data(QualitySettings.Preset.LOW)
	var me: Dictionary = QualitySettings.data(QualitySettings.Preset.MEDIUM)
	var hi: Dictionary = QualitySettings.data(QualitySettings.Preset.HIGH)
	ctx.check(float(lo["vfx_density"]) < float(me["vfx_density"]) and float(me["vfx_density"]) <= float(hi["vfx_density"]), "densidade LOW < MEDIUM <= HIGH")
	ctx.check(int(lo["vfx_max_active"]) < int(me["vfx_max_active"]) and int(me["vfx_max_active"]) < int(hi["vfx_max_active"]), "max_active LOW < MEDIUM < HIGH")
	ctx.check(int(lo["vfx_max_lights"]) == 0 and int(me["vfx_max_lights"]) < int(hi["vfx_max_lights"]), "luzes: LOW 0, MEDIUM < HIGH")
	var p: VfxPlayer = _player(tree, QualitySettings.Preset.LOW)
	ctx.check(not p.acquire_light(), "LOW: nenhuma luz dinamica")
	p.set_quality(QualitySettings.Preset.HIGH)
	var got: int = 0
	for i: int in 10:
		if p.acquire_light():
			got += 1
	ctx.check(got == int(hi["vfx_max_lights"]), "HIGH: %d luzes no maximo (%d)" % [int(hi["vfx_max_lights"]), got])
	p.set_quality(QualitySettings.Preset.MEDIUM)
	ctx.check(is_equal_approx(p.density, float(me["vfx_density"])) and p.max_active == int(me["vfx_max_active"]), "set_quality aplica densidade/limite")
	p.queue_free()
	await tree.physics_frame


func _settings(ctx: Variant) -> void:
	var tmp: String = "user://e83_vfx_settings_%d.cfg" % Time.get_ticks_usec()
	VfxSettings.reset()
	ctx.check(VfxSettings.shake_enabled() and VfxSettings.hit_stop_enabled(), "padrao: tremor leve e hit-stop ligados")
	VfxSettings.reduce_motion = true
	ctx.check(not VfxSettings.shake_enabled() and not VfxSettings.hit_stop_enabled() and not VfxSettings.strong_flash_enabled(), "reduce_motion desliga tremor, hit-stop e brilho forte")
	VfxSettings.reset()
	VfxSettings.camera_shake = false
	ctx.check(not VfxSettings.shake_enabled() and VfxSettings.hit_stop_enabled(), "camera_shake=false so desliga o tremor")
	ctx.check(VfxSettings.save(tmp) == OK, "grava ConfigFile")
	VfxSettings.reset()
	VfxSettings.load_saved(tmp)
	ctx.check(not VfxSettings.camera_shake, "le o que gravou")
	VfxSettings.resolve_startup(PackedStringArray(["--reduce-motion", "1"]), tmp)
	ctx.check(VfxSettings.reduce_motion and not VfxSettings.shake_enabled(), "--reduce-motion 1 vence o arquivo")
	VfxSettings.resolve_startup(PackedStringArray(["--reduce-motion=0"]), tmp)
	ctx.check(not VfxSettings.reduce_motion, "--reduce-motion=0")
	VfxSettings.reset()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp)) # tolerante: pode falhar onde rm e bloqueado (nome unico)
