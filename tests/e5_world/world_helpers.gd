extends RefCounted
## Utilitarios dos testes do mundo (nao e um teste: nome sem prefixo test_). Servidor em modo mundo
## (settings.world_id = "greenwood"), sem rede real; o tempo do diretor avanca por `tick` manual.

const H = preload("res://tests/e3/server_helpers.gd")
const HUB_PORTAL: Vector3 = Vector3(27.0, 0.05, 0.0)
const PLATE_A: Vector3 = Vector3(380.0, 0.05, -14.0)
const PLATE_B: Vector3 = Vector3(380.0, 0.05, 14.0)
const BOSS_TRIGGER: Vector3 = Vector3(415.0, 0.05, 0.0)


static func rig(tree: SceneTree, spawn_enemies: bool = false, max_players: int = 4) -> H.Rig:
	return H.make_rig(tree, spawn_enemies, max_players, false, "greenwood")


## Avanca o diretor `seconds` (passos de 0.1 s), sem depender de frames de fisica.
static func tick(r: H.Rig, seconds: float) -> void:
	for i: int in int(round(seconds / 0.1)):
		r.world.director.tick(0.1)


## Troca de zona completa (inicia + espera a transicao). Devolve se o jogador chegou.
static func travel(r: H.Rig, eid: int, zone: String, spawn: String) -> bool:
	if not r.world.director.begin_transition(eid, zone, spawn):
		return false
	tick(r, 1.0)
	return r.world.zone_of_player(eid) == zone


static func kill_player(r: H.Rig, eid: int) -> void:
	(r.world.get_player_node(eid).get_node("Health") as HealthComponent).apply_damage(DamageInfo.make(99999.0, null, Hitbox.new_hit_id()))


static func hit(target: Enemy, source: Node, amount: float = 99999.0) -> void:
	target.health.apply_damage(DamageInfo.make(amount, source, Hitbox.new_hit_id()))


static func place(r: H.Rig, eid: int, pos: Vector3) -> void:
	r.world.teleport_player(eid, pos)


static func enemies_of_type(r: H.Rig, zone: String, type_id: String) -> Array[Enemy]:
	var out: Array[Enemy] = []
	for id: int in r.world.enemy_ids_in_zone(zone):
		var e: Enemy = r.world.get_enemy_node(id)
		if e != null and String(e.data.id) == type_id:
			out.append(e)
	return out
