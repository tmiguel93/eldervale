class_name ClientHud
extends CanvasLayer
## HUD minima de rede: estado, id, entidades, RTT, snapshots. Apresentacao pura.

var _label: Label
var _notice: String = ""
var _notice_left: float = 0.0


static func format_status(session: ClientSession) -> String:
	var rtt: String = "-" if session.last_rtt_ms < 0.0 else "%d ms" % int(round(session.last_rtt_ms))
	var state_name: String = ClientSession.State.keys()[session.state]
	return "%s\nEstado: %s | Jogador: %s | Entidades: %d | RTT: %s | Snapshots: %d" % [
		session.message, state_name,
		"-" if session.player_id < 0 else str(session.player_id),
		session.entity_count, rtt, session.result.snapshots_received]


func _ready() -> void:
	_label = Label.new()
	_label.position = Vector2(12, 8)
	add_child(_label)


func show_notice(text: String) -> void:
	_notice = text
	_notice_left = 4.0


func refresh(session: ClientSession, delta: float) -> void:
	if _label == null:
		return
	_notice_left = maxf(_notice_left - delta, 0.0)
	var t: String = format_status(session)
	if _notice_left > 0.0:
		t += "\n" + _notice
	_label.text = t
