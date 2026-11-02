extends RefCounted
## E8.3: catalogo de VFX valido, todas as referencias existem e o mapeamento habilidade/ataque -> efeito esta COMPLETO
## (3 classes + todos os inimigos). So dados: nao carrega textura/shader.


func run(ctx: Variant) -> void:
	await (ctx as SceneTree).physics_frame
	var cat: VfxCatalog = VfxCatalog.load_dir()
	var skills: Array = []
	var dir: DirAccess = DirAccess.open("res://data/skills")
	for f: String in dir.get_files():
		if f.ends_with(".tres"):
			skills.append(f.get_basename())
	ctx.check(cat.load_errors.is_empty(), "catalogo: sem erros de leitura %s" % [cat.load_errors])
	ctx.check(cat.effects.size() >= 40, "catalogo: >= 40 efeitos (%d)" % cat.effects.size())
	var errs: Array[String] = cat.validate(skills)
	ctx.check(errs.is_empty(), "catalogo: validate sem erros %s" % [errs.slice(0, 5)])
	for id: String in cat.referenced_effect_ids():
		ctx.check(cat.has_effect(id), "referencia '%s' existe" % id)
	# esquema invalido e detectado (o validador nao e permissivo)
	var bad: VfxCatalog = VfxCatalog.load_dir()
	bad.effects["fx_ruim"] = {"layers": [{"type": "ring", "life": 0.5, "r0": 0.1, "r1": 999.0}]}
	ctx.check(not bad.validate(skills).is_empty(), "validate rejeita campo fora da faixa")
	bad.effects["fx_ruim"] = {"layers": [{"type": "nao_existe", "life": 0.5}]}
	ctx.check(not bad.validate(skills).is_empty(), "validate rejeita tipo de camada desconhecido")
	bad.effects.erase("fx_ruim")
	bad.bindings["events"]["damage_enemy"] = "fx_inexistente"
	ctx.check(not bad.validate(skills).is_empty(), "validate rejeita binding para efeito inexistente")
	# habilidades das 3 classes (todos os slots) tem binding com efeito de lancamento ou projetil
	var cc: ClassCatalog = ClassCatalog.shared()
	for cid: String in ["warrior", "mage", "ranger"]:
		var def: ClassDef = cc.get_def(cid)
		ctx.check(def != null, "classe %s existe" % cid)
		for slot: Variant in def.skills:
			var sid: String = String(def.skills[slot])
			var b: Dictionary = cat.skill_binding(sid)
			var main: String = String(b.get("cast", b.get("projectile", b.get("muzzle", ""))))
			ctx.check(not main.is_empty() and cat.has_effect(main), "%s/%s (%s): binding com efeito principal" % [cid, slot, sid])
			for f: String in ["cast", "muzzle", "projectile", "impact", "end"]:
				if b.has(f) and not String(b[f]).is_empty():
					ctx.check(cat.has_effect(String(b[f])), "%s.%s -> %s existe" % [sid, f, b[f]])
	# todo ataque de todo inimigo resolve para efeitos existentes
	var seen: int = 0
	for f: String in DirAccess.open("res://data/enemies").get_files():
		if not f.ends_with(".tres"):
			continue
		var ed: EnemyData = EnemyCatalog.data_for(StringName(f.get_basename()))
		ctx.check(ed != null, "inimigo %s carrega" % f)
		if ed == null:
			continue
		for atk: EnemyAttack in ed.all_attacks():
			var kn: String = VfxTelegraph.kind_name(atk)
			var b2: Dictionary = cat.enemy_binding(kn, String(atk.id))
			ctx.check(not b2.is_empty(), "%s/%s (%s): ataque tem binding" % [f, atk.id, kn])
			var any_fx: bool = false
			for k: String in ["windup", "strike", "projectile", "impact"]:
				var ref: String = String(b2.get(k, ""))
				if not ref.is_empty():
					any_fx = true
					ctx.check(cat.has_effect(ref), "%s/%s.%s -> %s existe" % [f, atk.id, k, ref])
			ctx.check(any_fx, "%s/%s: ao menos um efeito" % [f, atk.id])
			ctx.check(cat.telegraph_color(kn).a > 0.0, "cor de telegrafo '%s'" % kn)
			seen += 1
	ctx.check(seen >= 10, "ataques de inimigos verificados (%d)" % seen)
	# eventos, raridades e escala por tier
	for key: String in ["damage_enemy", "damage_crit", "damage_player", "death_enemy", "death_boss", "death_player", "spawn", "level_up", "heal", "portal_ambient", "boss_aura", "respawn"]:
		ctx.check(cat.has_effect(cat.event_effect(key)), "evento '%s' -> efeito" % key)
	for r: String in ["common", "uncommon", "rare", "epic", "legendary", "mythic"]:
		ctx.check(cat.has_effect(cat.drop_effect(r)), "drop %s -> efeito" % r)
	ctx.check(cat.tier_scale("boss") > cat.tier_scale("mini_boss") and cat.tier_scale("mini_boss") > cat.tier_scale("normal"), "tier_scale cresce normal < mini_boss < boss")
