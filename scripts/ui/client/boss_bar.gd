class_name BossBar
extends PanelContainer
## E5.5/E8.4: barra de vida do chefe/mini-chefe (EnemyData tier boss/mini_boss). Usa so campos ja replicados: hp, max_hp, type, phase.
## E8.4 corrige o bug "a barra do chefe permanece na tela longe do chefe / em outra zona": so aparece com o chefe VIVO, DENTRO da zona atual
## (ZoneDef.contains) e a menos de SHOW_RANGE m do jogador local (histerese: some alem de HIDE_RANGE); sem posicao local conhecida, sem
## snapshot recente ou fora de PLAYING a barra some (ClientUi.reset_boss / refresh sem posicao). Moldura dramatica (ferro, ouro e sangue)
## com caveiras, nome em Cinzel Decorative, barra com reflexo e atraso de dano (StatBar BOSS); aparece/some com fade e desliza.

const SHOW_RANGE: float = 40.0
const HIDE_RANGE: float = 46.0
const ZONE_MARGIN: float = 1.5

var current_id: int = -1
var current_phase: int = -1
var _name: Label
var _tier: Label
var _phase: Label
var _bar: StatBar
var _hiding: bool = false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	add_theme_stylebox_override("panel", UiArt.boss())
	var v: VBoxContainer = VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 3)
	add_child(v)
	var head: HBoxContainer = HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_theme_constant_override("separation", 10)
	v.add_child(head)
	head.add_child(UiIcons.make(UiIcons.ref("ui", "boss_left"), 30.0, Color("#e0693f"), "B"))
	_name = UiStyle.label("", Color("#ffd9a0"), 24, false, "title")
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.add_theme_color_override("font_outline_color", Color(0.1, 0.0, 0.0, 0.95))
	_name.add_theme_constant_override("outline_size", 5)
	head.add_child(_name)
	head.add_child(UiIcons.make(UiIcons.ref("ui", "boss_right"), 30.0, Color("#e0693f"), "B"))
	_bar = StatBar.new(StatBar.Kind.BOSS, 480, 22)
	v.add_child(_bar)
	var foot: HBoxContainer = HBoxContainer.new()
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(foot)
	_tier = UiStyle.label("", Color("#d9a27a"), 13, false, "heading")
	_tier.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(_tier)
	_phase = UiStyle.label("", UiStyle.TEXT_DIM, 13, false, "heading")
	foot.add_child(_phase)


## Escolhe o chefe vivo mais proximo de `from` (ou o primeiro). `zone` (opcional): so chefes dentro da zona. `max_range` (m, plano XZ):
## so chefes ate essa distancia (precisa de `from`). Devolve a entidade ou {}. Funcao pura.
static func pick_boss(entities: Array, from: Variant = null, zone: ZoneDef = null, max_range: float = INF) -> Dictionary:
	var best: Dictionary = {}
	var best_d: float = INF
	for e0: Variant in entities:
		if typeof(e0) != TYPE_DICTIONARY:
			continue
		var e: Dictionary = e0
		if int(e.get("kind", 0)) != Protocol.KIND_ENEMY or float(e.get("hp", 0.0)) <= 0.0:
			continue
		var data: EnemyData = EnemyCatalog.data_for(StringName(String(e.get("type", ""))))
		if data == null or not data.is_boss():
			continue
		var epos: Variant = e.get("pos")
		if zone != null and not (epos is Vector3 and zone.contains(epos as Vector3, ZONE_MARGIN)):
			continue
		var d: float = 0.0
		if from is Vector3 and epos is Vector3:
			d = Vector2((epos as Vector3).x - (from as Vector3).x, (epos as Vector3).z - (from as Vector3).z).length()
		if is_finite(max_range) and d > max_range:
			continue
		if d < best_d:
			best_d = d
			best = e
	return best


## Atualiza a barra. `from` = posicao local (Vector3); sem ela a barra fica oculta (nao da para saber se o chefe esta perto).
func refresh(entities: Array, from: Variant = null, zone: ZoneDef = null) -> void:
	if not (from is Vector3):
		reset()
		return
	var limit: float = HIDE_RANGE if current_id >= 0 else SHOW_RANGE
	var boss: Dictionary = pick_boss(entities, from, zone, limit)
	if boss.is_empty():
		hide_bar()
		return
	var was_visible: bool = visible and not _hiding
	_hiding = false
	var new_id: int = int(boss["id"])
	var phase: int = int(boss.get("phase", 0))
	current_id = new_id
	_name.text = UiText.enemy_name(String(boss["type"]))
	var data: EnemyData = EnemyCatalog.data_for(StringName(String(boss["type"])))
	_tier.text = "Mini-chefe" if data != null and data.tier == EnemyData.TIER_MINI_BOSS else "Chefe"
	_phase.text = "Fase %d" % (phase + 1) if boss.has("phase") else ""
	UiStyle.set_bar(_bar, float(boss["hp"]), float(boss["max_hp"]), "%d / %d" % [int(ceilf(float(boss["hp"]))), int(ceilf(float(boss["max_hp"])))])
	if not was_visible:
		UiFx.appear(self, -12.0)
	elif current_phase >= 0 and phase != current_phase:
		UiFx.pulse(self, Color(1.7, 1.2, 0.9, 1.0), 0.5)  # troca de fase: clarao + escala
		UiFx.shake(self, 4.0, 0.3)
	current_phase = phase


## Some com fade (imediato em headless).
func hide_bar() -> void:
	current_id = -1
	current_phase = -1
	if not visible or _hiding:
		return
	_hiding = true
	UiFx.vanish(self, func() -> void: _hiding = false)


## Some AGORA, sem animacao (troca de zona, desconexao, reset de sessao).
func reset() -> void:
	current_id = -1
	current_phase = -1
	_hiding = false
	UiFx.hide_now(self)
