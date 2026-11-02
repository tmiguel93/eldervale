class_name ClientVfx
extends Node3D
## E8.3: liga os dados do cliente (snapshot + eventos cosmeticos ja existentes) aos efeitos do VfxCatalog. SO apresentacao: nunca
## altera servidor, simulacao ou estado; sem display (headless/bot/teste) o ClientWorld nem cria isto.
## O que o cliente REALMENTE recebe (nenhum evento novo foi criado):
##  - jogadores: `state` do snapshot (ATTACK/DODGE/...), sem id da habilidade. Local: a habilidade vem do ultimo botao que o proprio cliente
##    enviou (note_local_actions); aliados remotos: sempre o golpe basico da classe deles (type "player:<classe>").
##  - inimigos: `state` ATTACK + `atk` (id do ataque) => telegrafo e golpe no fim do windup (dados do EnemyAttack).
##  - projeteis: nao ha entidade no snapshot; o projetil e COSMETICO (reta com velocidade/alcance da SkillData/EnemyAttack) e some no
##    EVENT_DAMAGE do mesmo atirador (`source_id`) perto dele.
##  - EVENT_DAMAGE/DEATH/ENEMY_SPAWN/DROP(+rarity)/ZONE/RESPAWN, nivel/talento (s_talents.level), cura (hp do snapshot sobe de uma vez).

signal shake_requested(strength: float, time: float)

const NAMES: Array[String] = ["melee", "aoe", "projectile", "charge", "summon"]
const HEAL_MIN_ABS: float = 6.0
const HEAL_MIN_FRAC: float = 0.06
const SKILL_WINDOW: float = 1.0
const SHAKE_RADIUS: float = 9.0
const HITSTOP_NORMAL: float = 0.04
const HITSTOP_CRIT: float = 0.07

var player: VfxPlayer
var catalog: VfxCatalog
var world: Node3D = null            ## ClientWorld (avatars, _last_pos...)
var local_id: int = -1
var local_class_id: String = ""
var counters: Dictionary = {"attacks": 0, "dodges": 0, "enemy_strikes": 0, "hits": 0, "deaths": 0, "spawns": 0, "drops": 0, "heals": 0, "level_ups": 0}

var _clock: float = 0.0
var _pstate: Dictionary = {}
var _php: Dictionary = {}
var _etrack: Dictionary = {}
var _auras: Dictionary = {}
var _last_skill: Dictionary = {}
var _dodge_end: Dictionary = {}
var _bit_time: Dictionary = {}
var _bits: int = 0
var _spawn_pending: Dictionary = {}
var _portals: Array[int] = []
var _skills: Dictionary = {}
var _level: int = -1
var _talent_total: int = -1


func _init() -> void:
	name = "ClientVfx"
	catalog = VfxCatalog.shared()
	player = VfxPlayer.new()
	add_child(player)
	player.shake_requested.connect(func(s: float, t: float) -> void: shake_requested.emit(s, t))


static func enabled() -> bool:
	return VfxPlayer.enabled()


func set_world(w: Node3D) -> void:
	world = w


func set_quality(preset: int) -> void:
	player.set_quality(preset)


## Recebe os bits de acao que o cliente acabou de ENVIAR (ClientMain): arestas de subida marcam a habilidade usada pelo jogador local.
func note_local_actions(bits: int) -> void:
	var rising: int = bits & ~_bits
	_bits = bits
	for b: int in [Protocol.ACTION_ATTACK, Protocol.ACTION_SKILL_1, Protocol.ACTION_SKILL_2, Protocol.ACTION_DODGE]:
		if (rising & b) != 0:
			_bit_time[b] = _clock


func _avatar(id: int) -> Node3D:
	if world == null:
		return null
	var av: Node3D = (world.get("avatars") as Dictionary).get(id) as Node3D
	return av if av != null and is_instance_valid(av) else null


func _quiet_for(pos: Vector3) -> bool:
	var lav: Node3D = _avatar(local_id)
	return lav != null and Vector2(lav.global_position.x - pos.x, lav.global_position.z - pos.z).length() > SHAKE_RADIUS


static func forward(yaw: float) -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


func _skill(skill_id: String) -> SkillData:
	if not _skills.has(skill_id):
		_skills[skill_id] = ClassCatalog.load_skill(StringName(skill_id))
	return _skills[skill_id] as SkillData


