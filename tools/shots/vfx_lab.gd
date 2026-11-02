extends SceneTree
## Ferramenta de desenvolvimento (E8.3): bancada de efeitos SEM servidor. Monta o ClientWorld real (zona + modelos + ClientVfx), alimenta
## amostras de snapshot sinteticas e eventos cosmeticos, avanca o relogio dos efeitos em passos fixos (determinista, independente da
## velocidade do GL por software) e salva recortes do viewport em instantes escolhidos.
## Uso (com display, p.ex. xvfb-run; SHOT_DIR=<pasta>):
##   godot --path . --rendering-driver opengl3 --resolution 1280x720 --script res://tools/shots/vfx_lab.gd -- \
##     --shot nome,modo,t1;t2;t3 [--shot ...] [--zone zone_hub] [--at 0,6] [--quality high] [--zoom 0.7]
## modos: p:<classe>:<slot>  (slot attack|skill_1|skill_2|dodge; inimigo-alvo a 3,2 m)   e:<tipo>:<ataque>  (inimigo ataca o jogador)
##        ev:levelup|heal|death|spawn|drop|crit|boss|portal|hurt
const DT: float = 0.05
const CROP: Vector2i = Vector2i(760, 500)

var world: ClientWorld
var cam: IsoCamera
var out_dir: String = ""
var ents: Dictionary = {}
var origin: Vector3 = Vector3(0, 0, 6)
var zone: String = "zone_hub"
var yaw: float = -0.6
var sim_t: float = 0.0
var peak: int = 0

func _initialize() -> void:
	out_dir = OS.get_environment("SHOT_DIR")
	_run.call_deferred()

var _last_us: int = 0

## Cada quadro renderizado vale exatamente DT/2 s de tempo de jogo (Engine.time_scale compensa o GL por software, que e lento):
## particulas e animacoes avancam de forma determinista junto com o relogio dos efeitos.
func _frames(n: int) -> void:
	for _i in n:
		var now: int = Time.get_ticks_usec()
		var real: float = clampf(float(now - _last_us) / 1.0e6, 0.005, 2.0) if _last_us > 0 else 0.1
		Engine.time_scale = clampf((DT * 0.5) / real, 0.005, 20.0)
		_last_us = now
		await process_frame

func _sample(kind: int, type: String, state: int, pos: Vector3, y: float, hp: float = 100.0, extra: Dictionary = {}) -> Dictionary:
	var d: Dictionary = {"pos": pos, "yaw": y, "hp": hp, "max_hp": 100.0, "state": state, "type": type, "kind": kind, "phase": 0, "atk": "", "qty": 0, "extrapolated": false}
	d.merge(extra, true)
	return d

func _step(n_steps: int = 1) -> void:
	for _i in n_steps:
		world.update_frame(ents.duplicate(), 1, null, DT)
		world.vfx.player.step(DT)
		sim_t += DT
		peak = maxi(peak, world.vfx.player.active_count())
		await _frames(2)

func _dump() -> void:
	for inst: VfxInstance in world.vfx.player._active:
		for c: Node in inst.get_children():
			if c is CPUParticles3D:
				var p: CPUParticles3D = c as CPUParticles3D
				print("[vfx] dbg ", inst.effect_id, " emitting=", p.emitting, " vis=", p.is_visible_in_tree(), " amount=", p.amount, " pos=", p.global_position, " aabb=", p.get_aabb(), " life=", p.lifetime, " mesh=", p.mesh, " mat=", (p.mesh as QuadMesh).material)

