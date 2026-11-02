class_name VfxPlayer
extends Node3D
## E8.3: toca efeitos do VfxCatalog com POOL de instancias (VfxInstance montada uma vez e reciclada), limite de efeitos simultaneos,
## orcamento de luzes e escalonamento por preset de qualidade (vfx_density / vfx_max_active / vfx_max_lights). Projeteis cosmeticos
## (movimento reto, velocidade/alcance dos dados da habilidade) e efeitos com atraso. Sem alocar por quadro: listas pre-dimensionadas
## e instancias recicladas. So o cliente com display cria isto (`enabled()`); em headless/bot/teste nada e carregado.

signal shake_requested(strength: float, time: float)

const MAX_PENDING: int = 48
const MAX_POOL_PER_EFFECT: int = 6
const MAX_DELTA: float = 0.1
const PRIORITY_CRITICAL: int = 2

var catalog: VfxCatalog
var quality: int = QualitySettings.DEFAULT_PRESET
var density: float = 1.0
var max_active: int = 20
var max_lights: int = 2
var lights_in_use: int = 0
var stats: Dictionary = {"played": 0, "dropped": 0, "evicted": 0, "built": 0, "peak_active": 0, "missing": 0}

var _pool: Dictionary = {}                 # id -> Array[VfxInstance] livres
var _active: Array[VfxInstance] = []
var _pending: Array[Dictionary] = []       # {t, id, pos, yaw, opts}
var _handles: Dictionary = {}              # handle -> VfxInstance
var _next_handle: int = 1
var _warm: Array[String] = []
var _t: float = 0.0


static func enabled() -> bool:
	return ModelRig.models_enabled()


func _init() -> void:
	name = "VfxPlayer"
	catalog = VfxCatalog.shared()
	set_quality(QualitySettings.current)


## Aplica o preset e descarta o pool (a densidade de particulas e fixada na montagem). Efeitos ativos terminam normalmente.
func set_quality(preset: int) -> void:
	quality = preset
	var d: Dictionary = QualitySettings.data(preset)
	density = float(d.get("vfx_density", 1.0))
	max_active = int(d.get("vfx_max_active", 20))
	max_lights = int(d.get("vfx_max_lights", 2))
	for id: Variant in _pool:
		for inst: VfxInstance in (_pool[id] as Array):
			inst.queue_free()
	_pool = {}


func acquire_light() -> bool:
	if lights_in_use >= max_lights:
		return false
	lights_in_use += 1
	return true


func release_light() -> void:
	lights_in_use = maxi(0, lights_in_use - 1)


func request_shake(strength: float, time: float) -> void:
	shake_requested.emit(strength, time)


func active_count() -> int:
	return _active.size()


func pooled_count(id: String = "") -> int:
	if not id.is_empty():
		return (_pool.get(id, []) as Array).size()
	var n: int = 0
	for k: Variant in _pool:
		n += (_pool[k] as Array).size()
	return n


## Pre-aquece (monta 1 instancia por id, no maximo 2 por quadro) para evitar engasgo no primeiro uso.
func prewarm(ids: Array) -> void:
	for id: Variant in ids:
		if catalog.has_effect(String(id)) and not _warm.has(String(id)) and pooled_count(String(id)) == 0:
			_warm.append(String(id))


## Toca `id` em `pos` com yaw (frente = -Z girada por yaw). opts: scale, tint(Color), delay, follow(Node3D), follow_offset,
## speed+range (movel: anda reto na frente do yaw), end (efeito ao fim do percurso), owner, pierce. Devolve o handle (-1 = nao tocou/atrasado).
func play(id: String, pos: Vector3, yaw: float = 0.0, opts: Dictionary = {}) -> int:
	if not catalog.has_effect(id):
		stats["missing"] = int(stats["missing"]) + 1
		return -1
	var delay: float = float(opts.get("delay", 0.0))
	if delay > 0.0:
		if _pending.size() < MAX_PENDING:
			var o2: Dictionary = opts.duplicate()
			o2.erase("delay")
			_pending.append({"t": _t + delay, "id": id, "pos": pos, "yaw": yaw, "opts": o2})
		else:
			stats["dropped"] = int(stats["dropped"]) + 1
		return -1
	var def: Dictionary = catalog.get_effect(id)
	var prio: int = int(def.get("priority", 1))
	if _active.size() >= max_active and not _make_room(prio):
		stats["dropped"] = int(stats["dropped"]) + 1
		return -1
	var inst: VfxInstance = _take(id, def)
	if inst == null:
		return -1
	var sc: float = float(opts.get("scale", 1.0))
	if bool(def.get("scale_with_tier", false)):
		sc *= float(opts.get("tier_scale", 1.0))
	inst.begin(self, sc, opts.get("tint", Color(0, 0, 0, 0)) as Color)
	inst.global_position = pos
	inst.rotation = Vector3(0.0, yaw, 0.0)
	if opts.has("speed") and float(opts["speed"]) > 0.0:
		inst.velocity = Vector3(-sin(yaw), 0.0, -cos(yaw)) * float(opts["speed"])
		inst.travel_left = float(opts.get("range", 10.0))
		inst.end_effect = String(opts.get("end", ""))
	inst.owner_id = int(opts.get("owner", -1))
	inst.pierce_left = int(opts.get("pierce", 0))
	inst.quiet = bool(opts.get("quiet", false))
	var fol: Variant = opts.get("follow", null)
	if fol is Node3D:
		inst.follow = fol as Node3D
		inst.follow_offset = opts.get("follow_offset", Vector3.ZERO) as Vector3
	inst.handle = _next_handle
	_next_handle += 1
	_handles[inst.handle] = inst
	_active.append(inst)
	stats["played"] = int(stats["played"]) + 1
	stats["peak_active"] = maxi(int(stats["peak_active"]), _active.size())
	return inst.handle


