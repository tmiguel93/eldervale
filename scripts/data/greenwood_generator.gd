extends "res://scripts/data/content_generator.gd"
## Gera o conteudo PLACEHOLDER de inimigos de Greenwood (E5.2): 6 inimigos novos, mini-chefe, chefe,
## tabelas de loot e a escala de dificuldade. Nao toca nos itens nem nos 2 inimigos do E2 (os ids de
## item sao so referenciados). Rodar (apos --import):
##   $G --headless --path . --script res://scripts/data/greenwood_generator.gd
## Sobrescreve data/enemies/<novos>.tres, data/loot/loot_<novos>.tres e data/difficulty/*.tres.
## As cenas scenes/enemy/<id>.tscn sao herdadas de enemy.tscn (so apontam `data`).

const RED: Color = Color(0.9, 0.15, 0.1, 0.45)
const ORANGE: Color = Color(1.0, 0.5, 0.1, 0.45)
const CYAN: Color = Color(0.2, 0.9, 0.8, 0.4)
const GREEN: Color = Color(0.5, 0.9, 0.2, 0.45)


func _initialize() -> void:
	var ok: bool = true
	ok = _loot_set() and ok
	ok = _enemies() and ok
	var diff: DifficultyScaling = DifficultyScaling.new()
	ok = _save(diff, "res://data/difficulty/greenwood_coop.tres") and ok
	print("GERADO (Greenwood): ", "OK" if ok else "COM ERROS")
	quit(0 if ok else 1)


func _loot_set() -> bool:
	var ok: bool = true
	var defs: Dictionary = {
		&"loot_forest_stalker": [1, 45.0, [_entry(&"scrap_material", 40.0, 1, 2), _entry(&"potion_minor", 15.0, 1, 1)]],
		&"loot_bow_scout": [1, 40.0, [_entry(&"scrap_material", 30.0, 1, 2), _entry(&"potion_minor", 20.0, 1, 1), _entry(&"armor_leather", 4.0, 1, 1)]],
		&"loot_bark_brute": [2, 30.0, [_entry(&"scrap_material", 40.0, 2, 4), _entry(&"potion_minor", 25.0, 1, 2), _entry(&"armor_heavy", 6.0, 1, 1), _entry(&"sword_basic", 6.0, 1, 1)]],
		&"loot_grove_shaman": [2, 25.0, [_entry(&"potion_minor", 30.0, 1, 2), _entry(&"scrap_material", 30.0, 1, 3), _entry(&"amulet_vigor", 8.0, 1, 1)]],
		&"loot_burrow_lurker": [1, 35.0, [_entry(&"scrap_material", 30.0, 1, 3), _entry(&"potion_minor", 20.0, 1, 1), _entry(&"armor_leather", 6.0, 1, 1), _entry(&"sword_rare", 2.0, 1, 1)]],
		&"loot_root_sprout": [1, 90.0, [_entry(&"scrap_material", 10.0, 1, 1)]],
		&"loot_thorn_alpha": [3, 10.0, [_entry(&"potion_minor", 30.0, 1, 3), _entry(&"scrap_material", 30.0, 3, 6), _entry(&"amulet_vigor", 15.0, 1, 1), _entry(&"armor_heavy", 15.0, 1, 1), _entry(&"sword_rare", 10.0, 1, 1)]],
		&"loot_blight_treant": [4, 0.0, [_entry(&"potion_minor", 25.0, 2, 4), _entry(&"scrap_material", 30.0, 4, 8), _entry(&"amulet_vigor", 20.0, 1, 1), _entry(&"armor_heavy", 20.0, 1, 1), _entry(&"sword_rare", 20.0, 1, 1)]],
	}
	for id: StringName in defs:
		var d: Array = defs[id]
		var entries: Array[LootEntry] = []
		entries.assign(d[2])
		ok = _save(_loot(id, int(d[0]), float(d[1]), entries), "res://data/loot/%s.tres" % id) and ok
	return ok


func _atk(id: StringName, kind: EnemyAttack.Kind, windup: float, cooldown: float, mult: float,
		min_r: float, max_r: float, extra: Dictionary = {}) -> EnemyAttack:
	var a: EnemyAttack = EnemyAttack.new()
	a.id = id
	a.kind = kind
	a.windup = windup
	a.cooldown = cooldown
	a.damage_multiplier = mult
	a.min_range = min_r
	a.max_range = max_r
	for k: String in extra:
		a.set(k, extra[k])
	return a


