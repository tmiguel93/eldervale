class_name InteractTarget
extends RefCounted
## E5.5: alvo de interacao mais proximo (NPC ou estacao de crafting) para o prompt da tecla `interact`.
## Usa os MESMOS dados do servidor (NpcDirectory/ZoneDef) so para decidir o que mostrar; quem valida a
## distancia de verdade e o servidor (too_far).

const MAX_DY: float = 6.0


## Devolve {} ou {kind: "npc"|"station", id, name, dist, radius}. `zone` null (arena): considera todos os NPCs.
static func find(pos: Vector3, zone: ZoneDef, npcs: NpcDirectory) -> Dictionary:
	var best: Dictionary = {}
	var npc_ids: Array[String] = zone.npcs if zone != null else npcs.ids()
	for nid: String in npc_ids:
		var n: Dictionary = npcs.get_npc(nid)
		if n.is_empty() or String(n.get("dialogue_id", "")).is_empty():
			continue
		var p: Vector3 = n["position"]
		var d: float = Vector2(pos.x - p.x, pos.z - p.z).length()
		if d <= float(n["radius"]) and absf(pos.y - p.y) <= MAX_DY and (best.is_empty() or d < float(best["dist"])):
			best = {"kind": "npc", "id": nid, "name": UiText.npc_name(nid), "dist": d, "radius": float(n["radius"])}
	if zone != null:
		for st: Dictionary in zone.stations:
			var sp: Vector3 = st["pos"]
			var sd: float = Vector2(pos.x - sp.x, pos.z - sp.z).length()
			if sd <= float(st["radius"]) and (best.is_empty() or sd < float(best["dist"])):
				best = {"kind": "station", "id": String(st["id"]), "name": String(st["display_name"]), "dist": sd, "radius": float(st["radius"])}
	return best


static func prompt_text(target: Dictionary) -> String:
	if target.is_empty():
		return ""
	return ("[F] Falar com %s" if String(target["kind"]) == "npc" else "[F] Usar %s") % String(target["name"])
