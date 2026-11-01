class_name MapView
extends Control
## E5.5: minimapa (canto) e mapa grande (M). Desenha a zona atual (retangulo dos dados de mundo), portais, NPCs,
## estacoes e entidades do snapshot (jogadores, inimigos proximos, pickups proprios). Apresentacao pura.
## MINI: janela de MINI_RADIUS m centrada no jogador, girada pelo yaw da camera (cima = frente da camera).
## FULL: zona inteira, norte (-Z) para cima. `build_draw_list()` e pura e testavel; `_draw` so a renderiza.

enum Mode { MINI, FULL }

const MINI_RADIUS: float = 36.0
const COL_BG: Color = Color(0.05, 0.06, 0.08, 0.85)
const COL_ZONE: Color = Color(0.2, 0.28, 0.2, 0.9)
const COL_PORTAL: Color = Color(0.4, 0.85, 1.0)
const COL_NPC: Color = Color(1.0, 0.9, 0.3)
const COL_STATION: Color = Color(1.0, 0.6, 0.2)
const COL_PLAYER: Color = Color(0.4, 0.95, 0.5)
const COL_LOCAL: Color = Color(1.0, 1.0, 1.0)
const COL_ENEMY: Color = Color(0.95, 0.3, 0.25)
const COL_BOSS: Color = Color(1.0, 0.5, 0.1)
const COL_PICKUP: Color = Color(1.0, 0.85, 0.2)

var mode: Mode = Mode.MINI
var zone: ZoneDef = null
var local_id: int = -1
var local_pos: Vector3 = Vector3.ZERO
var has_local: bool = false
var entities: Array = []
var view_yaw: float = PI * 0.25
var npcs: NpcDirectory = null
var show_labels: bool = false


func _init(p_mode: Mode = Mode.MINI, p_size: Vector2 = Vector2(168, 168)) -> void:
	mode = p_mode
	custom_minimum_size = p_size
	size = p_size
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	show_labels = mode == Mode.FULL
	npcs = NpcDirectory.shared()


func set_state(p_zone: ZoneDef, p_local_id: int, p_local_pos: Variant, p_entities: Array, p_view_yaw: float) -> void:
	zone = p_zone
	local_id = p_local_id
	has_local = p_local_pos is Vector3
	if has_local:
		local_pos = p_local_pos
	entities = p_entities
	if is_finite(p_view_yaw):
		view_yaw = p_view_yaw
	queue_redraw()


## Mundo -> tela. MINI: relativo ao jogador, rotacionado pelo yaw da camera. FULL: zona inteira, -Z para cima.
func project(p: Vector3) -> Vector2:
	var half: Vector2 = size * 0.5
	if mode == Mode.MINI:
		var scale: float = minf(size.x, size.y) * 0.5 / MINI_RADIUS
		var d: Vector3 = p - local_pos
		var fwd: Vector3 = PlayerMotion.world_direction(Vector2(0.0, 1.0), view_yaw)
		var right: Vector3 = PlayerMotion.world_direction(Vector2(1.0, 0.0), view_yaw)
		return half + Vector2(d.dot(right), -d.dot(fwd)) * scale
	var zsize: Vector2 = zone.size if zone != null else Vector2(60.0, 60.0)
	var zc: Vector3 = zone.center if zone != null else Vector3.ZERO
	var s: float = minf(size.x / zsize.x, size.y / zsize.y) * 0.9
	return half + Vector2(p.x - zc.x, p.z - zc.z) * s


func _inside(sp: Vector2, margin: float = 3.0) -> bool:
	return sp.x >= margin and sp.y >= margin and sp.x <= size.x - margin and sp.y <= size.y - margin


