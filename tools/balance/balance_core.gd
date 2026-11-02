class_name BalanceSim
extends RefCounted
## E6.5: simulador de balanceamento HEADLESS e DETERMINISTICO (sem rede, sem fisica, sem banco). Usa as MESMAS regras e dados do jogo:
## ClassCatalog/TalentCatalog (dados), SkillMods.collect/resolve, StatCalculator, Equipment + ItemRules/ItemRoller (instancias),
## DamageCalculator, CharacterProgress, LootTable/LootManager e os .tres de inimigos. Premissas do modelo e FAIXAS-ALVO ficam em
## data/balance/balance_config.json (nunca hardcoded aqui).
##
## Uso (a partir da raiz do projeto):
##   $G --headless --path . --script res://tools/balance/balance_sim.gd -- --label=before --out=docs/balance/e6_before.json [--quick]
##   $G --headless --path . --script res://tools/balance/balance_sim.gd -- --evaluate=docs/balance/e6_before.json --out=docs/balance/e6_before.json
## `--quick` reduz amostras (testes). `--evaluate` so reavalia os criterios de um resultado ja medido com a configuracao atual.
## Modelo (resumo; detalhes em docs/E6_BALANCE.md): rotacao gulosa por tempo (cooldown, custo/regen de recurso, tempo de conjuracao =
## windup+active+recover), dano no fim do windup (+ voo do projetil), esquiva periodica, alvo parado a distancia de engajamento.
## NAO modela: movimento, perda de alcance, IA real, aggro, invulnerabilidade/transicao de fase do chefe, adds, pocoes.

const DEFAULT_CONFIG: String = "res://data/balance/balance_config.json"
const SLOT_OF: Dictionary = {"weapon": ItemData.Slot.WEAPON, "armor": ItemData.Slot.ARMOR, "trinket": ItemData.Slot.TRINKET}
const UNIQUE_IDS: Array[String] = ["unique_emberfang", "unique_gravitas_plate", "unique_featherknot", "unique_twin_quiver", "unique_frostbrand"]
const WORLD_PATH: String = "res://data/areas/world/greenwood_world.json"

var cfg: Dictionary = {}
var sim: Dictionary = {}
var reg: ContentRegistry
var rules: ItemRules
var classes: ClassCatalog
var talents: TalentCatalog
var quick: bool = false
var seed_base: int = 0
var _enemy_ids: Array[String] = []
var _skill_cache: Dictionary = {}



## Carrega a configuracao (JSON) e devolve true se valida.
func load_config(path: String = DEFAULT_CONFIG) -> bool:
	var parsed: Variant = read_json(path)
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	cfg = parsed
	return true


static func read_json(path: String) -> Variant:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	return JSON.parse_string(f.get_as_text())


## Executa toda a medicao (determinista para a mesma configuracao + dados). Devolve o dicionario de resultados completo.
func run_all(label: String) -> Dictionary:
	setup()
	var res: Dictionary = {"meta": _meta(label)}
	res["xp"] = measure_xp()
	res["enemies"] = enemy_table()
	res["classes"] = measure_classes()
	res["uniques"] = measure_uniques()
	res["talents"] = measure_talents()
	res["loot"] = measure_loot()
	res["criteria"] = evaluate(res)
	return res


func setup() -> void:
	sim = cfg["sim"] as Dictionary
	seed_base = int(cfg["seed"])
	reg = ContentRegistry.new()
	reg.load_all()
	ItemRules.reset_shared()
	rules = ItemRules.shared()
	classes = ClassCatalog.shared()
	talents = TalentCatalog.shared()
	_enemy_ids = []
	for k: Variant in reg.enemies.keys():
		_enemy_ids.append(String(k))
	_enemy_ids.sort()


func _meta(label: String) -> Dictionary:
	var v: Dictionary = Engine.get_version_info()
	return {
		"label": label, "seed": seed_base, "quick": quick, "godot": "%d.%d.%d" % [int(v["major"]), int(v["minor"]), int(v["patch"])],
		"sim": sim.duplicate(true), "levels": cfg["levels"], "standard_level": cfg["standard_level"],
	}


func _gear_samples() -> int:
	return 3 if quick else int(sim["gear_samples"])


func _levels() -> Array:
	if quick:
		return [int(cfg["standard_level"]), int((cfg["build_criteria_levels"] as Array)[0])]
	return cfg["levels"] as Array


# ------------------------------------------------------------------ XP

func measure_xp() -> Dictionary:
	var levels: Array = []
	var prev: int = 0
	var cum: int = 0
	for lv: int in range(1, CharacterProgress.MAX_LEVEL):
		var need: int = CharacterProgress.xp_to_next(lv)
		levels.append({"level": lv, "to_next": need, "ratio": (float(need) / float(prev)) if prev > 0 else 0.0, "cumulative_at_next": cum + need})
		cum += need
		prev = need
	var kills: Dictionary = {}
	var kills_xp: int = 0
	var world: Variant = read_json(WORLD_PATH)
	var per_zone: Dictionary = {}
	if typeof(world) == TYPE_DICTIONARY:
		for z: Variant in ((world as Dictionary)["zones"] as Array):
			var zd: Dictionary = z
			var zxp: int = 0
			for e: Variant in (zd.get("enemies", []) as Array):
				var t: String = String((e as Dictionary)["type"])
				var en: EnemyData = reg.get_enemy(StringName(t))
				if en == null:
					continue
				kills[t] = int(kills.get(t, 0)) + 1
				zxp += en.xp_reward
			var enc: Variant = zd.get("encounter", null)
			if typeof(enc) == TYPE_DICTIONARY:
				var bo: EnemyData = reg.get_enemy(StringName(String((enc as Dictionary)["boss"])))
				if bo != null:
					kills[String(bo.id)] = int(kills.get(String(bo.id), 0)) + 1
					zxp += bo.xp_reward
			per_zone[String(zd["id"])] = zxp
			kills_xp += zxp
	var quests_xp: int = 0
	var quest_list: Array = []
	for n: String in JsonDir.list_json("res://data/quests"):
		if n.begins_with("_"):
			continue
		var q: Variant = read_json("res://data/quests/" + n)
		if typeof(q) == TYPE_DICTIONARY:
			var x: int = int(((q as Dictionary).get("rewards", {}) as Dictionary).get("xp", 0))
			quests_xp += x
			quest_list.append({"id": String((q as Dictionary)["id"]), "xp": x, "min_level": int(((q as Dictionary).get("prerequisites", {}) as Dictionary).get("min_level", 1))})
	var poi_xp: int = 0
	var poi_n: int = 0
	var ex: Variant = read_json("res://data/exploration/greenwood_exploration.json")
	if typeof(ex) == TYPE_DICTIONARY:
		for p: Variant in ((ex as Dictionary)["points"] as Array):
			poi_xp += int(((p as Dictionary).get("rewards", {}) as Dictionary).get("xp", 0))
			poi_n += 1
	var total: int = kills_xp + quests_xp + poi_xp
	var lvl_total: int = _level_for_xp(total)
	var lvl_quests: int = _level_for_xp(quests_xp)
	var lvl_kills: int = _level_for_xp(kills_xp)
	return {
		"levels": levels, "kills_by_enemy": kills, "kills_xp": kills_xp, "kills_xp_by_zone": per_zone, "quests_xp": quests_xp, "quest_count": quest_list.size(),
		"quests": quest_list, "poi_xp": poi_xp, "poi_count": poi_n, "total_xp": total, "final_level_all": lvl_total, "final_level_quests_only": lvl_quests,
		"final_level_kills_only": lvl_kills,
		"share": {"kills": snappedf(float(kills_xp) / maxf(float(total), 1.0), 0.001), "quests": snappedf(float(quests_xp) / maxf(float(total), 1.0), 0.001),
			"exploration": snappedf(float(poi_xp) / maxf(float(total), 1.0), 0.001)},
	}


static func _level_for_xp(xp: int) -> int:
	var lv: int = 1
	while lv < CharacterProgress.MAX_LEVEL and xp >= CharacterProgress.total_xp_for_level(lv + 1):
		lv += 1
	return lv


# ------------------------------------------------------------------ inimigos

func enemy_table() -> Dictionary:
	var out: Dictionary = {}
	for id: String in _enemy_ids:
		var en: EnemyData = reg.get_enemy(StringName(id))
		var th: Dictionary = enemy_threat(en)
		out[id] = {
			"tier": String(en.tier), "hp": en.stats.max_health, "defense": en.stats.defense, "resistance": en.stats.resistance, "attack_power": en.stats.attack_power,
			"xp": en.xp_reward, "threat_hit": th["hit"], "threat_cycle": th["cycle"],
		}
	return out