func _class_of(id: int, s: Dictionary) -> String:
	if id == local_id:
		return local_class_id if ClassCatalog.shared().has_class(local_class_id) else ClassCatalog.DEFAULT_CLASS_ID
	var cid: String = Protocol.class_of_player_type(s.get("type", ""))
	return cid if not cid.is_empty() and ClassCatalog.shared().has_class(cid) else ClassCatalog.DEFAULT_CLASS_ID


## Habilidade do slot usado: local = ultimo botao enviado ha < SKILL_WINDOW; remoto = golpe basico.
func skill_for(id: int, cid: String, want_dodge: bool = false) -> String:
	var def: ClassDef = ClassCatalog.shared().get_def(cid)
	if def == null:
		return ""
	var slot: String = "dodge" if want_dodge else "attack"
	if id == local_id and not want_dodge:
		var best: float = -1.0
		for pair: Array in [[Protocol.ACTION_ATTACK, "attack"], [Protocol.ACTION_SKILL_1, "skill_1"], [Protocol.ACTION_SKILL_2, "skill_2"]]:
			var tm: float = float(_bit_time.get(pair[0], -100.0))
			if _clock - tm <= SKILL_WINDOW and tm > best:
				best = tm
				slot = String(pair[1])
	return String(def.skills.get(slot, ""))


# ------------------------------------------------------------------ quadro a quadro

func on_frame(samples: Dictionary, p_local_id: int, delta: float) -> void:
	local_id = p_local_id
	_clock += delta
	for id: Variant in samples:
		var s: Dictionary = samples[id]
		var av: Node3D = _avatar(int(id))
		if av == null:
			continue
		if int(s["kind"]) == Protocol.KIND_PLAYER:
			_track_player(int(id), s, av)
		elif int(s["kind"]) == Protocol.KIND_ENEMY:
			_track_enemy(int(id), s, av, delta)
	var gone: Array = []
	for id2: Variant in _pstate:
		if not samples.has(id2):
			gone.append(id2)
	for id3: Variant in _etrack:
		if not samples.has(id3):
			gone.append(id3)
	for id4: Variant in _auras:
		if not samples.has(id4):
			gone.append(id4)
	for g: Variant in gone:
		on_avatar_removed(int(g))


func on_avatar_removed(id: int) -> void:
	_pstate.erase(id)
	_php.erase(id)
	_etrack.erase(id)
	_last_skill.erase(id)
	_dodge_end.erase(id)
	_spawn_pending.erase(id)
	if _auras.has(id):
		player.stop(int(_auras[id]))
		_auras.erase(id)


func _track_player(id: int, s: Dictionary, av: Node3D) -> void:
	var st: int = int(s["state"])
	var prev: int = int(_pstate.get(id, -1))
	_pstate[id] = st
	var pos: Vector3 = av.global_position
	var yaw: float = av.rotation.y
	if prev >= 0:
		if st == int(CharacterStateMachine.State.ATTACK) and prev != st:
			_player_attack(id, s, pos, yaw)
		elif st == int(CharacterStateMachine.State.DODGE) and prev != st:
			_player_dodge(id, s, pos, yaw)
		elif prev == int(CharacterStateMachine.State.DODGE) and st != prev:
			var endfx: String = String(_dodge_end.get(id, ""))
			_dodge_end.erase(id)
			if not endfx.is_empty():
				player.play(endfx, pos, yaw, {"quiet": _quiet_for(pos)})
	var hp: float = float(s["hp"])
	var old: float = float(_php.get(id, hp))
	_php[id] = hp
	var mx: float = maxf(float(s["max_hp"]), 1.0)
	if st != int(CharacterStateMachine.State.DEAD) and hp - old >= maxf(HEAL_MIN_ABS, mx * HEAL_MIN_FRAC):
		counters["heals"] = int(counters["heals"]) + 1
		player.play(catalog.event_effect("heal"), pos, 0.0, {"follow": av, "quiet": _quiet_for(pos)})
		if world != null and world.has_method("show_number"):
			world.show_number(id, hp - old, "heal")


