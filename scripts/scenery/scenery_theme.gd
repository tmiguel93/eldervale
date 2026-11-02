class_name SceneryTheme
extends RefCounted
## E8.2: dados de apresentacao do cenario por zona (humor/iluminacao, chao, "skins" dos props de gameplay, regras de espalhamento,
## perimetro, pecas fixas e luzes). Dados puros em GDScript: nada aqui carrega arte nem toca fisica; o SceneryPlan transforma
## estas regras em posicoes (deterministico por zona) e o SceneryBuilder (so cliente) instancia. Zona sem tema = sem cenario novo.
##
## Convencao de mundo: a camera isometrica olha de (+x,+z) para (-x,-z) (yaw 45, pitch 50). Pecas ALTAS fora dos lados
## perto da camera nunca ocluem o jogador; o planner rejeita as que ocluiriam (camera-safe) ou as deixa baixas.

const NATURE: String = "res://assets/third_party/quaternius_nature/"
const VILLAGE: String = "res://assets/third_party/quaternius_medieval_village/"
const SURVIVAL: String = "res://assets/third_party/quaternius_survival/"
const DUNGEON: String = "res://assets/third_party/kaykit_dungeon_remastered/"
const HALLOWEEN: String = "res://assets/third_party/kaykit_halloween_bits/"

## Pacotes de assets usados pelo E8.2 (o preset do cliente deixa de exclui-los; ver docs/E8_SCENERY.md).
const PACKAGES: PackedStringArray = ["quaternius_nature", "quaternius_medieval_village", "quaternius_survival", "kaykit_dungeon_remastered", "kaykit_halloween_bits"]

static var _cache: Dictionary = {}


static func zone_ids() -> PackedStringArray:
	return PackedStringArray(["zone_hub", "zone_wild", "zone_ruins"])


static func has_zone(zone_id: String) -> bool:
	return zone_ids().has(zone_id)


## Tema da zona ({} se nao ha). Cacheado (os dicionarios nao devem ser alterados por quem chama).
static func for_zone(zone_id: String) -> Dictionary:
	if _cache.has(zone_id):
		return _cache[zone_id] as Dictionary
	var t: Dictionary = {}
	match zone_id:
		"zone_hub": t = _hub()
		"zone_wild": t = _wild()
		"zone_ruins": t = _ruins()
	_cache[zone_id] = t
	return t


## Todo caminho res:// de asset citado pelos temas (para testes e para a lista de pacotes do export).
static func all_assets() -> PackedStringArray:
	var seen: Dictionary = {}
	for zid: String in zone_ids():
		_collect(for_zone(zid), seen)
	var out: PackedStringArray = PackedStringArray(seen.keys())
	out.sort()
	return out


static func _collect(v: Variant, seen: Dictionary) -> void:
	if typeof(v) == TYPE_STRING and String(v).begins_with("res://assets/"):
		seen[String(v)] = true
	elif typeof(v) == TYPE_ARRAY:
		for x: Variant in v:
			_collect(x, seen)
	elif typeof(v) == TYPE_DICTIONARY:
		for k: Variant in v:
			_collect((v as Dictionary)[k], seen)


static func _n(names: Array) -> Array:
	var out: Array = []
	for n: Variant in names:
		out.append(NATURE + String(n) + ".glb")
	return out


static func _pines(first: int, last: int, snow: bool = false) -> Array:
	var out: Array = []
	for i: int in range(first, last + 1):
		out.append(NATURE + ("PineTree_Snow_%d.glb" if snow else "PineTree_%d.glb") % i)
	return out


# ------------------------------------------------------------------ vila (entardecer dourado)