## Golpe medio (antes da mitigacao) e ciclo medio (s) do inimigo: media ponderada pelos pesos dos ataques que causam dano; chefes: media das fases.
func enemy_threat(en: EnemyData) -> Dictionary:
	var phases: Array[Dictionary] = []
	if not en.phases.is_empty():
		for ph: EnemyPhase in en.phases:
			phases.append(_attack_avg(en, ph.attacks, ph.damage_mult))
	elif not en.attacks.is_empty():
		phases.append(_attack_avg(en, en.attacks, 1.0))
	else:
		phases.append({"hit": en.stats.attack_power * en.attack_damage_multiplier, "cycle": en.windup + en.attack_cooldown})
	var hit: float = 0.0
	var cyc: float = 0.0
	for p: Dictionary in phases:
		hit += float(p["hit"])
		cyc += float(p["cycle"])
	var n: float = float(phases.size())
	return {"hit": snappedf(hit / n, 0.001), "cycle": snappedf(cyc / n, 0.001), "phases": phases}


func _attack_avg(en: EnemyData, atks: Array[EnemyAttack], dmg_mult: float) -> Dictionary:
	var w: float = 0.0
	var m: float = 0.0
	var c: float = 0.0
	for a: EnemyAttack in atks:
		if a.kind == EnemyAttack.Kind.SUMMON:
			continue
		w += a.weight
		m += a.weight * a.damage_multiplier
		c += a.weight * (a.windup + a.cooldown)
	if w <= 0.0:
		return {"hit": 0.0, "cycle": 1.0}
	return {"hit": en.stats.attack_power * (m / w) * dmg_mult, "cycle": c / w}


# ------------------------------------------------------------------ personagem

## Aloca a build na ordem de prioridade respeitando as regras reais (check_allocate). {state, spent, avail, skipped[]}.
func alloc_build(class_id: String, build: Dictionary, level: int) -> Dictionary:
	var tree: TalentTree = talents.get_tree(class_id)
	var st: TalentState = TalentState.new()
	var skipped: Array[String] = []
	var spec: String = String(build.get("spec", ""))
	if spec != "":
		var why: String = TalentState.check_choose_spec(tree, st, spec)
		if why != "":
			skipped.append("spec:" + why)
		else:
			st.apply_choose_spec(spec)
	for entry: Variant in (build["order"] as Array):
		var node: String = String((entry as Array)[0])
		var want: int = int((entry as Array)[1])
		for _r: int in want:
			var err: String = TalentState.check_allocate(tree, st, level, node, talents)
			if err != "":
				skipped.append("%s:%s" % [node, err])
				break
			st.apply_allocate(node)
	return {"state": st, "spent": st.points_spent(tree), "avail": talents.points_for_level(level), "skipped": skipped}


func make_equipment(slots: Dictionary, insts: Dictionary = {}) -> Equipment:
	var eq: Equipment = Equipment.new(reg, Inventory.new(reg, 20))
	for k: Variant in slots:
		eq.set_equipped(int(SLOT_OF[String(k)]), StringName(String(slots[k])), (insts.get(String(k), {}) as Dictionary))
	return eq


## Personagem pronto para simular: stats finais (mesma formula do servidor) + habilidades + mods.
func make_character(class_id: String, level: int, st: TalentState, eq: Equipment) -> Dictionary:
	var def: ClassDef = classes.get_def(class_id)
	var tree: TalentTree = talents.get_tree(class_id)
	var prog: CharacterProgress = CharacterProgress.new()
	prog.level = level
	prog.bonus_per_level = def.growth.copy()
	var col: Dictionary = SkillMods.collect(tree, st)
	SkillMods.merge_effects(col, eq.get_skill_effects())
	var stats: StatBlock = StatCalculator.compute(def.base_stats, eq, prog, col["stats"] as StatBlock)
	var skl: Array[SkillData] = []
	for slot: String in ["attack", "skill_1", "skill_2"]:
		skl.append(_skill(String(def.skills[slot])))
	return {"class_id": class_id, "level": level, "stats": stats, "skills": skl, "dodge": _skill(String(def.skills["dodge"])), "mods": col["skills"], "resource_kind": def.resource_kind}


func _skill(id: String) -> SkillData:
	if not _skill_cache.has(id):
		_skill_cache[id] = ClassCatalog.load_skill(StringName(id))
	return _skill_cache[id] as SkillData


# ------------------------------------------------------------------ luta

func target(hp: float, def: float, res: float) -> Dictionary:
	return {"hp": hp, "max": hp, "def": def, "res": res}


func targets_for(spec_id: String, players: int = 1) -> Array:
	if spec_id == "pack":
		var en: EnemyData = reg.get_enemy(StringName(String(sim["pack_enemy"])))
		var out: Array = []
		for _i: int in int(sim["pack_size"]):
			out.append(target(en.stats.max_health * float(sim["pack_hp_mult"]), en.stats.defense, en.stats.resistance))
		return out
	var e: EnemyData = reg.get_enemy(StringName(spec_id))
	var mult: float = DifficultyScaling.load_default().health_mult(players, e.tier)
	return [target(e.stats.max_health * mult, e.stats.defense, e.stats.resistance)]


func _mods_for(ch: Dictionary, skill: SkillData) -> Array:
	var all: Dictionary = ch["mods"] as Dictionary
	var mods: Array = (all.get(String(skill.id), []) as Array).duplicate()
	if skill.kind != SkillData.Kind.DODGE and all.has("*"):
		mods.append_array(all["*"] as Array)
	return mods


## Luta de UM jogador contra `tgts` (Array de target()). `opts`: hp_ratio (contexto das condicoes), dodge (bool), boss (bool).
## Devolve {ttk, dealt, casts{id:n}, dmg{id:x}, dodges, timeout}.
func fight(ch: Dictionary, tgts: Array, opts: Dictionary = {}) -> Dictionary:
	var dt: float = float(sim["dt"])
	var max_t: float = float(sim["max_time_s"])
	var stats: StatBlock = ch["stats"] as StatBlock
	var alive: Array = []
	for t: Variant in tgts:
		alive.append((t as Dictionary).duplicate())
	var res_cur: float = stats.max_resource
	var cds: Dictionary = {}
	var last_use: Dictionary = {}
	var busy_until: float = 0.0
	var now: float = 0.0
	var events: Array[Dictionary] = []
	var casts: Dictionary = {}
	var dmg: Dictionary = {}
	var dodges: int = 0
	var last_dodge: float = -1000.0
	var dealt: float = 0.0
	var use_dodge: bool = bool(opts.get("dodge", true))
	var dodge_iv: float = float(sim["dodge_interval_s"])
	var hp_ratio: float = float(opts.get("hp_ratio", 1.0))
	var is_boss: bool = bool(opts.get("boss", false))
	var eng: float = float(sim["engage_distance_m"])
	var extra_rate: float = float(sim["extra_projectile_hit_rate_boss"]) if is_boss else float(sim["extra_projectile_hit_rate"])
	var skl: Array = ch["skills"] as Array
	var dodge_skill: SkillData = ch["dodge"] as SkillData
	var timeout: bool = false
	while not alive.is_empty():
		if now >= max_t:
			timeout = true
			break
		# 1) efeitos que pousam agora
		while not events.is_empty() and float(events[0]["t"]) <= now + 0.0001:
			var ev: Dictionary = events.pop_front()
			var d: float = _land(ev, alive, stats)
			dealt += d
			dmg[ev["sid"]] = float(dmg.get(ev["sid"], 0.0)) + d
			if alive.is_empty():
				break
		if alive.is_empty():
			break
		# 2) decisao quando livre
		if now >= busy_until - 0.0001:
			var ctx: Dictionary = {"hp_ratio": hp_ratio, "resource_ratio": res_cur / maxf(stats.max_resource, 0.001), "clock": now, "last_use": last_use}
			var chosen: Dictionary = {}
			if use_dodge and now - last_dodge >= dodge_iv and _ready(cds, dodge_skill, ch, ctx, res_cur, now):
				chosen = _resolve_cast(ch, dodge_skill, ctx)
			else:
				var best_rate: float = -1.0
				for sk: Variant in skl:
					var s: SkillData = sk
					if not _ready(cds, s, ch, ctx, res_cur, now):
						continue
					var r: Dictionary = _resolve_cast(ch, s, ctx)
					var rate: float = _expected_damage(r, stats, alive, extra_rate) / maxf(float((r["skill"] as SkillData).total_duration()), 0.05)
					if rate > best_rate + 0.0001:
						best_rate = rate
						chosen = r
			if not chosen.is_empty():
				var eff: SkillData = chosen["skill"] as SkillData
				var base_id: String = String(chosen["base_id"])
				res_cur -= eff.resource_cost
				cds[base_id] = now + eff.cooldown
				last_use[base_id] = now
				busy_until = now + eff.total_duration()
				casts[base_id] = int(casts.get(base_id, 0)) + 1
				if eff.kind == SkillData.Kind.DODGE:
					dodges += 1
					last_dodge = now
				else:
					var travel: float = (eng / eff.projectile_speed) if eff.is_projectile() else 0.0
					var ev2: Dictionary = {"t": now + eff.windup + travel, "sid": base_id, "skill": eff, "res": chosen["res"], "extra_rate": extra_rate}
					var ins: int = events.size()
					for i: int in events.size():
						if float(events[i]["t"]) > float(ev2["t"]):
							ins = i
							break
					events.insert(ins, ev2)
		# 3) avanco do tempo
		now += dt
		res_cur = minf(stats.max_resource, res_cur + stats.resource_regen * dt)
	return {"ttk": now, "dealt": dealt, "casts": casts, "dmg": dmg, "dodges": dodges, "timeout": timeout}


