class_name VisualSpec
extends RefCounted
## E8.1: descricao de apresentacao 3D de uma entidade (classe, inimigo ou NPC). SO dados + validacao, sem carregar
## nada: o servidor pode ler isto sem tocar em assets. Campos (mesmos nomes no .tres do inimigo e no JSON de classe/NPC):
##  visual_scene (alias|id de asset|res://assets/third_party/...glb), visual_height (m), visual_tint ([r,g,b] 0..1 no JSON),
##  visual_yaw_offset (graus), visual_clips ({estado: clip}), visual_equip ([nomes de mesh]), visual_placeholder (bool).
## Ver docs/E8_MODELS.md.

const KEYS: Array[String] = ["visual_scene", "visual_height", "visual_tint", "visual_yaw_offset", "visual_clips", "visual_equip", "visual_placeholder"]
const MIN_HEIGHT: float = 0.1
const MAX_HEIGHT: float = 12.0
const MAX_EQUIP: int = 16
const MAX_NAME: int = 64
const ASSET_PREFIX: String = "res://assets/third_party/"

var scene: String = ""
var height: float = 1.8
var tint: Color = Color(1.0, 1.0, 1.0, 0.0) ## alpha 0 = sem tintura
var yaw_offset_deg: float = 0.0
var clips: Dictionary = {}                  ## String(estado) -> String(clip)
var equip: PackedStringArray = PackedStringArray()
var placeholder: bool = false


func has_tint() -> bool:
	return tint.a > 0.0


## Caminho res:// do modelo ("" se o alias nao existe no manifest).
func resolved_path() -> String:
	return AssetAliases.resolve(scene)


static func is_valid_scene_ref(ref: String) -> bool:
	if ref.is_empty() or ref.length() > 200 or ref.contains(".."):
		return false
	if ref.begins_with("res://"):
		return ref.begins_with(ASSET_PREFIX) and (ref.ends_with(".glb") or ref.ends_with(".gltf"))
	var re: RegEx = RegEx.new()
	re.compile("^[a-z][a-z0-9_]*(\\.[a-z0-9_]+)+$")
	return re.search(ref) != null


static func make(p_scene: String, p_height: float, p_tint: Color = Color(1, 1, 1, 0), p_yaw_deg: float = 0.0, p_clips: Dictionary = {}, p_equip: PackedStringArray = PackedStringArray(), p_placeholder: bool = false) -> VisualSpec:
	var v: VisualSpec = VisualSpec.new()
	v.scene = p_scene
	v.height = p_height
	v.tint = p_tint
	v.yaw_offset_deg = p_yaw_deg
	v.clips = p_clips.duplicate()
	v.equip = p_equip
	v.placeholder = p_placeholder
	return v


## Do EnemyData (.tres); null se o inimigo nao tem visual_scene.
static func from_enemy(e: EnemyData) -> VisualSpec:
	if e == null or e.visual_scene.is_empty():
		return null
	return make(e.visual_scene, e.visual_height, e.visual_tint, e.visual_yaw_offset, e.visual_clips, e.visual_equip, e.visual_placeholder)