static func _hub() -> Dictionary:
	return {
		"mood": {
			"sun_color": Color(1.0, 0.72, 0.44), "sun_energy": 1.6, "sun_pitch": -30.0, "sun_yaw": -28.0,
			"ambient_color": Color(0.40, 0.50, 0.72), "ambient_energy": 0.62,
			"sky_top": Color(0.20, 0.28, 0.52), "sky_horizon": Color(0.96, 0.66, 0.42), "sky_ground": Color(0.30, 0.27, 0.26),
			"fog_color": Color(0.80, 0.64, 0.52), "fog_density": 0.0016, "fog_sun_scatter": 0.2,
			"exposure": 0.95, "white": 6.0, "glow_intensity": 0.55, "glow_bloom": 0.10, "glow_threshold": 0.95,
			"saturation": 1.1, "contrast": 1.08, "vol_fog_density": 0.012,
		},
		"ground": {"a": Color(0.16, 0.32, 0.14), "b": Color(0.28, 0.43, 0.18), "c": Color(0.33, 0.27, 0.16), "patch": 0.55, "tile": 0.0, "scale": 0.12},
		"outer": {"margin": 40.0, "a": Color(0.15, 0.28, 0.14), "b": Color(0.21, 0.34, 0.16), "c": Color(0.26, 0.23, 0.15), "patch": 0.5},
		"path_styles": {
			"Plaza": {"a": Color(0.50, 0.49, 0.47), "b": Color(0.58, 0.57, 0.54), "c": Color(0.42, 0.41, 0.40), "tile": 1.6, "grout": Color(0.22, 0.21, 0.21), "patch": 0.4, "soft": 0.0},
			"Road": {"a": Color(0.42, 0.34, 0.24), "b": Color(0.50, 0.41, 0.29), "c": Color(0.34, 0.28, 0.20), "tile": 0.0, "patch": 0.5, "soft": 0.5},
		},
		"skins": {
			"HutOrla": {"asset": VILLAGE + "House_2.glb", "fit": "footprint", "fill": 0.95, "max_h": 1.9, "yaw": 45.0},
			"HutBrannoch": {"asset": VILLAGE + "House_1.glb", "fit": "footprint", "fill": 0.95, "max_h": 1.9, "yaw": 45.0},
			"HutIlmar": {"asset": VILLAGE + "House_3.glb", "fit": "footprint", "fill": 0.95, "max_h": 2.4, "yaw": 45.0},
			"Well": {"asset": VILLAGE + "Well.glb", "fit": "width", "width": 2.5, "yaw": 0.0},
			"Workbench": {"asset": VILLAGE + "MarketStand_2.glb", "fit": "footprint", "fill": 1.0, "max_h": 2.3, "yaw": 90.0},
			"Crate": {"asset": VILLAGE + "Crate.glb", "fit": "stretch", "yaw": 15.0},
		},
		"tree_skin": {"assets": _pines(1, 5), "height": [6.5, 8.5]},
		"hide_walls": true,
		"perimeter": [
			{"id": "fence", "sides": ["N", "W", "S", "E"], "assets": [VILLAGE + "Fence.glb"], "step": 2.1, "height": 0.95, "inset": 0.5, "jitter": 0.0, "shadow": true},
			{"id": "wall_bushes", "sides": ["N", "W", "S", "E"], "assets": _n(["Bush_1", "Bush_2", "Rock_1", "Rock_3"]), "step": 2.4, "height": 0.9, "inset": 1.4, "jitter": 0.7, "shadow": false},
		],
		"scatter": [
			{"id": "grass", "assets": _n(["Grass", "Grass_2", "Grass_Short"]), "count": 520, "region": "inside", "inset": 1.2, "height": [0.55, 0.95], "min_dist": 0.7, "cls": "flat", "shadow": false},
			{"id": "flowers", "assets": _n(["Flowers", "Plant_1", "Plant_3"]), "count": 70, "region": "inside", "inset": 1.5, "height": [0.30, 0.5], "min_dist": 1.5, "cls": "flat", "shadow": false},
			{"id": "pebbles", "assets": _n(["Rock_1", "Rock_2", "Rock_5", "Rock_6"]), "count": 46, "region": "inside", "inset": 1.5, "height": [0.22, 0.5], "min_dist": 2.0, "cls": "flat", "shadow": true},
			{"id": "path_rocks", "assets": _n(["Rock_3", "Rock_4", "Rock_7"]), "count": 40, "region": "path_edge", "height": [0.2, 0.42], "min_dist": 1.6, "cls": "flat", "shadow": true},
			{"id": "forest", "assets": _pines(1, 5), "count": 520, "region": "outer", "outer_margin": 40.0, "height": [5.5, 9.0], "min_dist": 3.0, "cls": "tall", "shadow": true},
			{"id": "birch", "assets": _n(["BirchTree_Snow_1", "BirchTree_Snow_2", "BirchTree_Snow_3"]), "count": 60, "region": "outer", "outer_margin": 40.0, "height": [4.5, 6.5], "min_dist": 4.0, "cls": "tall", "shadow": true},
			{"id": "backdrop_houses", "assets": [VILLAGE + "House_1.glb", VILLAGE + "House_2.glb", VILLAGE + "House_3.glb", VILLAGE + "House_4.glb", VILLAGE + "Inn.glb", VILLAGE + "Stable.glb", VILLAGE + "Mill.glb", VILLAGE + "Sawmill.glb", VILLAGE + "Blacksmith.glb"], "count": 26, "region": "outer", "outer_margin": 26.0, "outer_near": 3.0, "height": [4.2, 6.0], "min_dist": 9.0, "cls": "tall", "shadow": true, "face_center": true},
			{"id": "outer_rocks", "assets": _n(["Rock_Moss_1", "Rock_Moss_2", "Rock_Moss_3", "Rock_4", "Rock_5"]), "count": 80, "region": "outer", "outer_margin": 38.0, "outer_near": 1.0, "height": [0.7, 1.8], "min_dist": 3.0, "cls": "low", "shadow": true},
			{"id": "outer_bushes", "assets": _n(["Bush_1", "Bush_2", "Plant_2", "Plant_4"]), "count": 120, "region": "outer", "outer_margin": 34.0, "outer_near": 1.0, "height": [0.8, 1.5], "min_dist": 1.6, "cls": "low", "shadow": false},
			{"id": "stumps", "assets": _n(["TreeStump", "WoodLog", "TreeStump_Moss"]), "count": 18, "region": "outer", "outer_margin": 20.0, "outer_near": 1.0, "height": [0.5, 0.8], "min_dist": 4.0, "cls": "low", "shadow": true},
			{"id": "young_trees", "assets": _pines(1, 5) + _n(["BirchTree_Snow_1", "BirchTree_Snow_2"]), "count": 120, "region": "outer", "outer_margin": 18.0, "outer_near": 1.5, "height": [2.4, 3.8], "min_dist": 2.4, "cls": "tall", "shadow": true},
			{"id": "edge_fill", "assets": _n(["Bush_1", "Bush_2", "Plant_2", "Plant_4", "Rock_Moss_1", "Rock_2", "Flowers"]), "count": 260, "region": "outer", "outer_margin": 14.0, "outer_near": 0.9, "height": [0.6, 1.5], "min_dist": 1.2, "cls": "low", "shadow": true},
		],
		"features": [
			{"id": "plaza_fire", "asset": VILLAGE + "Bonfire_Lit.glb", "pos": Vector3(-5.0, 0.0, 1.5), "height": 0.8, "yaw": 0.0, "shadow": true,
				"light": {"color": Color(1.0, 0.58, 0.26), "energy": 2.6, "range": 11.0, "flame_y": 0.9, "flame_size": 1.5, "flicker": 0.25}},
			{"id": "forge_fire", "asset": VILLAGE + "Bonfire_Lit.glb", "pos": Vector3(8.6, 0.0, -4.2), "height": 0.7, "yaw": 40.0, "shadow": true,
				"light": {"color": Color(1.0, 0.45, 0.18), "energy": 2.2, "range": 8.0, "flame_y": 0.8, "flame_size": 1.3, "flicker": 0.3}},
			{"id": "forge_cauldron", "asset": VILLAGE + "Cauldron.glb", "pos": Vector3(3.7, 0.0, -3.0), "height": 0.9, "yaw": 20.0, "shadow": true},
			{"id": "forge_barrel", "asset": VILLAGE + "Barrel.glb", "pos": Vector3(4.2, 0.0, -2.2), "height": 1.0, "yaw": 0.0, "shadow": true},
			{"id": "lamp_a", "asset": HALLOWEEN + "post_lantern.gltf", "pos": Vector3(-8.2, 0.0, 9.0), "height": 3.3, "yaw": 0.0, "shadow": false,
				"light": {"color": Color(1.0, 0.72, 0.38), "energy": 1.7, "range": 9.0, "flame_y": 2.65, "flame_size": 0.7, "flicker": 0.08}},
			{"id": "lamp_b", "asset": HALLOWEEN + "post_lantern.gltf", "pos": Vector3(8.2, 0.0, 9.0), "height": 3.3, "yaw": 180.0, "shadow": false,
				"light": {"color": Color(1.0, 0.72, 0.38), "energy": 1.7, "range": 9.0, "flame_y": 2.65, "flame_size": 0.7, "flicker": 0.08}},
			{"id": "lamp_c", "asset": HALLOWEEN + "post_lantern.gltf", "pos": Vector3(15.0, 0.0, 3.6), "height": 3.3, "yaw": 0.0, "shadow": false,
				"light": {"color": Color(1.0, 0.72, 0.38), "energy": 1.6, "range": 9.0, "flame_y": 2.65, "flame_size": 0.7, "flicker": 0.08}},
			{"id": "gate_fire", "asset": SURVIVAL + "WoodenTorch_Fire.glb", "pos": Vector3(25.0, 0.0, -3.6), "height": 2.2, "yaw": 0.0, "shadow": false,
				"light": {"color": Color(1.0, 0.6, 0.28), "energy": 1.8, "range": 9.0, "flame_y": 1.95, "flame_size": 0.8, "flicker": 0.25}},
			{"id": "gate_fire2", "asset": SURVIVAL + "WoodenTorch_Fire.glb", "pos": Vector3(25.0, 0.0, 3.6), "height": 2.2, "yaw": 0.0, "shadow": false,
				"light": {"color": Color(1.0, 0.6, 0.28), "energy": 1.8, "range": 9.0, "flame_y": 1.95, "flame_size": 0.8, "flicker": 0.25}},
			{"id": "hay_a", "asset": VILLAGE + "Hay.glb", "pos": Vector3(18.8, 0.0, 12.0), "height": 1.3, "yaw": 30.0, "shadow": true},
			{"id": "cart_a", "asset": VILLAGE + "Cart.glb", "pos": Vector3(-14.0, 0.0, -7.0), "height": 1.5, "yaw": 70.0, "shadow": true},
		],
		"portal": {"post_asset": HALLOWEEN + "pillar.gltf", "post_height": 3.6, "light": Color(0.45, 0.85, 1.0), "light_energy": 1.6, "light_range": 8.0},
	}


