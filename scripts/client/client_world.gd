class_name ClientWorld
extends Node3D
## Mundo cliente SOMENTE de apresentacao: cria/atualiza/remove avatares a partir do interpolador
## (remotos) e da predicao (jogador local) e aplica eventos cosmeticos. Nao simula combate, IA,
## dano nem loot. Malhas placeholder: jogador local azul (capsula), outros jogadores verdes,
## inimigos vermelhos (caixa; o tipo varia o tom).

signal notice(text: String)

const HEIGHT_DAMAGE: float = 2.2
const FLASH_TIME: float = 0.12

var avatars: Dictionary = {}  # id -> Node3D
var local_id: int = -1
var local_avatar: Node3D = null

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


func _ready() -> void:
	_flash_mat = StandardMaterial3D.new()
	_flash_mat.albedo_color = Color.WHITE
	_flash_mat.emission_enabled = true
	_flash_mat.emission = Color.WHITE
	_build_ground()


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


## Atualiza avatares. `samples`: id -> dict do interpolador; `local_pos` (predicao) para o local.
func update_frame(samples: Dictionary, p_local_id: int, local_pos: Variant, delta: float) -> void:
	local_id = p_local_id
	for id: Variant in samples:
		var s: Dictionary = samples[id]
		var pos: Vector3 = s["pos"]
		var yaw: float = s["yaw"]
		if int(id) == local_id and local_pos is Vector3:
			pos = local_pos
			var step: Vector3 = pos - _prev_local
			step.y = 0.0
			if step.length_squared() > 0.000001:
				var cur: float = float(_facing.get(id, yaw))
				_facing[id] = PlayerMotion.smooth_angle(cur, PlayerMotion.facing_yaw(step, cur), 14.0, delta)
			yaw = float(_facing.get(id, yaw))
			_prev_local = pos
		var av: Node3D = avatars.get(id) as Node3D
		if av == null or not is_instance_valid(av):
			av = _create_avatar(int(id), s)
			avatars[id] = av
		av.position = pos
		av.rotation.y = yaw
		_last_pos[id] = pos
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
		_flash_left.erase(id)
		_facing.erase(id)
		_last_pos.erase(id)
	local_avatar = avatars.get(local_id) as Node3D
	_tick_flash(delta)


func _create_avatar(id: int, s: Dictionary) -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = "Entity_%d" % id
	var vis: Node3D = Node3D.new()
	vis.name = "Visual"
	root.add_child(vis)
	var body: MeshInstance3D = MeshInstance3D.new()
	body.name = "Body"
	var mat: StandardMaterial3D = StandardMaterial3D.new()
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
		var tag: Label3D = Label3D.new()
		tag.text = String(s["type"]) if int(s.get("qty", 1)) <= 1 else "%s x%d" % [String(s["type"]), int(s.get("qty", 1))]
		tag.position = Vector3(0.0, 0.9, 0.0)
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.pixel_size = 0.008
		root.add_child(tag)
	else:
		var cm: CapsuleMesh = CapsuleMesh.new()
		cm.radius = 0.4
		cm.height = 1.8
		body.mesh = cm
		body.position.y = 0.9
		mat.albedo_color = Color(0.25, 0.5, 1.0) if id == local_id else Color(0.3, 0.8, 0.4)
	body.material_override = mat
	vis.add_child(body)
	add_child(root)
	return root


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
				label.global_position = av.global_position + Vector3(randf_range(-0.3, 0.3), HEIGHT_DAMAGE, 0.0)
				_flash(target, av)
		Protocol.EVENT_DEATH:
			_play_death(int(data.get("id", -1)))
		Protocol.EVENT_ZONE:
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
	zone_id = new_zone_id
	if _ground != null:
		_ground.visible = false
	_apply_puzzle()
	return true


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
