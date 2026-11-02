extends RefCounted
## Ajudantes dos testes do E8.1 (sem prefixo test_: o runner nao o executa como teste).

## Todos os (rotulo, VisualSpec) referenciados por dados: 10 inimigos, 3 classes, 6 NPCs.
static func all_specs() -> Array:
	var out: Array = []
	for id: StringName in EnemyCatalog.all_ids():
		var ed: EnemyData = EnemyCatalog.data_for(id)
		out.append(["enemy:" + String(id), ed.visual_spec() if ed != null else null])
	var cc: ClassCatalog = ClassCatalog.shared()
	for cid: String in cc.ids():
		out.append(["class:" + cid, cc.get_def(cid).visual])
	var nd: NpcDirectory = NpcDirectory.shared()
	for nid: String in nd.ids():
		out.append(["npc:" + nid, nd.get_npc(nid).get("visual")])
	return out


## Nomes de clip do AnimationPlayer de um rig recem-montado.
static func clips_of(rig: ModelRig) -> PackedStringArray:
	return rig.anim.get_animation_list() if rig.anim != null else PackedStringArray()


## Amostra de snapshot (formato do interpolador).
static func sample(kind: int, type: String, state: int, pos: Vector3 = Vector3.ZERO, extra: Dictionary = {}) -> Dictionary:
	var d: Dictionary = {"pos": pos, "yaw": 0.0, "hp": 10.0, "max_hp": 10.0, "state": state, "type": type, "kind": kind, "phase": 0, "atk": "", "qty": 0, "extrapolated": false}
	d.merge(extra, true)
	return d
