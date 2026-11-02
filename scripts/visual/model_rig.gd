class_name ModelRig
extends Node3D
## E8.1: instancia um modelo GLB animado, normaliza a escala pela ALTURA medida (AABB das malhas do corpo), esconde
## acessorios nao equipados, aplica tintura e toca clips conforme o estado visual (ClipTable). SO apresentacao:
## nunca mexe na posicao autoritativa; o giro suave e uma defasagem local em relacao ao yaw da entidade.
## Hierarquia: ModelRig (defasagem de yaw suave) > Pivot (yaw_offset, escala, pe no chao) > cena do GLB.
## Cache: um PackedScene por caminho (instancia, nao recarrega). Em modo headless nao carrega nada (models_enabled()).

const BASE_YAW_DEG: float = 180.0       ## os GLB (KayKit/Quaternius) olham para +Z; o jogo usa -Z como frente
const BLEND_TIME: float = 0.15
const TURN_SPEED: float = 14.0
const LOCK_FRACTION: float = 0.6        ## one-shot protegido de ser cortado por idle/move ate esta fracao
const FLASH_ALPHA: float = 0.55

## Testes: -1 automatico (nao headless), 0 desliga, 1 liga.
static var force_enabled: int = -1
static var load_count: int = 0           ## quantas vezes um GLB foi realmente carregado do disco
static var _scenes: Dictionary = {}      ## caminho -> PackedScene (ou null para ausente)
static var _tint_cache: Dictionary = {}  ## "mat_id:cor" -> Material
static var _flash_material: StandardMaterial3D = null

var spec: VisualSpec
var model: Node3D = null
var anim: AnimationPlayer = null
var measured_height: float = 0.0         ## altura do AABB do modelo antes da escala
var scale_factor: float = 1.0
var current: StringName = &""            ## estado visual em reproducao
var dead: bool = false

var _pivot: Node3D
var _index: Dictionary = {}
var _meshes: Array[MeshInstance3D] = []
var _requested: StringName = &""
var _one_shot: bool = false
var _lock_left: float = 0.0
var _pending_base: StringName = &""
var _yaw_lag: float = 0.0
var _yaw_ready: bool = false
var _flash_left: float = 0.0
var _stop_left: float = 0.0              ## E8.3: hit-stop cosmetico (animacao quase parada por alguns centesimos)
var _stop_prev: float = 1.0


# ------------------------------------------------------------------ fabrica / cache

static func models_enabled() -> bool:
	if force_enabled >= 0:
		return force_enabled == 1
	return DisplayServer.get_name() != "headless"


## Cena em cache (null se o arquivo nao existe). O primeiro uso carrega; os demais so instanciam.
static func load_scene(path: String) -> PackedScene:
	if _scenes.has(path):
		return _scenes[path] as PackedScene
	var ps: PackedScene = null
	if not path.is_empty() and ResourceLoader.exists(path):
		ps = load(path) as PackedScene
		load_count += 1
	_scenes[path] = ps
	return ps


static func clear_cache() -> void:
	_scenes = {}
	_tint_cache = {}
	load_count = 0


## Cria o rig do spec, ou null (spec vazio, headless/desligado, asset ausente). Quem chama cai nas primitivas.
static func create(p_spec: VisualSpec) -> ModelRig:
	if p_spec == null or not models_enabled():
		return null
	return build(p_spec)


## Como create(), sem a checagem de modo (usado em testes e por create()).
static func build(p_spec: VisualSpec) -> ModelRig:
	if p_spec == null or not p_spec.validate().is_empty():
		return null
	var ps: PackedScene = load_scene(p_spec.resolved_path())
	if ps == null:
		return null
	var rig: ModelRig = ModelRig.new()
	rig.name = "Rig"
	if not rig.setup(p_spec, ps):
		rig.free()
		return null
	return rig


# ------------------------------------------------------------------ montagem

func setup(p_spec: VisualSpec, packed: PackedScene) -> bool:
	spec = p_spec
	var inst: Node = packed.instantiate()
	model = inst as Node3D
	if model == null:
		inst.free()
		return false
	_pivot = Node3D.new()
	_pivot.name = "Pivot"
	add_child(_pivot)
	_pivot.add_child(model)
	_apply_equip()
	_collect_meshes(model)
	if spec.has_tint():
		_apply_tint()
	var box: AABB = measure(model)
	measured_height = box.size.y
	scale_factor = 1.0
	if measured_height > 0.001:
		scale_factor = spec.height / measured_height
	_pivot.scale = Vector3.ONE * scale_factor
	_pivot.position = Vector3(0.0, -box.position.y * scale_factor, 0.0)
	_pivot.rotation.y = deg_to_rad(BASE_YAW_DEG + spec.yaw_offset_deg)
	anim = _find_anim(model)
	if anim != null:
		anim.playback_default_blend_time = BLEND_TIME
		_index = ClipTable.build_index(anim.get_animation_list())
		anim.animation_finished.connect(_on_clip_finished)
		_prepare_loops()
	set_process(false)
	return true


