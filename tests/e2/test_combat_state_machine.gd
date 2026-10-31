extends RefCounted
## CharacterStateMachine: transicoes validas/invalidas e ausencia de softlock.

const S = CharacterStateMachine.State
const P = CharacterStateMachine.Phase


func run(ctx: Object) -> void:
	var m: CharacterStateMachine = CharacterStateMachine.new()
	ctx.check(m.state == S.IDLE, "inicia em IDLE")
	m.set_moving(true)
	ctx.check(m.state == S.MOVE, "idle -> move")
	m.set_moving(false)
	ctx.check(m.state == S.IDLE, "move -> idle")

	var phases: Array[int] = []
	m.phase_changed.connect(func(_s: int, p: int) -> void: phases.append(p))
	ctx.check(m.try_attack(0.1, 0.2, 0.3), "ataca a partir de IDLE")
	ctx.check(m.state == S.ATTACK and m.phase == P.WINDUP, "ataque comeca em WINDUP")
	ctx.check(m.movement_locked() and not m.is_strike_active(), "windup trava movimento, sem golpe ativo")
	ctx.check(not m.try_attack(0.1, 0.2, 0.3), "nao ataca durante ataque")
	m.set_moving(true)
	ctx.check(m.state == S.ATTACK, "set_moving nao sai de ATTACK")
	m.tick(0.05)
	ctx.check(m.phase == P.WINDUP, "ainda WINDUP")
	m.tick(0.06)
	ctx.check(m.phase == P.ACTIVE and m.is_strike_active(), "WINDUP -> ACTIVE")
	m.tick(0.2)
	ctx.check(m.phase == P.RECOVER and not m.movement_locked(), "ACTIVE -> RECOVER libera movimento")
	m.tick(0.3)
	ctx.check(m.state == S.IDLE and m.phase == P.NONE, "ataque termina em IDLE")
	ctx.check(phases == [P.WINDUP, P.ACTIVE, P.RECOVER], "fases emitidas em ordem")

	# delta grande atravessa varias fases sem travar
	ctx.check(m.try_attack(0.1, 0.1, 0.1), "novo ataque")
	m.tick(10.0)
	ctx.check(m.state == S.IDLE, "delta enorme termina em IDLE (sem softlock)")

	# fases de duracao 0 sao puladas
	ctx.check(m.try_dodge(0.0, 0.2, 0.0), "esquiva sem windup/recover")
	ctx.check(m.state == S.DODGE and m.phase == P.ACTIVE, "esquiva inicia direto em ACTIVE")
	ctx.check(not m.try_dodge(0.0, 0.2, 0.1), "nao esquiva durante DODGE")
	ctx.check(not m.try_attack(0.1, 0.1, 0.1), "nao ataca durante DODGE")
	ctx.check(not m.hit(0.3), "DODGE nao sofre stagger")
	m.tick(0.2)
	ctx.check(m.state == S.IDLE, "esquiva termina em IDLE")

	# cancelamento de ataque por esquiva so no RECOVER
	m.try_attack(0.1, 0.1, 0.3)
	ctx.check(not m.try_dodge(0.0, 0.2, 0.1), "nao esquiva em WINDUP")
	m.tick(0.15)
	ctx.check(not m.try_dodge(0.0, 0.2, 0.1), "nao esquiva em ACTIVE")
	m.tick(0.1)
	ctx.check(m.phase == P.RECOVER and m.try_dodge(0.0, 0.2, 0.1), "esquiva cancela RECOVER")
	ctx.check(m.state == S.DODGE, "agora em DODGE")
	m.tick(1.0)

	# hit interrompe ataque; nao empilha
	m.try_attack(0.1, 0.1, 0.1)
	ctx.check(m.hit(0.25) and m.state == S.HIT, "hit interrompe ataque")
	ctx.check(m.movement_locked() and not m.is_strike_active(), "HIT trava movimento")
	ctx.check(not m.hit(0.25), "sem novo stun enquanto atordoado")
	ctx.check(not m.try_attack(0.1, 0.1, 0.1), "nao ataca atordoado")
	m.tick(0.3)
	ctx.check(m.state == S.IDLE, "HIT volta a IDLE")
	ctx.check(m.hit(0.0) == true and m.state == S.IDLE, "stun 0 volta direto a IDLE")

	# morte
	m.try_attack(0.1, 0.1, 0.1)
	ctx.check(m.die() and m.state == S.DEAD, "morre durante ataque")
	ctx.check(not m.try_attack(0.1, 0.1, 0.1), "morto nao ataca")
	ctx.check(not m.try_dodge(0.0, 0.2, 0.1), "morto nao esquiva")
	ctx.check(not m.hit(0.2), "morto nao sofre hit")
	ctx.check(not m.die(), "nao morre duas vezes")
	m.set_moving(true)
	m.tick(5.0)
	ctx.check(m.state == S.DEAD, "DEAD permanece ate revive")
	ctx.check(m.revive() and m.state == S.IDLE, "revive -> IDLE")
	ctx.check(not m.revive(), "revive so de DEAD")
	ctx.check(not m.try_attack(0.0, 0.0, 0.0), "duracao total 0 e rejeitada")