func _phase(id: StringName, threshold: float, attacks: Array[EnemyAttack], extra: Dictionary = {}) -> EnemyPhase:
	var p: EnemyPhase = EnemyPhase.new()
	p.id = id
	p.health_threshold = threshold
	p.attacks = attacks
	for k: String in extra:
		p.set(k, extra[k])
	return p


func _enemy(id: StringName, name: String, role: StringName, behavior: StringName, stats: StatBlock, xp: int, extra: Dictionary) -> bool:
	var e: EnemyData = EnemyData.new()
	e.id = id
	e.display_name = name
	e.role = role
	e.behavior = behavior
	e.stats = stats
	e.xp_reward = xp
	e.placeholder = true
	e.loot_table = load("res://data/loot/loot_%s.tres" % id) as LootTable
	for k: String in extra:
		e.set(k, extra[k])
	return _save(e, "res://data/enemies/%s.tres" % id)


func _enemies() -> bool:
	var ok: bool = true
	var melee: StringName = EnemyData.BEHAVIOR_MELEE
	var ranged: StringName = EnemyData.BEHAVIOR_RANGED

	ok = _enemy(&"forest_stalker", "Espreitador [PLACEHOLDER]", &"fast", melee, _stats(36.0, 0.0, 0.0, 6.0, 0.0, 0.0, 5.6), 45, {
		"aggro_range": 11.0, "attack_range": 1.7, "attack_cooldown": 1.0, "windup": 0.3,
		"visual_shape": &"low", "visual_color": Color(0.85, 0.55, 0.15, 1.0), "visual_scale": 0.9,
		"attacks": _typed([_atk(&"bite", EnemyAttack.Kind.MELEE, 0.3, 1.0, 1.0, 0.0, 1.7, {"width": 1.3, "telegraph_color": ORANGE})]),
	}) and ok

	ok = _enemy(&"bow_scout", "Arqueiro [PLACEHOLDER]", &"ranged", ranged, _stats(34.0, 0.0, 0.0, 9.0, 0.0, 0.0, 3.4), 55, {
		"aggro_range": 16.0, "attack_range": 11.0, "attack_cooldown": 2.0, "windup": 0.6, "projectile_speed": 20.0,
		"visual_shape": &"cone", "visual_color": Color(0.3, 0.7, 0.3, 1.0),
		"attacks": _typed([_atk(&"arrow", EnemyAttack.Kind.PROJECTILE, 0.6, 2.0, 1.1, 3.0, 12.0, {"projectile_speed": 20.0, "telegraph_color": ORANGE})]),
	}) and ok

	ok = _enemy(&"bark_brute", "Brutamontes [PLACEHOLDER]", &"brute", melee, _stats(140.0, 0.0, 0.0, 16.0, 3.0, 0.0, 2.6), 110, {
		"aggro_range": 9.0, "attack_range": 2.6, "attack_cooldown": 2.0, "windup": 0.9,
		"visual_shape": &"tall", "visual_color": Color(0.45, 0.3, 0.15, 1.0), "visual_scale": 1.3,
		"attacks": _typed([
			_atk(&"swipe", EnemyAttack.Kind.MELEE, 0.6, 1.6, 0.8, 0.0, 2.6, {"width": 2.2, "weight": 2.0}),
			_atk(&"slam", EnemyAttack.Kind.AOE, 0.9, 2.4, 1.1, 0.0, 3.2, {"radius": 2.6, "aoe_offset": 1.4, "own_cooldown": 4.0, "weight": 2.0}),
		]),
	}) and ok

	ok = _enemy(&"grove_shaman", "Xama do Bosque [PLACEHOLDER]", &"summoner", ranged, _stats(50.0, 0.0, 0.0, 7.0, 0.0, 0.0, 2.8), 90, {
		"aggro_range": 14.0, "attack_range": 9.0, "attack_cooldown": 2.2, "windup": 0.55, "projectile_speed": 11.0,
		"visual_shape": &"cone", "visual_color": Color(0.2, 0.6, 0.5, 1.0),
		"attacks": _typed([
			_atk(&"thorn_bolt", EnemyAttack.Kind.PROJECTILE, 0.55, 2.2, 1.0, 0.0, 11.0, {"projectile_speed": 11.0, "weight": 3.0}),
			_atk(&"summon_sprouts", EnemyAttack.Kind.SUMMON, 1.2, 1.5, 1.0, 0.0, 14.0, {
				"summon_id": &"root_sprout", "summon_count": 2, "summon_max_alive": 3, "summon_max_total": 6,
				"own_cooldown": 14.0, "weight": 2.0, "telegraph_color": CYAN}),
		]),
	}) and ok

	ok = _enemy(&"burrow_lurker", "Emboscador [PLACEHOLDER]", &"ambusher", melee, _stats(55.0, 0.0, 0.0, 11.0, 1.0, 0.0, 4.2), 85, {
		"aggro_range": 6.5, "leash_range": 16.0, "attack_range": 1.8, "attack_cooldown": 1.2, "windup": 0.35, "ambush": true,
		"visual_shape": &"low", "visual_color": Color(0.4, 0.3, 0.5, 1.0),
		"attacks": _typed([
			_atk(&"pounce", EnemyAttack.Kind.CHARGE, 0.45, 1.2, 1.3, 2.8, 6.5, {
				"width": 1.6, "charge_distance": 6.0, "charge_speed": 14.0, "own_cooldown": 6.0, "weight": 3.0, "telegraph_color": ORANGE}),
			_atk(&"claw", EnemyAttack.Kind.MELEE, 0.35, 1.2, 0.9, 0.0, 1.8, {"width": 1.5, "weight": 2.0}),
		]),
	}) and ok

	ok = _enemy(&"root_sprout", "Broto [PLACEHOLDER]", &"add", melee, _stats(18.0, 0.0, 0.0, 5.0, 0.0, 0.0, 3.8), 8, {
		"aggro_range": 12.0, "attack_range": 1.5, "attack_cooldown": 1.6, "windup": 0.5,
		"visual_shape": &"low", "visual_color": Color(0.3, 0.7, 0.2, 1.0), "visual_scale": 0.7,
		"attacks": _typed([_atk(&"lash", EnemyAttack.Kind.MELEE, 0.5, 1.6, 1.0, 0.0, 1.5, {"width": 1.1, "telegraph_color": GREEN})]),
	}) and ok

	# Mini-chefe: 2 fases. Fase 2 (<= 50%): mais rapido/forte, ganha investida e chama 2 espreitadores.
	ok = _enemy(&"thorn_alpha", "Alfa Espinhoso [PLACEHOLDER]", &"mini_boss", melee, _stats(420.0, 0.0, 0.0, 14.0, 4.0, 0.0, 3.2), 400, {
		"tier": EnemyData.TIER_MINI_BOSS,
		"aggro_range": 14.0, "leash_range": 30.0, "attack_range": 3.0, "attack_cooldown": 1.4, "windup": 0.6,
		"visual_shape": &"box", "visual_color": Color(0.6, 0.25, 0.1, 1.0), "visual_scale": 1.7,
		"phases": _typed_phases([
			_phase(&"alpha_p1", 1.0, _typed([
				_atk(&"swipe", EnemyAttack.Kind.MELEE, 0.6, 1.4, 1.0, 0.0, 3.0, {"width": 2.6, "weight": 3.0}),
				_atk(&"slam", EnemyAttack.Kind.AOE, 1.0, 2.0, 1.2, 0.0, 4.0, {"radius": 3.2, "own_cooldown": 5.0, "weight": 2.0}),
			])),
			_phase(&"alpha_p2", 0.5, _typed([
				_atk(&"swipe", EnemyAttack.Kind.MELEE, 0.6, 1.4, 1.0, 0.0, 3.0, {"width": 2.6, "weight": 3.0}),
				_atk(&"slam", EnemyAttack.Kind.AOE, 1.0, 2.0, 1.2, 0.0, 4.0, {"radius": 3.2, "own_cooldown": 5.0, "weight": 2.0}),
				_atk(&"gore", EnemyAttack.Kind.CHARGE, 0.8, 1.8, 1.4, 5.0, 12.0, {
					"width": 2.2, "charge_distance": 8.0, "charge_speed": 15.0, "own_cooldown": 7.0, "weight": 2.0, "telegraph_color": ORANGE}),
			]), {"speed_mult": 1.25, "damage_mult": 1.2, "cooldown_mult": 0.8, "transition_time": 0.8,
				"summon_id": &"forest_stalker", "summon_count": 2}),
		]),
	}) and ok

	# Chefe: 3 fases (100/66/33%). F2 invoca 3 brotos e ganha saraivada + invocacao; F3 ganha pisoteio.
	ok = _enemy(&"blight_treant", "Anciao Corrompido [PLACEHOLDER]", &"boss", melee, _stats(1200.0, 0.0, 0.0, 18.0, 6.0, 0.0, 2.4), 1200, {
		"tier": EnemyData.TIER_BOSS,
		"aggro_range": 20.0, "leash_range": 45.0, "attack_range": 3.5, "attack_cooldown": 1.8, "windup": 0.8,
		"visual_shape": &"tall", "visual_color": Color(0.25, 0.4, 0.15, 1.0), "visual_scale": 2.2,
		"phases": _typed_phases([
			_phase(&"treant_p1", 1.0, _typed([
				_atk(&"sweep", EnemyAttack.Kind.MELEE, 0.8, 1.8, 1.0, 0.0, 4.0, {"width": 3.6, "weight": 3.0}),
				_atk(&"stomp", EnemyAttack.Kind.AOE, 1.1, 2.2, 1.2, 0.0, 4.5, {"radius": 4.5, "own_cooldown": 6.0, "weight": 2.0}),
			])),
			_phase(&"treant_p2", 0.66, _typed([
				_atk(&"sweep", EnemyAttack.Kind.MELEE, 0.8, 1.8, 1.0, 0.0, 4.0, {"width": 3.6, "weight": 3.0}),
				_atk(&"stomp", EnemyAttack.Kind.AOE, 1.1, 2.2, 1.2, 0.0, 4.5, {"radius": 4.5, "own_cooldown": 6.0, "weight": 2.0}),
				_atk(&"seed_volley", EnemyAttack.Kind.PROJECTILE, 0.9, 2.0, 0.7, 4.0, 16.0, {
					"projectile_count": 5, "spread_degrees": 50.0, "projectile_speed": 10.0, "own_cooldown": 6.0, "weight": 2.0, "telegraph_color": ORANGE}),
				_atk(&"call_sprouts", EnemyAttack.Kind.SUMMON, 1.3, 1.5, 1.0, 0.0, 16.0, {
					"summon_id": &"root_sprout", "summon_count": 2, "summon_max_alive": 4, "summon_max_total": 8,
					"own_cooldown": 18.0, "weight": 1.0, "telegraph_color": CYAN}),
			]), {"transition_time": 1.0, "summon_id": &"root_sprout", "summon_count": 3}),
			_phase(&"treant_p3", 0.33, _typed([
				_atk(&"sweep", EnemyAttack.Kind.MELEE, 0.8, 1.8, 1.0, 0.0, 4.0, {"width": 3.6, "weight": 3.0}),
				_atk(&"stomp", EnemyAttack.Kind.AOE, 1.1, 2.2, 1.2, 0.0, 4.5, {"radius": 4.5, "own_cooldown": 6.0, "weight": 2.0}),
				_atk(&"seed_volley", EnemyAttack.Kind.PROJECTILE, 0.9, 2.0, 0.7, 4.0, 16.0, {
					"projectile_count": 7, "spread_degrees": 70.0, "projectile_speed": 10.0, "own_cooldown": 6.0, "weight": 2.0, "telegraph_color": ORANGE}),
				_atk(&"trample", EnemyAttack.Kind.CHARGE, 1.0, 2.0, 1.5, 6.0, 14.0, {
					"width": 3.0, "charge_distance": 10.0, "charge_speed": 13.0, "own_cooldown": 9.0, "weight": 2.0, "telegraph_color": ORANGE}),
			]), {"speed_mult": 1.2, "damage_mult": 1.25, "cooldown_mult": 0.75, "transition_time": 1.0,
				"summon_id": &"forest_stalker", "summon_count": 2}),
		]),
	}) and ok
	return ok


func _typed(list: Array) -> Array[EnemyAttack]:
	var out: Array[EnemyAttack] = []
	out.assign(list)
	return out


func _typed_phases(list: Array) -> Array[EnemyPhase]:
	var out: Array[EnemyPhase] = []
	out.assign(list)
	return out