## O AnimationPlayer so toca de forma confiavel dentro da arvore: o estado pedido antes disso (ou idle) comeca aqui.
func _ready() -> void:
	var st: StringName = _requested if _requested != &"" else &"idle"
	_requested = st
	_enter(st, 0.0, true)
	if st == &"idle":
		_seek_random()


## Altura/base do corpo no espaco local do modelo: malhas visiveis e SKINNED, mais malhas estaticas que nao estao
## penduradas em BoneAttachment3D (chapeus/armas ficam de fora: a altura e a do corpo). Sem malhas = AABB vazio.
static func measure(root: Node3D) -> AABB:
	var out: Dictionary = {"box": AABB(), "first": true}
	_measure_node(root, Transform3D.IDENTITY, true, false, out)
	return out["box"] as AABB


static func _measure_node(n: Node3D, parent_xf: Transform3D, is_root: bool, under_attachment: bool, out: Dictionary) -> void:
	var xf: Transform3D = parent_xf if is_root else parent_xf * n.transform
	var attach: bool = under_attachment or n is BoneAttachment3D
	if n is MeshInstance3D and n.visible:
		var mi: MeshInstance3D = n as MeshInstance3D
		if mi.mesh != null and (mi.skin != null or not attach):
			var b: AABB = xf * mi.get_aabb()
			if bool(out["first"]):
				out["box"] = b
				out["first"] = false
			else:
				out["box"] = (out["box"] as AABB).merge(b)
	for c: Node in n.get_children():
		if c is Node3D:
			_measure_node(c as Node3D, xf, false, attach, out)


func _apply_equip() -> void:
	if spec.equip.is_empty():
		return
	for bone: Node in model.find_children("*", "BoneAttachment3D", true, false):
		for c: Node in bone.get_children():
			var mi: MeshInstance3D = c as MeshInstance3D
			if mi != null and mi.skin == null:
				mi.visible = spec.equip.has(String(mi.name))


func _collect_meshes(n: Node) -> void:
	if n is MeshInstance3D:
		_meshes.append(n as MeshInstance3D)
	for c: Node in n.get_children():
		_collect_meshes(c)


func _apply_tint() -> void:
	for mi: MeshInstance3D in _meshes:
		if mi.mesh == null:
			continue
		for i: int in mi.mesh.get_surface_count():
			var base: BaseMaterial3D = mi.get_active_material(i) as BaseMaterial3D
			if base == null:
				continue
			var key: String = "%d:%s" % [base.get_instance_id(), spec.tint.to_html(false)]
			var tinted: Material = _tint_cache.get(key) as Material
			if tinted == null:
				var dup: BaseMaterial3D = base.duplicate() as BaseMaterial3D
				dup.albedo_color = Color(base.albedo_color.r * spec.tint.r, base.albedo_color.g * spec.tint.g, base.albedo_color.b * spec.tint.b, base.albedo_color.a)
				_tint_cache[key] = dup
				tinted = dup
			mi.set_surface_override_material(i, tinted)


static func _find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n as AnimationPlayer
	for c: Node in n.get_children():
		var r: AnimationPlayer = _find_anim(c)
		if r != null:
			return r
	return null


## Os clips do glTF vem sem loop: idle/move em loop linear, o resto one-shot (propriedade do recurso compartilhado).
func _prepare_loops() -> void:
	for st: StringName in ClipTable.STATES:
		var real: String = clip_for(st)
		if real.is_empty():
			continue
		var a: Animation = anim.get_animation(real)
		if a != null:
			a.loop_mode = Animation.LOOP_LINEAR if ClipTable.is_looping(st) else Animation.LOOP_NONE


func _seek_random() -> void:
	if anim == null or not anim.is_playing() or anim.current_animation_length <= 0.01:
		return
	anim.seek(randf() * anim.current_animation_length, true)


# ------------------------------------------------------------------ estados

## Nome real do clip usado para o estado ("" = nenhum).
func clip_for(state: StringName) -> String:
	return ClipTable.pick(_index, state, spec.clips) if spec != null else ""


func has_clip(state: StringName) -> bool:
	return not clip_for(state).is_empty()


## Estado vindo do snapshot (autoritativo): so reage a MUDANCAS, para one-shots nao reiniciarem a cada frame.
func set_state(state: StringName, seconds_hint: float = 0.0) -> void:
	if state == _requested:
		return
	_requested = state
	if is_inside_tree():
		_enter(state, seconds_hint, true)


