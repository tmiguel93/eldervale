class_name UiPanel
extends PanelContainer
## E5.5: base dos paineis modais da UI do cliente. Apresentacao pura: o painel recebe dados prontos,
## emite sinais com a intencao do jogador e NAO conhece ClientSession (a cola e o ClientUi).
## Teclado: `handle_key(ev)` devolve true se consumiu o evento. Esc e tratado pelo ClientUi.

signal close_requested()

var title_label: Label
var status_label: Label
var body: VBoxContainer
var hint_label: Label
var close_button: Button
var rune_label: Label
var _open: bool = false


## E8.4: `p_rune` = runa decorativa dos dois lados do titulo; `p_icon` = referencia game-icons (UiIcons) ao lado do titulo.
func _init(p_title: String = "", p_size: Vector2 = Vector2(520, 360), p_rune: String = "ᛟ", p_icon: String = "") -> void:
	custom_minimum_size = p_size
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme_type_variation = &"ModalPanel"
	visible = false
	var root: VBoxContainer = VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	add_child(root)
	var head: HBoxContainer = HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	root.add_child(head)
	if not p_icon.is_empty():
		var ic: Control = UiIcons.make(p_icon, 28.0, UiStyle.ACCENT, p_title)
		head.add_child(ic)
	rune_label = Label.new()
	rune_label.text = p_rune
	rune_label.theme_type_variation = &"RuneLabel"
	rune_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(rune_label)
	title_label = Label.new()
	title_label.text = p_title
	title_label.theme_type_variation = &"PanelTitle"
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title_label)
	close_button = UiStyle.button("X")
	close_button.name = "CloseButton"
	close_button.theme_type_variation = &"CloseButton"
	close_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	close_button.tooltip_text = "Fechar (Esc)"
	close_button.pressed.connect(func() -> void: close_requested.emit())
	head.add_child(close_button)
	root.add_child(RuneDivider.new())
	body = VBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 6)
	root.add_child(body)
	status_label = UiStyle.label("", UiStyle.TEXT_DIM, 0, true)
	root.add_child(status_label)
	hint_label = UiStyle.label("", UiStyle.TEXT_DIM, 13, true)
	root.add_child(hint_label)


## E8.4: mantem o painel do tamanho do conteudo e centrado (offsets de ancora 0.5; o Godot so cresce o offset, nunca encolhe).
func recenter() -> void:
	var m: Vector2 = get_combined_minimum_size()
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	offset_left = -m.x * 0.5
	offset_right = m.x * 0.5
	offset_top = -m.y * 0.5
	offset_bottom = m.y * 0.5


func _process(_delta: float) -> void:
	if visible and (size - get_combined_minimum_size()).length() > 1.0:
		recenter()


func open() -> void:
	_open = true
	recenter()
	UiFx.appear(self)  # E8.4: fade + escala/subida (imediato em headless; so fade com reduce_motion)
	_on_open()


func close() -> void:
	if not _open and not visible:
		return
	_open = false
	UiFx.vanish(self)  # E8.4: fade-out; `is_open()` ja e false, `visible` cai ao fim do fade (imediato em headless)


func is_open() -> bool:
	return _open


## Mensagem de estado/erro do painel (cor por `kind`: info, good, bad).
func set_status(text: String, kind: String = "info") -> void:
	status_label.text = text
	match kind:
		"bad": status_label.add_theme_color_override("font_color", UiStyle.BAD)
		"good": status_label.add_theme_color_override("font_color", UiStyle.GOOD)
		_: status_label.add_theme_color_override("font_color", UiStyle.TEXT_DIM)


## Avanca temporizadores internos (chamado pelo ClientUi a cada frame).
func advance(_delta: float) -> void:
	pass


func handle_key(_ev: InputEvent) -> bool:
	return false


func _on_open() -> void:
	pass


## E8.4: pinta uma linha-botao de lista (cor do texto/icone para todos os estados; selecionada = moldura de hover do tema).
static func mark_row(b: Button, selected: bool, col: Color) -> void:
	for c: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(c, col)
	for ic: String in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color", "icon_hover_pressed_color"]:
		b.add_theme_color_override(ic, col)
	if selected:
		b.add_theme_stylebox_override("normal", UiArt.button("hover"))
	else:
		b.remove_theme_stylebox_override("normal")


## E8.4: icone (game-icons) a esquerda do texto de uma linha-botao; sem arquivo nao poe nada.
static func set_row_icon(b: Button, icon_ref: String, px: int = 22) -> void:
	var tex: Texture2D = UiIcons.texture(icon_ref)
	if tex == null:
		return
	b.icon = tex
	b.expand_icon = true
	b.add_theme_constant_override("icon_max_width", px)
	b.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


## Remove e libera os filhos de um container.
static func clear_children(node: Node) -> void:
	for c: Node in node.get_children():
		node.remove_child(c)
		c.queue_free()


## Move um indice de selecao (com wrap) por teclado; devolve o novo indice ou -1 se `ev` nao e Cima/Baixo.
static func step_index(ev: InputEvent, current: int, count: int) -> int:
	if count <= 0:
		return -1
	if UiStyle.key_pressed(ev, KEY_UP):
		return posmod(current - 1, count)
	if UiStyle.key_pressed(ev, KEY_DOWN):
		return posmod(current + 1, count)
	return -1


static func is_confirm(ev: InputEvent) -> bool:
	return UiStyle.key_pressed(ev, KEY_ENTER, false) or UiStyle.key_pressed(ev, KEY_KP_ENTER, false)
