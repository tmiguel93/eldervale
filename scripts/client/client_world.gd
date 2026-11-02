class_name ClientWorld
extends Node3D
## Mundo cliente SOMENTE de apresentacao: cria/atualiza/remove avatares a partir do interpolador
## (remotos) e da predicao (jogador local) e aplica eventos cosmeticos. Nao simula combate, IA,
## dano nem loot. Malhas placeholder: jogador local azul (capsula), outros jogadores verdes,
## inimigos vermelhos (caixa; o tipo varia o tom).
## E8.1: com display e asset disponivel, o avatar usa um ModelRig (GLB animado, visual_scene dos dados); sem asset, em modo
## headless/bot/teste ou com `use_models = false`, continua nas primitivas acima. O servidor nunca ve a arte.

signal notice(text: String)

const HEIGHT_DAMAGE: float = 2.2
const FLASH_TIME: float = 0.12
const HEAD_MARGIN: float = 0.4
const MOVING_EPS_SQ: float = 0.000004
## Aliado remoto: o snapshot nao informa a classe dos outros jogadores (protocolo inalterado), entao usam o Cavaleiro.
const ALLY_SCENE: String = "class.warrior_alt"

var avatars: Dictionary = {}  # id -> Node3D
var local_id: int = -1
## Evento de zona recebido antes de local_id ser conhecido (o join chega antes do primeiro frame): reaplicado depois.
var _pending_zone: Dictionary = {}
var local_avatar: Node3D = null
## E8.1: modelos 3D ligados? (desligado em headless/testes: ModelRig.models_enabled()). Classe do jogador local (ClientMain).
var use_models: bool = true
var local_class_id: String = ""
var _rigs: Dictionary = {}          # id -> ModelRig
var _spawn_pending: Dictionary = {} # id -> true (EVENT_ENEMY_SPAWN antes do avatar existir)

var _flash_left: Dictionary = {}   # id -> s
var _last_pos: Dictionary = {}     # id -> Vector3 (para o efeito de morte)
var _facing: Dictionary = {}       # id -> yaw
var _flash_mat: StandardMaterial3D
var _prev_local: Vector3 = Vector3.ZERO
## E5.3: visual da zona atual (montado dos mesmos dados do servidor) e ultimo estado do puzzle.
var zone_root: Node3D = null
var zone_id: String = ""
var _ground: MeshInstance3D
var _puzzle_event: Dictionary = {}
## E8.2: iluminacao/atmosfera e decoracao 3D da zona (so cliente com display; null em headless/bot/teste = fallback de sempre).
var scenery_env: SceneryEnv = null
var scenery_info: Dictionary = {}
var _sun: DirectionalLight3D = null


func _ready() -> void:
	use_models = ModelRig.models_enabled()
	_flash_mat = StandardMaterial3D.new()
	_flash_mat.albedo_color = Color.WHITE
	_flash_mat.emission_enabled = true
	_flash_mat.emission = Color.WHITE
	_build_ground()
	if SceneryBuilder.enabled():
		scenery_env = SceneryEnv.new()
		add_child(scenery_env)
		scenery_env.set_quality(QualitySettings.current)


func _build_ground() -> void:
	var ground: MeshInstance3D = MeshInstance3D.new()
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(80.0, 80.0)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.22, 0.25, 0.22)
	plane.material = mat
	ground.mesh = plane
	ground.name = "Ground"
	_ground = ground
	add_child(ground)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, 30.0, 0.0)
	add_child(sun)
	_sun = sun


