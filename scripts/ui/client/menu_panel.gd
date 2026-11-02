class_name MenuPanel
extends UiPanel
## E8.4: menu de pausa (Esc quando nada esta aberto): Continuar, Opcoes, Creditos. Nao pausa o jogo (e online; so abre a UI e bloqueia as
## acoes de combate como os demais paineis). Emite pedidos; o ClientUi abre o painel correspondente.

signal options_requested()
signal credits_requested()

var buttons: Array[Button] = []
var selected: int = 0


func _init() -> void:
	super._init("Menu", Vector2(380, 330), "ᛟ", UiIcons.ref("ui", "menu"))
	var entries: Array = [["Continuar", &"resume"], ["Opções  (O)", &"options"], ["Créditos  (F1)", &"credits"]]
	for e: Array in entries:
		var b: Button = UiStyle.button(String(e[0]))
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.custom_minimum_size = Vector2(0, 44)
		b.add_theme_font_size_override("font_size", 19)
		b.name = "Menu_" + String(e[1])
		b.pressed.connect(_activate.bind(String(e[1])))
		body.add_child(b)
		buttons.append(b)
	hint_label.text = "Cima/Baixo escolhem | Enter confirma | Esc fecha"
	_paint()


func _paint() -> void:
	for i: int in buttons.size():
		mark_row(buttons[i], i == selected, UiStyle.ACCENT if i == selected else UiStyle.TEXT)


func _on_open() -> void:
	selected = 0
	_paint()


func _activate(which: String) -> void:
	match which:
		"options": options_requested.emit()
		"credits": credits_requested.emit()
		_: close_requested.emit()


func handle_key(ev: InputEvent) -> bool:
	var n: int = UiPanel.step_index(ev, selected, buttons.size())
	if n >= 0:
		selected = n
		_paint()
		return true
	if UiPanel.is_confirm(ev):
		_activate(["resume", "options", "credits"][selected])
		return true
	return false
