class_name Boot
extends Control
## Cena de boot minima (E0). Sem gameplay, rede ou backend.
## Valida referencias no _ready, exibe status e imprime a versao da engine.

const BOOT_MESSAGE: String = "Eldervale — boot OK"

@onready var _status_label: Label = $StatusLabel


func _ready() -> void:
	if _status_label == null:
		push_error("Boot: no 'StatusLabel' nao encontrado em boot.tscn.")
		return
	_status_label.text = BOOT_MESSAGE
	var info: Dictionary = Engine.get_version_info()
	print("Eldervale boot: Godot %s" % str(info.get("string", "desconhecida")))