func _shot(name: String, idx: int) -> void:
	if OS.get_environment("VFX_DEBUG") == "1":
		_dump()
	await _frames(1)
	var img: Image = root.get_texture().get_image()
	var c: Vector2i = Vector2i(img.get_width() / 2, int(img.get_height() * 0.54))
	var r: Rect2i = Rect2i(c.x - CROP.x / 2, c.y - CROP.y / 2, CROP.x, CROP.y)
	img.get_region(r).save_png("%s/%s_f%d.png" % [out_dir, name, idx])

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var shots: Array = []
	var zoom: float = 0.7
	var i: int = 0
	while i < args.size():
		if args[i] == "--shot" and i + 1 < args.size():
			shots.append(args[i + 1].split(","))
			i += 1
		elif args[i] == "--zone" and i + 1 < args.size():
			zone = args[i + 1]
			i += 1
		elif args[i] == "--at" and i + 1 < args.size():
			var p: PackedStringArray = args[i + 1].split(",")
			origin = Vector3(p[0].to_float(), 0.0, p[1].to_float())
			i += 1
		elif args[i] == "--zoom" and i + 1 < args.size():
			zoom = args[i + 1].to_float()
			i += 1
		elif args[i] == "--yaw" and i + 1 < args.size():
			yaw = args[i + 1].to_float()
			i += 1
		i += 1
	QualitySettings.current = QualitySettings.resolve_startup(args)
	world = ClientWorld.new()
	root.add_child(world)
	var cam_scene: PackedScene = load("res://scenes/camera/iso_camera.tscn") as PackedScene
	cam = cam_scene.instantiate() as IsoCamera
	root.add_child(cam)
	world.camera_shake.connect(cam.shake)
	if world.vfx == null:
		print("[vfx] ERRO: ClientVfx nao criado (sem display?)")
		quit(1)
		return
	world.vfx.player.set_process(false)
	world.show_zone(zone)
	cam.zoom = zoom
	cam._zoom_target = zoom
	cam._apply_projection(true)
	for s: PackedStringArray in shots:
		await _scenario(s)
	print("[vfx] stats=", world.vfx.player.stats, " peak_active=", peak, " counters=", world.vfx.counters)
	quit()

func _reset(cls: String) -> void:
	for id: Variant in ents.keys():
		ents.erase(id)
	world.vfx.player.clear_all()
	world.local_class_id = cls
	world.vfx.local_class_id = cls
	ents[1] = _sample(Protocol.KIND_PLAYER, "player:" + cls, int(CharacterStateMachine.State.IDLE), origin, yaw)
	world.update_frame(ents.duplicate(), 1, null, DT)
	world.vfx.on_frame(ents.duplicate(), 1, DT)
	cam.set_target(world.avatars[1] as Node3D)
	cam.global_position = origin + Vector3.UP * cam.target_height
	sim_t = 0.0

func _fwd() -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))