## Do dicionario de um JSON (classe/NPC). Sem `visual_scene` devolve null (e erro se houver outras chaves visual_*).
## Erros sao acrescentados a `errors`; com erro o resultado e null.
static func from_dict(d: Dictionary, errors: Array[String]) -> VisualSpec:
	var before: int = errors.size()
	if not d.has("visual_scene"):
		for k: String in KEYS:
			if d.has(k):
				errors.append("%s sem visual_scene" % k)
		return null
	var v: VisualSpec = VisualSpec.new()
	if typeof(d["visual_scene"]) != TYPE_STRING:
		errors.append("visual_scene deve ser texto")
	else:
		v.scene = d["visual_scene"]
	if d.has("visual_height"):
		if typeof(d["visual_height"]) not in [TYPE_INT, TYPE_FLOAT] or not Protocol.is_finite_number(d["visual_height"]):
			errors.append("visual_height deve ser numero")
		else:
			v.height = float(d["visual_height"])
	if d.has("visual_tint"):
		var t: Variant = d["visual_tint"]
		if typeof(t) != TYPE_ARRAY or (t as Array).size() != 3:
			errors.append("visual_tint deve ser [r, g, b]")
		else:
			var ok: bool = true
			for c: Variant in t:
				if typeof(c) not in [TYPE_INT, TYPE_FLOAT] or not Protocol.is_finite_number(c) or float(c) < 0.0 or float(c) > 4.0:
					ok = false
			if ok:
				v.tint = Color(float(t[0]), float(t[1]), float(t[2]), 1.0)
			else:
				errors.append("visual_tint: componentes devem estar em 0..4")
	if d.has("visual_yaw_offset"):
		if typeof(d["visual_yaw_offset"]) not in [TYPE_INT, TYPE_FLOAT] or not Protocol.is_finite_number(d["visual_yaw_offset"]):
			errors.append("visual_yaw_offset deve ser numero (graus)")
		else:
			v.yaw_offset_deg = float(d["visual_yaw_offset"])
	if d.has("visual_clips"):
		if typeof(d["visual_clips"]) != TYPE_DICTIONARY:
			errors.append("visual_clips deve ser objeto")
		else:
			for k: Variant in (d["visual_clips"] as Dictionary):
				if typeof((d["visual_clips"] as Dictionary)[k]) != TYPE_STRING:
					errors.append("visual_clips.%s deve ser texto" % str(k).left(24))
				else:
					v.clips[String(k)] = String((d["visual_clips"] as Dictionary)[k])
	if d.has("visual_equip"):
		if typeof(d["visual_equip"]) != TYPE_ARRAY:
			errors.append("visual_equip deve ser lista")
		else:
			for n: Variant in (d["visual_equip"] as Array):
				if typeof(n) != TYPE_STRING:
					errors.append("visual_equip: itens devem ser texto")
				else:
					v.equip.append(String(n))
	if d.has("visual_placeholder"):
		if typeof(d["visual_placeholder"]) != TYPE_BOOL:
			errors.append("visual_placeholder deve ser bool")
		else:
			v.placeholder = bool(d["visual_placeholder"])
	if errors.size() > before:
		return null
	errors.append_array(v.validate())
	return v if errors.size() == before else null


## Erros de valor (vazio = ok). Nao confere se o arquivo existe (o servidor nao tem assets): use path_exists().
func validate() -> Array[String]:
	var errs: Array[String] = []
	if not is_valid_scene_ref(scene):
		errs.append("visual_scene invalido: '%s' (use alias, id de asset ou res://assets/third_party/...glb)" % scene.left(60))
	if not Protocol.is_finite_number(height) or height < MIN_HEIGHT or height > MAX_HEIGHT:
		errs.append("visual_height fora de %s..%s" % [MIN_HEIGHT, MAX_HEIGHT])
	if not Protocol.is_finite_number(yaw_offset_deg) or absf(yaw_offset_deg) > 360.0:
		errs.append("visual_yaw_offset fora de -360..360")
	for k: Variant in clips:
		if not ClipTable.STATES.has(StringName(String(k))):
			errs.append("visual_clips: estado desconhecido '%s'" % str(k).left(24))
		var c: String = String(clips[k])
		if c.is_empty() or c.length() > MAX_NAME:
			errs.append("visual_clips.%s: nome de clip vazio/longo" % str(k).left(24))
	if equip.size() > MAX_EQUIP:
		errs.append("visual_equip: no maximo %d nomes" % MAX_EQUIP)
	for n: String in equip:
		if n.is_empty() or n.length() > MAX_NAME:
			errs.append("visual_equip: nome vazio/longo")
	return errs


## True se o alias resolve e o arquivo existe (CLIENTE/testes/validador; nao chame no servidor).
func path_exists() -> bool:
	var p: String = resolved_path()
	return not p.is_empty() and ResourceLoader.exists(p)