## Atualiza avatares. `samples`: id -> dict do interpolador; `local_pos` (predicao) para o local.
func update_frame(samples: Dictionary, p_local_id: int, local_pos: Variant, delta: float) -> void:
	local_id = p_local_id
	if not _pending_zone.is_empty() and local_id >= 0:
		var pz: Dictionary = _pending_zone
		_pending_zone = {}
		apply_event(Protocol.EVENT_ZONE, pz)
	for id: Variant in samples:
		var s: Dictionary = samples[id]
		var pos: Vector3 = s["pos"]
		var yaw: float = s["yaw"]
		var moving: int = -1
		if int(id) == local_id and local_pos is Vector3:
			pos = local_pos
			var step: Vector3 = pos - _prev_local
			step.y = 0.0
			if step.length_squared() > 0.000001:
				var cur: float = float(_facing.get(id, yaw))
				_facing[id] = PlayerMotion.smooth_angle(cur, PlayerMotion.facing_yaw(step, cur), 14.0, delta)
			yaw = float(_facing.get(id, yaw))
			moving = 1 if step.length_squared() > MOVING_EPS_SQ else 0
			_prev_local = pos
		var av: Node3D = avatars.get(id) as Node3D
		if av == null or not is_instance_valid(av):
			av = _create_avatar(int(id), s)
			avatars[id] = av
		elif String(av.get_meta("vkey", "")) != _visual_key(int(id), s):
			_rebuild_visual(av, int(id), s)
		av.position = pos
		av.rotation.y = yaw
		_last_pos[id] = pos
		_drive_rig(int(id), s, yaw, moving, delta)
		if int(s["kind"]) == Protocol.KIND_ENEMY:
			_update_enemy_telegraph(av, s)
	var gone: Array = []
	for id: Variant in avatars:
		if not samples.has(id):
			gone.append(id)
	for id: Variant in gone:
		var a: Node3D = avatars[id]
		if is_instance_valid(a):
			a.queue_free()
		avatars.erase(id)
		_rigs.erase(id)
		_spawn_pending.erase(id)
		_flash_left.erase(id)
		_facing.erase(id)
		_last_pos.erase(id)
	local_avatar = avatars.get(local_id) as Node3D
	_tick_flash(delta)
	if scenery_env != null and local_avatar != null and is_instance_valid(local_avatar):
		scenery_env.update(delta, local_avatar.position)


func _create_avatar(id: int, s: Dictionary) -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = "Entity_%d" % id
	var vis: Node3D = Node3D.new()
	vis.name = "Visual"
	root.add_child(vis)
	add_child(root)
	_build_visual(root, id, s)
	return root


## Chave do visual atual (muda quando a classe do jogador local chega depois do avatar, por exemplo).
func _visual_key(id: int, s: Dictionary) -> String:
	match int(s["kind"]):
		Protocol.KIND_ENEMY:
			return "e:" + String(s["type"])
		Protocol.KIND_PICKUP:
			return "k:" + String(s["type"])
	return "p:" + (_class_of(id) if use_models else "prim")


func _class_of(id: int) -> String:
	if id != local_id:
		return "ally"
	return local_class_id if ClassCatalog.shared().has_class(local_class_id) else ClassCatalog.DEFAULT_CLASS_ID


## VisualSpec do avatar (null = primitivas). So consultado com use_models.
func _spec_for(id: int, s: Dictionary) -> VisualSpec:
	match int(s["kind"]):
		Protocol.KIND_ENEMY:
			var ed: EnemyData = EnemyCatalog.data_for(StringName(String(s["type"])))
			return ed.visual_spec() if ed != null else null
		Protocol.KIND_PICKUP:
			var item: String = String(s["type"])
			if item.begins_with("potion"):
				return VisualSpec.make("res://assets/third_party/quaternius_rpg_items/Potion1_Filled.glb", 0.5)
			return VisualSpec.make("prop.chest", 0.55)
	var cid: String = _class_of(id)
	if cid == "ally":
		return VisualSpec.make(ALLY_SCENE, 1.9, Color(1, 1, 1, 0), 0.0, {"move": "Running_A"}, PackedStringArray(["1H_Sword", "Rectangle_Shield"]))
	var def: ClassDef = ClassCatalog.shared().get_def(cid)
	return def.visual if def != null else null


func _rebuild_visual(root: Node3D, id: int, s: Dictionary) -> void:
	var vis: Node3D = root.get_node("Visual") as Node3D
	for c: Node in vis.get_children():
		vis.remove_child(c)
		c.queue_free()
	_rigs.erase(id)
	vis.scale = Vector3.ONE
	_build_visual(root, id, s)


