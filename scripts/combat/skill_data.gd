class_name SkillData
extends Resource
## Definicao estatica de habilidade (dados, sem logica de jogo). Arquivos em data/skills/*.tres.
## Dano do golpe = attack_power do atacante * damage_multiplier.
## Hitbox: BOX usa hitbox_size (x largura, y altura, z profundidade); SPHERE usa hitbox_size.x como raio.
## O centro fica `hitbox_offset` metros a frente do facing (0 = ao redor do jogador, ex.: whirlwind).
## DODGE: nao causa dano; desloca `dodge_distance` m durante windup+active e da `i_frames` s de invulnerabilidade.
## E6.1 PROJETIL: `projectile_speed` > 0 faz o ATAQUE disparar um SkillProjectile (esfera de raio hitbox_size.x) na fase ACTIVE,
## na direcao do facing, que percorre ate `projectile_range` m e atravessa `projectile_pierce` alvos ADICIONAIS (0 = some no 1o).
## `hitbox_offset` vira a distancia do ponto de disparo a frente do jogador. Area a distancia = esfera com hitbox_offset > 0.

enum Kind { ATTACK, DODGE }
enum HitboxShape { BOX, SPHERE }

@export var id: StringName = &""
@export var display_name: String = ""
@export var kind: Kind = Kind.ATTACK
@export var resource_cost: float = 0.0
@export var cooldown: float = 0.0
@export var damage_multiplier: float = 1.0
@export var windup: float = 0.0 ## s antes do golpe ficar ativo
@export var active: float = 0.1 ## s com hitbox ativo (esquiva: s de deslocamento)
@export var recover: float = 0.0 ## s finais sem poder agir
@export var hitbox_shape: HitboxShape = HitboxShape.BOX
@export var hitbox_size: Vector3 = Vector3(1.5, 1.5, 1.5)
@export var hitbox_offset: float = 1.0
@export var i_frames: float = 0.0 ## s de invulnerabilidade desde o inicio (esquiva)
@export var dodge_distance: float = 0.0
## Fracao da velocidade de movimento permitida durante windup+active de um ataque (0 = travado, 1 = livre).
@export_range(0.0, 1.0) var attack_move_scale: float = 0.5
@export var projectile_speed: float = 0.0 ## m/s; 0 = golpe corpo a corpo/area (sem projetil)
@export var projectile_range: float = 0.0 ## m percorridos antes de sumir
@export var projectile_pierce: int = 0 ## alvos adicionais atravessados
@export var tags: PackedStringArray = PackedStringArray() ## ex.: "projectile", "area", "fire", "mobility"


const MAX_PROJECTILE_SPEED: float = 40.0 ## limite sanitario (o projetil e varrido em sub-passos, entao nao ha tunelamento)
const MAX_PROJECTILE_RANGE: float = 40.0
const MAX_PROJECTILE_PIERCE: int = 8


func is_projectile() -> bool:
	return kind == Kind.ATTACK and projectile_speed > 0.0


func total_duration() -> float:
	return windup + active + recover


## Lista de erros de validacao (vazia = valido).
func validate() -> PackedStringArray:
	var errors: PackedStringArray = PackedStringArray()
	if id == &"":
		errors.append("id vazio")
	if display_name.strip_edges() == "":
		errors.append("display_name vazio")
	if resource_cost < 0.0:
		errors.append("resource_cost < 0")
	if attack_move_scale < 0.0 or attack_move_scale > 1.0:
		errors.append("attack_move_scale fora de 0..1")
	if cooldown < 0.0:
		errors.append("cooldown < 0")
	if windup < 0.0 or recover < 0.0:
		errors.append("windup/recover < 0")
	if active <= 0.0:
		errors.append("active deve ser > 0")
	if kind == Kind.ATTACK:
		if damage_multiplier <= 0.0:
			errors.append("damage_multiplier deve ser > 0")
		if hitbox_size.x <= 0.0 or hitbox_size.y <= 0.0 or hitbox_size.z <= 0.0:
			errors.append("hitbox_size deve ser > 0 em todos os eixos")
		if hitbox_offset < 0.0:
			errors.append("hitbox_offset < 0")
		if projectile_speed < 0.0 or projectile_speed > MAX_PROJECTILE_SPEED:
			errors.append("projectile_speed fora de 0..%d" % int(MAX_PROJECTILE_SPEED))
		if projectile_speed > 0.0:
			if hitbox_shape != HitboxShape.SPHERE:
				errors.append("projetil exige hitbox_shape SPHERE")
			if projectile_range <= 0.0 or projectile_range > MAX_PROJECTILE_RANGE:
				errors.append("projectile_range fora de (0..%d]" % int(MAX_PROJECTILE_RANGE))
			if projectile_pierce < 0 or projectile_pierce > MAX_PROJECTILE_PIERCE:
				errors.append("projectile_pierce fora de 0..%d" % MAX_PROJECTILE_PIERCE)
		elif projectile_range != 0.0 or projectile_pierce != 0:
			errors.append("projectile_range/pierce exigem projectile_speed > 0")
	else:
		if projectile_speed != 0.0:
			errors.append("esquiva nao dispara projetil")
		if i_frames <= 0.0:
			errors.append("esquiva: i_frames deve ser > 0")
		if i_frames > total_duration():
			errors.append("esquiva: i_frames maior que a duracao total")
		if dodge_distance <= 0.0:
			errors.append("esquiva: dodge_distance deve ser > 0")
	return errors