func _scenario(s: PackedStringArray) -> void:
	var name: String = s[0]
	var mode: PackedStringArray = s[1].split(":")
	var times: PackedFloat32Array = PackedFloat32Array()
	for t: String in s[2].split(";"):
		times.append(t.to_float())
	var last: float = times[times.size() - 1]
	var cls: String = "warrior"
	if mode[0] == "p":
		cls = mode[1]
	await _reset(cls)
	await _step(6)
	sim_t = 0.0
	var next_i: int = 0
	var hit_at: float = -1.0
	var event_script: Callable = Callable()
	var wind: float = 0.0
	var state_until: float = 0.0
	var dodge_dir: Vector3 = _fwd()
	match mode[0]:
		"p":
			ents[20] = _sample(Protocol.KIND_ENEMY, "melee_grunt", int(EnemyAI.State.CHASE), origin + _fwd() * 3.2, yaw + PI)
			var def: ClassDef = ClassCatalog.shared().get_def(cls)
			var slot: String = mode[2]
			var skill: SkillData = ClassCatalog.load_skill(StringName(String(def.skills[slot])))
			var bit: int = {"attack": Protocol.ACTION_ATTACK, "skill_1": Protocol.ACTION_SKILL_1, "skill_2": Protocol.ACTION_SKILL_2, "dodge": Protocol.ACTION_DODGE}[slot]
			world.note_local_actions(0)
			world.note_local_actions(bit)
			wind = skill.windup
			var st: int = int(CharacterStateMachine.State.DODGE) if slot == "dodge" else int(CharacterStateMachine.State.ATTACK)
			(ents[1] as Dictionary)["state"] = st
			state_until = skill.total_duration() if slot != "dodge" else 0.4
			hit_at = skill.windup + 0.06
			if skill.is_projectile():
				hit_at = skill.windup + (3.2 - skill.hitbox_offset) / skill.projectile_speed
			if slot == "dodge":
				hit_at = -1.0
			elif skill.tags.has("area"):
				hit_at = skill.windup + 0.12
		"e":
			ents[1] = _sample(Protocol.KIND_PLAYER, "player:warrior", int(CharacterStateMachine.State.IDLE), origin + _fwd() * 4.6, yaw + PI)
			var ed: EnemyData = EnemyCatalog.data_for(StringName(mode[1]))
			var epos: Vector3 = origin
			ents[30] = _sample(Protocol.KIND_ENEMY, mode[1], int(EnemyAI.State.ATTACK), epos, yaw, 100.0, {"atk": mode[2]})
			world.update_frame(ents.duplicate(), 1, null, DT)
			world.vfx.on_event(Protocol.EVENT_ENEMY_SPAWN, {"id": 30})
			for a: EnemyAttack in ed.all_attacks():
				if String(a.id) == mode[2]:
					wind = a.windup
			hit_at = wind + 0.15
			state_until = wind + 1.2
		"ev":
			match mode[1]:
				"levelup":
					world.on_talents_state({"level": 1, "points_spent": 0})
					world.on_talents_state({"level": 2, "points_spent": 0})
				"heal":
					(ents[1] as Dictionary)["hp"] = 30.0
					await _step(1)
					(ents[1] as Dictionary)["hp"] = 80.0
				"death":
					ents[20] = _sample(Protocol.KIND_ENEMY, "melee_grunt", int(EnemyAI.State.CHASE), origin + _fwd() * 3.0, yaw + PI)
					await _step(2)
					world.apply_event(Protocol.EVENT_DEATH, {"id": 20})
				"spawn":
					ents[20] = _sample(Protocol.KIND_ENEMY, "bark_brute", int(EnemyAI.State.IDLE), origin + _fwd() * 3.0, yaw + PI)
					world.apply_event(Protocol.EVENT_ENEMY_SPAWN, {"id": 20})
				"drop":
					world.apply_event(Protocol.EVENT_DROP, {"pos": origin + _fwd() * 2.5, "item_id": "sword_rare", "qty": 1, "rarity": mode[2] if mode.size() > 2 else "legendary"})
				"crit":
					ents[20] = _sample(Protocol.KIND_ENEMY, "melee_grunt", int(EnemyAI.State.CHASE), origin + _fwd() * 2.2, yaw + PI)
					await _step(1)
					world.apply_event(Protocol.EVENT_DAMAGE, {"target_id": 20, "source_id": 1, "amount": 87.0, "crit": true})
				"hurt":
					await _step(1)
					world.apply_event(Protocol.EVENT_DAMAGE, {"target_id": 1, "source_id": 20, "amount": 18.0, "crit": false})
				"boss":
					ents[40] = _sample(Protocol.KIND_ENEMY, "blight_treant", int(EnemyAI.State.IDLE), origin + _fwd() * 5.0, yaw + PI)
					world.apply_event(Protocol.EVENT_ENEMY_SPAWN, {"id": 40})
				"portal":
					world.vfx.on_zone(WorldDef.shared().get_zone(zone))
					world.apply_event(Protocol.EVENT_ZONE, {"id": 1, "zone": zone, "phase": Protocol.ZONE_PHASE_ARRIVED, "pos": origin + _fwd() * 2.0})
	var hit_done: bool = false
	while sim_t <= last + 0.001:
		if state_until > 0.0 and sim_t >= state_until:
			(ents[1] as Dictionary)["state"] = int(CharacterStateMachine.State.IDLE)
			if ents.has(30):
				(ents[30] as Dictionary)["state"] = int(EnemyAI.State.IDLE)
			state_until = 0.0
		if mode[0] == "p" and mode[2] == "dodge" and sim_t < 0.4:
			(ents[1] as Dictionary)["pos"] = origin + dodge_dir * 4.0 * (sim_t / 0.4)
		if hit_at >= 0.0 and not hit_done and sim_t >= hit_at:
			hit_done = true
			if mode[0] == "p":
				world.apply_event(Protocol.EVENT_DAMAGE, {"target_id": 20, "source_id": 1, "amount": 24.0, "crit": false})
			elif mode[0] == "e":
				world.apply_event(Protocol.EVENT_DAMAGE, {"target_id": 1, "source_id": 30, "amount": 17.0, "crit": false})
		if next_i < times.size() and sim_t >= times[next_i] - 0.001:
			await _shot(name, next_i)
			next_i += 1
		await _step(1)
	print("[vfx] shot ", name, " frames=", next_i, " active_end=", world.vfx.player.active_count())
