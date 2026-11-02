class_name ClipTable
extends RefCounted
## E8.1: tabela estado -> clip de animacao, remocao de prefixo (`AnimalArmature|Idle` -> `Idle`) e fallback.
## Estados visuais: idle, move, attack, skill, dodge, hit, death, spawn. Cada estado tem candidatos padrao (KayKit e
## Quaternius); `overrides` (visual_clips do dado) tem prioridade. Clip faltando NUNCA e erro: cai na cadeia de
## fallback e, no fim, idle usa o primeiro clip disponivel (ignorando poses) e os demais ficam sem clip ("").

const STATES: Array[StringName] = [&"idle", &"move", &"attack", &"skill", &"dodge", &"hit", &"death", &"spawn"]

const DEFAULTS: Dictionary = {
	&"idle": ["Idle", "Idle_A", "Unarmed_Idle"],
	&"move": ["Walking_A", "Walk", "Running_A", "Gallop", "Walking_B"],
	&"attack": ["1H_Melee_Attack_Chop", "Attack", "2H_Melee_Attack_Chop", "Unarmed_Melee_Attack_Punch_A"],
	&"skill": ["Spellcast_Shoot", "Spellcast_Raise", "2H_Melee_Attack_Spin"],
	&"dodge": ["Dodge_Forward", "Roll"],
	&"hit": ["Hit_A", "Idle_HitReact_Left", "Hit_B"],
	&"death": ["Death_A", "Death"],
	&"spawn": ["Spawn_Ground", "Skeletons_Awaken_Standing", "Spawn_Air"],
}

## Se nenhum candidato do estado existir, tenta o estado seguinte da cadeia (nunca em ciclo).
const FALLBACK: Dictionary = {
	&"move": &"idle", &"skill": &"attack", &"attack": &"skill", &"dodge": &"move",
}

## Duracao alvo (s) de cada one-shot quando o chamador nao informa: o clip e acelerado/desacelerado para caber.
const TARGET_SECONDS: Dictionary = {&"attack": 0.5, &"skill": 0.6, &"dodge": 0.45, &"hit": 0.4, &"spawn": 1.2}
const MIN_SPEED: float = 0.6
const MAX_SPEED: float = 3.0
const LOOPING: Array[StringName] = [&"idle", &"move"]
const ONE_SHOT: Array[StringName] = [&"attack", &"skill", &"dodge", &"hit", &"spawn"]


## `AnimalArmature|Idle` -> `Idle`; sem barra, devolve igual.
static func strip_prefix(clip: String) -> String:
	var i: int = clip.rfind("|")
	return clip.substr(i + 1) if i >= 0 else clip


## Indice minusculo: nome sem prefixo (lower) -> nome real do AnimationPlayer. Mantem a ordem original (primeiro vence).
static func build_index(names: PackedStringArray) -> Dictionary:
	var idx: Dictionary = {}
	for n: String in names:
		var key: String = strip_prefix(n).to_lower()
		if not idx.has(key):
			idx[key] = n
	return idx


static func lookup(index: Dictionary, clip: String) -> String:
	return String(index.get(strip_prefix(clip).to_lower(), ""))


static func candidates(state: StringName, overrides: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var o: Variant = overrides.get(String(state), overrides.get(state, null))
	if typeof(o) == TYPE_STRING and not String(o).is_empty():
		out.append(String(o))
	elif typeof(o) == TYPE_ARRAY:
		for c: Variant in o:
			out.append(String(c))
	for c: String in (DEFAULTS.get(state, []) as Array):
		out.append(c)
	return out


## Nome REAL do clip para o estado ("" = nenhum). `index` vem de build_index.
static func pick(index: Dictionary, state: StringName, overrides: Dictionary = {}) -> String:
	var cur: StringName = state
	var seen: Dictionary = {}
	while not seen.has(cur):
		seen[cur] = true
		for c: String in candidates(cur, overrides):
			var real: String = lookup(index, c)
			if not real.is_empty():
				return real
		if not FALLBACK.has(cur):
			break
		cur = FALLBACK[cur]
	if state == &"idle" or state == &"move":
		return first_available(index)
	return ""


## Primeiro clip que nao e pose estatica (T-Pose, *_Pose).
static func first_available(index: Dictionary) -> String:
	for key: Variant in index:
		if not String(key).contains("pose"):
			return String(index[key])
	return ""


static func is_looping(state: StringName) -> bool:
	return LOOPING.has(state)


static func is_one_shot(state: StringName) -> bool:
	return ONE_SHOT.has(state)


## Velocidade do AnimationPlayer para o clip caber em `seconds` (0 = usa TARGET_SECONDS do estado). Limitada a [MIN, MAX].
static func speed_for(state: StringName, clip_length: float, seconds: float = 0.0) -> float:
	if not is_one_shot(state) or clip_length <= 0.001:
		return 1.0
	var target: float = seconds if seconds > 0.01 else float(TARGET_SECONDS.get(state, clip_length))
	return clampf(clip_length / target, MIN_SPEED, MAX_SPEED)


## Estado visual a partir do `state` do snapshot. Jogador: CharacterStateMachine.State; inimigo: EnemyAI.State.
## `moving` (opcional, >=0): o cliente local sabe se anda pela predicao; -1 = usa so o snapshot.
static func state_from_snapshot(kind: int, snap_state: int, moving: int = -1, attack_is_skill: bool = false) -> StringName:
	if kind == Protocol.KIND_ENEMY:
		match snap_state:
			EnemyAI.State.CHASE, EnemyAI.State.RETURN:
				return &"move"
			EnemyAI.State.ATTACK:
				return &"skill" if attack_is_skill else &"attack"
			EnemyAI.State.DEAD:
				return &"death"
		return &"idle"
	match snap_state:
		CharacterStateMachine.State.ATTACK:
			return &"attack"
		CharacterStateMachine.State.DODGE:
			return &"dodge"
		CharacterStateMachine.State.HIT:
			return &"hit"
		CharacterStateMachine.State.DEAD:
			return &"death"
		CharacterStateMachine.State.MOVE:
			return &"idle" if moving == 0 else &"move"
	return &"move" if moving == 1 else &"idle"
