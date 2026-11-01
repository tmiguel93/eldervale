class_name WorldDef
extends RefCounted
## Mundo de uma regiao (E5.3), carregado de data/areas/world/<regiao>_world.json: zonas conectadas por
## portais, spawns, puzzle e encontro de chefe. Dados puros; o servidor (WorldDirector) e o cliente
## (WorldBuilder) leem o MESMO arquivo. Coordenadas em MUNDO (zonas em posicoes distintas do mesmo espaco).

const WORLD_DIR: String = "res://data/areas/world"
const DEFAULT_REGION: String = "greenwood"
const MIN_ZONE_GAP: float = 20.0

static var _shared: Dictionary = {}

var region: String = ""
var start_zone: String = ""
var respawn_delay: float = 3.0
var transition_time: float = 0.6
var unload_grace: float = 12.0
var portal_lock: float = 1.5
var zones: Dictionary = {}           ## id -> ZoneDef
var zone_order: Array[String] = []
var load_errors: Array[String] = []


static func shared(region_id: String = DEFAULT_REGION) -> WorldDef:
	if not _shared.has(region_id):
		_shared[region_id] = load_region(region_id)
	return _shared[region_id] as WorldDef


static func load_region(region_id: String) -> WorldDef:
	var w: WorldDef = WorldDef.new()
	if not Protocol.is_content_id(region_id):
		w.load_errors.append("regiao invalida")
		return w
	var r: Dictionary = JsonDir.read_json("%s/%s_world.json" % [WORLD_DIR, region_id])
	if not bool(r["ok"]):
		w.load_errors.append(String(r["error"]))
		return w
	var err: String = w.parse(r["data"])
	if not err.is_empty():
		w.load_errors.append(err)
	return w


## Devolve "" ou o primeiro erro de estrutura (as referencias cruzadas ficam em `validate`).
func parse(raw: Variant) -> String:
	if typeof(raw) != TYPE_DICTIONARY:
		return "raiz deve ser objeto"
	var d: Dictionary = raw
	region = String(d.get("region", ""))
	start_zone = String(d.get("start_zone", ""))
	var st: Variant = d.get("settings", {})
	if typeof(st) == TYPE_DICTIONARY:
		respawn_delay = clampf(float((st as Dictionary).get("respawn_delay", respawn_delay)), 0.5, 30.0)
		transition_time = clampf(float((st as Dictionary).get("transition_time", transition_time)), 0.0, 5.0)
		unload_grace = clampf(float((st as Dictionary).get("unload_grace", unload_grace)), 0.0, 300.0)
		portal_lock = clampf(float((st as Dictionary).get("portal_lock", portal_lock)), 0.2, 10.0)
	var zs: Variant = d.get("zones", null)
	if typeof(zs) != TYPE_ARRAY or (zs as Array).is_empty() or (zs as Array).size() > 16:
		return "zones deve ser lista (1..16)"
	for raw_zone: Variant in zs:
		var z: ZoneDef = ZoneDef.new()
		var err: String = z.parse(raw_zone)
		if not err.is_empty():
			return err
		if zones.has(z.id):
			return "zona duplicada: " + z.id
		zones[z.id] = z
		zone_order.append(z.id)
	if not zones.has(start_zone):
		return "start_zone inexistente: " + start_zone
	return ""


func has_zone(zone_id: String) -> bool:
	return zones.has(zone_id)


func get_zone(zone_id: String) -> ZoneDef:
	return zones.get(zone_id) as ZoneDef


## Zona cujo retangulo contem `pos` ("" se nenhuma).
func zone_id_at(pos: Vector3) -> String:
	for id: String in zone_order:
		if (zones[id] as ZoneDef).contains(pos):
			return id
	return ""


