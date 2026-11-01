extends RefCounted
## Utilitarios dos testes E6.1 (classes). Nao e um teste (sem prefixo test_).

const H = preload("res://tests/e2/loop_helpers.gd")

const CLASS_IDS: Array[String] = ["warrior", "mage", "ranger"]
const SKILLS: Dictionary = {
	"warrior": ["basic_attack", "heavy_strike", "whirlwind", "dodge"],
	"mage": ["arcane_bolt", "fireball", "frost_nova", "blink"],
	"ranger": ["quick_shot", "piercing_arrow", "arrow_rain", "roll"],
}


## Jogador do servidor-like (fisica manual) com a classe aplicada pelo Loadout.
static func spawn(world: Node3D, class_id: String, pos: Vector3 = Vector3.ZERO) -> Player:
	var p: Player = H.spawn_player(world, pos)
	var lo: PlayerLoadout = PlayerLoadout.find_for(p)
	lo.apply_class(ClassCatalog.shared().get_def(class_id))
	return p


static func combat_of(p: Player) -> PlayerCombat:
	return p.get_node("Combat") as PlayerCombat


## Alvo inimigo parado (Hurtbox na camada ENEMY_HURT) com vida alta e defesa 0, centrado em `pos`.
static func dummy(world: Node3D, pos: Vector3, hp: float = 100000.0) -> HealthComponent:
	var root: Node3D = Node3D.new()
	var hc: HealthComponent = HealthComponent.new()
	var st: StatBlock = StatBlock.new()
	st.max_health = hp
	st.defense = 0.0
	st.resistance = 0.0
	hc.stats = st
	root.add_child(hc)
	var hb: Hurtbox = Hurtbox.new()
	hb.team = CombatLayers.Team.ENEMY
	hb.health = hc
	var col: CollisionShape3D = CollisionShape3D.new()
	var sh: BoxShape3D = BoxShape3D.new()
	sh.size = Vector3(0.8, 1.2, 0.8)
	col.shape = sh
	hb.add_child(col)
	root.add_child(hb)
	world.add_child(root)
	root.position = pos
	return hc


## Usa a skill e avanca ate a fase ACTIVE (o golpe/projetil nasce aqui).
static func use_to_active(combat: PlayerCombat, skill: SkillData) -> bool:
	var ok: bool = combat.try_use(skill)
	if ok:
		combat.step(skill.windup + 0.001)
	return ok


## Reinicia estado de combate entre casos (cooldowns, recurso cheio, maquina em IDLE).
static func reset(combat: PlayerCombat) -> void:
	combat.step(5.0)
	combat.cooldowns.clear()
	combat.resource_pool.restore(100000.0)


## Avanca o projetil manualmente (a fisica propria dele e desligada pelo teste) ate consumir ou estourar `max_steps`.
static func run_projectile(proj: SkillProjectile, dt: float = 0.05, max_steps: int = 400) -> int:
	var n: int = 0
	while is_instance_valid(proj) and not proj.consumed and n < max_steps:
		proj.step(dt)
		n += 1
	return n
