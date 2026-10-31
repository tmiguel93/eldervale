extends RefCounted
## Validacao dos SkillData em data/skills e do proprio validador.

const IDS: Array[StringName] = [&"basic_attack", &"heavy_strike", &"whirlwind", &"dodge"]


func run(ctx: Object) -> void:
	var seen: Dictionary = {}
	for id: StringName in IDS:
		var skill: SkillData = load("res://data/skills/%s.tres" % id) as SkillData
		ctx.check(skill != null, "carrega %s" % id)
		if skill == null:
			continue
		ctx.check(skill.id == id, "%s: id estavel igual ao nome do arquivo" % id)
		var errors: PackedStringArray = skill.validate()
		ctx.check(errors.is_empty(), "%s: valido %s" % [id, ", ".join(errors)])
		ctx.check(skill.active > 0.0, "%s: active > 0" % id)
		seen[skill.id] = true
		if skill.kind == SkillData.Kind.ATTACK:
			ctx.check(skill.damage_multiplier > 0.0, "%s: damage_multiplier > 0" % id)
		else:
			ctx.check(skill.i_frames > 0.0 and skill.dodge_distance > 0.0, "%s: i_frames e distancia > 0" % id)
	ctx.check(seen.size() == IDS.size(), "ids unicos")
	var whirl: SkillData = load("res://data/skills/whirlwind.tres") as SkillData
	ctx.check(whirl.hitbox_shape == SkillData.HitboxShape.SPHERE and whirl.hitbox_offset == 0.0, "whirlwind: esfera ao redor do jogador")

	# o validador realmente rejeita dados ruins
	var bad: SkillData = SkillData.new()
	ctx.check(bad.validate().size() >= 2, "skill vazia: id e display_name invalidos")
	bad.id = &"x"
	bad.display_name = "X"
	bad.active = 0.0
	ctx.check(not bad.validate().is_empty(), "active 0 rejeitado")
	bad.active = 0.1
	bad.damage_multiplier = 0.0
	ctx.check(not bad.validate().is_empty(), "damage_multiplier 0 rejeitado")
	bad.damage_multiplier = 1.0
	bad.cooldown = -1.0
	ctx.check(not bad.validate().is_empty(), "cooldown negativo rejeitado")
	bad.cooldown = 0.0
	ctx.check(bad.validate().is_empty(), "skill corrigida valida")
	bad.kind = SkillData.Kind.DODGE
	ctx.check(not bad.validate().is_empty(), "esquiva sem i_frames/distancia rejeitada")

	var stats: StatBlock = load("res://data/player_base_stats.tres") as StatBlock
	ctx.check(stats != null and stats.max_health > 0.0 and stats.attack_power > 0.0 and stats.max_resource > 0.0, "player_base_stats valido")