## Lista de primitivas: {type: zone|portal|npc|station|player|local|enemy|boss|pickup, pos: Vector2 (tela),
## label?, points? (zone)}. Itens fora da janela do minimapa sao omitidos (a zona e sempre desenhada).
func build_draw_list() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if zone != null:
		var c: Vector3 = zone.center
		var hx: float = zone.size.x * 0.5
		var hz: float = zone.size.y * 0.5
		var pts: PackedVector2Array = PackedVector2Array([
			project(Vector3(c.x - hx, 0, c.z - hz)), project(Vector3(c.x + hx, 0, c.z - hz)),
			project(Vector3(c.x + hx, 0, c.z + hz)), project(Vector3(c.x - hx, 0, c.z + hz))])
		out.append({"type": "zone", "points": pts, "pos": project(c)})
		for p: Dictionary in zone.portals:
			var sp: Vector2 = project(p["pos"])
			if mode == Mode.FULL or _inside(sp):
				out.append({"type": "portal", "pos": sp, "label": String(p.get("label", ""))})
		for st: Dictionary in zone.stations:
			var ss: Vector2 = project(st["pos"])
			if mode == Mode.FULL or _inside(ss):
				out.append({"type": "station", "pos": ss, "label": String(st.get("display_name", ""))})
		for nid: String in zone.npcs:
			var n: Dictionary = npcs.get_npc(nid) if npcs != null else {}
			if n.is_empty():
				continue
			var sn: Vector2 = project(n["position"])
			if mode == Mode.FULL or _inside(sn):
				out.append({"type": "npc", "pos": sn, "label": UiText.npc_name(nid)})
	for e0: Variant in entities:
		if typeof(e0) != TYPE_DICTIONARY or not ((e0 as Dictionary).get("pos") is Vector3):
			continue
		var e: Dictionary = e0
		var se: Vector2 = project(e["pos"])
		if not (mode == Mode.FULL or _inside(se)):
			continue
		var kind: int = int(e.get("kind", 0))
		if kind == Protocol.KIND_PLAYER:
			if int(e["id"]) == local_id:
				continue  # o local e desenhado por ultimo, por cima
			out.append({"type": "player", "pos": se, "label": ""})
		elif kind == Protocol.KIND_ENEMY:
			if float(e.get("hp", 0.0)) <= 0.0:
				continue
			var data: EnemyData = EnemyCatalog.data_for(StringName(String(e.get("type", ""))))
			out.append({"type": "boss" if (data != null and data.is_boss()) else "enemy", "pos": se, "label": ""})
		elif kind == Protocol.KIND_PICKUP:
			out.append({"type": "pickup", "pos": se, "label": ""})
	if has_local:
		out.append({"type": "local", "pos": project(local_pos), "label": ""})
	return out


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), COL_BG)
	var font: Font = ThemeDB.fallback_font
	for it: Dictionary in build_draw_list():
		var p: Vector2 = it["pos"]
		match String(it["type"]):
			"zone":
				draw_colored_polygon(it["points"] as PackedVector2Array, COL_ZONE)
				var pts: PackedVector2Array = it["points"]
				for i: int in pts.size():
					draw_line(pts[i], pts[(i + 1) % pts.size()], UiStyle.BORDER, 1.5)
			"portal":
				draw_circle(p, 5.0, COL_PORTAL)
				draw_arc(p, 7.0, 0.0, TAU, 16, COL_PORTAL, 1.0)
			"station":
				draw_rect(Rect2(p - Vector2(4, 4), Vector2(8, 8)), COL_STATION)
			"npc":
				draw_circle(p, 4.0, COL_NPC)
			"player":
				draw_circle(p, 3.5, COL_PLAYER)
			"enemy":
				draw_circle(p, 2.5, COL_ENEMY)
			"boss":
				draw_circle(p, 5.0, COL_BOSS)
			"pickup":
				draw_rect(Rect2(p - Vector2(2, 2), Vector2(4, 4)), COL_PICKUP)
			"local":
				draw_circle(p, 4.5, COL_LOCAL)
				draw_arc(p, 6.5, 0.0, TAU, 16, UiStyle.INFO, 1.5)
		if show_labels and not String(it.get("label", "")).is_empty():
			draw_string(font, p + Vector2(8, 4), String(it["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UiStyle.TEXT)
