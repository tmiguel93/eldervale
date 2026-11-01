class_name MapPanel
extends UiPanel
## E5.5: mapa grande (tecla M) com legenda. Envolve um MapView em modo FULL.

var view: MapView
var zone_label: Label


func _init() -> void:
	super._init("Mapa", Vector2(580, 640))
	zone_label = UiStyle.label("", UiStyle.INFO, 15)
	body.add_child(zone_label)
	view = MapView.new(MapView.Mode.FULL, Vector2(540, 500))
	body.add_child(view)
	body.add_child(UiStyle.label("Branco: voce | Verde: jogadores | Amarelo: NPC | Ciano: portal | Laranja: bancada | Vermelho: inimigos", UiStyle.TEXT_DIM, 12, true))
	hint_label.text = "M abre/fecha | Esc fecha"


func set_zone_title(text: String) -> void:
	zone_label.text = text
