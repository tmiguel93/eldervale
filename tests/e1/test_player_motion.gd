extends RefCounted
## Funcoes puras de PlayerMotion: entrada -> direcao no mundo.

const EPS: float = 0.0001


func run(ctx: Object) -> void:
	var s: float = sqrt(0.5)
	# yaw 0: frente = -Z, direita = +X
	var d: Vector3 = PlayerMotion.world_direction(Vector2(0, 1), 0.0)
	ctx.check(d.distance_to(Vector3(0, 0, -1)) < EPS, "yaw 0: frente -> -Z")
	d = PlayerMotion.world_direction(Vector2(1, 0), 0.0)
	ctx.check(d.distance_to(Vector3(1, 0, 0)) < EPS, "yaw 0: direita -> +X")
	# yaw 45 graus
	var yaw: float = deg_to_rad(45.0)
	d = PlayerMotion.world_direction(Vector2(0, 1), yaw)
	ctx.check(d.distance_to(Vector3(-s, 0, -s)) < EPS, "yaw 45: frente -> (-0.707,0,-0.707)")
	d = PlayerMotion.world_direction(Vector2(0, -1), yaw)
	ctx.check(d.distance_to(Vector3(s, 0, s)) < EPS, "yaw 45: tras -> (0.707,0,0.707)")
	d = PlayerMotion.world_direction(Vector2(1, 0), yaw)
	ctx.check(d.distance_to(Vector3(s, 0, -s)) < EPS, "yaw 45: direita -> (0.707,0,-0.707)")
	d = PlayerMotion.world_direction(Vector2(-1, 0), yaw)
	ctx.check(d.distance_to(Vector3(-s, 0, s)) < EPS, "yaw 45: esquerda -> (-0.707,0,0.707)")
	d = PlayerMotion.world_direction(Vector2(1, 1), yaw)
	ctx.check(absf(d.length() - 1.0) < EPS, "diagonal de entrada normalizada (velocidade constante)")
	ctx.check(PlayerMotion.world_direction(Vector2.ZERO, yaw) == Vector3.ZERO, "sem entrada -> zero")
	# facing
	ctx.check(absf(PlayerMotion.facing_yaw(Vector3(0, 0, -1), 9.0)) < EPS, "facing: -Z -> yaw 0")
	ctx.check(absf(PlayerMotion.facing_yaw(Vector3(1, 0, 0), 0.0) + PI * 0.5) < EPS, "facing: +X -> yaw -90")
	ctx.check(PlayerMotion.facing_yaw(Vector3.ZERO, 1.25) == 1.25, "facing: direcao nula -> fallback")
	var a: float = PlayerMotion.smooth_angle(0.0, PI * 0.9, 14.0, 1.0 / 60.0)
	ctx.check(a > 0.0 and a < PI * 0.9, "smooth_angle avanca sem ultrapassar")
