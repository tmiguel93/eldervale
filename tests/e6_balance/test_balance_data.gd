extends RefCounted
## E6.5 - guardas de compatibilidade de saves: o balanceamento mexe so em dados NAO persistidos por personagem.
## Stats base/crescimento das classes (de onde sai o final_stats recalculado a cada login) ficam congelados aqui;
## qualquer mudanca deve ser decisao explicita (DEC) e vir com migracao/nota, nao um ajuste de balanceamento.

const FROZEN: Dictionary = {
	"warrior": {
		"base": {"max_health": 100.0, "max_resource": 50.0, "resource_regen": 5.0, "attack_power": 10.0, "defense": 0.0, "resistance": 0.0, "move_speed": 5.0},
		"growth": {"max_health": 10.0, "max_resource": 3.0, "attack_power": 1.0, "defense": 0.25},
	},
	"mage": {
		"base": {"max_health": 80.0, "max_resource": 100.0, "resource_regen": 6.0, "attack_power": 13.0, "defense": 0.0, "resistance": 0.05, "move_speed": 5.0},
		"growth": {"max_health": 7.0, "max_resource": 6.0, "attack_power": 1.4, "defense": 0.1},
	},
	"ranger": {
		"base": {"max_health": 90.0, "max_resource": 70.0, "resource_regen": 8.0, "attack_power": 11.0, "defense": 0.0, "resistance": 0.0, "move_speed": 5.5},
		"growth": {"max_health": 8.5, "max_resource": 4.0, "attack_power": 1.2, "defense": 0.15},
	},
}


func run(ctx: Object) -> void:
	for cid: String in FROZEN.keys():
		var d: Variant = BalanceSim.read_json("res://data/classes/%s.json" % cid)
		ctx.check(typeof(d) == TYPE_DICTIONARY, "%s: arquivo de classe legivel" % cid)
		if typeof(d) != TYPE_DICTIONARY:
			continue
		var want: Dictionary = FROZEN[cid]
		ctx.check(_same(d["base_stats"], want["base"]), "%s: base_stats inalterados (compat. de saves)" % cid)
		ctx.check(_same(d["growth_per_level"], want["growth"]), "%s: growth_per_level inalterado (compat. de saves)" % cid)
		# o espelho consumido pelo backend continua igual ao dado do Godot
		var mirror: Variant = BalanceSim.read_json("res://shared/content_schemas/classes.json")
		for c: Variant in (mirror as Dictionary)["classes"]:
			if (c as Dictionary)["id"] == cid:
				ctx.check(_same((c as Dictionary)["base_stats"], want["base"]), "%s: espelho do backend (classes.json) coerente" % cid)
	ctx.check(MAX_LEVEL_OK(), "nivel maximo e curva de XP inalterados (MAX_LEVEL 50; xp_to_next(1)=100, (4)=800)")
	# dados ajustados no E6.5 (nao persistidos por personagem): valores finais travados para evitar regressao silenciosa
	var boss: EnemyData = load("res://data/enemies/blight_treant.tres") as EnemyData
	ctx.check(boss != null and boss.stats != null and is_equal_approx(boss.stats.max_health, 1800.0), "E6.5: blight_treant max_health 1800 (dado de chefe, nao persistido)")
	var rain: SkillData = load("res://data/skills/arrow_rain.tres") as SkillData
	ctx.check(rain != null and is_equal_approx(rain.damage_multiplier, 2.0), "E6.5: arrow_rain damage_multiplier 2.0")
	var rar: Variant = BalanceSim.read_json("res://data/items/_rarity.json")
	ctx.check(typeof(rar) == TYPE_DICTIONARY, "tabela de raridade legivel")


func MAX_LEVEL_OK() -> bool:
	return CharacterProgress.MAX_LEVEL == 50 and CharacterProgress.xp_to_next(1) == 100 and CharacterProgress.xp_to_next(4) == 800


func _same(a: Variant, b: Dictionary) -> bool:
	var da: Dictionary = a as Dictionary
	if da.size() != b.size():
		return false
	for k: Variant in b.keys():
		if not da.has(k) or not is_equal_approx(float(da[k]), float(b[k])):
			return false
	return true
