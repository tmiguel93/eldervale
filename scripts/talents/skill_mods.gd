class_name SkillMods
extends RefCounted
## Modificadores de habilidade e bonus de stats dos talentos (E6.2). DUAS fases, ambas SO no servidor:
##  1. `collect(tree, state)`: agrega os efeitos dos nos alocados em {stats: StatBlock, skills: {skill_id -> Array[mod]}}; cada mod
##     leva o `rank` do no (parametros sao POR RANK). Roda ao entrar, ao mudar talentos e ao subir de nivel.
##  2. `resolve(skill, mods, ctx)`: em TEMPO DE USO, devolve os valores efetivos da habilidade. NUNCA muta o SkillData compartilhado
##     (o recurso carregado do disco e unico para todos os jogadores): quando ha mods, trabalha numa COPIA (`duplicate`).
## Tipos: damage, extra_projectiles, area, duration (invulnerabilidade da esquiva), cost (custo/cooldown), convert (elemento),
## condition (vida/recurso do proprio jogador no momento do uso) e synergy (apos usar outra habilidade dentro de uma janela).
## Bonus de dano somam-se entre si (aditivo) e multiplicam o multiplicador base; limites sanitarios abaixo.

const MAX_EXTRA_PROJECTILES: int = 6
const MAX_DAMAGE_BONUS: float = 9.0
const MIN_DAMAGE_BONUS: float = -0.9
const MIN_COST_FACTOR: float = 0.25 ## custo/cooldown nunca caem abaixo de 25% do base
const MIN_AREA_FACTOR: float = 0.25
const MAX_AREA_FACTOR: float = 3.0


## Resultado de `resolve`. `skill` e o proprio SkillData (sem mods) ou uma copia efetiva (com mods).
class Resolved extends RefCounted:
	var skill: SkillData
	var extra_projectiles: int = 0
	var spread_deg: float = 0.0
	var extra_damage_scale: float = 1.0
	var damage_type: StringName = &"physical"
	var damage_bonus: float = 0.0 ## soma aditiva dos bonus de dano aplicados (0 = nenhum)
	var applied: int = 0 ## quantos mods tiveram efeito neste uso


## {stats: StatBlock (bonus a somar), skills: Dictionary skill_id -> Array[Dictionary]}. Nos de outra especializacao sao ignorados.
static func collect(tree: TalentTree, state: TalentState) -> Dictionary:
	var stats: StatBlock = StatUtil.zero()
	var skills: Dictionary = {}
	if tree == null or state == null:
		return {"stats": stats, "skills": skills}
	for id: String in tree.order:
		var rank: int = state.rank_of(id)
		if rank < 1:
			continue
		var n: Dictionary = tree.nodes[id]
		var spec: String = String(n["spec"])
		if spec != "" and spec != state.spec_id:
			continue
		rank = mini(rank, int(n["max_rank"]))
		for fx: Dictionary in (n["effects"] as Array):
			if String(fx["type"]) == "stat":
				var key: String = String(fx["stat"])
				stats.set(key, float(stats.get(key)) + float(fx["amount"]) * float(rank))
			else:
				var m: Dictionary = fx.duplicate()
				m["rank"] = rank
				m["node"] = id
				var sid: String = String(fx["skill"])
				if not skills.has(sid):
					skills[sid] = []
				(skills[sid] as Array).append(m)
	return {"stats": stats, "skills": skills}