# ------------------------------------------------------------------ mata selvagem (azul-esverdeado enevoado)

static func _wild() -> Dictionary:
	return {
		"mood": {
			"sun_color": Color(0.82, 0.92, 0.84), "sun_energy": 1.35, "sun_pitch": -40.0, "sun_yaw": -36.0,
			"ambient_color": Color(0.32, 0.45, 0.50), "ambient_energy": 0.58,
			"sky_top": Color(0.18, 0.30, 0.36), "sky_horizon": Color(0.52, 0.70, 0.68), "sky_ground": Color(0.14, 0.2, 0.2),
			"fog_color": Color(0.40, 0.52, 0.50), "fog_density": 0.0016, "fog_sun_scatter": 0.1,
			"exposure": 0.95, "white": 6.0, "glow_intensity": 0.45, "glow_bloom": 0.08, "glow_threshold": 1.0,
			"saturation": 1.0, "contrast": 1.1, "vol_fog_density": 0.03,
		},
		"ground": {"a": Color(0.09, 0.20, 0.10), "b": Color(0.16, 0.29, 0.14), "c": Color(0.27, 0.21, 0.12), "patch": 0.6, "tile": 0.0, "scale": 0.12},
		"outer": {"margin": 40.0, "a": Color(0.07, 0.15, 0.09), "b": Color(0.12, 0.22, 0.12), "c": Color(0.18, 0.15, 0.10), "patch": 0.5},
		"path_styles": {
			"Trail": {"a": Color(0.33, 0.27, 0.18), "b": Color(0.40, 0.32, 0.21), "c": Color(0.25, 0.20, 0.14), "tile": 0.0, "patch": 0.6, "soft": 0.7},
		},
		"skins": {
			"Log1": {"asset": NATURE + "WoodLog.glb", "fit": "stretch", "yaw": 90.0},
			"Rock1": {"asset": NATURE + "Rock_Moss_3.glb", "fit": "stretch", "yaw": 20.0},
			"Rock2": {"asset": NATURE + "Rock_Moss_1.glb", "fit": "stretch", "yaw": 140.0},
			"DenStone1": {"asset": NATURE + "Rock_Snow_3.glb", "fit": "stretch", "yaw": 10.0},
			"DenStone2": {"asset": NATURE + "Rock_Snow_5.glb", "fit": "stretch", "yaw": 80.0},
			"DenStone3": {"asset": NATURE + "Rock_Snow_6.glb", "fit": "stretch", "yaw": 150.0},
		},
		"tree_skin": {"assets": _pines(1, 5) + _pines(1, 2, true), "height": [7.0, 9.5]},
		"hide_walls": true,
		"perimeter": [
			{"id": "wall_rocks", "sides": ["N", "W", "S", "E"], "assets": _n(["Rock_Moss_1", "Rock_Moss_2", "Rock_Moss_3", "Rock_Moss_4", "Bush_1", "Bush_2", "WoodLog"]), "step": 2.2, "height": 1.0, "inset": 1.2, "jitter": 0.8, "shadow": true},
		],
		"scatter": [
			{"id": "grass", "assets": _n(["Grass", "Grass_2", "Grass_Short", "Plant_5"]), "count": 700, "region": "inside", "inset": 1.2, "height": [0.55, 1.0], "min_dist": 0.7, "cls": "flat", "shadow": false},
			{"id": "ferns", "assets": _n(["Plant_1", "Plant_2", "Plant_3", "Plant_4"]), "count": 170, "region": "inside", "inset": 1.2, "height": [0.4, 0.8], "min_dist": 1.2, "cls": "flat", "shadow": false},
			{"id": "pebbles", "assets": _n(["Rock_Moss_2", "Rock_Moss_4", "Rock_5", "Rock_6"]), "count": 70, "region": "inside", "inset": 1.5, "height": [0.25, 0.6], "min_dist": 2.0, "cls": "flat", "shadow": true},
			{"id": "stumps", "assets": _n(["TreeStump_Moss", "TreeStump", "WoodLog"]), "count": 26, "region": "inside", "inset": 2.0, "height": [0.45, 0.7], "min_dist": 5.0, "cls": "flat", "shadow": true},
			{"id": "path_rocks", "assets": _n(["Rock_Moss_2", "Rock_Moss_4", "Rock_3"]), "count": 70, "region": "path_edge", "height": [0.2, 0.45], "min_dist": 1.6, "cls": "flat", "shadow": true},
			{"id": "forest", "assets": _pines(1, 5) + _pines(1, 3, true), "count": 640, "region": "outer", "outer_margin": 42.0, "height": [6.0, 10.5], "min_dist": 2.6, "cls": "tall", "shadow": true},
			{"id": "dead_trees", "assets": _n(["CommonTree_Dead_1", "CommonTree_Dead_2", "CommonTree_Dead_3", "BirchTree_Dead_Snow_1"]), "count": 70, "region": "outer", "outer_margin": 38.0, "height": [4.5, 6.5], "min_dist": 4.0, "cls": "tall", "shadow": true},
			{"id": "outer_rocks", "assets": _n(["Rock_Moss_1", "Rock_Moss_3", "Rock_Moss_4", "Rock_Snow_1", "Rock_Snow_4"]), "count": 100, "region": "outer", "outer_margin": 40.0, "outer_near": 1.0, "height": [0.9, 2.4], "min_dist": 3.0, "cls": "low", "shadow": true},
			{"id": "outer_bushes", "assets": _n(["Bush_1", "Bush_2", "Plant_2", "Plant_4", "Plant_5"]), "count": 180, "region": "outer", "outer_margin": 36.0, "outer_near": 1.0, "height": [0.8, 1.6], "min_dist": 1.4, "cls": "low", "shadow": false},
			{"id": "young_trees", "assets": _pines(1, 5) + _pines(1, 2, true), "count": 150, "region": "outer", "outer_margin": 18.0, "outer_near": 1.5, "height": [2.6, 4.2], "min_dist": 2.2, "cls": "tall", "shadow": true},
			{"id": "edge_fill", "assets": _n(["Bush_1", "Bush_2", "Plant_2", "Plant_4", "Rock_Moss_1", "Rock_Moss_3", "WoodLog", "TreeStump_Moss"]), "count": 300, "region": "outer", "outer_margin": 14.0, "outer_near": 0.9, "height": [0.6, 1.6], "min_dist": 1.1, "cls": "low", "shadow": true},
			{"id": "bones", "assets": [HALLOWEEN + "skull.gltf", HALLOWEEN + "bone_A.gltf", HALLOWEEN + "bone_B.gltf", HALLOWEEN + "ribcage.gltf"], "count": 10, "region": "den", "height": [0.3, 0.6], "min_dist": 1.5, "cls": "flat", "shadow": true},
		],
		"den": {"center": Vector2(236.0, -31.0), "radius": 10.0},
		"features": [
			{"id": "camp_fire", "asset": SURVIVAL + "Bonfire_Fire.glb", "pos": Vector3(164.0, 0.0, 9.0), "height": 1.0, "yaw": 0.0, "shadow": true,
				"light": {"color": Color(1.0, 0.55, 0.24), "energy": 2.4, "range": 10.0, "flame_y": 0.95, "flame_size": 1.5, "flicker": 0.3}},
			{"id": "camp_log_a", "asset": NATURE + "WoodLog.glb", "pos": Vector3(166.0, 0.0, 11.0), "height": 0.6, "yaw": 110.0, "shadow": true},
			{"id": "camp_tent", "asset": SURVIVAL + "Tent.glb", "pos": Vector3(160.0, 0.0, 12.0), "height": 2.6, "yaw": 20.0, "shadow": true},
			{"id": "den_torch_a", "asset": SURVIVAL + "WoodenTorch_Fire.glb", "pos": Vector3(233.0, 0.0, -22.0), "height": 2.4, "yaw": 0.0, "shadow": false,
				"light": {"color": Color(0.75, 0.9, 1.0), "energy": 1.3, "range": 9.0, "flame_y": 2.1, "flame_size": 0.9, "flicker": 0.2}},
			{"id": "den_torch_b", "asset": SURVIVAL + "WoodenTorch_Fire.glb", "pos": Vector3(240.0, 0.0, -22.0), "height": 2.4, "yaw": 0.0, "shadow": false,
				"light": {"color": Color(0.75, 0.9, 1.0), "energy": 1.3, "range": 9.0, "flame_y": 2.1, "flame_size": 0.9, "flicker": 0.2}},
			{"id": "gate_fire", "asset": SURVIVAL + "WoodenTorch_Fire.glb", "pos": Vector3(244.0, 0.0, -3.8), "height": 2.4, "yaw": 0.0, "shadow": false,
				"light": {"color": Color(1.0, 0.62, 0.3), "energy": 1.6, "range": 9.0, "flame_y": 2.1, "flame_size": 0.9, "flicker": 0.25}},
			{"id": "gate_fire2", "asset": SURVIVAL + "WoodenTorch_Fire.glb", "pos": Vector3(244.0, 0.0, 3.8), "height": 2.4, "yaw": 0.0, "shadow": false,
				"light": {"color": Color(1.0, 0.62, 0.3), "energy": 1.6, "range": 9.0, "flame_y": 2.1, "flame_size": 0.9, "flicker": 0.25}},
		],
		"portal": {"post_asset": HALLOWEEN + "pillar.gltf", "post_height": 3.8, "light": Color(0.45, 0.85, 1.0), "light_energy": 1.6, "light_range": 8.0},
	}


