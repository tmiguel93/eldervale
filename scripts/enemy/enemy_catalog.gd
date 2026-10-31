class_name EnemyCatalog
extends RefCounted
## Convencao de caminhos de inimigos: id `x` => data/enemies/x.tres e scenes/enemy/x.tscn.
## IDs vindos da rede/dados passam por `is_valid_id` antes de virarem caminho (sem path traversal).

const DATA_DIR: String = "res://data/enemies/"
const SCENE_DIR: String = "res://scenes/enemy/"

## Ids de Greenwood (E5.2), na ordem do documento docs/E5_ENEMIES.md.
const GREENWOOD_REGULAR: Array[StringName] = [
	&"melee_grunt", &"ranged_caster", &"forest_stalker", &"bow_scout",
	&"bark_brute", &"grove_shaman", &"burrow_lurker", &"root_sprout",
]
const MINI_BOSS_ID: StringName = &"thorn_alpha"
const BOSS_ID: StringName = &"blight_treant"

static var _cache: Dictionary = {}


static func is_valid_id(id: String) -> bool:
	if id.is_empty() or id.length() > 32:
		return false
	for i: int in id.length():
		var c: int = id.unicode_at(i)
		if not ((c >= 97 and c <= 122) or (c >= 48 and c <= 57) or c == 95):
			return false
	return true


static func all_ids() -> Array[StringName]:
	var out: Array[StringName] = GREENWOOD_REGULAR.duplicate()
	out.append(MINI_BOSS_ID)
	out.append(BOSS_ID)
	return out


static func scene_path(id: StringName) -> String:
	return SCENE_DIR + String(id) + ".tscn" if is_valid_id(String(id)) else ""


static func data_path(id: StringName) -> String:
	return DATA_DIR + String(id) + ".tres" if is_valid_id(String(id)) else ""


## EnemyData do id (cache estatico) ou null se id invalido/inexistente.
static func data_for(id: StringName) -> EnemyData:
	if _cache.has(id):
		return _cache[id] as EnemyData
	var path: String = data_path(id)
	var d: EnemyData = null
	if path != "" and ResourceLoader.exists(path):
		d = load(path) as EnemyData
	_cache[id] = d
	return d
