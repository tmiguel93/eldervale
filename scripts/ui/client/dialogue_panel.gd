class_name DialoguePanel
extends UiPanel
## E5.5: janela de dialogo com NPC. Mostra a fala e as escolhas ENVIADAS PELO SERVIDOR (view de s_dialogue);
## emite `choice_picked(index)` (o indice e o da lista visivel do servidor). Teclado: Cima/Baixo, Enter,
## teclas 1..9, Esc fecha (ClientUi). No no terminal ha so "Fechar".

signal choice_picked(index: int)
signal finished()  ## fechar no no terminal (o servidor ja encerrou a conversa)

const MAX_CHOICES: int = 16
const MAX_TEXT_LEN: int = 700

var speaker_label: Label
var text_label: Label
var list: VBoxContainer
var npc_id: String = ""
var terminal: bool = false
var selected: int = 0
var _choices: Array[Dictionary] = []  ## {index, text}
var _buttons: Array[Button] = []


func _init() -> void:
	super._init("Dialogo", Vector2(560, 300))
	speaker_label = UiStyle.label("", UiStyle.INFO, 17)
	body.add_child(speaker_label)
	text_label = UiStyle.label("", UiStyle.TEXT, 0, true)
	text_label.custom_minimum_size = Vector2(0, 90)
	body.add_child(text_label)
	list = VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	body.add_child(list)
	hint_label.text = "Cima/Baixo ou 1-9 escolhem, Enter confirma, Esc sai"


## Mostra uma view do servidor ({npc_id, speaker, text, text_key, choices:[{index,text,text_key}], terminal}).
func show_view(view: Dictionary) -> void:
	npc_id = String(view.get("npc_id", ""))
	var speaker: String = String(view.get("speaker", ""))
	speaker_label.text = UiText.npc_name(speaker) if speaker.begins_with("npc_") else UiText.clamp_text(speaker, 48)
	title_label.text = speaker_label.text if not speaker_label.text.is_empty() else "Dialogo"
	var txt: String = String(view.get("text", ""))
	if txt.strip_edges().is_empty():
		txt = String(view.get("text_key", ""))
	text_label.text = UiText.clamp_text(txt, MAX_TEXT_LEN)
	_choices = []
	var raw: Variant = view.get("choices", [])
	if typeof(raw) == TYPE_ARRAY:
		for c: Variant in raw:
			if _choices.size() >= MAX_CHOICES:
				break
			if typeof(c) != TYPE_DICTIONARY or typeof((c as Dictionary).get("index", null)) != TYPE_INT:
				continue
			var ct: String = String((c as Dictionary).get("text", ""))
			if ct.strip_edges().is_empty():
				ct = String((c as Dictionary).get("text_key", "..."))
			_choices.append({"index": int((c as Dictionary)["index"]), "text": UiText.clamp_text(ct, 160)})
	terminal = _choices.is_empty() or bool(view.get("terminal", false))
	selected = 0
	set_status("")
	_rebuild()
	open()


func choice_count() -> int:
	return _choices.size()


## Texto das escolhas exibidas (para testes/leitura).
func choice_texts() -> Array[String]:
	var out: Array[String] = []
	for c: Dictionary in _choices:
		out.append(String(c["text"]))
	return out


func _rebuild() -> void:
	clear_children(list)
	_buttons = []
	if terminal:
		var b: Button = UiStyle.button("[Enter] Fechar")
		b.name = "CloseChoice"
		b.pressed.connect(_finish)
		list.add_child(b)
		_buttons.append(b)
	else:
		for i: int in _choices.size():
			var b2: Button = UiStyle.button("%d. %s" % [i + 1, String(_choices[i]["text"])])
			b2.name = "Choice%d" % i
			b2.pressed.connect(_pick.bind(i))
			list.add_child(b2)
			_buttons.append(b2)
	_paint()


func _paint() -> void:
	for i: int in _buttons.size():
		_buttons[i].add_theme_color_override("font_color", UiStyle.ACCENT if i == selected else UiStyle.TEXT)


func _pick(i: int) -> void:
	if i < 0 or i >= _choices.size():
		return
	selected = i
	_paint()
	choice_picked.emit(int(_choices[i]["index"]))


func _finish() -> void:
	finished.emit()


func advance_or_close() -> void:
	if terminal:
		_finish()


func handle_key(ev: InputEvent) -> bool:
	if not is_open():
		return false
	if terminal:
		if is_confirm(ev):
			_finish()
			return true
		return false
	var n: int = step_index(ev, selected, _choices.size())
	if n >= 0:
		selected = n
		_paint()
		return true
	if is_confirm(ev):
		_pick(selected)
		return true
	if ev is InputEventKey and (ev as InputEventKey).pressed and not (ev as InputEventKey).echo:
		var k: InputEventKey = ev
		for d: int in 9:
			if k.keycode == KEY_1 + d or k.physical_keycode == KEY_1 + d:
				if d < _choices.size():
					_pick(d)
				return true
	return false
