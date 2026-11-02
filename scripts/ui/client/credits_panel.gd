class_name CreditsPanel
extends UiPanel
## E8.4: tela de Creditos (tecla F1 ou Menu > Creditos). Lista os pacotes de assets/ASSET_MANIFEST.json agrupados por licenca (CC BY 3.0/4.0
## primeiro, com o aviso de atribuicao obrigatoria), fontes OFL, CC0 e a engine, a partir de CreditsModel (data-driven). Cima/Baixo rolam.

var scroll: ScrollContainer
var content: VBoxContainer
var model: Dictionary = {}


func _init() -> void:
	super._init("Créditos", Vector2(700, 520), "ᛞ", UiIcons.ref("ui", "credits"))
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 340)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 6)
	scroll.add_child(content)
	hint_label.text = "Cima/Baixo rolam | F1 ou Esc fecha"
	rebuild()


func rebuild(p_model: Dictionary = {}) -> void:
	model = p_model if not p_model.is_empty() else CreditsModel.build()
	clear_children(content)
	var intro: String = String(model.get("intro", ""))
	if not intro.is_empty():
		content.add_child(UiStyle.label(intro, UiStyle.TEXT, 0, true))
	for g: Variant in model.get("groups", []):
		var gd: Dictionary = g
		content.add_child(RuneDivider.new())
		content.add_child(UiStyle.heading(String(gd["label"]), UiStyle.ACCENT, 18))
		for n: Variant in gd["notices"]:
			var nl: Label = UiStyle.label(String(n), UiStyle.INFO, 14, true)
			content.add_child(nl)
		for e: Variant in gd["entries"]:
			var ed: Dictionary = e
			var row: VBoxContainer = VBoxContainer.new()
			row.add_theme_constant_override("separation", 0)
			row.add_child(UiStyle.label(String(ed["name"]), UiStyle.TEXT, 16, true))
			var sub: String = String(ed["author"])
			if not String(ed["source"]).is_empty():
				sub += "  -  " + String(ed["source"])
			row.add_child(UiStyle.label(sub, UiStyle.TEXT_DIM, 13, true))
			content.add_child(row)


## Textos exibidos (para testes): nomes de todos os pacotes listados.
func listed_names() -> Array[String]:
	var out: Array[String] = []
	for g: Variant in model.get("groups", []):
		for e: Variant in (g as Dictionary)["entries"]:
			out.append(String((e as Dictionary)["name"]))
	return out


func _on_open() -> void:
	scroll.scroll_vertical = 0


func handle_key(ev: InputEvent) -> bool:
	if UiStyle.key_pressed(ev, KEY_DOWN):
		scroll.scroll_vertical += 70
		return true
	if UiStyle.key_pressed(ev, KEY_UP):
		scroll.scroll_vertical = maxi(scroll.scroll_vertical - 70, 0)
		return true
	return false
