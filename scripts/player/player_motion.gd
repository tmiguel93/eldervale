class_name PlayerMotion
extends RefCounted
## Funcoes puras de movimento (sem nos, sem fisica) para o jogador. Testaveis headless.
## Convencao: yaw em radianos em torno de +Y; a camera olha para -Z local do rig,
## logo, com yaw = 0 "frente" = (0, 0, -1) e "direita" = (+1, 0, 0).

const UP: Vector3 = Vector3.UP


## input: x = direita (+1) / esquerda (-1); y = frente (+1) / tras (-1).
## Retorna direcao no mundo (plano XZ), com comprimento <= 1 (diagonais normalizadas).
static func world_direction(input: Vector2, yaw: float) -> Vector3:
	var v: Vector2 = input.limit_length(1.0)
	var forward: Vector3 = Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right: Vector3 = Vector3(cos(yaw), 0.0, -sin(yaw))
	return right * v.x + forward * v.y


## Yaw (rotacao em Y) para que o -Z local do personagem aponte para `direction`.
## Direcao nula devolve `fallback`.
static func facing_yaw(direction: Vector3, fallback: float) -> float:
	var flat: Vector3 = Vector3(direction.x, 0.0, direction.z)
	if flat.length_squared() < 0.000001:
		return fallback
	return atan2(-flat.x, -flat.z)


## Aproxima `current` de `target` (angulos) de forma suave e independente de framerate.
static func smooth_angle(current: float, target: float, turn_speed: float, delta: float) -> float:
	return lerp_angle(current, target, 1.0 - exp(-turn_speed * delta))
