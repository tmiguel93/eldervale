class_name VfxTelegraph
extends RefCounted
## E8.3: indicador de chao dos ataques de inimigo com cor por tipo (melee vermelho, area magenta, projetil amarelo, investida laranja,
## invocacao verde). Area/invocacao = circulo de runas com disco que enche (sweep); melee/investida/projetil = faixa com borda
## luminosa, setas em movimento e preenchimento ate o instante do golpe. Mesmo referencial do EnemyTelegraph (-Z = frente do inimigo).
## So apresentacao (cliente com display); sem display o ClientWorld continua usando o EnemyTelegraph de sempre.

const GROUND_Y: float = 0.06
const KIND_NAMES: Array[String] = ["melee", "aoe", "projectile", "charge", "summon"]


static func kind_name(attack: EnemyAttack) -> String:
	return KIND_NAMES[clampi(int(attack.kind), 0, KIND_NAMES.size() - 1)]


static func build(attack: EnemyAttack, color: Color) -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = "Telegraph"
	var dark: Vector3 = Vector3(color.r, color.g, color.b) * 0.55
	var bright: Vector3 = Vector3(minf(color.r + 0.25, 1.0), minf(color.g + 0.25, 1.0), minf(color.b + 0.25, 1.0))
	match attack.kind:
		EnemyAttack.Kind.AOE, EnemyAttack.Kind.SUMMON:
			var r: float = attack.radius if attack.kind == EnemyAttack.Kind.AOE else 2.6
			var m: ShaderMaterial = VfxAssets.shader_material("rune")
			node.mesh = VfxMeshes.ground_quad(r * 2.0, r * 2.0)
			node.position = Vector3(0.0, GROUND_Y, -attack.aoe_offset if attack.kind == EnemyAttack.Kind.AOE else 0.0)
			m.set_shader_parameter("style", 2 if attack.kind == EnemyAttack.Kind.AOE else 1)
			m.set_shader_parameter("color_a", bright)
			m.set_shader_parameter("color_b", dark)
			m.set_shader_parameter("intensity", 1.5)
			m.set_shader_parameter("progress", 0.35)
			m.set_shader_parameter("appear", 0.2)
			m.set_shader_parameter("vanish", 0.35)
			m.set_shader_parameter("fill", 0.55)
			node.material_override = m
		_:
			var len: float = attack.max_range
			var wid: float = attack.width
			if attack.kind == EnemyAttack.Kind.CHARGE:
				len = attack.charge_distance
			elif attack.kind == EnemyAttack.Kind.PROJECTILE:
				wid = 0.5
			node.mesh = VfxMeshes.ground_quad(wid, len)
			node.position = Vector3(0.0, GROUND_Y, -len * 0.5)
			var mb: ShaderMaterial = VfxAssets.shader_material("box")
			mb.set_shader_parameter("color_a", bright)
			mb.set_shader_parameter("color_b", dark)
			mb.set_shader_parameter("intensity", 1.5)
			mb.set_shader_parameter("size_m", Vector2(wid, len))
			node.material_override = mb
	node.set_meta("attack_kind", int(attack.kind))
	return node


## `progress` 0..1 do windup; `t` = segundos desde o inicio (animacoes).
static func update(node: MeshInstance3D, progress: float, t: float) -> void:
	var m: ShaderMaterial = node.material_override as ShaderMaterial
	if m == null:
		return
	var pulse: float = 0.5 + 0.5 * sin(t * (5.0 + 9.0 * progress))
	m.set_shader_parameter("pulse", pulse)
	if int(node.get_meta("attack_kind", 0)) == int(EnemyAttack.Kind.AOE) or int(node.get_meta("attack_kind", 0)) == int(EnemyAttack.Kind.SUMMON):
		m.set_shader_parameter("sweep", clampf(progress, 0.0, 1.0))
		m.set_shader_parameter("rot", t * 0.6)
	else:
		m.set_shader_parameter("progress", clampf(progress, 0.0, 1.0))