func _ready(cds: Dictionary, s: SkillData, ch: Dictionary, ctx: Dictionary, res_cur: float, now: float) -> bool:
	if now < float(cds.get(String(s.id), -1.0)) - 0.0001:
		return false
	var r: Dictionary = _resolve_cast(ch, s, ctx)
	return res_cur + 0.0001 >= (r["skill"] as SkillData).resource_cost


func _resolve_cast(ch: Dictionary, s: SkillData, ctx: Dictionary) -> Dictionary:
	var mods: Array = _mods_for(ch, s)
	var r: SkillMods.Resolved
	if mods.is_empty():
		r = SkillMods.Resolved.new()
		r.skill = s
	else:
		r = SkillMods.resolve(s, mods, ctx)
	return {"skill": r.skill, "res": r, "base_id": String(s.id)}


## Dano esperado do uso `r` agora (mesma regra de acerto de `_land`), para a escolha gulosa.
func _expected_damage(r: Dictionary, stats: StatBlock, alive: Array, extra_rate: float) -> float:
	var eff: SkillData = r["skill"] as SkillData
	if eff.kind == SkillData.Kind.DODGE:
		return 0.0
	var n: int = alive.size()
	var total: float = 0.0
	for pr: Variant in _hit_list(eff, alive):
		var tg: Dictionary = (pr as Array)[0] as Dictionary
		total += float((pr as Array)[1]) * DamageCalculator.compute(stats.attack_power * eff.damage_multiplier, float(tg["def"]), float(tg["res"]))
	var res: SkillMods.Resolved = r["res"] as SkillMods.Resolved
	if eff.is_projectile() and res.extra_projectiles > 0 and n > 0:
		var first: Dictionary = alive[0]
		total += float(res.extra_projectiles) * extra_rate * DamageCalculator.compute(stats.attack_power * eff.damage_multiplier * res.extra_damage_scale, float(first["def"]), float(first["res"]))
	return total


## Alvos atingidos pelo golpe principal como pares [alvo, peso]: area = todos (peso 1); projetil = o primeiro (peso 1) + perfurados
## (peso `pierce_hit_rate`: alinhamento esperado); corpo a corpo em caixa = o primeiro.
func _hit_list(eff: SkillData, alive: Array) -> Array:
	var out: Array = []
	if alive.is_empty():
		return out
	if eff.is_projectile():
		for i: int in mini(1 + eff.projectile_pierce, alive.size()):
			out.append([alive[i], 1.0 if i == 0 else float(sim["pierce_hit_rate"])])
	elif eff.hitbox_shape == SkillData.HitboxShape.SPHERE:
		for t: Variant in alive:
			out.append([t, 1.0])
	else:
		out.append([alive[0], 1.0])
	return out


func _land(ev: Dictionary, alive: Array, stats: StatBlock) -> float:
	var eff: SkillData = ev["skill"] as SkillData
	var res: SkillMods.Resolved = ev["res"] as SkillMods.Resolved
	var dealt: float = 0.0
	var hit_now: Array = _hit_list(eff, alive)
	for pr: Variant in hit_now:
		var tg: Dictionary = (pr as Array)[0] as Dictionary
		var d: float = float((pr as Array)[1]) * DamageCalculator.compute(stats.attack_power * eff.damage_multiplier, float(tg["def"]), float(tg["res"]))
		tg["hp"] = float(tg["hp"]) - d
		dealt += d
	if eff.is_projectile() and res.extra_projectiles > 0 and not alive.is_empty():
		var first: Dictionary = alive[0]
		var d2: float = float(res.extra_projectiles) * float(ev["extra_rate"]) * DamageCalculator.compute(stats.attack_power * eff.damage_multiplier * res.extra_damage_scale, float(first["def"]), float(first["res"]))
		first["hp"] = float(first["hp"]) - d2
		dealt += d2
	var i: int = alive.size() - 1
	while i >= 0:
		if float((alive[i] as Dictionary)["hp"]) <= 0.0:
			alive.remove_at(i)
		i -= 1
	return dealt


# ------------------------------------------------------------------ sobrevivencia

## Dano medio recebido por segundo de um inimigo (golpe mitigado pela defesa/resistencia do jogador x taxa de acerto / ciclo).
func incoming_dps(en: EnemyData, stats: StatBlock, players: int = 1) -> float:
	var diff: DifficultyScaling = DifficultyScaling.load_default()
	var dmult: float = diff.damage_mult(players, en.tier)
	var th: Dictionary = enemy_threat(en)
	var total: float = 0.0
	var phases: Array = th["phases"] as Array
	for p: Variant in phases:
		var hit: float = float((p as Dictionary)["hit"]) * dmult
		var per_hit: float = DamageCalculator.compute(hit, stats.defense, stats.resistance)
		total += per_hit * float(sim["enemy_hit_rate"]) / maxf(float((p as Dictionary)["cycle"]), 0.1)
	return total / float(phases.size())


# ------------------------------------------------------------------ medicao por classe

func _stat_summary(s: StatBlock) -> Dictionary:
	return {"max_health": snappedf(s.max_health, 0.01), "max_resource": snappedf(s.max_resource, 0.01), "resource_regen": snappedf(s.resource_regen, 0.01),
		"attack_power": snappedf(s.attack_power, 0.01), "defense": snappedf(s.defense, 0.01), "resistance": snappedf(s.resistance, 0.001), "move_speed": snappedf(s.move_speed, 0.01)}


## Metricas de um personagem contra o conjunto de alvos `target_ids`. DPS = vida total / tempo de abate (uma vez por alvo).
func eval_character(ch: Dictionary, target_ids: Array, with_boss_extras: bool) -> Dictionary:
	var out: Dictionary = {"stats": _stat_summary(ch["stats"] as StatBlock), "ttk": {}, "dps": {}}
	var stats: StatBlock = ch["stats"] as StatBlock
	for tid: Variant in target_ids:
		var id: String = String(tid)
		var is_boss: bool = id != "pack" and reg.get_enemy(StringName(id)) != null and reg.get_enemy(StringName(id)).tier == EnemyData.TIER_BOSS
		var tg: Array = targets_for(id, 1)
		var hp_total: float = 0.0
		for t: Variant in tg:
			hp_total += float((t as Dictionary)["max"])
		var f: Dictionary = fight(ch, tg, {"boss": is_boss})
		(out["ttk"] as Dictionary)[id] = snappedf(float(f["ttk"]), 0.01)
		(out["dps"] as Dictionary)[id] = snappedf(hp_total / maxf(float(f["ttk"]), 0.001), 0.01)
		if id == String(cfg["reference_boss"]):
			out["skills"] = _skill_usage(f)
		if id != "pack":
			var en: EnemyData = reg.get_enemy(StringName(id))
			var idps: float = incoming_dps(en, stats, 1)
			(out.get("survive_s", {}) as Dictionary)
			if not out.has("survive_s"):
				out["survive_s"] = {}
				out["duel_ratio"] = {}
			(out["survive_s"] as Dictionary)[id] = snappedf(stats.max_health / maxf(idps, 0.0001), 0.1)
			(out["duel_ratio"] as Dictionary)[id] = snappedf(float(f["ttk"]) / (stats.max_health / maxf(idps, 0.0001)), 0.001)
	if with_boss_extras:
		var bid: String = String(cfg["reference_boss"])
		var b4: Array = targets_for(bid, 4)
		var f4: Dictionary = fight(ch, b4, {"boss": true})
		# 4 jogadores identicos: tempo = ttk de UM jogador contra a vida escalada / 4 (aproximacao linear, sem friendly fire)
		out["boss_ttk_4p"] = snappedf(float(f4["ttk"]) / 4.0, 0.01)
		var f_low: Dictionary = fight(ch, targets_for(bid, 1), {"boss": true, "hp_ratio": 0.3})
		out["boss_ttk_1p_lowhp"] = snappedf(float(f_low["ttk"]), 0.01)
	return out