func _player_attack(id: int, s: Dictionary, pos: Vector3, yaw: float) -> void:
	var cid: String = _class_of(id, s)
	var skill_id: String = skill_for(id, cid)
	if skill_id.is_empty():
		return
	counters["attacks"] = int(counters["attacks"]) + 1
	_last_skill[id] = {"skill": skill_id, "t": _clock}
	var b: Dictionary = catalog.skill_binding(skill_id)
	var sd: SkillData = _skill(skill_id)
	var q: bool = id != local_id and _quiet_for(pos)
	var windup: float = sd.windup if sd != null else 0.1
	var center: Vector3 = pos
	if sd != null and sd.hitbox_offset > 0.0 and (sd.tags.has("area") or sd.hitbox_shape == SkillData.HitboxShape.SPHERE and not sd.is_projectile()):
		center = pos + forward(yaw) * sd.hitbox_offset
	var muzzle: String = String(b.get("muzzle", ""))
	if not muzzle.is_empty():
		player.play(muzzle, pos, yaw, {"quiet": q})
	var cast: String = String(b.get("cast", ""))
	if not cast.is_empty():
		player.play(cast, center, yaw, {"delay": windup, "quiet": q})
	var proj: String = String(b.get("projectile", ""))
	if not proj.is_empty() and sd != null and sd.is_projectile():
		var origin: Vector3 = pos + forward(yaw) * maxf(sd.hitbox_offset, 0.5)
		player.play(proj, origin, yaw, {"delay": windup, "speed": sd.projectile_speed, "range": sd.projectile_range, "end": String(b.get("impact", "")), "owner": id, "pierce": sd.projectile_pierce, "quiet": q})


func _player_dodge(id: int, s: Dictionary, pos: Vector3, yaw: float) -> void:
	var cid: String = _class_of(id, s)
	var skill_id: String = skill_for(id, cid, true)
	counters["dodges"] = int(counters["dodges"]) + 1
	var b: Dictionary = catalog.skill_binding(skill_id)
	var cast: String = String(b.get("cast", ""))
	if not cast.is_empty():
		player.play(cast, pos, yaw, {"quiet": id != local_id and _quiet_for(pos)})
	if not String(b.get("end", "")).is_empty():
		_dodge_end[id] = String(b["end"])


func _attack_of(ed: EnemyData, atk_id: String) -> EnemyAttack:
	for a: EnemyAttack in ed.all_attacks():
		if a != null and String(a.id) == atk_id:
			return a
	return null


func _track_enemy(id: int, s: Dictionary, av: Node3D, delta: float) -> void:
	var ed: EnemyData = EnemyCatalog.data_for(StringName(String(s["type"])))
	if ed == null:
		return
	var alive: bool = float(s["hp"]) > 0.0
	if ed.is_boss() and alive and not _auras.has(id):
		var h: int = player.play(catalog.event_effect("boss_aura"), av.global_position, 0.0, {"follow": av, "tier_scale": catalog.tier_scale(String(ed.tier)), "quiet": true})
		if h >= 0:
			_auras[id] = h
	elif not alive and _auras.has(id):
		player.stop(int(_auras[id]))
		_auras.erase(id)
	var atk_id: String = String(s.get("atk", ""))
	if int(s["state"]) != int(EnemyAI.State.ATTACK) or atk_id.is_empty() or not alive:
		_etrack.erase(id)
		return
	var tr: Dictionary = _etrack.get(id, {}) as Dictionary
	if tr.is_empty() or String(tr["atk"]) != atk_id:
		var atk: EnemyAttack = _attack_of(ed, atk_id)
		if atk == null:
			return
		tr = {"atk": atk_id, "t": 0.0, "fired": false, "a": atk}
		_etrack[id] = tr
		var wb: Dictionary = catalog.enemy_binding(VfxTelegraph.kind_name(atk), atk_id)
		var wfx: String = String(wb.get("windup", ""))
		if not wfx.is_empty():
			player.play(wfx, av.global_position, av.rotation.y, {"follow": av, "scale": 1.0, "tier_scale": catalog.tier_scale(String(ed.tier)), "quiet": _quiet_for(av.global_position)})
	tr["t"] = float(tr["t"]) + delta
	if not bool(tr["fired"]) and float(tr["t"]) >= (tr["a"] as EnemyAttack).windup:
		tr["fired"] = true
		_enemy_strike(id, ed, tr["a"] as EnemyAttack, av.global_position, av.rotation.y)