func _build_visual(root: Node3D, id: int, s: Dictionary) -> void:
	var vis: Node3D = root.get_node("Visual") as Node3D
	root.set_meta("vkey", _visual_key(id, s))
	if use_models:
		var rig: ModelRig = ModelRig.create(_spec_for(id, s))
		if rig != null:
			vis.add_child(rig)
			_rigs[id] = rig
			root.set_meta("height", rig.spec.height)
			if int(s["kind"]) == Protocol.KIND_PICKUP:
				root.add_child(_pickup_label(s, rig.spec.height + 0.3))
			if _spawn_pending.has(id):
				_spawn_pending.erase(id)
				rig.trigger(&"spawn")
			return
	var body: MeshInstance3D = MeshInstance3D.new()
	body.name = "Body"
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	root.set_meta("height", 1.8)
	if int(s["kind"]) == Protocol.KIND_ENEMY:
		var bm: BoxMesh = BoxMesh.new()
		bm.size = Vector3(0.9, 1.2, 0.9)
		body.mesh = bm
		body.position.y = 0.6
		var h: float = float(absi(String(s["type"]).hash()) % 100) / 100.0
		mat.albedo_color = Color.from_hsv(0.0 + h * 0.08, 0.75, 0.8)
		# E5.2: cor/escala vindas dos dados do tipo (o cliente so apresenta).
		var edata: EnemyData = EnemyCatalog.data_for(StringName(String(s["type"])))
		if edata != null:
			if edata.visual_color.a > 0.0:
				mat.albedo_color = Color(edata.visual_color.r, edata.visual_color.g, edata.visual_color.b, 1.0)
			vis.scale = Vector3.ONE * edata.visual_scale
	elif int(s["kind"]) == Protocol.KIND_PICKUP:
		# E5.4: pickup individual (so existe no snapshot do dono). Placeholder: caixinha dourada + nome do item.
		var pm: BoxMesh = BoxMesh.new()
		pm.size = Vector3(0.4, 0.4, 0.4)
		body.mesh = pm
		body.position.y = 0.3
		mat.albedo_color = Color(1.0, 0.85, 0.2)
		root.add_child(_pickup_label(s, 0.9))
	else:
		var cm: CapsuleMesh = CapsuleMesh.new()
		cm.radius = 0.4
		cm.height = 1.8
		body.mesh = cm
		body.position.y = 0.9
		mat.albedo_color = Color(0.25, 0.5, 1.0) if id == local_id else Color(0.3, 0.8, 0.4)
	body.material_override = mat
	vis.add_child(body)


func _pickup_label(s: Dictionary, y: float) -> Label3D:
	var tag: Label3D = Label3D.new()
	tag.name = "PickupLabel"
	tag.text = String(s["type"]) if int(s.get("qty", 1)) <= 1 else "%s x%d" % [String(s["type"]), int(s.get("qty", 1))]
	tag.position = Vector3(0.0, y, 0.0)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.pixel_size = 0.008
	return tag


## E8.1: estado do snapshot -> clip. `moving` (0/1) vem da predicao do jogador local; -1 = so o snapshot.
func _drive_rig(id: int, s: Dictionary, yaw: float, moving: int, delta: float) -> void:
	var rig: ModelRig = _rigs.get(id) as ModelRig
	if rig == null or not is_instance_valid(rig):
		return
	rig.follow_yaw(yaw, delta)
	var kind: int = int(s["kind"])
	if kind == Protocol.KIND_PICKUP:
		return
	var is_skill: bool = false
	var hint: float = 0.0
	if kind == Protocol.KIND_ENEMY and int(s.get("state", 0)) == int(EnemyAI.State.ATTACK):
		var atk: EnemyAttack = _attack_of(String(s["type"]), String(s.get("atk", "")))
		if atk != null:
			is_skill = atk.kind != EnemyAttack.Kind.MELEE
			hint = atk.windup + 0.3
	rig.set_state(ClipTable.state_from_snapshot(kind, int(s.get("state", 0)), moving, is_skill), hint)


func _attack_of(type: String, atk_id: String) -> EnemyAttack:
	var ed: EnemyData = EnemyCatalog.data_for(StringName(type))
	if ed == null or atk_id.is_empty():
		return null
	for a: EnemyAttack in ed.all_attacks():
		if a != null and String(a.id) == atk_id:
			return a
	return null


