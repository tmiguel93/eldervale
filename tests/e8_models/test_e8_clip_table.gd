extends RefCounted
## E8.1: remocao de prefixo, selecao de clip por estado com fallback, estado do snapshot -> estado visual, velocidade.


func run(ctx: Variant) -> void:
	await (ctx as SceneTree).physics_frame
	ctx.check(ClipTable.strip_prefix("AnimalArmature|Idle") == "Idle", "prefixo AnimalArmature| removido")
	ctx.check(ClipTable.strip_prefix("SpiderArmature|Spider_Walk") == "Spider_Walk", "prefixo SpiderArmature| removido")
	ctx.check(ClipTable.strip_prefix("Walking_A") == "Walking_A", "sem prefixo = igual")
	ctx.check(ClipTable.strip_prefix("A|B|C") == "C", "ultimo segmento")
	var kay: Dictionary = ClipTable.build_index(PackedStringArray(["Idle", "Walking_A", "Running_A", "Hit_A", "Death_A", "T-Pose", "1H_Melee_Attack_Chop"]))
	ctx.check(ClipTable.pick(kay, &"idle") == "Idle", "KayKit idle")
	ctx.check(ClipTable.pick(kay, &"move") == "Walking_A", "KayKit move padrao = Walking_A")
	ctx.check(ClipTable.pick(kay, &"move", {"move": "Running_A"}) == "Running_A", "override do dado vence")
	ctx.check(ClipTable.pick(kay, &"attack") == "1H_Melee_Attack_Chop", "attack padrao")
	ctx.check(ClipTable.pick(kay, &"skill") == "1H_Melee_Attack_Chop", "skill sem clip cai em attack")
	ctx.check(ClipTable.pick(kay, &"dodge") == "Walking_A", "dodge sem clip cai em move")
	ctx.check(ClipTable.pick(kay, &"spawn") == "", "spawn ausente = nenhum clip (sem erro)")
	ctx.check(ClipTable.pick(kay, &"hit") == "Hit_A" and ClipTable.pick(kay, &"death") == "Death_A", "hit e death")
	ctx.check(ClipTable.pick(kay, &"move", {"move": "NaoExiste"}) == "Walking_A", "override inexistente cai no padrao")
	ctx.check(ClipTable.pick(kay, &"idle", {"idle": ["X", "idle"]}) == "Idle", "lista de candidatos, sem diferenciar maiusculas")
	var quat: Dictionary = ClipTable.build_index(PackedStringArray(["AnimalArmature|Attack", "AnimalArmature|Death", "AnimalArmature|Gallop", "AnimalArmature|Idle", "AnimalArmature|Idle_HitReact_Left", "AnimalArmature|Walk"]))
	ctx.check(ClipTable.pick(quat, &"idle") == "AnimalArmature|Idle", "Quaternius idle devolve o nome REAL com prefixo")
	ctx.check(ClipTable.pick(quat, &"move") == "AnimalArmature|Walk", "Quaternius move = Walk")
	ctx.check(ClipTable.pick(quat, &"move", {"move": "Gallop"}) == "AnimalArmature|Gallop", "override sem prefixo acha clip com prefixo")
	ctx.check(ClipTable.pick(quat, &"attack") == "AnimalArmature|Attack", "Quaternius attack")
	ctx.check(ClipTable.pick(quat, &"hit") == "AnimalArmature|Idle_HitReact_Left", "Quaternius hit")
	ctx.check(ClipTable.pick(quat, &"death") == "AnimalArmature|Death", "Quaternius death")
	# sem nenhum clip conhecido: idle = primeiro disponivel, o resto nenhum
	var odd: Dictionary = ClipTable.build_index(PackedStringArray(["T-Pose", "Foo_Pose", "Bar", "Baz"]))
	ctx.check(ClipTable.pick(odd, &"idle") == "Bar", "idle cai no primeiro clip que nao e pose")
	ctx.check(ClipTable.pick(odd, &"move") == "Bar", "move sem clip cai em idle")
	ctx.check(ClipTable.pick(odd, &"death") == "" and ClipTable.pick(odd, &"attack") == "", "death/attack sem clip = nenhum")
	var empty: Dictionary = ClipTable.build_index(PackedStringArray())
	for st: StringName in ClipTable.STATES:
		ctx.check(ClipTable.pick(empty, st) == "", "sem clips: %s = nenhum (sem erro)" % st)
	# estado do snapshot
	var P: int = Protocol.KIND_PLAYER
	var E: int = Protocol.KIND_ENEMY
	ctx.check(ClipTable.state_from_snapshot(P, CharacterStateMachine.State.IDLE) == &"idle", "jogador IDLE")
	ctx.check(ClipTable.state_from_snapshot(P, CharacterStateMachine.State.MOVE) == &"move", "jogador MOVE")
	ctx.check(ClipTable.state_from_snapshot(P, CharacterStateMachine.State.ATTACK) == &"attack", "jogador ATTACK")
	ctx.check(ClipTable.state_from_snapshot(P, CharacterStateMachine.State.DODGE) == &"dodge", "jogador DODGE")
	ctx.check(ClipTable.state_from_snapshot(P, CharacterStateMachine.State.HIT) == &"hit", "jogador HIT")
	ctx.check(ClipTable.state_from_snapshot(P, CharacterStateMachine.State.DEAD) == &"death", "jogador DEAD")
	ctx.check(ClipTable.state_from_snapshot(P, CharacterStateMachine.State.IDLE, 1) == &"move", "predicao local andando vence IDLE do snapshot")
	ctx.check(ClipTable.state_from_snapshot(P, CharacterStateMachine.State.MOVE, 0) == &"idle", "predicao local parada vence MOVE")
	ctx.check(ClipTable.state_from_snapshot(P, CharacterStateMachine.State.ATTACK, 1) == &"attack", "ataque nao e trocado pela predicao")
	ctx.check(ClipTable.state_from_snapshot(E, EnemyAI.State.IDLE) == &"idle", "inimigo IDLE")
	ctx.check(ClipTable.state_from_snapshot(E, EnemyAI.State.CHASE) == &"move" and ClipTable.state_from_snapshot(E, EnemyAI.State.RETURN) == &"move", "inimigo CHASE/RETURN = move")
	ctx.check(ClipTable.state_from_snapshot(E, EnemyAI.State.ATTACK) == &"attack", "inimigo ATTACK corpo a corpo")
	ctx.check(ClipTable.state_from_snapshot(E, EnemyAI.State.ATTACK, -1, true) == &"skill", "inimigo ATTACK em area/projetil = skill")
	ctx.check(ClipTable.state_from_snapshot(E, EnemyAI.State.DEAD) == &"death", "inimigo DEAD")
	# velocidade de reproducao
	ctx.check(is_equal_approx(ClipTable.speed_for(&"idle", 1.0), 1.0) and is_equal_approx(ClipTable.speed_for(&"move", 1.0), 1.0), "idle/move a 1x")
	ctx.check(ClipTable.speed_for(&"attack", 1.0, 0.5) > 1.9 and ClipTable.speed_for(&"attack", 1.0, 0.5) < 2.1, "attack de 1 s em 0.5 s = 2x")
	ctx.check(ClipTable.speed_for(&"attack", 10.0, 0.1) == ClipTable.MAX_SPEED, "velocidade limitada")
	ctx.check(ClipTable.speed_for(&"attack", 0.1, 5.0) == ClipTable.MIN_SPEED, "velocidade minima")