# ------------------------------------------------------------------ ruinas (fria, escura, tochas; chefe dramatico)

static func _ruins() -> Dictionary:
	var wall_mix: Array = [DUNGEON + "wall.glb", DUNGEON + "wall.glb", DUNGEON + "wall_cracked.glb", DUNGEON + "wall_broken.glb", DUNGEON + "wall_arched.glb", DUNGEON + "wall_pillar.glb"]
	var low_mix: Array = [DUNGEON + "barrier.glb", DUNGEON + "barrier.glb", DUNGEON + "barrier_column.glb", DUNGEON + "rubble_half.glb"]
	var torch: Dictionary = {"color": Color(1.0, 0.58, 0.26), "energy": 3.0, "range": 11.0, "flame_y": 0.62, "flame_size": 0.7, "flicker": 0.3}
	var torch_stand: Dictionary = {"color": Color(1.0, 0.58, 0.26), "energy": 2.8, "range": 10.5, "flame_y": 0.78, "flame_size": 0.7, "flicker": 0.3}
	var feats: Array = []
	# tochas na muralha norte (voltada para dentro: +z) e oeste
	var i: int = 0
	for x: float in [366.0, 380.0, 408.0, 424.0, 438.0]:
		feats.append({"id": "torch_n%d" % i, "asset": DUNGEON + "torch_mounted.glb", "pos": Vector3(x, 0.0, -29.0), "elev": 2.2, "height": 1.05, "yaw": 0.0, "shadow": false, "light": torch})
		i += 1
	feats.append({"id": "torch_w0", "asset": DUNGEON + "torch_mounted.glb", "pos": Vector3(356.0, 0.0, -9.0), "elev": 2.2, "height": 1.05, "yaw": 90.0, "shadow": false, "light": torch})
	feats.append({"id": "torch_w1", "asset": DUNGEON + "torch_mounted.glb", "pos": Vector3(356.0, 0.0, 9.0), "elev": 2.2, "height": 1.05, "yaw": 90.0, "shadow": false, "light": torch})
	# tochas em pe: antecamara (pilares), portao, salao e altar
	var stand: Array = [Vector3(370.0, 0.0, -3.8), Vector3(370.0, 0.0, 3.8), Vector3(385.0, 0.0, -3.8), Vector3(385.0, 0.0, 3.8),
		Vector3(392.2, 0.0, -4.4), Vector3(392.2, 0.0, 4.4), Vector3(412.5, 0.0, -9.5), Vector3(412.5, 0.0, 9.5),
		Vector3(427.5, 0.0, -9.5), Vector3(427.5, 0.0, 9.5), Vector3(438.0, 0.0, -4.0), Vector3(438.0, 0.0, 4.0)]
	i = 0
	for p: Vector3 in stand:
		feats.append({"id": "torch_s%d" % i, "asset": DUNGEON + "torch_lit.glb", "pos": p, "height": 1.7, "yaw": 0.0, "shadow": false, "light": torch_stand})
		i += 1
	feats.append({"id": "altar_glow", "asset": HALLOWEEN + "shrine_candles.gltf", "pos": Vector3(443.0, 0.0, 0.0), "height": 1.8, "yaw": 270.0, "shadow": false,
		"light": {"color": Color(0.7, 0.35, 1.0), "energy": 2.6, "range": 12.0, "flame_y": 1.6, "flame_size": 1.2, "flicker": 0.12}})
	feats.append({"id": "boss_brazier_a", "asset": SURVIVAL + "Bonfire_Fire.glb", "pos": Vector3(420.0, 0.0, -9.0), "height": 1.1, "yaw": 0.0, "shadow": false,
		"light": {"color": Color(1.0, 0.32, 0.12), "energy": 2.8, "range": 12.0, "flame_y": 1.05, "flame_size": 1.6, "flicker": 0.35}})
	feats.append({"id": "boss_brazier_b", "asset": SURVIVAL + "Bonfire_Fire.glb", "pos": Vector3(420.0, 0.0, 9.0), "height": 1.1, "yaw": 0.0, "shadow": false,
		"light": {"color": Color(1.0, 0.32, 0.12), "energy": 2.8, "range": 12.0, "flame_y": 1.05, "flame_size": 1.6, "flicker": 0.35}})
	feats.append({"id": "skulls_a", "asset": HALLOWEEN + "skull.gltf", "pos": Vector3(436.0, 0.0, -5.5), "height": 0.45, "yaw": 40.0, "shadow": true})
	feats.append({"id": "bones_a", "asset": HALLOWEEN + "ribcage.gltf", "pos": Vector3(429.5, 0.0, 6.0), "height": 0.8, "yaw": 120.0, "shadow": true})
	return {
		"mood": {
			"sun_color": Color(0.55, 0.68, 0.95), "sun_energy": 0.85, "sun_pitch": -52.0, "sun_yaw": -20.0,
			"ambient_color": Color(0.24, 0.30, 0.46), "ambient_energy": 0.8,
			"sky_top": Color(0.05, 0.07, 0.14), "sky_horizon": Color(0.14, 0.18, 0.30), "sky_ground": Color(0.06, 0.07, 0.10),
			"fog_color": Color(0.12, 0.16, 0.26), "fog_density": 0.0018, "fog_sun_scatter": 0.0,
			"exposure": 1.08, "white": 5.5, "glow_intensity": 0.7, "glow_bloom": 0.14, "glow_threshold": 0.9,
			"saturation": 1.0, "contrast": 1.1, "vol_fog_density": 0.035,
		},
		# antecamara (x < 395) usa o humor base; o salao do chefe (x >= 395) e dramatico: vermelho-ambar por baixo, ceu quase preto
		"regions": [
			{"id": "boss_hall", "rect": Rect2(395.0, -30.0, 50.0, 60.0), "mood": {
				"sun_color": Color(0.80, 0.56, 0.50), "sun_energy": 0.7, "sun_pitch": -38.0, "sun_yaw": 50.0,
				"ambient_color": Color(0.30, 0.24, 0.36), "ambient_energy": 0.78,
				"fog_color": Color(0.20, 0.09, 0.12), "fog_density": 0.0022,
				"exposure": 1.05, "glow_intensity": 0.8, "saturation": 0.95, "contrast": 1.12}},
		],
		"ground": {"a": Color(0.20, 0.22, 0.28), "b": Color(0.27, 0.29, 0.35), "c": Color(0.13, 0.14, 0.19), "patch": 0.5, "tile": 0.0, "scale": 0.2},
		"outer": {"margin": 40.0, "a": Color(0.10, 0.11, 0.15), "b": Color(0.14, 0.15, 0.20), "c": Color(0.06, 0.07, 0.10), "patch": 0.4},
		"path_styles": {
			"HallFloor": {"a": Color(0.36, 0.37, 0.45), "b": Color(0.44, 0.45, 0.53), "c": Color(0.27, 0.28, 0.35), "tile": 2.0, "grout": Color(0.14, 0.14, 0.18), "patch": 0.5, "soft": 0.0},
			"AnteFloor": {"a": Color(0.36, 0.37, 0.45), "b": Color(0.44, 0.45, 0.53), "c": Color(0.27, 0.28, 0.35), "tile": 2.0, "grout": Color(0.14, 0.14, 0.18), "patch": 0.5, "soft": 0.0},
		},
		"skins": {
			"DividerN": {"asset": DUNGEON + "wall.glb", "fit": "wall_run", "yaw": 90.0, "pieces": [DUNGEON + "wall.glb", DUNGEON + "wall_cracked.glb", DUNGEON + "wall.glb", DUNGEON + "wall_broken.glb", DUNGEON + "wall_pillar.glb"]},
			"DividerS": {"asset": DUNGEON + "wall.glb", "fit": "wall_run", "yaw": 90.0, "pieces": [DUNGEON + "wall.glb", DUNGEON + "wall_pillar.glb", DUNGEON + "wall_cracked.glb", DUNGEON + "wall.glb", DUNGEON + "wall_broken.glb"]},
			"PuzzleGate": {"asset": DUNGEON + "wall_gated.glb", "fit": "stretch", "yaw": 90.0},
			"Pillar": {"asset": DUNGEON + "pillar.glb", "fit": "stretch", "yaw": 0.0},
			"HallColumn": {"asset": DUNGEON + "pillar_decorated.glb", "fit": "stretch", "yaw": 0.0},
			"Rubble1": {"asset": DUNGEON + "rubble_half.glb", "fit": "stretch", "yaw": 0.0},
			"Rubble2": {"asset": DUNGEON + "rubble_large.glb", "fit": "stretch", "yaw": 90.0},
			"Altar": {"asset": HALLOWEEN + "coffin.gltf", "fit": "stretch", "yaw": 90.0},
		},
		"tree_skin": {"assets": [HALLOWEEN + "tree_dead_large.gltf"], "height": [5.0, 6.0]},
		"hide_walls": true,
		"perimeter": [
			{"id": "wall_far", "sides": ["N", "W"], "assets": wall_mix, "step": 4.0, "height": 4.0, "inset": 0.5, "jitter": 0.0, "shadow": true, "cls": "tall"},
			{"id": "wall_near", "sides": ["S", "E"], "assets": low_mix, "step": 4.0, "height": 1.1, "inset": 0.5, "jitter": 0.0, "shadow": true, "cls": "flat"},
		],
		"scatter": [
			{"id": "tiles", "assets": [DUNGEON + "floor_tile_small_broken_A.glb", DUNGEON + "floor_tile_small_broken_B.glb", DUNGEON + "floor_tile_small_weeds_A.glb", DUNGEON + "floor_tile_small_weeds_B.glb", DUNGEON + "floor_dirt_small_weeds.glb"], "count": 60, "region": "inside", "inset": 2.0, "height": [0.12, 0.2], "min_dist": 3.0, "cls": "flat", "shadow": false, "flat_tile": true},
			{"id": "weeds", "assets": _n(["Grass_Short", "Grass_2", "Plant_5"]), "count": 130, "region": "inside", "inset": 1.5, "height": [0.3, 0.55], "min_dist": 0.9, "cls": "flat", "shadow": false},
			{"id": "rubble", "assets": [DUNGEON + "rubble_half.glb", DUNGEON + "rubble_large.glb", DUNGEON + "trunk_small_A.glb", DUNGEON + "trunk_medium_B.glb"], "count": 18, "region": "inside", "inset": 2.5, "height": [0.4, 0.9], "min_dist": 4.0, "cls": "flat", "shadow": true},
			{"id": "bones", "assets": [HALLOWEEN + "skull.gltf", HALLOWEEN + "bone_A.gltf", HALLOWEEN + "bone_B.gltf", HALLOWEEN + "bone_C.gltf"], "count": 22, "region": "inside", "inset": 2.0, "height": [0.25, 0.5], "min_dist": 2.5, "cls": "flat", "shadow": true},
			{"id": "graves", "assets": [HALLOWEEN + "gravemarker_A.gltf", HALLOWEEN + "gravemarker_B.gltf", HALLOWEEN + "gravestone.gltf"], "count": 26, "region": "outer", "outer_margin": 22.0, "outer_near": 2.0, "height": [0.9, 1.5], "min_dist": 3.0, "cls": "low", "shadow": true},
			{"id": "dead_forest", "assets": [HALLOWEEN + "tree_dead_large.gltf", HALLOWEEN + "tree_dead_medium.gltf"] + _n(["CommonTree_Dead_Snow_1", "CommonTree_Dead_Snow_2", "CommonTree_Dead_Snow_3"]), "count": 150, "region": "outer", "outer_margin": 40.0, "height": [4.5, 8.0], "min_dist": 3.2, "cls": "tall", "shadow": true},
			{"id": "pines", "assets": _pines(1, 3, true), "count": 160, "region": "outer", "outer_margin": 42.0, "outer_near": 8.0, "height": [6.0, 10.0], "min_dist": 3.0, "cls": "tall", "shadow": true},
			{"id": "outer_rocks", "assets": _n(["Rock_Snow_1", "Rock_Snow_2", "Rock_Snow_3", "Rock_Snow_5", "Rock_Snow_6", "Rock_Snow_7"]), "count": 110, "region": "outer", "outer_margin": 40.0, "outer_near": 1.0, "height": [1.0, 3.0], "min_dist": 3.0, "cls": "low", "shadow": true},
			{"id": "outer_ruins", "assets": [DUNGEON + "wall_broken.glb", DUNGEON + "wall_cracked.glb", DUNGEON + "pillar.glb", DUNGEON + "pillar_decorated.glb", HALLOWEEN + "arch.gltf", HALLOWEEN + "crypt.gltf"], "count": 12, "region": "outer", "outer_margin": 24.0, "outer_near": 4.0, "height": [3.5, 5.5], "min_dist": 8.0, "cls": "tall", "shadow": true, "face_center": true},
		],
		"features": feats,
		"portal": {"post_asset": HALLOWEEN + "pillar.gltf", "post_height": 3.6, "light": Color(0.45, 0.85, 1.0), "light_energy": 1.5, "light_range": 8.0},
	}