## Evento cosmetico (dano -> hit, spawn): respeita a prioridade e nao interrompe algo mais importante.
func trigger(state: StringName, seconds_hint: float = 0.0) -> void:
	if is_inside_tree():
		_enter(state, seconds_hint, false)


func _priority(state: StringName) -> int:
	match state:
		&"death": return 5
		&"spawn": return 4
		&"dodge": return 3
		&"attack", &"skill": return 2
		&"hit": return 1
	return 0


func _enter(state: StringName, seconds_hint: float, forced: bool) -> void:
	if dead:
		return
	if state == &"death":
		dead = true
		_one_shot = false
		_play(state, 0.0)
		return
	if ClipTable.is_one_shot(state):
		if not forced and _one_shot and _priority(current) >= _priority(state):
			return
		if not _play(state, seconds_hint):
			return
		_one_shot = true
		_pending_base = &""
		return
	# idle/move: nao corta um one-shot recente
	if _one_shot and _lock_left > 0.0:
		_pending_base = state
		set_process(true)
		return
	_one_shot = false
	_play(state, 0.0)


## Toca o clip do estado; false se nao ha clip (nada muda, sem erro).
func _play(state: StringName, seconds_hint: float) -> bool:
	if anim == null:
		current = state
		return false
	var real: String = clip_for(state)
	if real.is_empty():
		return false
	var a: Animation = anim.get_animation(real)
	var speed: float = ClipTable.speed_for(state, a.length, seconds_hint)
	anim.play(real, -1.0, speed)
	current = state
	_lock_left = (a.length / speed) * LOCK_FRACTION if ClipTable.is_one_shot(state) else 0.0
	if _lock_left > 0.0:
		set_process(true)
	return true


func _on_clip_finished(_name: StringName) -> void:
	if dead or not _one_shot:
		return
	_end_one_shot()


func _end_one_shot() -> void:
	_one_shot = false
	_lock_left = 0.0
	var next: StringName = _pending_base if _pending_base != &"" else (_requested if not ClipTable.is_one_shot(_requested) and _requested != &"death" else &"idle")
	_pending_base = &""
	_play(next, 0.0)


func _process(delta: float) -> void:
	if _lock_left > 0.0:
		_lock_left -= delta
		if _lock_left <= 0.0 and _one_shot and _pending_base != &"":
			_end_one_shot()
	if _flash_left > 0.0:
		_flash_left -= delta
		if _flash_left <= 0.0:
			_set_flash(false)
	if _stop_left > 0.0:
		_stop_left -= delta
		if _stop_left <= 0.0 and anim != null:
			anim.speed_scale = _stop_prev
	if _lock_left <= 0.0 and _flash_left <= 0.0 and _stop_left <= 0.0:
		set_process(false)


# ------------------------------------------------------------------ giro suave e flash

## Suaviza o giro VISUAL em direcao ao yaw da entidade (a entidade continua com o yaw autoritativo).
func follow_yaw(entity_yaw: float, delta: float) -> void:
	if not _yaw_ready:
		_yaw_lag = entity_yaw
		_yaw_ready = true
	_yaw_lag = PlayerMotion.smooth_angle(_yaw_lag, entity_yaw, TURN_SPEED, delta)
	rotation.y = wrapf(_yaw_lag - entity_yaw, -PI, PI)


## E8.3: hit-stop cosmetico: congela (quase) a animacao deste modelo por `seconds`. So apresentacao; nao toca simulacao nem tempo global.
func hit_stop(seconds: float) -> void:
	if anim == null or _stop_left > 0.0 or seconds <= 0.0:
		return
	_stop_prev = anim.speed_scale
	anim.speed_scale = 0.04
	_stop_left = seconds
	set_process(true)


func flash(seconds: float) -> void:
	if _meshes.is_empty():
		return
	_set_flash(true)
	_flash_left = seconds
	set_process(true)


func _set_flash(on: bool) -> void:
	if _flash_material == null:
		_flash_material = StandardMaterial3D.new()
		_flash_material.albedo_color = Color(1.0, 1.0, 1.0, FLASH_ALPHA)
		_flash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for mi: MeshInstance3D in _meshes:
		if is_instance_valid(mi) and mi.visible:
			mi.material_overlay = _flash_material if on else null


func debug_line() -> String:
	return "%s h=%.2f medido=%.2f escala=%.3f clips idle=%s move=%s attack=%s" % [spec.scene, spec.height, measured_height, scale_factor, clip_for(&"idle"), clip_for(&"move"), clip_for(&"attack")]
