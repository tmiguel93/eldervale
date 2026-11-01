class_name LoginScreen
extends Control
## Tela minima de login/personagens/entrada (E4). A logica fica em metodos async testaveis com
## transporte fake; a UI e montada em _ready. Render NAO verificado neste ambiente (headless).
## Emite `play_requested(conn)` com {ticket, host, port, session_id, character_id} para o ClientMain.
## Senha e ticket nunca vao para labels, logs ou campos persistentes.

signal play_requested(conn: Dictionary)

var api: BackendApi
var flow: BackendFlow
var characters: Array = []
var selected: int = -1
var busy: bool = false
var status_text: String = ""
var wanted_session: String = ""
var auto_create_name: String = ""
## E6.1: classe do novo personagem (id do catalogo; o backend valida de novo). Padrao: classe padrao do catalogo.
var selected_class: String = ClassCatalog.DEFAULT_CLASS_ID

var _email: LineEdit
var _password: LineEdit
var _list: ItemList
var _new_name: LineEdit
var _class_pick: OptionButton
var _status: Label
var _buttons: Array[Button] = []
var _play_btn: Button


func setup(p_api: BackendApi, p_session_id: String = "") -> void:
	api = p_api
	flow = BackendFlow.new(api)
	wanted_session = p_session_id


func _ready() -> void:
	if api == null:  # execucao isolada da cena
		var a: BackendApi = BackendApi.new()
		add_child(a)
		var args: ClientArgs = ClientArgs.from_environment()
		var err: String = a.set_base_url(args.backend_url) if args.uses_backend() else "Informe --backend-url."
		setup(a, args.session_id)
		status_text = err
	_build_ui()
	_set_status(status_text)


func _build_ui() -> void:
	var box: VBoxContainer = VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.custom_minimum_size = Vector2(360, 0)
	add_child(box)
	var title: Label = Label.new()
	title.text = "Eldervale"
	box.add_child(title)
	_email = LineEdit.new()
	_email.placeholder_text = "E-mail"
	box.add_child(_email)
	_password = LineEdit.new()
	_password.placeholder_text = "Senha"
	_password.secret = true
	box.add_child(_password)
	var row: HBoxContainer = HBoxContainer.new()
	box.add_child(row)
	row.add_child(_btn("Entrar", func() -> void: await do_login(_email.text, _password.text)))
	row.add_child(_btn("Registrar", func() -> void: await do_register(_email.text, _password.text)))
	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(0, 120)
	_list.item_selected.connect(func(i: int) -> void: selected = i)
	box.add_child(_list)
	_new_name = LineEdit.new()
	_new_name.placeholder_text = "Nome do novo personagem"
	box.add_child(_new_name)
	_class_pick = OptionButton.new()
	for cid: String in ClassCatalog.shared().ids():
		_class_pick.add_item(ClassCatalog.shared().get_def(cid).display_name)
		_class_pick.set_item_metadata(_class_pick.item_count - 1, cid)
		if cid == selected_class:
			_class_pick.select(_class_pick.item_count - 1)
	_class_pick.item_selected.connect(func(i: int) -> void: select_class(String(_class_pick.get_item_metadata(i))))
	box.add_child(_class_pick)
	box.add_child(_btn("Criar personagem", func() -> void: await do_create(_new_name.text)))
	_play_btn = _btn("Jogar", func() -> void: await do_play())
	box.add_child(_play_btn)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)


func _btn(text: String, cb: Callable) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.pressed.connect(cb)
	_buttons.append(b)
	return b


func _set_status(t: String) -> void:
	status_text = t
	if _status != null:
		_status.text = t


func _set_busy(v: bool) -> void:
	busy = v
	for b: Button in _buttons:
		b.disabled = v


## Mensagem mostrada ao voltar do jogo (ex.: servidor recusou).
func show_message(t: String) -> void:
	visible = true
	_set_status(t)


func do_login(email: String, password: String) -> bool:
	if busy:
		return false
	if email.strip_edges().is_empty() or password.is_empty():
		_set_status("Informe e-mail e senha.")
		return false
	_set_busy(true)
	_set_status("Entrando...")
	var ok: bool = await flow.login(email, password, false)
	if ok:
		if _password != null:
			_password.text = ""
		ok = await _refresh_characters()
	else:
		_set_status(flow.last_error)
	_set_busy(false)
	return ok


func do_register(email: String, password: String) -> bool:
	if busy:
		return false
	if email.strip_edges().is_empty() or password.length() < 10:
		_set_status("Informe e-mail e uma senha de pelo menos 10 caracteres.")
		return false
	_set_busy(true)
	var r: Dictionary = await api.register(email, password)
	var ok: bool = bool(r["ok"])
	if ok:
		_set_status("Registro enviado. Agora clique em Entrar.")
	else:
		_set_status(BackendFlow.friendly(String(r["code"]), String(r["message"])))
	_set_busy(false)
	return ok


## Escolhe a classe do proximo personagem. Id fora do catalogo e ignorado (devolve false).
func select_class(class_id: String) -> bool:
	if not ClassCatalog.shared().has_class(class_id):
		return false
	selected_class = class_id
	return true


func do_create(char_name: String) -> bool:
	if busy or not api.is_logged_in():
		return false
	if char_name.strip_edges().length() < 2:
		_set_status("Nome muito curto.")
		return false
	_set_busy(true)
	var r: Dictionary = await api.create_character(char_name.strip_edges(), selected_class)
	var ok: bool = bool(r["ok"])
	if ok:
		ok = await _refresh_characters()
		if ok:
			selected = characters.size() - 1
			_select_in_list()
	else:
		_set_status(BackendFlow.friendly(String(r["code"]), String(r["message"])))
	_set_busy(false)
	return ok


func do_play() -> bool:
	if busy or not api.is_logged_in():
		return false
	if selected < 0 or selected >= characters.size():
		_set_status("Escolha um personagem.")
		return false
	_set_busy(true)
	_set_status("Procurando sessao...")
	var ch: Dictionary = characters[selected]
	var s: Dictionary = await flow.choose_session(wanted_session)
	var conn: Dictionary = {}
	if not s.is_empty():
		_set_status("Pedindo entrada...")
		conn = await flow.request_ticket(s, String(ch.get("id", "")))
	_set_busy(false)
	if conn.is_empty():
		_set_status(flow.last_error)
		return false
	conn["character_id"] = String(ch.get("id", ""))
	_set_status("Conectando...")
	play_requested.emit(conn)
	return true


func _refresh_characters() -> bool:
	var r: Dictionary = await api.list_characters()
	if not r["ok"]:
		_set_status(BackendFlow.friendly(String(r["code"]), String(r["message"])))
		return false
	characters = r["data"]
	if _list != null:
		_list.clear()
		for c: Variant in characters:
			var d: Dictionary = c if c is Dictionary else {}
			var cdef: ClassDef = ClassCatalog.shared().get_def(String(d.get("class_id", "")))
			_list.add_item("%s  (%s nv %d)" % [String(d.get("name", "?")), cdef.display_name if cdef != null else "?", int(d.get("level", 1))])
	selected = 0 if not characters.is_empty() else -1
	_select_in_list()
	_set_status("Escolha um personagem ou crie um novo." if characters.is_empty() else "Pronto.")
	return true


func _select_in_list() -> void:
	if _list != null and selected >= 0 and selected < _list.item_count:
		_list.select(selected)