## E5.2: indicador de chao do telegrafo. O servidor manda `atk` (id) enquanto o inimigo esta em ATTACK;
## o desenho vem do EnemyAttack do tipo. So apresentacao.
func _update_enemy_telegraph(av: Node3D, s: Dictionary) -> void:
	var atk_id: String = String(s.get("atk", ""))
	var existing: Node = av.get_node_or_null("Telegraph")
	if atk_id.is_empty() or int(s.get("state", 0)) != int(EnemyAI.State.ATTACK):
		_drop_telegraph(av, existing)
		return
	if existing != null and String(existing.get_meta("atk_id", "")) == atk_id:
		return
	_drop_telegraph(av, existing)
	var edata: EnemyData = EnemyCatalog.data_for(StringName(String(s["type"])))
	if edata == null:
		return
	for a: EnemyAttack in edata.all_attacks():
		if a != null and String(a.id) == atk_id:
			var tg: MeshInstance3D = EnemyTelegraph.build(a)
			tg.set_meta("atk_id", atk_id)
			av.add_child(tg) # filho da raiz (nao do Visual escalado); gira com o yaw da entidade
			return


func _drop_telegraph(av: Node3D, existing: Node) -> void:
	if existing != null:
		av.remove_child(existing)
		existing.free()


func apply_event(kind: int, data: Dictionary) -> void:
	match kind:
		Protocol.EVENT_DAMAGE:
			var target: int = int(data.get("target_id", -1))
			var amount: float = float(data.get("amount", 0.0))
			var crit: bool = bool(data.get("crit", false))
			var av: Node3D = avatars.get(target) as Node3D
			if av != null and is_instance_valid(av):
				var label: DamageNumber = DamageNumber.new()
				label.setup(amount, Color(1.0, 0.8, 0.3) if crit else Color(1.0, 0.9, 0.3))
				add_child(label)
				label.global_position = av.global_position + Vector3(randf_range(-0.3, 0.3), float(av.get_meta("height", HEIGHT_DAMAGE - HEAD_MARGIN)) + HEAD_MARGIN, 0.0)
				_flash(target, av)
		Protocol.EVENT_DEATH:
			_play_death(int(data.get("id", -1)))
		Protocol.EVENT_ENEMY_SPAWN:
			var sid: int = int(data.get("id", -1))
			var srig: ModelRig = _rigs.get(sid) as ModelRig
			if srig != null and is_instance_valid(srig):
				srig.trigger(&"spawn")
			elif use_models:
				_spawn_pending[sid] = true
		Protocol.EVENT_ZONE:
			if local_id < 0 and int(data.get("phase", -1)) == Protocol.ZONE_PHASE_ARRIVED:
				_pending_zone = data
				return
			if int(data.get("id", -1)) == local_id and int(data.get("phase", -1)) == Protocol.ZONE_PHASE_ARRIVED:
				show_zone(String(data.get("zone", "")))
		Protocol.EVENT_PUZZLE:
			_puzzle_event = data
			_apply_puzzle()
		Protocol.EVENT_BOSS:
			if int(data.get("state", -1)) == Protocol.BOSS_ACTIVE:
				notice.emit("O Anciao Corrompido desperta!")
			elif int(data.get("state", -1)) == Protocol.BOSS_DEFEATED:
				notice.emit("O Anciao Corrompido foi derrotado!")
			elif int(data.get("state", -1)) == Protocol.BOSS_ARMED:
				notice.emit("O encontro reiniciou.")
		Protocol.EVENT_RESPAWN:
			if int(data.get("id", -1)) == local_id:
				notice.emit("Voce reapareceu no ponto de retorno.")
		Protocol.EVENT_PLAYER_JOINED:
			notice.emit("Jogador entrou: %s" % str(data.get("id", data.get("player_id", "?"))))
		Protocol.EVENT_PLAYER_LEFT:
			notice.emit("Jogador saiu: %s" % str(data.get("id", data.get("player_id", "?"))))
		_:
			pass


## E5.3: monta o visual da zona (primitivas, mesmos dados do servidor) e esconde o chao generico.
func show_zone(new_zone_id: String, def: WorldDef = null) -> bool:
	var world_def: WorldDef = def if def != null else WorldDef.shared()
	var zone: ZoneDef = world_def.get_zone(new_zone_id)
	if zone == null:
		return false
	if zone_id == new_zone_id and zone_root != null and is_instance_valid(zone_root):
		return true
	if zone_root != null and is_instance_valid(zone_root):
		remove_child(zone_root)
		zone_root.queue_free()
	zone_root = WorldBuilder.build_zone(self, zone, true, NpcDirectory.shared())
	var first_zone: bool = zone_id.is_empty()
	zone_id = new_zone_id
	if _ground != null:
		_ground.visible = false
	_decorate_zone(zone, first_zone)
	_apply_puzzle()
	return true