func stop(handle: int) -> void:
	var inst: VfxInstance = _handles.get(handle) as VfxInstance
	if inst != null and is_instance_valid(inst):
		inst.stop()


func is_playing(handle: int) -> bool:
	return _handles.has(handle)


func instance_of(handle: int) -> VfxInstance:
	return _handles.get(handle) as VfxInstance


## Projeteis cosmeticos ativos (instancias com velocidade).
func projectiles() -> Array[VfxInstance]:
	var out: Array[VfxInstance] = []
	for inst: VfxInstance in _active:
		if inst.velocity != Vector3.ZERO and not inst.stopping:
			out.append(inst)
	return out


## Para o projetil `inst` agora (acertou) e toca `impact_id` em `pos`.
func end_projectile(inst: VfxInstance, impact_id: String, pos: Vector3, p_scale: float = 1.0) -> void:
	inst.velocity = Vector3.ZERO
	inst.end_effect = ""
	inst.stop()
	if not impact_id.is_empty():
		play(impact_id, pos, 0.0, {"scale": p_scale})


func _make_room(prio: int) -> bool:
	var victim: VfxInstance = null
	for inst: VfxInstance in _active:
		if inst.priority >= PRIORITY_CRITICAL or inst.looping and inst.priority >= prio:
			continue
		if inst.priority > prio:
			continue
		if victim == null or inst.priority < victim.priority or (inst.priority == victim.priority and inst.age > victim.age):
			victim = inst
	if victim == null:
		return false
	_release(victim)
	stats["evicted"] = int(stats["evicted"]) + 1
	return true


func _take(id: String, def: Dictionary) -> VfxInstance:
	var free: Array = _pool.get(id, []) as Array
	if not free.is_empty():
		var inst: VfxInstance = free.pop_back() as VfxInstance
		if is_instance_valid(inst):
			return inst
	var ni: VfxInstance = VfxInstance.new()
	ni.build(id, def, density)
	add_child(ni)
	stats["built"] = int(stats["built"]) + 1
	return ni


func _release(inst: VfxInstance) -> void:
	inst.finish()
	_active.erase(inst)
	_handles.erase(inst.handle)
	var free: Array = _pool.get(inst.effect_id, []) as Array
	if free.size() >= MAX_POOL_PER_EFFECT:
		inst.queue_free()
	else:
		free.append(inst)
		_pool[inst.effect_id] = free


func _process(delta: float) -> void:
	step(minf(delta, MAX_DELTA))


## Avanca o relogio (testavel sem arvore de cena).
func step(delta: float) -> void:
	_t += delta
	if not _warm.is_empty():
		for _i: int in 2:
			if _warm.is_empty():
				break
			var wid: String = _warm.pop_front()
			if pooled_count(wid) == 0:
				var wi: VfxInstance = VfxInstance.new()
				wi.build(wid, catalog.get_effect(wid), density)
				add_child(wi)
				wi.finish()
				var arr: Array = _pool.get(wid, []) as Array
				arr.append(wi)
				_pool[wid] = arr
				stats["built"] = int(stats["built"]) + 1
	var i: int = 0
	while i < _pending.size():
		if float(_pending[i]["t"]) <= _t:
			var p: Dictionary = _pending[i]
			_pending.remove_at(i)
			play(String(p["id"]), p["pos"] as Vector3, float(p["yaw"]), p["opts"] as Dictionary)
		else:
			i += 1
	var n: int = _active.size() - 1
	while n >= 0:
		var inst: VfxInstance = _active[n]
		if inst.velocity != Vector3.ZERO and not inst.stopping:
			var move: Vector3 = inst.velocity * delta
			inst.global_position += move
			inst.travel_left -= move.length()
			if inst.travel_left <= 0.0:
				var endp: String = inst.end_effect
				inst.velocity = Vector3.ZERO
				inst.end_effect = ""
				inst.stop()
				if not endp.is_empty():
					play(endp, inst.global_position, inst.rotation.y)
		if inst.step(delta):
			_release(inst)
		n -= 1


## Descarta tudo (troca de zona/teste).
func clear_all() -> void:
	for inst: VfxInstance in _active.duplicate():
		_release(inst)
	_pending.clear()
