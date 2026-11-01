extends RefCounted
## Utilitarios dos testes E6.2 (talentos). Nao e um teste (sem prefixo test_).

const H = preload("res://tests/e2/loop_helpers.gd")
const C = preload("res://tests/e6_classes/class_helpers.gd")


static func read_json(path: String) -> Variant:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	return JSON.parse_string(f.get_as_text())


## Jogador com a classe aplicada, a especializacao e os ranks DADOS (estado de memoria; a validacao de pontos e testada em outro lugar).
static func build(world: Node3D, class_id: String, spec: String, ranks: Dictionary, pos: Vector3 = Vector3.ZERO) -> Player:
	var p: Player = C.spawn(world, class_id, pos)
	var lo: PlayerLoadout = PlayerLoadout.find_for(p)
	lo.talents.spec_id = spec
	lo.talents.ranks = ranks.duplicate()
	lo.apply_talents()
	return p


static func projectiles_of(combat: PlayerCombat) -> Array[SkillProjectile]:
	var got: Array[SkillProjectile] = []
	combat.projectile_spawned.connect(func(pr: SkillProjectile) -> void:
		pr.set_physics_process(false)
		got.append(pr))
	return got


## Copia rasa das propriedades de uma habilidade (para provar que o recurso compartilhado nao foi mutado).
static func snapshot(s: SkillData) -> Dictionary:
	return {"cost": s.resource_cost, "cd": s.cooldown, "mult": s.damage_multiplier, "size": s.hitbox_size, "i": s.i_frames,
		"speed": s.projectile_speed, "pierce": s.projectile_pierce}