## E8.2: cenario 3D + iluminacao da zona (so com display e modelos ligados; sem tema ou sem asset mantem as primitivas).
func _decorate_zone(zone: ZoneDef, instant: bool) -> void:
	scenery_info = {}
	if scenery_env == null or zone_root == null:
		return
	scenery_info = SceneryBuilder.decorate(zone_root, zone, QualitySettings.current, NpcDirectory.shared())
	if scenery_info.is_empty():
		return
	if scenery_env.set_zone(zone.id, instant) and _sun != null:
		_sun.visible = false # o sol do SceneryEnv assume
	scenery_env.set_lights(scenery_info["lights"] as Array[OmniLight3D])


## E8.2: troca o preset de qualidade (Baixa/Media/Alta) e reconstroi o cenario da zona atual (densidade/luzes mudam).
func set_quality(preset: int) -> void:
	QualitySettings.current = preset
	if scenery_env == null:
		return
	scenery_env.set_quality(preset)
	if zone_root != null and not zone_id.is_empty():
		var again: String = zone_id
		zone_id = ""
		show_zone(again)
		zone_id = again


func _apply_puzzle() -> void:
	if zone_root == null or not is_instance_valid(zone_root) or _puzzle_event.is_empty():
		return
	if String(_puzzle_event.get("zone", "")) != zone_id:
		return
	var plates: Array = _puzzle_event.get("plates", [])
	for i: int in plates.size():
		WorldBuilder.set_plate_lit(zone_root, i, bool(plates[i]))
	WorldBuilder.set_gate_open(zone_root, bool(_puzzle_event.get("open", false)))


func _flash(id: int, av: Node3D) -> void:
	var rig: ModelRig = _rigs.get(id) as ModelRig
	if rig != null and is_instance_valid(rig):
		rig.flash(FLASH_TIME)
		rig.trigger(&"hit")
		return
	var body: MeshInstance3D = av.get_node_or_null("Visual/Body") as MeshInstance3D
	if body != null:
		if not body.has_meta("orig"):
			body.set_meta("orig", body.material_override)
		body.material_override = _flash_mat
		_flash_left[id] = FLASH_TIME


func _tick_flash(delta: float) -> void:
	var done: Array = []
	for id: Variant in _flash_left:
		_flash_left[id] = float(_flash_left[id]) - delta
		if float(_flash_left[id]) <= 0.0:
			done.append(id)
	for id: Variant in done:
		_flash_left.erase(id)
		var av: Node3D = avatars.get(id) as Node3D
		if av != null and is_instance_valid(av):
			var body: MeshInstance3D = av.get_node_or_null("Visual/Body") as MeshInstance3D
			if body != null and body.has_meta("orig"):
				body.material_override = body.get_meta("orig") as Material


## Efeito de morte reutilizando DeathEffect do E2 em um "fantasma" destacado (a entidade real
## some via snapshot). O fantasma se libera sozinho.
func _play_death(id: int) -> void:
	var rig: ModelRig = _rigs.get(id) as ModelRig
	if rig != null and is_instance_valid(rig):
		rig.set_state(&"death") # E8.1: o corpo toca o clip de morte e some quando o servidor o remove do snapshot
		return
	if not _last_pos.has(id):
		return
	var ghost: Node3D = Node3D.new()
	var vis: Node3D = Node3D.new()
	vis.name = "Visual"
	ghost.add_child(vis)
	var src: Node3D = avatars.get(id) as Node3D
	var src_body: MeshInstance3D = null
	if src != null and is_instance_valid(src):
		src_body = src.get_node_or_null("Visual/Body") as MeshInstance3D
	if src_body != null:
		var copy: MeshInstance3D = MeshInstance3D.new()
		copy.mesh = src_body.mesh
		copy.position = src_body.position
		vis.add_child(copy)
	var fx: DeathEffect = DeathEffect.new()
	fx.name = "DeathEffect"
	ghost.add_child(fx)
	add_child(ghost)
	ghost.global_position = _last_pos[id]
	fx.play()
	var timer: SceneTreeTimer = get_tree().create_timer(fx.duration + 0.2)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(ghost):
			ghost.queue_free())