func _enemy_strike(id: int, ed: EnemyData, atk: EnemyAttack, pos: Vector3, yaw: float) -> void:
	counters["enemy_strikes"] = int(counters["enemy_strikes"]) + 1
	var kn: String = VfxTelegraph.kind_name(atk)
	var b: Dictionary = catalog.enemy_binding(kn, String(atk.id))
	var tier: float = catalog.tier_scale(String(ed.tier))
	var q: bool = _quiet_for(pos)
	var base: Dictionary = {"tier_scale": tier, "quiet": q}
	match atk.kind:
		EnemyAttack.Kind.MELEE:
			var o: Dictionary = base.duplicate()
			o["scale"] = clampf(atk.max_range / 2.2, 0.6, 2.0)
			player.play(String(b.get("strike", "")), pos, yaw, o)
		EnemyAttack.Kind.AOE:
			var o2: Dictionary = base.duplicate()
			o2["scale"] = maxf(atk.radius / 2.7, 0.5)
			player.play(String(b.get("strike", "")), pos + forward(yaw) * atk.aoe_offset, yaw, o2)
		EnemyAttack.Kind.PROJECTILE:
			var n: int = maxi(atk.projectile_count, 1)
			for i: int in n:
				var off: float = 0.0 if n == 1 else deg_to_rad(atk.spread_degrees) * (float(i) / float(n - 1) - 0.5)
				var yy: float = yaw + off
				player.play(String(b.get("projectile", "")), pos + forward(yy) * 0.8, yy, {"speed": atk.projectile_speed, "range": atk.max_range + 2.0, "end": String(b.get("impact", "")), "owner": id, "quiet": q})
		EnemyAttack.Kind.CHARGE:
			player.play(String(b.get("strike", "")), pos, yaw, {"speed": atk.charge_speed, "range": atk.charge_distance, "quiet": q})
		EnemyAttack.Kind.SUMMON:
			player.play(String(b.get("strike", "")), pos, 0.0, base)


# ------------------------------------------------------------------ eventos

func on_event(kind: int, data: Dictionary) -> void:
	match kind:
		Protocol.EVENT_DAMAGE:
			_on_damage(data)
		Protocol.EVENT_DEATH:
			_on_death(int(data.get("id", -1)))
		Protocol.EVENT_ENEMY_SPAWN:
			var sid: int = int(data.get("id", -1))
			var av: Node3D = _avatar(sid)
			if av != null:
				_spawn_fx(sid, av)
			else:
				_spawn_pending[sid] = true
		Protocol.EVENT_DROP:
			_on_drop(data)
		Protocol.EVENT_ZONE:
			if int(data.get("id", -1)) == local_id and data.get("pos") is Vector3:
				var key: String = "zone_arrive" if int(data.get("phase", -1)) == Protocol.ZONE_PHASE_ARRIVED else "zone_leave"
				player.play(catalog.event_effect(key), data["pos"] as Vector3, 0.0, {})
		Protocol.EVENT_RESPAWN:
			if data.get("pos") is Vector3:
				player.play(catalog.event_effect("respawn"), data["pos"] as Vector3, 0.0, {"quiet": int(data.get("id", -1)) != local_id})


## Avatar recem-criado: aplica o spawn que chegou antes dele.
func on_avatar_created(id: int, av: Node3D) -> void:
	if _spawn_pending.has(id):
		_spawn_pending.erase(id)
		_spawn_fx(id, av)


func _spawn_fx(id: int, av: Node3D) -> void:
	counters["spawns"] = int(counters["spawns"]) + 1
	var tier: float = 1.0
	var ed: EnemyData = EnemyCatalog.data_for(StringName(String(av.get_meta("vtype", ""))))
	if ed != null:
		tier = catalog.tier_scale(String(ed.tier))
	player.play(catalog.event_effect("spawn"), av.global_position, 0.0, {"tier_scale": tier, "quiet": true})


func _on_damage(data: Dictionary) -> void:
	var tid: int = int(data.get("target_id", -1))
	var src: int = int(data.get("source_id", -1))
	var av: Node3D = _avatar(tid)
	if av == null:
		return
	counters["hits"] = int(counters["hits"]) + 1
	var crit: bool = bool(data.get("crit", false))
	var pos: Vector3 = av.global_position
	var q: bool = _quiet_for(pos)
	var tkind: int = int(av.get_meta("kind", Protocol.KIND_ENEMY))
	var fx_id: String = ""
	if tkind == Protocol.KIND_PLAYER:
		fx_id = catalog.event_effect("damage_player")
		if tid == local_id:
			shake_requested.emit(0.12 if float(data.get("amount", 0.0)) < 25.0 else 0.2, 0.18)
	else:
		fx_id = catalog.event_effect("damage_enemy")
		var ls: Dictionary = _last_skill.get(src, {}) as Dictionary
		if not ls.is_empty() and _clock - float(ls["t"]) <= 1.2:
			var imp: String = String(catalog.skill_binding(String(ls["skill"])).get("impact", ""))
			if not imp.is_empty():
				fx_id = imp
	var yaw: float = randf() * TAU
	if not fx_id.is_empty():
		player.play(fx_id, pos, yaw, {"quiet": q})
	if crit:
		player.play(catalog.event_effect("damage_crit"), pos, yaw, {"quiet": q})
	_match_projectile(src, pos)
	if src == local_id and VfxSettings.hit_stop_enabled() and world != null and world.has_method("hit_stop"):
		world.hit_stop(src, HITSTOP_CRIT if crit else HITSTOP_NORMAL)


