extends SceneTree
## Ferramenta de desenvolvimento (E8.2): monta o cenario de cada zona em modo headless (modelos forcados) e imprime o orcamento
## estatico por preset: instancias, MultiMeshes (= draw calls maximos de decoracao), pecas fixas, luzes, assets ausentes.
## Uso: godot --headless --path . --script res://tools/scenery_stats.gd
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await physics_frame
	ModelRig.force_enabled = 1
	var wd: WorldDef = WorldDef.shared()
	for zid: String in SceneryTheme.zone_ids():
		var zone: ZoneDef = wd.get_zone(zid)
		for preset: int in [QualitySettings.Preset.LOW, QualitySettings.Preset.MEDIUM, QualitySettings.Preset.HIGH]:
			var holder: Node3D = Node3D.new()
			root.add_child(holder)
			var t0: int = Time.get_ticks_msec()
			var zr: Node3D = WorldBuilder.build_zone(holder, zone, true, NpcDirectory.shared())
			var info: Dictionary = SceneryBuilder.decorate(zr, zone, preset, NpcDirectory.shared())
			var ms: int = Time.get_ticks_msec() - t0
			print("[stats] %s %s %s plan=%d build_ms=%d" % [zid, QualitySettings.preset_name(preset), str(info.get("stats", {})), int(info.get("plan_size", 0)), ms])
			holder.queue_free()
			await process_frame
	print("[stats] extract_count=", SceneryBuilder.extract_count)
	quit()
