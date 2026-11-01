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
var _open: bool = false


func _init(p_title: String = "", p_size: Vector2 = Vector2(520, 360)) -> void:
	custom_minimum_size = p_size
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var root: VBoxContainer = VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	add_child(root)
	var head: HBoxContainer = HBoxContainer.new()
	root.add_child(head)
	title_label = UiStyle.label(p_title, UiStyle.ACCENT, 18)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title_label)
	var close_btn: Button = UiStyle.button("X")
	close_btn.name = "CloseButton"
	close_btn.tooltip_text = "Fechar (Esc)"
	close_btn.pressed.connect(func() -> void: close_requested.emit())
	head.add_child(close_btn)
	body = VBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 6)
	root.add_child(body)
	status_label = UiStyle.label("", UiStyle.TEXT_DIM, 0, true)
	root.add_child(status_label)
	hint_label = UiStyle.label("", UiStyle.TEXT_DIM, 12, true)
	root.add_child(hint_label)


func open() -> void:
	_open = true
	visible = true
	_on_open()


func close() -> void:
	_open = false
	visible = false


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