## Valores efetivos de `skill` com `mods` (Array de collect()["skills"][id]). `ctx`: {hp_ratio, resource_ratio, clock, last_use{id->clock}}.
static func resolve(skill: SkillData, mods: Array, ctx: Dictionary = {}) -> Resolved:
	var r: Resolved = Resolved.new()
	r.skill = skill
	if mods.is_empty():
		return r
	var dmg: float = 0.0
	var cost_pct: float = 0.0
	var cd_pct: float = 0.0
	var area_pct: float = 0.0
	var i_add: float = 0.0
	var extra: int = 0
	var spread: float = 0.0
	var scale_min: float = 1.0
	var convert_to: StringName = &"physical"
	var is_dodge: bool = skill.kind == SkillData.Kind.DODGE
	for m: Dictionary in mods:
		var k: float = float(int(m.get("rank", 1)))
		match String(m.get("mod", "")):
			"damage":
				dmg += float(m["damage_pct"]) * k
				r.applied += 1
			"extra_projectiles":
				if skill.is_projectile():
					extra += int(m["count"]) * int(k)
					spread = maxf(spread, float(m["spread_deg"]))
					scale_min = minf(scale_min, float(m["damage_scale"]))
					r.applied += 1
			"area":
				area_pct += float(m["radius_pct"]) * k
				r.applied += 1
			"duration":
				if is_dodge:
					i_add += float(m["i_frames_add"]) * k
					r.applied += 1
			"cost":
				cost_pct += float(m.get("cost_pct", 0.0)) * k
				cd_pct += float(m.get("cooldown_pct", 0.0)) * k
				r.applied += 1
			"convert":
				convert_to = StringName(String(m["to"]))
				dmg += float(m.get("damage_pct", 0.0)) * k
				r.applied += 1
			"condition":
				if _condition_met(String(m["when"]), float(m["threshold"]), ctx):
					dmg += float(m["damage_pct"]) * k
					r.applied += 1
			"synergy":
				if _synergy_met(String(m["after_skill"]), float(m["window"]), ctx):
					dmg += float(m["damage_pct"]) * k
					r.applied += 1
	if r.applied == 0:
		return r
	var eff: SkillData = skill.duplicate() as SkillData # copia rasa: o recurso compartilhado nao e tocado
	dmg = clampf(dmg, MIN_DAMAGE_BONUS, MAX_DAMAGE_BONUS)
	eff.damage_multiplier = skill.damage_multiplier * (1.0 + dmg)
	eff.resource_cost = maxf(0.0, skill.resource_cost * maxf(MIN_COST_FACTOR, 1.0 + cost_pct)) if skill.resource_cost > 0.0 else 0.0
	eff.cooldown = skill.cooldown * maxf(MIN_COST_FACTOR, 1.0 + cd_pct) if skill.cooldown > 0.0 else 0.0
	if area_pct != 0.0:
		var f: float = clampf(1.0 + area_pct, MIN_AREA_FACTOR, MAX_AREA_FACTOR)
		var sz: Vector3 = skill.hitbox_size
		if skill.hitbox_shape == SkillData.HitboxShape.SPHERE:
			eff.hitbox_size = Vector3(sz.x * f, sz.y, sz.z)
		else:
			eff.hitbox_size = Vector3(sz.x * f, sz.y, sz.z * f)
	if i_add > 0.0:
		eff.i_frames = minf(skill.i_frames + i_add, skill.total_duration())
	r.skill = eff
	r.extra_projectiles = clampi(extra, 0, MAX_EXTRA_PROJECTILES)
	r.spread_deg = spread
	r.extra_damage_scale = scale_min
	r.damage_type = convert_to
	r.damage_bonus = dmg
	return r


static func _condition_met(when: String, threshold: float, ctx: Dictionary) -> bool:
	match when:
		"self_hp_below": return float(ctx.get("hp_ratio", 1.0)) < threshold
		"self_hp_above": return float(ctx.get("hp_ratio", 1.0)) > threshold
		"resource_above": return float(ctx.get("resource_ratio", 0.0)) > threshold
	return false


static func _synergy_met(after_skill: String, window: float, ctx: Dictionary) -> bool:
	var last: Dictionary = ctx.get("last_use", {}) as Dictionary
	if not last.has(after_skill):
		return false
	return float(ctx.get("clock", 0.0)) - float(last[after_skill]) <= window


## Angulo (graus) do k-esimo projetil de um leque de `spread` graus: 0, +s, -s, +2s, -2s, ...
static func fan_angle(k: int, spread: float) -> float:
	if k <= 0:
		return 0.0
	@warning_ignore("integer_division")
	var step: int = (k + 1) / 2
	return spread * float(step) * (1.0 if k % 2 == 1 else -1.0)
