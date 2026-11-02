extends RefCounted
## E8.1: cada visual_scene referenciado carrega, instancia e acha o AnimationPlayer; escala por altura; acessorios; tintura;
## cache de PackedScene; clips por estado com fallback; one-shots voltam ao idle; morte segura o ultimo quadro.

const H = preload("res://tests/e8_models/e8_helpers.gd")


func run(ctx: Variant) -> void:
	var tree: SceneTree = ctx as SceneTree
	await tree.physics_frame
	ModelRig.clear_cache()
	var holder: Node3D = Node3D.new()
	tree.root.add_child(holder)
	await _every_visual(ctx, holder)
	await _fallback_and_states(ctx, holder)
	_cache(ctx)
	_equip_tint(ctx, holder)
	_missing(ctx)
	holder.queue_free()


func _every_visual(ctx: Variant, holder: Node3D) -> void:
	var heights: Dictionary = {}
	for e: Array in H.all_specs():
		var spec: VisualSpec = e[1] as VisualSpec
		if spec == null:
			continue
		var rig: ModelRig = ModelRig.build(spec)
		ctx.check(rig != null, "%s: ModelRig instancia a cena" % e[0])
		if rig == null:
			continue
		holder.add_child(rig)
		ctx.check(rig.anim != null, "%s: AnimationPlayer encontrado" % e[0])
		ctx.check(rig.measured_height > 0.05, "%s: altura medida %.2f" % [e[0], rig.measured_height])
		# a altura do corpo apos a escala == altura alvo
		var box: AABB = ModelRig.measure(rig.model)
		ctx.check(absf(box.size.y * rig.scale_factor - spec.height) < 0.01, "%s: altura final %.3f == alvo %.2f" % [e[0], box.size.y * rig.scale_factor, spec.height])
		ctx.check(absf(rig.get_node("Pivot").position.y + box.position.y * rig.scale_factor) < 0.001, "%s: pe no chao (y=0)" % e[0])
		for st: StringName in [&"idle", &"move", &"attack", &"death"]:
			ctx.check(rig.has_clip(st), "%s: clip para %s = %s" % [e[0], st, rig.clip_for(st)])
		ctx.check(rig.current == &"idle" and rig.anim.current_animation == rig.clip_for(&"idle"), "%s: comeca em idle (nao fica em T-pose)" % e[0])
		heights[e[0]] = rig.scale_factor
		rig.queue_free()
	# modelos de escalas internas muito diferentes ficam todos na altura pedida
	ctx.check(heights.size() == 19, "19 modelos normalizados")
	ctx.check(not is_equal_approx(float(heights["enemy:forest_stalker"]), float(heights["enemy:melee_grunt"])), "fatores de escala distintos entre pacotes (normalizacao em runtime)")
	await (ctx as SceneTree).process_frame


func _fallback_and_states(ctx: Variant, holder: Node3D) -> void:
	var spec: VisualSpec = VisualSpec.make("class.warrior", 1.9, Color(1, 1, 1, 0), 0.0, {"attack": "ClipQueNaoExiste", "move": "Running_A", "dodge": "Dodge_Forward"})
	var rig: ModelRig = ModelRig.build(spec)
	holder.add_child(rig)
	ctx.check(rig.clip_for(&"attack") == "1H_Melee_Attack_Chop", "clip inexistente no dado cai no padrao (%s)" % rig.clip_for(&"attack"))
	ctx.check(rig.clip_for(&"move") == "Running_A", "override valido do dado")
	rig.set_state(&"move")
	ctx.check(rig.current == &"move" and rig.anim.current_animation == "Running_A", "set_state(move) toca Running_A")
	ctx.check(rig.anim.get_animation("Running_A").loop_mode == Animation.LOOP_LINEAR, "move em loop")
	rig.set_state(&"attack", 0.5)
	ctx.check(rig.current == &"attack" and rig.anim.current_animation == "1H_Melee_Attack_Chop", "set_state(attack) toca o ataque")
	ctx.check(rig.anim.get_playing_speed() > 1.5, "ataque acelerado para caber na duracao (%.2f)" % rig.anim.get_playing_speed())
	rig.set_state(&"idle")
	ctx.check(rig.current == &"attack", "idle nao corta o ataque recem-iniciado (pendente)")
	rig.anim.advance(5.0)
	ctx.check(rig.current == &"idle", "ao fim do one-shot volta ao idle pendente")
	rig.set_state(&"attack")
	rig.anim.advance(5.0)
	ctx.check(rig.current == &"idle", "ataque terminado com o servidor ainda em ATTACK volta ao idle (nao reinicia a cada frame)")
	rig.set_state(&"idle")
	rig.set_state(&"dodge")
	ctx.check(rig.current == &"dodge", "dodge")
	rig.trigger(&"hit")
	ctx.check(rig.current == &"dodge", "evento de dano nao interrompe esquiva (prioridade)")
	rig.anim.advance(5.0)
	rig.set_state(&"idle")
	rig.trigger(&"hit")
	ctx.check(rig.current == &"hit", "evento de dano toca hit react")
	rig.anim.advance(5.0)
	rig.set_state(&"death")
	ctx.check(rig.current == &"death" and rig.dead, "death")
	var at: float = rig.anim.current_animation_position
	rig.anim.advance(10.0)
	ctx.check(rig.current == &"death" and rig.anim.get_animation("Death_A").loop_mode == Animation.LOOP_NONE, "death sem loop, segura o ultimo quadro")
	rig.set_state(&"idle")
	rig.trigger(&"hit")
	ctx.check(rig.current == &"death", "morto nao reage")
	ctx.check(at >= 0.0, "posicao do clip legivel")
	rig.queue_free()
	# giro suave: so defasagem local, nunca altera a entidade
	var r2: ModelRig = ModelRig.build(VisualSpec.make("class.mage", 1.8))
	holder.add_child(r2)
	r2.follow_yaw(0.0, 0.016)
	ctx.check(is_zero_approx(r2.rotation.y), "primeiro quadro sem defasagem")
	r2.follow_yaw(1.5, 0.016)
	var lag: float = r2.rotation.y
	ctx.check(lag < 0.0 and lag > -1.5, "giro suave: visual ainda atras do yaw da entidade (%.3f)" % lag)
	for _i in 120:
		r2.follow_yaw(1.5, 0.016)
	ctx.check(absf(r2.rotation.y) < 0.02, "converge para o yaw da entidade")
	r2.queue_free()
	# modelo sem AnimationPlayer (bau): nao quebra
	var chest: ModelRig = ModelRig.build(VisualSpec.make("prop.chest", 0.55))
	holder.add_child(chest)
	chest.set_state(&"move")
	chest.trigger(&"hit")
	ctx.check(chest != null and chest.anim == null, "modelo sem animacao aceita estados sem erro")
	ctx.check(absf(ModelRig.measure(chest.model).size.y * chest.scale_factor - 0.55) < 0.01, "bau normalizado para 0.55 m")
	chest.queue_free()