func _match_projectile(src: int, hit_pos: Vector3) -> void:
	for inst: VfxInstance in player.projectiles():
		if inst.owner_id != src:
			continue
		if Vector2(inst.global_position.x - hit_pos.x, inst.global_position.z - hit_pos.z).length() > 3.0:
			continue
		if inst.pierce_left > 0:
			inst.pierce_left -= 1
		else:
			player.end_projectile(inst, "", hit_pos)
		return


func _on_death(id: int) -> void:
	var av: Node3D = _avatar(id)
	var pos: Vector3 = av.global_position if av != null else Vector3.INF
	if av == null and world != null and (world.get("_last_pos") as Dictionary).has(id):
		pos = (world.get("_last_pos") as Dictionary)[id] as Vector3
	if pos == Vector3.INF:
		return
	counters["deaths"] = int(counters["deaths"]) + 1
	var key: String = "death_enemy"
	var tier: float = 1.0
	if av != null and int(av.get_meta("kind", 0)) == Protocol.KIND_PLAYER:
		key = "death_player"
	elif av != null:
		var ed: EnemyData = EnemyCatalog.data_for(StringName(String(av.get_meta("vtype", ""))))
		if ed != null:
			tier = catalog.tier_scale(String(ed.tier))
			if ed.tier == EnemyData.TIER_BOSS:
				key = "death_boss"
	player.play(catalog.event_effect(key), pos, 0.0, {"tier_scale": tier, "quiet": _quiet_for(pos)})
	if _auras.has(id):
		player.stop(int(_auras[id]))
		_auras.erase(id)


func _on_drop(data: Dictionary) -> void:
	if not (data.get("pos") is Vector3):
		return
	counters["drops"] = int(counters["drops"]) + 1
	var rarity: String = String(data.get("rarity", "common"))
	var fx_id: String = catalog.drop_effect(rarity)
	var opts: Dictionary = {"quiet": true}
	if rarity != "common" and catalog.drop_effect("common") != fx_id:
		opts["tint"] = catalog.rarity_color(rarity)
	player.play(fx_id, data["pos"] as Vector3, 0.0, opts)


# ------------------------------------------------------------------ nivel / talento / zona

## s_talents.level subiu => coluna de luz com runas no jogador local; pontos gastos subiram => runa de talento.
func on_talents_state(state: Dictionary) -> void:
	var lvl: int = int(state.get("level", -1))
	var spent: int = int(state.get("points_spent", -1))
	var av: Node3D = _avatar(local_id)
	if av != null:
		if _level >= 0 and lvl > _level:
			counters["level_ups"] = int(counters["level_ups"]) + 1
			player.play(catalog.event_effect("level_up"), av.global_position, 0.0, {"follow": av})
		elif _talent_total >= 0 and spent > _talent_total:
			player.play(catalog.event_effect("talent"), av.global_position, 0.0, {"follow": av})
	_level = lvl
	_talent_total = spent


func play_level_up() -> void:
	var av: Node3D = _avatar(local_id)
	if av != null:
		player.play(catalog.event_effect("level_up"), av.global_position, 0.0, {"follow": av})


## Zona nova: portais ganham o aro de runas ambiente (limitado pelo preset: baixa qualidade = no maximo 2).
func on_zone(zone: ZoneDef) -> void:
	for h: int in _portals:
		player.stop(h)
	_portals.clear()
	var cap: int = 2 if player.quality == QualitySettings.Preset.LOW else 8
	var fx_id: String = catalog.event_effect("portal_ambient")
	for portal: Dictionary in zone.portals:
		if _portals.size() >= cap:
			break
		var h2: int = player.play(fx_id, portal["pos"] as Vector3, 0.0, {"scale": clampf(float(portal["radius"]) / 1.6, 0.6, 2.0), "quiet": true})
		if h2 >= 0:
			_portals.append(h2)