func _skill_usage(f: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var total: float = 0.0
	for k: Variant in (f["dmg"] as Dictionary):
		total += float((f["dmg"] as Dictionary)[k])
	var ttk: float = maxf(float(f["ttk"]), 0.001)
	var ids: Array = (f["casts"] as Dictionary).keys()
	ids.sort()
	for k2: Variant in ids:
		var key: String = String(k2)
		out[key] = {"casts": int((f["casts"] as Dictionary)[key]), "casts_per_min": snappedf(float((f["casts"] as Dictionary)[key]) * 60.0 / ttk, 0.1),
			"dmg_share": snappedf(float((f["dmg"] as Dictionary).get(key, 0.0)) / maxf(total, 0.001), 0.001)}
	return out


func _mean_of(list: Array, keys: Array) -> Variant:
	## media de valores numericos em dicionarios aninhados (mesma forma em todos os elementos)
	return null


func _agg_numbers(samples: Array) -> Dictionary:
	## agrega uma lista de resultados de eval_character: media, p10, p90 de ttk/dps/duel por alvo e das estatisticas
	var out: Dictionary = {"n": samples.size(), "ttk": {}, "dps": {}, "duel_ratio": {}, "survive_s": {}, "stats": {}}
	if samples.is_empty():
		return out
	for group: String in ["ttk", "dps", "duel_ratio", "survive_s"]:
		var first: Dictionary = (samples[0] as Dictionary).get(group, {}) as Dictionary
		for k: Variant in first:
			var vals: Array = []
			for s: Variant in samples:
				vals.append(float(((s as Dictionary)[group] as Dictionary)[k]))
			vals.sort()
			(out[group] as Dictionary)[k] = {"mean": snappedf(_mean(vals), 0.01), "p10": snappedf(_pct(vals, 0.1), 0.01), "p90": snappedf(_pct(vals, 0.9), 0.01)}
	for key: Variant in ((samples[0] as Dictionary)["stats"] as Dictionary):
		var vv: Array = []
		for s2: Variant in samples:
			vv.append(float((((s2 as Dictionary)["stats"]) as Dictionary)[key]))
		(out["stats"] as Dictionary)[key] = snappedf(_mean(vv), 0.01)
	if (samples[0] as Dictionary).has("boss_ttk_4p"):
		var b4: Array = []
		var bl: Array = []
		for s3: Variant in samples:
			b4.append(float((s3 as Dictionary)["boss_ttk_4p"]))
			bl.append(float((s3 as Dictionary)["boss_ttk_1p_lowhp"]))
		out["boss_ttk_4p"] = snappedf(_mean(b4), 0.01)
		out["boss_ttk_1p_lowhp"] = snappedf(_mean(bl), 0.01)
	if (samples[0] as Dictionary).has("skills"):
		out["skills"] = (samples[0] as Dictionary)["skills"]
	return out


static func _mean(vals: Array) -> float:
	var t: float = 0.0
	for v: Variant in vals:
		t += float(v)
	return t / float(maxi(vals.size(), 1))


static func _pct(sorted_vals: Array, p: float) -> float:
	if sorted_vals.is_empty():
		return 0.0
	var idx: int = clampi(int(roundf(p * float(sorted_vals.size() - 1))), 0, sorted_vals.size() - 1)
	return float(sorted_vals[idx])


func measure_classes() -> Dictionary:
	var out: Dictionary = {}
	var all_targets: Array = _enemy_ids.duplicate()
	all_targets.append("pack")
	var sample_targets: Array = cfg["sample_targets"] as Array
	for class_id: String in ["warrior", "mage", "ranger"]:
		var cdata: Dictionary = {}
		for lv_v: Variant in _levels():
			var lv: int = int(lv_v)
			var builds_out: Dictionary = {}
			for b: Variant in ((cfg["builds"] as Dictionary)[class_id] as Array):
				var build: Dictionary = b
				var al: Dictionary = alloc_build(class_id, build, lv)
				var st: TalentState = al["state"] as TalentState
				var bo: Dictionary = {"spec": String(build["spec"]), "points_spent": al["spent"], "points_available": al["avail"], "skipped": al["skipped"],
					"ranks": st.ranks.duplicate(), "tiers": {}}
				var tiers: Dictionary = bo["tiers"] as Dictionary
				var g: Dictionary = cfg["gear"] as Dictionary
				# common e fixed_best: conjunto completo de alvos
				var eq_c: Equipment = make_equipment(g["common"] as Dictionary)
				tiers["common"] = _agg_numbers([eval_character(make_character(class_id, lv, st, eq_c), all_targets, true)])
				var eq_f: Equipment = make_equipment(g["fixed_best"] as Dictionary)
				tiers["fixed_best"] = _agg_numbers([eval_character(make_character(class_id, lv, st, eq_f), sample_targets, false)])
				for rar: Variant in (g["rolled_rarities"] as Array):
					var samples: Array = []
					var failed_roll: int = 0
					for i: int in _gear_samples():
						var set: Dictionary = roll_gear_set(String(rar), lv, "%s:%s:%d:%d" % [class_id, String(rar), lv, i])
						failed_roll += int(set["failed"])
						var eq_r: Equipment = make_equipment(g["rolled_base"] as Dictionary, set["insts"] as Dictionary)
						samples.append(eval_character(make_character(class_id, lv, st, eq_r), sample_targets, false))
					var agg: Dictionary = _agg_numbers(samples)
					agg["roll_failures"] = failed_roll
					tiers[String(rar)] = agg
				builds_out[String(build["id"])] = bo
			cdata[str(lv)] = {"builds": builds_out}
		out[class_id] = cdata
	return out


## Conjunto de 3 instancias (arma/armadura/amuleto) de uma raridade, rolado com semente derivada (determinista).
func roll_gear_set(rarity: String, ilvl: int, seed_key: String) -> Dictionary:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = absi(("%d|%s" % [seed_base, seed_key]).hash()) % 2147483647
	var g: Dictionary = (cfg["gear"] as Dictionary)["rolled_base"] as Dictionary
	var insts: Dictionary = {}
	var failed: int = 0
	var n: int = 0
	for slot: String in ["weapon", "armor", "trinket"]:
		n += 1
		var base: ItemData = reg.get_item(StringName(String(g[slot])))
		var uid: String = ItemRoller.make_uid("sim|%d" % seed_base, ilvl, n, absi(seed_key.hash()) % 100000)
		var inst: Dictionary = ItemRoller.roll_instance(rules, base, rarity, ilvl, rng, uid)
		if inst.is_empty() or rules.validate_instance(inst, base) != "":
			failed += 1
			continue
		insts[slot] = inst
	return {"insts": insts, "failed": failed}


# ------------------------------------------------------------------ unicos

func measure_uniques() -> Dictionary:
	var out: Dictionary = {}
	var lv: int = int(cfg["standard_level"])
	var bid: String = String(cfg["reference_boss"])
	for class_id: String in ["warrior", "mage", "ranger"]:
		var build: Dictionary = _find_build(class_id, "none")
		var best_id: String = _best_offense_build(class_id)
		var best: Dictionary = _find_build(class_id, best_id)
		var cls: Dictionary = {}
		for bname: String in ["none", best_id]:
			var bb: Dictionary = build if bname == "none" else best
			var st: TalentState = alloc_build(class_id, bb, lv)["state"] as TalentState
			var base_eq: Equipment = make_equipment((cfg["gear"] as Dictionary)["common"] as Dictionary)
			var base_ch: Dictionary = make_character(class_id, lv, st, base_eq)
			var base_full: Dictionary = {}
			for hp: float in [1.0, 0.3]:
				var f0: Dictionary = fight(base_ch, targets_for(bid, 1), {"boss": true, "hp_ratio": hp})
				base_full[str(hp)] = float(f0["ttk"])
			var per_u: Dictionary = {}
			for uid: String in UNIQUE_IDS:
				var item: ItemData = reg.get_item(StringName(uid))
				var slot_name: String = rules.slot_name_of(item)
				var gear: Dictionary = ((cfg["gear"] as Dictionary)["common"] as Dictionary).duplicate()
				gear[slot_name] = uid
				var eq_u: Equipment = make_equipment(gear)
				var ch_u: Dictionary = make_character(class_id, lv, st, eq_u)
				var entry: Dictionary = {"slot": slot_name}
				for hp2: float in [1.0, 0.3]:
					var f1: Dictionary = fight(ch_u, targets_for(bid, 1), {"boss": true, "hp_ratio": hp2})
					var gain: float = (float(base_full[str(hp2)]) / maxf(float(f1["ttk"]), 0.001) - 1.0) * 100.0
					entry["dps_gain_pct_hp%d" % int(hp2 * 100.0)] = snappedf(gain, 0.1)
				var bs: StatBlock = base_ch["stats"] as StatBlock
				var us: StatBlock = ch_u["stats"] as StatBlock
				var pk0: Dictionary = fight(base_ch, targets_for("pack"), {})
				var pk1: Dictionary = fight(ch_u, targets_for("pack"), {})
				entry["pack_dps_gain_pct"] = snappedf((float(pk0["ttk"]) / maxf(float(pk1["ttk"]), 0.001) - 1.0) * 100.0, 0.1)
				var boss_en: EnemyData = reg.get_enemy(StringName(bid))
				var sv_b: float = bs.max_health / maxf(incoming_dps(boss_en, bs, 1), 0.0001)
				var sv_u: float = us.max_health / maxf(incoming_dps(boss_en, us, 1), 0.0001)
				entry["survive_gain_pct_boss"] = snappedf((sv_u / sv_b - 1.0) * 100.0, 0.1)
				entry["max_health_delta"] = snappedf(us.max_health - bs.max_health, 0.01)
				entry["defense_delta"] = snappedf(us.defense - bs.defense, 0.01)
				entry["move_speed_delta"] = snappedf(us.move_speed - bs.move_speed, 0.01)
				per_u[uid] = entry
			cls[bname] = per_u
		out[class_id] = cls
	return out


func _find_build(class_id: String, build_id: String) -> Dictionary:
	for b: Variant in ((cfg["builds"] as Dictionary)[class_id] as Array):
		if String((b as Dictionary)["id"]) == build_id:
			return b as Dictionary
	return {}


## Build de ofensiva de referencia da classe: a primeira com especializacao (listada primeiro no config).
func _best_offense_build(class_id: String) -> String:
	for b: Variant in ((cfg["builds"] as Dictionary)[class_id] as Array):
		if String((b as Dictionary)["spec"]) != "":
			return String((b as Dictionary)["id"])
	return "none"


# ------------------------------------------------------------------ talentos (efeito isolado por no)

func measure_talents() -> Dictionary:
	var out: Dictionary = {}
	var lv: int = 20 if not quick else int(cfg["standard_level"])
	var bid: String = String(cfg["reference_boss"])
	for class_id: String in ["warrior", "mage", "ranger"]:
		var tree: TalentTree = talents.get_tree(class_id)
		var def: ClassDef = classes.get_def(class_id)
		var spec: String = String((def.active_specializations()[0] as Dictionary)["id"])
		var eq: Equipment = make_equipment((cfg["gear"] as Dictionary)["common"] as Dictionary)
		var st0: TalentState = TalentState.new()
		st0.spec_id = spec
		var ch0: Dictionary = make_character(class_id, lv, st0, eq)
		var f0: Dictionary = fight(ch0, targets_for(bid, 1), {"boss": true})
		var f0_pack: Dictionary = fight(ch0, targets_for("pack"), {})
		var hp0: float = (ch0["stats"] as StatBlock).max_health
		var nodes: Dictionary = {}
		for id: String in tree.order:
			var n: Dictionary = tree.get_node_def(id)
			if String(n["spec"]) != "" and String(n["spec"]) != spec:
				continue
			var st: TalentState = TalentState.new()
			st.spec_id = spec
			st.ranks[id] = int(n["max_rank"])
			var ch: Dictionary = make_character(class_id, lv, st, eq)
			var f1: Dictionary = fight(ch, targets_for(bid, 1), {"boss": true})
			var f1p: Dictionary = fight(ch, targets_for("pack"), {})
			var pts: int = int(n["cost"]) * int(n["max_rank"])
			var gain: float = (float(f0["ttk"]) / maxf(float(f1["ttk"]), 0.001) - 1.0) * 100.0
			var gain_pack: float = (float(f0_pack["ttk"]) / maxf(float(f1p["ttk"]), 0.001) - 1.0) * 100.0
			var hp_gain: float = ((ch["stats"] as StatBlock).max_health / maxf(hp0, 0.001) - 1.0) * 100.0
			nodes[id] = {"tier": String(n["tier"]), "spec": String(n["spec"]), "points": pts, "dps_gain_pct_boss": snappedf(gain, 0.01), "dps_gain_pct_pack": snappedf(gain_pack, 0.01),
				"hp_gain_pct": snappedf(hp_gain, 0.01), "gain_per_point_pct": snappedf(maxf(gain, gain_pack) / float(pts), 0.001)}
		out[class_id] = {"level": lv, "spec": spec, "baseline_ttk_boss": snappedf(float(f0["ttk"]), 0.01), "nodes": nodes}
	return out


# ------------------------------------------------------------------ loot

## Probabilidade por abate (analitica, a partir das tabelas e dos pesos) e Monte Carlo com semente fixa (LootManager real).
func measure_loot() -> Dictionary:
	var out: Dictionary = {"rarity_weights": {}, "by_enemy": {}}
	for tier: String in ["normal", "mini_boss", "boss"]:
		var w: Dictionary = ItemRoller.rarity_weights(rules, tier)
		var tot: float = 0.0
		for k: Variant in w:
			tot += float(w[k])
		var p: Dictionary = {}
		for k2: Variant in w:
			p[String(k2)] = snappedf(float(w[k2]) / maxf(tot, 0.0001), 0.0001)
		(out["rarity_weights"] as Dictionary)[tier] = p
	var obt: Dictionary = {}
	for uid: String in rules.uniques.keys():
		var u: Dictionary = rules.uniques[uid]
		var srcs: Array = []
		var best: float = 1e12
		for src: Variant in ((u["obtain"] as Dictionary)["sources"] as Array):
			var ch: float = float((src as Dictionary)["chance"])
			srcs.append({"loot_table": String((src as Dictionary)["loot_table"]), "chance": ch, "kills_per_unique": snappedf(1.0 / maxf(ch, 0.0000001), 0.1)})
			best = minf(best, 1.0 / maxf(ch, 0.0000001))
		obt[uid] = {"min_level": int((u["obtain"] as Dictionary)["min_level"]), "sources": srcs, "best_kills": snappedf(best, 0.1)}
	out["uniques_obtain"] = obt
	var ls: ServerSettings = ServerSettings.new()
	ls.rolled_loot = true
	var lm: LootManager = LootManager.new(null, ls)
	lm.base_seed = seed_base
	lm.uid_salt = "sim"
	var lv: int = int(cfg["standard_level"])
	var n_normal: int = 300 if quick else int(sim["loot_kills"])
	var n_boss: int = 300 if quick else int(sim["loot_kills_boss"])
	for id: String in _enemy_ids:
		var en: EnemyData = reg.get_enemy(StringName(id))
		if en.loot_table == null:
			continue
		var tier: String = String(en.tier)
		var n: int = n_normal if tier == "normal" else n_boss
		var counts: Dictionary = {"common": 0, "uncommon": 0, "rare": 0, "epic": 0, "legendary": 0, "mythic": 0}
		var uniques: Dictionary = {}
		var items: Dictionary = {}
		var gear_units: int = 0
		for i: int in n:
			var drops: Array[LootDrop] = lm.roll_for(en.loot_table, i + 1, 1, lv, tier, lv)
			for d: LootDrop in drops:
				var base: ItemData = reg.get_item(d.item_id)
				items[String(d.item_id)] = int(items.get(String(d.item_id), 0)) + d.quantity
				if base == null or not base.is_equippable():
					continue
				if rules.is_unique(String(base.id)):
					uniques[String(d.item_id)] = int(uniques.get(String(d.item_id), 0)) + 1
					continue
				gear_units += d.quantity
				var rar: String = String(d.inst.get("rarity", "common")) if not d.inst.is_empty() else "common"
				counts[rar] = int(counts[rar]) + d.quantity
		var per_kill: Dictionary = {}
		for r: Variant in counts:
			per_kill[String(r)] = snappedf(float(counts[r]) / float(n), 0.00001)
		var analytic: Dictionary = _analytic_loot(en, tier, lv)
		(out["by_enemy"] as Dictionary)[id] = {"tier": tier, "kills": n, "gear_units": gear_units, "gear_per_kill": snappedf(float(gear_units) / float(n), 0.0001),
			"rarity_counts": counts, "rarity_per_kill": per_kill, "uniques": uniques, "analytic": analytic}
	return out


## Esperanca por abate: unidades de equipamento (nao unico) x probabilidade de raridade do tier + chance dos unicos da tabela.
func _analytic_loot(en: EnemyData, tier: String, lv: int) -> Dictionary:
	var t: LootTable = en.loot_table
	var pool: float = t.total_weight() + maxf(t.nothing_weight, 0.0)
	var gear: float = 0.0
	for e: LootEntry in t.entries:
		var base: ItemData = reg.get_item(e.item_id)
		if base != null and base.is_equippable() and not rules.is_unique(String(base.id)):
			gear += float(t.rolls) * (e.weight / maxf(pool, 0.0001)) * (float(maxi(e.min_qty, 1) + maxi(e.max_qty, maxi(e.min_qty, 1))) / 2.0)
	var w: Dictionary = ItemRoller.rarity_weights(rules, tier)
	var tot: float = 0.0
	for k: Variant in w:
		tot += float(w[k])
	var per: Dictionary = {}
	for k2: Variant in w:
		per[String(k2)] = gear * float(w[k2]) / maxf(tot, 0.0001)
	var uniq: float = 0.0
	for uid: String in rules.uniques.keys():
		var u: Dictionary = rules.uniques[uid]
		if lv < int((u["obtain"] as Dictionary)["min_level"]):
			continue
		for src: Variant in ((u["obtain"] as Dictionary)["sources"] as Array):
			if String((src as Dictionary)["loot_table"]) == String(t.id):
				uniq += float((src as Dictionary)["chance"])
	var kills_for: Dictionary = {}
	for k3: Variant in per:
		kills_for[String(k3)] = snappedf(1.0 / maxf(float(per[k3]), 0.0000001), 0.1)
	var plus: Dictionary = {}
	var order: Array = ["common", "uncommon", "rare", "epic", "legendary", "mythic"]
	for i: int in order.size():
		var s: float = 0.0
		for j: int in range(i, order.size()):
			s += float(per[order[j]])
		plus[String(order[i]) + "_plus_per_kill"] = snappedf(s, 0.000001)
	return {"gear_per_kill": snappedf(gear, 0.0001), "rarity_per_kill": _snap_dict(per, 0.000001), "plus_per_kill": plus, "kills_per_item": kills_for, "unique_per_kill": snappedf(uniq, 0.0001)}


static func _snap_dict(d: Dictionary, step: float) -> Dictionary:
	var out: Dictionary = {}
	for k: Variant in d:
		out[String(k)] = snappedf(float(d[k]), step)
	return out


# ------------------------------------------------------------------ criterios

func _crit(list: Array, id: String, ok: bool, detail: String) -> void:
	list.append({"id": id, "pass": ok, "detail": detail})


## Avalia as faixas-alvo (cfg.criteria) sobre os resultados. Cada criterio: {id, pass, detail}.
func evaluate(res: Dictionary) -> Array:
	var c: Dictionary = cfg["criteria"] as Dictionary
	var out: Array = []
	var std: String = str(int(cfg["standard_level"]))
	var boss: String = String(cfg["reference_boss"])
	var classes_r: Dictionary = res["classes"] as Dictionary
	# C1: paridade de DPS entre classes (build "none", gear Comum, nivel padrao): dps vs boss e vs grunt
	for tid: String in [boss, "pack"]:
		var vals: Dictionary = {}
		for cid: Variant in classes_r:
			vals[String(cid)] = float(((((classes_r[cid] as Dictionary)[std] as Dictionary)["builds"] as Dictionary)["none"] as Dictionary)["tiers"]["common"]["dps"][tid]["mean"])
		var m: float = _mean(vals.values())
		var worst: float = 0.0
		for k: Variant in vals:
			worst = maxf(worst, absf(float(vals[k]) / m - 1.0) * 100.0)
		_crit(out, "C1_class_dps_parity_" + tid, worst <= float(c["class_dps_parity_pct"]), "max desvio %.1f%% da media (limite %.0f%%); dps %s" % [worst, float(c["class_dps_parity_pct"]), JSON.stringify(vals)])
	# C1b: paridade entre as MELHORES builds (por classe) e entre as builds de especializacao medias
	var best: Dictionary = {}
	for cid2: Variant in classes_r:
		var bm: float = 0.0
		var builds: Dictionary = ((classes_r[cid2] as Dictionary)[std] as Dictionary)["builds"] as Dictionary
		for bn: Variant in builds:
			bm = maxf(bm, float((((builds[bn] as Dictionary)["tiers"] as Dictionary)["common"] as Dictionary)["dps"][boss]["mean"]))
		best[String(cid2)] = bm
	var bmean: float = _mean(best.values())
	var bworst: float = 0.0
	for k2: Variant in best:
		bworst = maxf(bworst, absf(float(best[k2]) / bmean - 1.0) * 100.0)
	_crit(out, "C1b_best_build_parity", bworst <= float(c["class_dps_parity_pct"]), "max desvio das melhores builds %.1f%% (limite %.0f%%); %s" % [bworst, float(c["class_dps_parity_pct"]), JSON.stringify(best)])
	# C2: builds distintas e sem build dominante (niveis com pontos suficientes para builds: cfg.build_criteria_levels)
	for cid3: Variant in classes_r:
		for blv: Variant in (cfg["build_criteria_levels"] as Array):
			if not (classes_r[cid3] as Dictionary).has(str(int(blv))):
				continue # nivel nao medido (ex.: --quick)
			_eval_builds(out, classes_r, String(cid3), str(int(blv)), boss, c)
	# C3: escada de raridade de equipamento (build "none"), por nivel: indice de poder = sqrt(dps_chefe x sobrevivencia_chefe)
	for cid4: Variant in classes_r:
		for lvk: Variant in (classes_r[cid4] as Dictionary):
			var tiers4: Dictionary = (((((classes_r[cid4] as Dictionary)[lvk] as Dictionary)["builds"] as Dictionary)["none"] as Dictionary)["tiers"]) as Dictionary
			var order: Array = ["common", "uncommon", "rare", "epic", "legendary", "mythic"]
			var prev: float = 0.0
			var first: float = 0.0
			var ok: bool = true
			var msg: String = ""
			var pw: Dictionary = {}
			for r: Variant in order:
				var t4: Dictionary = tiers4[r] as Dictionary
				var v: float = sqrt(float((t4["dps"] as Dictionary)[boss]["mean"]) * float((t4["survive_s"] as Dictionary)[boss]["mean"]))
				pw[String(r)] = v
				msg += "%s=%.1f " % [String(r), v]
				if prev > 0.0 and (v / prev - 1.0) * 100.0 < float(c["tier_monotonic_min_gain_pct"]):
					ok = false
				if first == 0.0:
					first = v
				prev = v
			var rare_ratio: float = float(pw["rare"]) / first
			var leg_ratio: float = float(pw["legendary"]) / first
			_crit(out, "C3_gear_ladder_%s_lv%s" % [String(cid4), String(lvk)], ok and rare_ratio <= float(c["tier_rare_over_common_max_ratio"]) and leg_ratio <= float(c["tier_legendary_over_common_max_ratio"]) and leg_ratio >= float(c["tier_legendary_over_common_min_ratio"]),
				"poder %s| raro/comum=%.2f (max %.2f) lendario/comum=%.2f (min %.2f, max %.2f); variacao minima por degrau %.0f%% (tolerancia de amostragem)" % [msg, rare_ratio, float(c["tier_rare_over_common_max_ratio"]), leg_ratio, float(c["tier_legendary_over_common_min_ratio"]), float(c["tier_legendary_over_common_max_ratio"]), float(c["tier_monotonic_min_gain_pct"])])
	# C4: unicos nao dominam (ganho de dps <= teto) em nenhum contexto
	var uworst: float = -1000.0
	var uwhere: String = ""
	for cid5: Variant in (res["uniques"] as Dictionary):
		for bn5: Variant in ((res["uniques"] as Dictionary)[cid5] as Dictionary):
			for uid: Variant in (((res["uniques"] as Dictionary)[cid5] as Dictionary)[bn5] as Dictionary):
				var e: Dictionary = ((((res["uniques"] as Dictionary)[cid5] as Dictionary)[bn5] as Dictionary)[uid]) as Dictionary
				for key: String in ["dps_gain_pct_hp100", "dps_gain_pct_hp30"]:
					if float(e[key]) > uworst:
						uworst = float(e[key])
						uwhere = "%s/%s/%s/%s" % [String(cid5), String(bn5), String(uid), key]
	_crit(out, "C4_unique_no_domination", uworst <= float(c["unique_max_dps_gain_pct"]), "maior ganho de dps de um unico = %.1f%% em %s (limite %.0f%%)" % [uworst, uwhere, float(c["unique_max_dps_gain_pct"])])
	# C5: nenhum talento domina: ganho por ponto <= k x mediana dos nos ofensivos da mesma classe
	for cid6: Variant in (res["talents"] as Dictionary):
		var nodes: Dictionary = ((res["talents"] as Dictionary)[cid6] as Dictionary)["nodes"] as Dictionary
		var gains: Array = []
		for nid: Variant in nodes:
			var g: float = float((nodes[nid] as Dictionary)["gain_per_point_pct"])
			if g > 0.0:
				gains.append(g)
		gains.sort()
		var med: float = _pct(gains, 0.5)
		var top: float = float(gains[gains.size() - 1]) if not gains.is_empty() else 0.0
		var top_id: String = ""
		for nid2: Variant in nodes:
			if float((nodes[nid2] as Dictionary)["gain_per_point_pct"]) == top:
				top_id = String(nid2)
		_crit(out, "C5_talent_no_domination_" + String(cid6), top <= float(c["talent_max_gain_per_point_vs_median"]) * med, "maior ganho/ponto = %.3f%% (%s) vs mediana %.3f%% (limite %.1fx)" % [top, top_id, med, float(c["talent_max_gain_per_point_vs_median"])])
	# C6: tempo de abate do chefe (1 e 4 jogadores) no nivel padrao, build "none", gear Comum
	var w1: Array = c["boss_ttk_1p_window_s"] as Array
	var w4: Array = c["boss_ttk_4p_window_s"] as Array
	for cid7: Variant in classes_r:
		var tc7: Dictionary = (((((classes_r[cid7] as Dictionary)[std] as Dictionary)["builds"] as Dictionary)["none"] as Dictionary)["tiers"]["common"]) as Dictionary
		var t1: float = float((tc7["ttk"] as Dictionary)[boss]["mean"])
		var t4: float = float(tc7["boss_ttk_4p"])
		_crit(out, "C6_boss_ttk_" + String(cid7), t1 >= float(w1[0]) and t1 <= float(w1[1]) and t4 >= float(w4[0]) and t4 <= float(w4[1]),
			"1 jogador %.1f s (janela %.0f-%.0f); 4 jogadores %.1f s (janela %.0f-%.0f)" % [t1, float(w1[0]), float(w1[1]), t4, float(w4[0]), float(w4[1])])
		var tg: float = float((tc7["ttk"] as Dictionary)["melee_grunt"]["mean"])
		_crit(out, "C6b_grunt_ttk_" + String(cid7), tg <= float(c["grunt_ttk_max_s"]), "abate do bruto %.1f s (max %.1f)" % [tg, float(c["grunt_ttk_max_s"])])
		var worst_duel: float = 0.0
		var worst_id: String = ""
		for eid: Variant in (tc7["duel_ratio"] as Dictionary):
			var en: EnemyData = reg.get_enemy(StringName(String(eid)))
			if en.tier != EnemyData.TIER_NORMAL:
				continue
			var dv: float = float((tc7["duel_ratio"] as Dictionary)[eid]["mean"])
			if dv > worst_duel:
				worst_duel = dv
				worst_id = String(eid)
		_crit(out, "C6c_normal_duel_" + String(cid7), worst_duel <= float(c["duel_ratio_max_normal"]), "pior duelo contra inimigo comum: %s tempo_para_matar/sobrevivencia = %.3f (max %.2f)" % [worst_id, worst_duel, float(c["duel_ratio_max_normal"])])
	# C7: curva de XP
	var xp: Dictionary = res["xp"] as Dictionary
	var lvls: Array = xp["levels"] as Array
	var mono: bool = true
	for i: int in lvls.size():
		if i > 0 and int((lvls[i] as Dictionary)["to_next"]) <= int((lvls[i - 1] as Dictionary)["to_next"]):
			mono = false
	var r_first: float = float((lvls[1] as Dictionary)["ratio"])
	var after_first: float = _max_ratio_from(lvls, 3)
	_crit(out, "C7_xp_curve", mono and r_first <= float(c["xp_ratio_first_step_max"]) and after_first <= float(c["xp_ratio_max_after_first_step"]),
		"crescente=%s; razao 1->2 vs 2->3 (primeiro passo) %.2f (max %.1f); maior razao nos passos seguintes %.2f (max %.1f)" % [str(mono), r_first, float(c["xp_ratio_first_step_max"]), after_first, float(c["xp_ratio_max_after_first_step"])])
	var lw: Array = c["greenwood_arc_final_level_window"] as Array
	_crit(out, "C7b_greenwood_arc_level", int(xp["final_level_all"]) >= int(lw[0]) and int(xp["final_level_all"]) <= int(lw[1]), "nivel ao concluir todo o conteudo (%d xp) = %d (janela %d-%d); so quests = %d; so abates = %d" % [int(xp["total_xp"]), int(xp["final_level_all"]), int(lw[0]), int(lw[1]), int(xp["final_level_quests_only"]), int(xp["final_level_kills_only"])])
	# C8: loot por abate (analitico)
	var lo: Dictionary = (res["loot"] as Dictionary)["by_enemy"] as Dictionary
	var worst_rare: float = 0.0
	var worst_epic: float = 0.0
	var wr_id: String = ""
	var we_id: String = ""
	for eid2: Variant in lo:
		var ent: Dictionary = lo[eid2] as Dictionary
		if String(ent["tier"]) != "normal":
			continue
		var plus: Dictionary = (ent["analytic"] as Dictionary)["plus_per_kill"] as Dictionary
		if float(plus["rare_plus_per_kill"]) > worst_rare:
			worst_rare = float(plus["rare_plus_per_kill"])
			wr_id = String(eid2)
		if float(plus["epic_plus_per_kill"]) > worst_epic:
			worst_epic = float(plus["epic_plus_per_kill"])
			we_id = String(eid2)
	_crit(out, "C8a_normal_rare_plus", worst_rare <= float(c["loot_normal_rare_plus_per_kill_max"]), "Raro+ por abate de inimigo comum: max %.4f (%s), limite %.3f" % [worst_rare, wr_id, float(c["loot_normal_rare_plus_per_kill_max"])])
	_crit(out, "C8b_normal_epic_plus", worst_epic <= float(c["loot_normal_epic_plus_per_kill_max"]), "Epico+ por abate de inimigo comum: max %.5f (%s), limite %.4f" % [worst_epic, we_id, float(c["loot_normal_epic_plus_per_kill_max"])])
	if lo.has(boss):
		var ba: Dictionary = (lo[boss] as Dictionary)["analytic"] as Dictionary
		var kp: Dictionary = {}
		var plus2: Dictionary = ba["plus_per_kill"] as Dictionary
		for rr: String in ["epic", "legendary", "mythic"]:
			kp[rr] = 1.0 / maxf(float(plus2[rr + "_plus_per_kill"]), 0.0000001)
		var lw2: Array = c["loot_boss_legendary_kills_window"] as Array
		var ew: Array = c["loot_boss_epic_plus_kills_window"] as Array
		_crit(out, "C8c_boss_legendary_reachable", float(kp["legendary"]) >= float(lw2[0]) and float(kp["legendary"]) <= float(lw2[1]), "abates do chefe por Lendario+ = %.1f (janela %.0f-%.0f)" % [float(kp["legendary"]), float(lw2[0]), float(lw2[1])])
		_crit(out, "C8d_boss_epic_reachable", float(kp["epic"]) >= float(ew[0]) and float(kp["epic"]) <= float(ew[1]), "abates do chefe por Epico+ = %.1f (janela %.0f-%.0f)" % [float(kp["epic"]), float(ew[0]), float(ew[1])])
		_crit(out, "C8e_boss_mythic_rare", float(kp["mythic"]) >= float(c["loot_boss_mythic_kills_min"]), "abates do chefe por Mitico = %.1f (minimo %.0f)" % [float(kp["mythic"]), float(c["loot_boss_mythic_kills_min"])])
	# C6d/e: duelo contra o chefe e relacao 4p/1p
	var dw: Array = c["boss_duel_ratio_window"] as Array
	var rw: Array = c["boss_ttk_4p_over_1p_window"] as Array
	for cid8: Variant in classes_r:
		var tc8: Dictionary = (((((classes_r[cid8] as Dictionary)[std] as Dictionary)["builds"] as Dictionary)["none"] as Dictionary)["tiers"]["common"]) as Dictionary
		var dr: float = float((tc8["duel_ratio"] as Dictionary)[boss]["mean"])
		_crit(out, "C6d_boss_duel_" + String(cid8), dr >= float(dw[0]) and dr <= float(dw[1]), "tempo_para_matar/sobrevivencia contra o chefe = %.2f (janela %.1f-%.1f)" % [dr, float(dw[0]), float(dw[1])])
		var q: float = float(tc8["boss_ttk_4p"]) / float((tc8["ttk"] as Dictionary)[boss]["mean"])
		_crit(out, "C6e_boss_4p_over_1p_" + String(cid8), q >= float(rw[0]) and q <= float(rw[1]), "ttk 4 jogadores / 1 jogador = %.2f (janela %.1f-%.1f)" % [q, float(rw[0]), float(rw[1])])
	# C8f-h: mini-chefe
	for mid: Variant in lo:
		if String((lo[mid] as Dictionary)["tier"]) != "mini_boss":
			continue
		var pm: Dictionary = (((lo[mid] as Dictionary)["analytic"] as Dictionary)["plus_per_kill"]) as Dictionary
		var ke: float = 1.0 / maxf(float(pm["epic_plus_per_kill"]), 0.0000001)
		var kl: float = 1.0 / maxf(float(pm["legendary_plus_per_kill"]), 0.0000001)
		var km: float = 1.0 / maxf(float(pm["mythic_plus_per_kill"]), 0.0000001)
		var mew: Array = c["loot_mini_boss_epic_plus_kills_window"] as Array
		var mlw: Array = c["loot_mini_boss_legendary_plus_kills_window"] as Array
		_crit(out, "C8f_mini_boss_epic_" + String(mid), ke >= float(mew[0]) and ke <= float(mew[1]), "abates por Epico+ = %.1f (janela %.0f-%.0f)" % [ke, float(mew[0]), float(mew[1])])
		_crit(out, "C8g_mini_boss_legendary_" + String(mid), kl >= float(mlw[0]) and kl <= float(mlw[1]), "abates por Lendario+ = %.1f (janela %.0f-%.0f)" % [kl, float(mlw[0]), float(mlw[1])])
		_crit(out, "C8h_mini_boss_mythic_" + String(mid), km >= float(c["loot_mini_boss_mythic_kills_min"]), "abates por Mitico = %.1f (minimo %.0f)" % [km, float(c["loot_mini_boss_mythic_kills_min"])])
	# C9: obtencao dos unicos (melhor fonte) e relevancia de decisao
	var uw: Array = c["unique_kills_window"] as Array
	var bad_u: Array = []
	var uinfo: Dictionary = {}
	for uid2: Variant in ((res["loot"] as Dictionary)["uniques_obtain"] as Dictionary):
		var bk: float = float((((res["loot"] as Dictionary)["uniques_obtain"] as Dictionary)[uid2] as Dictionary)["best_kills"])
		uinfo[String(uid2)] = bk
		if bk < float(uw[0]) or bk > float(uw[1]):
			bad_u.append(String(uid2))
	_crit(out, "C9a_unique_obtain", bad_u.is_empty(), "abates da melhor fonte por unico %s (janela %.0f-%.0f); fora: %s" % [JSON.stringify(uinfo), float(uw[0]), float(uw[1]), str(bad_u)])
	var useless: Array = []
	for uid3: String in UNIQUE_IDS:
		var best_eff: float = 0.0
		for cid9: Variant in (res["uniques"] as Dictionary):
			for bn9: Variant in ((res["uniques"] as Dictionary)[cid9] as Dictionary):
				var ee: Dictionary = (((res["uniques"] as Dictionary)[cid9] as Dictionary)[bn9] as Dictionary)[uid3] as Dictionary
				for kk: String in ["dps_gain_pct_hp100", "dps_gain_pct_hp30", "pack_dps_gain_pct", "survive_gain_pct_boss"]:
					best_eff = maxf(best_eff, absf(float(ee[kk])))
		if best_eff < float(c["unique_min_decision_effect_pct"]):
			useless.append(uid3)
	_crit(out, "C9b_unique_relevant", useless.is_empty(), "unicos sem efeito >= %.0f%% em dps/grupo/sobrevivencia em nenhuma classe/build: %s" % [float(c["unique_min_decision_effect_pct"]), str(useless)])
	return out


func _eval_builds(out: Array, classes_r: Dictionary, cid3: String, lvk: String, boss: String, c: Dictionary) -> void:
	var builds3: Dictionary = ((classes_r[cid3] as Dictionary)[lvk] as Dictionary)["builds"] as Dictionary
	var dpss: Dictionary = {}
	var packd: Dictionary = {}
	var surv: Dictionary = {}
	for bn3: Variant in builds3:
		var tc: Dictionary = (((builds3[bn3] as Dictionary)["tiers"] as Dictionary)["common"]) as Dictionary
		dpss[String(bn3)] = float((tc["dps"] as Dictionary)[boss]["mean"])
		packd[String(bn3)] = float((tc["dps"] as Dictionary)["pack"]["mean"])
		surv[String(bn3)] = float((tc["survive_s"] as Dictionary)[boss]["mean"])
	var mx: float = 0.0
	var mn: float = 1e9
	for k3: Variant in dpss:
		if String(k3) == "none":
			continue # "none" (nenhum ponto gasto) e so a referencia; o espalhamento e entre builds que gastam pontos
		mx = maxf(mx, float(dpss[k3]))
		mn = minf(mn, float(dpss[k3]))
	_crit(out, "C2_build_spread_" + cid3 + "_lv" + lvk, mx / mn <= float(c["build_spread_max_ratio"]), "maior/menor dps entre builds com pontos gastos = %.2f (limite %.2f); %s" % [mx / mn, float(c["build_spread_max_ratio"]), JSON.stringify(dpss)])
	var pmx: float = 0.0
	var pmn: float = 1e9
	var pws: Dictionary = {}
	for k6: Variant in dpss:
		if String(k6) == "none":
			continue
		var pw: float = sqrt(float(dpss[k6]) * float(surv[k6]))
		pws[String(k6)] = snappedf(pw, 0.1)
		pmx = maxf(pmx, pw)
		pmn = minf(pmn, pw)
	_crit(out, "C2d_build_power_spread_" + cid3 + "_lv" + lvk, pmx / pmn <= float(c["build_power_spread_max_ratio"]), "indice de poder sqrt(dps x sobrevivencia) maior/menor = %.2f (limite %.2f); %s" % [pmx / pmn, float(c["build_power_spread_max_ratio"]), JSON.stringify(pws)])
	# builds distintas: cada build nao-"none" difere de "none" em dps OU sobrevivencia >= min pct
	var base_d: float = float(dpss["none"])
	var base_s: float = float(surv["none"])
	var not_distinct: Array = []
	for k4: Variant in dpss:
		if String(k4) == "none":
			continue
		var dd: float = absf(float(dpss[k4]) / base_d - 1.0) * 100.0
		var ss: float = absf(float(surv[k4]) / base_s - 1.0) * 100.0
		var pp: float = absf(float(packd[k4]) / float(packd["none"]) - 1.0) * 100.0
		if maxf(maxf(dd, ss), pp) < float(c["build_min_distinct_pct"]):
			not_distinct.append(String(k4))
	_crit(out, "C2b_builds_distinct_" + cid3 + "_lv" + lvk, not_distinct.is_empty(), "builds sem diferenca >= %.0f%% (dps vs chefe, dps vs grupo ou sobrevivencia): %s" % [float(c["build_min_distinct_pct"]), str(not_distinct)])
	# distincao qualitativa: ha trade-off (build mais forte em dps nao e tambem a mais resistente)
	var best_d: String = ""
	var best_s: String = ""
	var bdv: float = -1.0
	var bsv: float = -1.0
	for k5: Variant in dpss:
		if float(dpss[k5]) > bdv:
			bdv = float(dpss[k5])
			best_d = String(k5)
		if float(surv[k5]) > bsv:
			bsv = float(surv[k5])
			best_s = String(k5)
	_crit(out, "C2c_tradeoff_" + cid3 + "_lv" + lvk, best_d != best_s, "build de maior dps = %s; de maior sobrevivencia = %s" % [best_d, best_s])


static func _max_ratio_from(lvls: Array, from_level: int) -> float:
	var m: float = 0.0
	for e: Variant in lvls:
		if int((e as Dictionary)["level"]) >= from_level:
			m = maxf(m, float((e as Dictionary)["ratio"]))
	return m