func _cache(ctx: Variant) -> void:
	ModelRig.clear_cache()
	var spec: VisualSpec = VisualSpec.make("class.mage", 1.8)
	var a: ModelRig = ModelRig.build(spec)
	var b: ModelRig = ModelRig.build(spec)
	var c: ModelRig = ModelRig.build(VisualSpec.make("class.mage", 3.0))
	ctx.check(ModelRig.load_count == 1, "PackedScene em cache: 3 instancias, 1 carga (%d)" % ModelRig.load_count)
	ctx.check(a.model != b.model and a.scale_factor != c.scale_factor, "instancias independentes")
	a.free()
	b.free()
	c.free()


func _equip_tint(ctx: Variant, holder: Node3D) -> void:
	var spec: VisualSpec = VisualSpec.make("class.warrior", 1.9, Color(0.5, 1, 1, 1), 0.0, {}, PackedStringArray(["2H_Axe"]))
	var rig: ModelRig = ModelRig.build(spec)
	holder.add_child(rig)
	var axe: MeshInstance3D = rig.model.find_child("2H_Axe", true, false) as MeshInstance3D
	var mug: MeshInstance3D = rig.model.find_child("Mug", true, false) as MeshInstance3D
	var shield: MeshInstance3D = rig.model.find_child("Barbarian_Round_Shield", true, false) as MeshInstance3D
	var body: MeshInstance3D = rig.model.find_child("Barbarian_Body", true, false) as MeshInstance3D
	ctx.check(axe != null and axe.visible, "equipado fica visivel")
	ctx.check(mug != null and not mug.visible and shield != null and not shield.visible, "nao equipado e escondido")
	ctx.check(body != null and body.visible, "corpo skinned sempre visivel")
	var mat: BaseMaterial3D = body.get_surface_override_material(0) as BaseMaterial3D
	var base: BaseMaterial3D = body.mesh.surface_get_material(0) as BaseMaterial3D
	ctx.check(mat != null and base != null and mat.albedo_color.r < base.albedo_color.r * 0.6 + 0.001, "tintura multiplica o albedo (r %.2f -> %.2f)" % [base.albedo_color.r, mat.albedo_color.r])
	var untinted: ModelRig = ModelRig.build(VisualSpec.make("class.warrior", 1.9))
	holder.add_child(untinted)
	var ub: MeshInstance3D = untinted.model.find_child("Barbarian_Body", true, false) as MeshInstance3D
	ctx.check(ub.get_surface_override_material(0) == null, "sem tintura nao cria material")
	rig.flash(0.1)
	ctx.check(body.material_overlay != null, "flash liga o overlay")
	rig._process(0.2)
	ctx.check(body.material_overlay == null, "flash desliga")
	# escolher so a altura do corpo: o mesmo corpo com acessorios diferentes tem a mesma altura
	var other: ModelRig = ModelRig.build(VisualSpec.make("class.warrior", 1.9, Color(1, 1, 1, 0), 0.0, {}, PackedStringArray(["2H_Axe", "Barbarian_Hat"])))
	ctx.check(is_equal_approx(other.scale_factor, untinted.scale_factor) or absf(other.scale_factor - untinted.scale_factor) < 0.0001, "acessorios nao mudam a escala do corpo")
	other.free()
	rig.queue_free()
	untinted.queue_free()


func _missing(ctx: Variant) -> void:
	ctx.check(ModelRig.build(VisualSpec.make("class.nao_existe", 1.8)) == null, "alias inexistente = null (cai na primitiva)")
	ctx.check(ModelRig.build(VisualSpec.make("res://assets/third_party/nao/existe.glb", 1.8)) == null, "arquivo ausente = null")
	ctx.check(ModelRig.build(null) == null and ModelRig.create(null) == null, "spec nulo = null")
	ctx.check(ModelRig.build(VisualSpec.make("class.mage", -1.0)) == null, "spec invalido = null")