## Referencias cruzadas e regras de jogabilidade. Lista vazia = valido.
func validate(npcs: NpcDirectory, areas: AreaSet, quest_area_ids: Array[String] = []) -> Array[String]:
	var errs: Array[String] = load_errors.duplicate()
	for id: String in zone_order:
		var z: ZoneDef = zones[id]
		for p: Dictionary in z.portals:
			var dest: ZoneDef = get_zone(String(p["to_zone"]))
			if dest == null:
				errs.append("%s: portal %s aponta para zona inexistente %s" % [id, p["id"], p["to_zone"]])
				continue
			if not dest.spawns.has(String(p["to_spawn"])):
				errs.append("%s: portal %s: spawn '%s' inexistente em %s" % [id, p["id"], p["to_spawn"], dest.id])
			if not z.contains(p["pos"] as Vector3):
				errs.append("%s: portal %s fora da zona" % [id, p["id"]])
		for name: String in z.spawn_names():
			for sp: Vector3 in (z.spawns[name] as Array):
				if not z.contains(sp, -1.0):
					errs.append("%s: spawn '%s' fora da zona" % [id, name])
				for p2: Dictionary in z.portals:  # anti-loop: nunca nascer dentro de um portal (+1 m de folga)
					if Vector2(sp.x - (p2["pos"] as Vector3).x, sp.z - (p2["pos"] as Vector3).z).length() <= float(p2["radius"]) + 1.0:
						errs.append("%s: spawn '%s' dentro do raio do portal %s" % [id, name, p2["id"]])
		for e: Dictionary in z.enemies:
			if not EnemyCatalog.all_ids().has(e["type"]) or EnemyCatalog.data_for(e["type"]) == null:
				errs.append("%s: tipo de inimigo desconhecido %s" % [id, e["type"]])
			if not z.contains(e["pos"] as Vector3, -1.0):
				errs.append("%s: inimigo %s fora da zona" % [id, e["type"]])
		for n: String in z.npcs:
			if npcs == null or not npcs.has_npc(n):
				errs.append("%s: NPC inexistente %s" % [id, n])
			elif not z.contains((npcs.get_npc(n)["position"] as Vector3), -1.0):
				errs.append("%s: NPC %s fora da zona" % [id, n])
		if not z.puzzle.is_empty():
			for pl: Dictionary in z.puzzle["plates"]:
				if not z.contains(pl["pos"] as Vector3, -1.0):
					errs.append("%s: placa fora da zona" % id)
		if not z.encounter.is_empty():
			var boss: StringName = z.encounter["boss"]
			if not EnemyCatalog.all_ids().has(boss) or EnemyCatalog.data_for(boss) == null:
				errs.append("%s: chefe desconhecido %s" % [id, boss])
			if not z.contains(z.encounter["spawn"] as Vector3, -1.0) or not z.contains(z.encounter["trigger_center"] as Vector3, -1.0):
				errs.append("%s: encontro fora da zona" % id)
	# zonas nao se sobrepoem (zone_id_at e unico) e ficam separadas por >= MIN_ZONE_GAP
	for i: int in zone_order.size():
		for j: int in range(i + 1, zone_order.size()):
			var a: ZoneDef = zones[zone_order[i]]
			var b: ZoneDef = zones[zone_order[j]]
			var gap_x: float = absf(a.center.x - b.center.x) - (a.size.x + b.size.x) * 0.5
			var gap_z: float = absf(a.center.z - b.center.z) - (a.size.y + b.size.y) * 0.5
			if maxf(gap_x, gap_z) < MIN_ZONE_GAP:
				errs.append("zonas %s e %s muito proximas (< %.0f m)" % [a.id, b.id, MIN_ZONE_GAP])
	# conectividade: toda zona alcanca o start e e alcancada por ele (sem zona-armadilha)
	var from_start: Dictionary = _reach(start_zone, false)
	var to_start: Dictionary = _reach(start_zone, true)
	for id: String in zone_order:
		if not from_start.has(id):
			errs.append("zona %s inalcancavel a partir de %s" % [id, start_zone])
		if not to_start.has(id):
			errs.append("zona %s nao tem caminho de volta a %s" % [id, start_zone])
	# NPCs e areas de quest em coordenadas reais, dentro de alguma zona
	if npcs != null:
		for n: String in npcs.ids():
			if (npcs.get_npc(n)["region"] as String) == region and zone_id_at(npcs.get_npc(n)["position"] as Vector3).is_empty():
				errs.append("NPC %s fora de qualquer zona" % n)
	if areas != null:
		for a_id: String in (quest_area_ids if not quest_area_ids.is_empty() else areas.ids()):
			var a: Dictionary = areas.areas.get(a_id, {})
			if not a.is_empty() and zone_id_at(a["center"] as Vector3).is_empty():
				errs.append("area %s fora de qualquer zona" % a_id)
	return errs


## Zonas alcancaveis por portais a partir de `origin` (reverse = grafo invertido).
func _reach(origin: String, reverse: bool) -> Dictionary:
	var seen: Dictionary = {}
	var stack: Array[String] = [origin]
	while not stack.is_empty():
		var cur: String = stack.pop_back()
		if seen.has(cur) or not zones.has(cur):
			continue
		seen[cur] = true
		for id: String in zone_order:
			var z: ZoneDef = zones[id]
			for p: Dictionary in z.portals:
				if not reverse and id == cur:
					stack.append(String(p["to_zone"]))
				elif reverse and String(p["to_zone"]) == cur:
					stack.append(id)
	return seen
