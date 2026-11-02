class_name UiTooltip
extends RefCounted
## E8.4: tooltip estilizado (1a linha em cabecalho na cor da raridade, resto em corpo, largura limitada). Usado por ItemSlot e
## SkillSlot via _make_custom_tooltip; o texto continua em `tooltip_text` (testes/leitores de tela).

const MAX_W: float = 300.0


static func build(text: String, accent: Color = UiStyle.ACCENT) -> Control:
	var pc: PanelContainer = PanelContainer.new()
	pc.theme = UiStyle.theme()
	pc.add_theme_stylebox_override("panel", UiArt.tooltip())
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v: VBoxContainer = VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	pc.add_child(v)
	var lines: PackedStringArray = text.split("\n")
	for i: int in lines.size():
		var l: Label = UiStyle.label(lines[i], accent if i == 0 else (UiStyle.TEXT_DIM if i == 1 else UiStyle.TEXT), 17 if i == 0 else 15, true, "heading" if i == 0 else "")
		l.custom_minimum_size = Vector2(minf(MAX_W, 120.0 + lines[i].length() * 6.0), 0)
		v.add_child(l)
	return pc
