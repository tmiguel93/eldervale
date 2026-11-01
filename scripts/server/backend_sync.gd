class_name BackendSync
extends Node
## Ciclo de vida da sessao no backend + persistencia dos personagens (lado servidor Godot).
## - Registra a sessao (POST /internal/sessions), heartbeat periodico, close no encerramento.
## - Por personagem: `revision` e uma fila SERIALIZADA de operacoes (load, checkpoint, reward,
##   disconnect, release): uma por vez, na ordem de enfileiramento (checkpoint e recompensa nunca
##   correm em paralelo). Autosave periodico envia o estado completo com expected_revision.
## - 409 de revision no checkpoint: recarrega o personagem, adota a revision e avisa o
##   `conflict_handler` (a sessao reaplica o estado do backend); nao derruba ninguem.
## - Falha permanente de recompensa: logada; o estado em memoria fica e o proximo checkpoint reconcilia.
## - Tempo: tudo avanca em `tick(delta)` (chamado por _process; testes chamam direto).
## Nunca loga tickets nem o segredo.

signal registered(session_id: String)

class CharSync extends RefCounted:
	var character_id: String = ""
	var revision: int = -1
	var queue: Array[Dictionary] = []
	var busy: bool = false
	var inflight_kind: String = ""
	var live: bool = false ## jogador conectado: elegivel a autosave
	var terminal: bool = false ## depois de drenar a fila, esquecer o personagem

var client: BackendClient
var region: String = "local"
var capacity: int = 4
var endpoint: String = "127.0.0.1:24680"
var protocol_version: int = Protocol.VERSION
var heartbeat_interval_sec: float = 10.0
var autosave_interval_sec: float = 30.0
var register_retry_sec: float = 5.0
var register_retry_max_sec: float = 30.0
var shutdown_timeout_sec: float = 8.0
var session_id_file: String = ""
## (character_id: String) -> Dictionary com o estado completo ({} se nao ha jogador).
var snapshot_provider: Callable
## (character_id: String, character: Dictionary) quando um 409 de revision recarregou o personagem.
var conflict_handler: Callable

var session_id: String = ""
var _registered: bool = false
var _register_inflight: bool = false
var _register_wait: float = 0.0
var _register_delay: float = 0.0
var _register_failures: int = 0
var _hb_timer: float = 0.0
var _hb_inflight: bool = false
var _hb_failures: int = 0
var _autosave_timer: float = 0.0
var _chars: Dictionary = {} ## character_id -> CharSync
var _shutting_down: bool = false
var _close_sent: bool = false
var _shutdown_done: bool = false
var _shutdown_elapsed: float = 0.0


func _ready() -> void:
	set_process(true)


func _process(delta: float) -> void:
	tick(delta)


func start() -> void:
	_register_delay = register_retry_sec
	_try_register()


func is_ready() -> bool:
	return _registered and not session_id.is_empty() and not _shutting_down


func char_sync(character_id: String) -> CharSync:
	return _chars.get(character_id) as CharSync


func revision_of(character_id: String) -> int:
	var cs: CharSync = char_sync(character_id)
	return cs.revision if cs != null else -1


func pending_ops() -> int:
	var n: int = 0
	for cs: CharSync in _chars.values():
		n += cs.queue.size() + (1 if cs.busy else 0)
	return n


# ------------------------------------------------------------------ tempo

func tick(delta: float) -> void:
	if _shutting_down:
		_tick_shutdown(delta)
		return
	if not _registered:
		if not _register_inflight:
			_register_wait += delta
			if _register_wait >= _register_delay:
				_try_register()
		return
	_hb_timer += delta
	if _hb_timer >= heartbeat_interval_sec and not _hb_inflight:
		_hb_timer = 0.0
		_send_heartbeat()
	_autosave_timer += delta
	if _autosave_timer >= autosave_interval_sec:
		_autosave_timer = 0.0
		autosave_now()


## Enfileira um checkpoint (com coalescencia) de todo personagem vivo. Devolve quantos enfileirou.
func autosave_now() -> int:
	var n: int = 0
	if not snapshot_provider.is_valid():
		return 0
	for cid: String in _chars.keys():
		var cs: CharSync = _chars[cid] as CharSync
		if cs == null or not cs.live or cs.terminal or cs.revision < 0:
			continue
		var state: Dictionary = snapshot_provider.call(cid)
		if state.is_empty():
			continue
		if enqueue_checkpoint(cid, state, true):
			n += 1
	return n


# ------------------------------------------------------------------ registro / heartbeat

func _try_register() -> void:
	if _registered or _register_inflight or client == null or not client.is_configured():
		return
	_register_inflight = true
	client.register_session(region, capacity, protocol_version, endpoint, _on_registered)


func _on_registered(r: Dictionary) -> void:
	_register_inflight = false
	_register_wait = 0.0
	var sid: String = String(r["data"].get("session_id", "")) if r["ok"] else ""
	if r["ok"] and BackendClient._id(sid) != "invalid":
		session_id = sid
		client.fencing_session_id = sid
		_registered = true
		_hb_timer = 0.0
		_hb_failures = 0
		_register_failures = 0
		_register_delay = register_retry_sec
		var hb_timeout: float = float(r["data"].get("heartbeat_timeout_seconds", 0.0))
		if hb_timeout >= 3.0:
			heartbeat_interval_sec = minf(heartbeat_interval_sec, hb_timeout / 3.0)
		ServerLog.info("[sync] sessao registrada (%s)" % sid)
		_write_session_file()
		registered.emit(sid)
	else:
		_register_failures += 1
		_register_delay = minf(register_retry_max_sec, register_retry_sec * pow(2.0, float(_register_failures - 1)))
		ServerLog.warn("[sync] falha ao registrar sessao (status %d, %s); nova tentativa em %.0fs" % [int(r["status"]), String(r["code"]), _register_delay])


func _write_session_file() -> void:
	if session_id_file.is_empty():
		return
	var f: FileAccess = FileAccess.open(session_id_file, FileAccess.WRITE)
	if f == null:
		ServerLog.warn("[sync] nao foi possivel gravar --session-id-file (erro %d)" % FileAccess.get_open_error())
		return
	f.store_string(session_id)
	f.close()


func _send_heartbeat() -> void:
	_hb_inflight = true
	client.heartbeat(session_id, _on_heartbeat)


func _on_heartbeat(r: Dictionary) -> void:
	_hb_inflight = false
	if r["ok"]:
		_hb_failures = 0
		return
	_hb_failures += 1
	if int(r["status"]) == 404 or String(r["code"]) == "session_closed":
		ServerLog.warn("[sync] sessao perdida no backend (%s); registrando de novo" % String(r["code"]))
		_registered = false
		session_id = ""
		client.fencing_session_id = ""
		_register_wait = 0.0
		_register_delay = register_retry_sec
	else:
		ServerLog.warn("[sync] heartbeat falhou (%s), falhas seguidas: %d" % [String(r["code"]), _hb_failures])


# ------------------------------------------------------------------ resgate / carga

## Resgata o ticket. cb({ok, status, code, character_id, reconnected}). Sem retry (uso unico).
func redeem(ticket: String, cb: Callable) -> void:
	if not is_ready():
		cb.call({"ok": false, "status": 0, "code": "session_unavailable", "character_id": "", "reconnected": false})
		return
	client.redeem(ticket, session_id, _on_redeem_result.bind(cb))


func _on_redeem_result(r: Dictionary, cb: Callable) -> void:
	var cid: String = String(r["data"].get("character_id", "")) if r["ok"] else ""
	var ok: bool = r["ok"] and BackendClient._id(cid) != "invalid"
	if cb.is_valid():
		cb.call({"ok": ok, "status": r["status"], "code": r["code"] if r["code"] != "" or ok else "bad_response",
			"character_id": cid if ok else "", "reconnected": bool(r["data"].get("reconnected", false))})


## Enfileira a carga (GET). cb({ok, status, code, character}). Define a revision do personagem.
func load_character(character_id: String, cb: Callable) -> void:
	var cs: CharSync = _get_or_create(character_id)
	cs.terminal = false
	cs.live = false
	_enqueue(cs, {"kind": "load", "cb": cb})


func mark_live(character_id: String) -> void:
	var cs: CharSync = char_sync(character_id)
	if cs != null:
		cs.live = true


# ------------------------------------------------------------------ operacoes enfileiradas

## Checkpoint com o estado ja capturado. coalesce=true descarta se ja ha um checkpoint pendente/em voo.
func enqueue_checkpoint(character_id: String, state: Dictionary, coalesce: bool) -> bool:
	var cs: CharSync = char_sync(character_id)
	if cs == null:
		return false
	if coalesce:
		if cs.inflight_kind == "checkpoint":
			return false
		for op: Dictionary in cs.queue:
			if op["kind"] == "checkpoint":
				return false
	_enqueue(cs, {"kind": "checkpoint", "state": state})
	return true


func enqueue_reward(character_id: String, idempotency_key: String, xp: int, items: Array, quest_id: String = "") -> bool:
	var cs: CharSync = char_sync(character_id)
	if cs == null:
		return false
	_enqueue(cs, {"kind": "reward", "key": idempotency_key, "xp": xp, "items": items, "quest_id": quest_id})
	return true


## E5.4: crafting. cb({ok, status, code, replayed}) quando a operacao termina (a fila e a mesma dos checkpoints/recompensas).
func enqueue_craft(character_id: String, idempotency_key: String, recipe_id: String, cb: Callable) -> bool:
	var cs: CharSync = char_sync(character_id)
	if cs == null:
		return false
	_enqueue(cs, {"kind": "craft", "key": idempotency_key, "recipe_id": recipe_id, "cb": cb})
	return true


## E5.4: recarrega o personagem do banco (na ordem da fila) e reaplica na memoria via `conflict_handler`.
func enqueue_reload(character_id: String) -> bool:
	var cs: CharSync = char_sync(character_id)
	if cs == null:
		return false
	_enqueue(cs, {"kind": "reload"})
	return true


## Desconexao do peer: checkpoint final + POST disconnect (lock mantido pela janela de reconexao).
func disconnect_character(character_id: String, final_state: Dictionary) -> void:
	var cs: CharSync = char_sync(character_id)
	if cs == null:
		return
	cs.live = false
	cs.terminal = true
	if not final_state.is_empty():
		_enqueue(cs, {"kind": "checkpoint", "state": final_state})
	_enqueue(cs, {"kind": "disconnect"})


## Encerramento (ou carga que falhou): checkpoint opcional + release.
func release_character(character_id: String, final_state: Dictionary) -> void:
	var cs: CharSync = char_sync(character_id)
	if cs == null:
		cs = _get_or_create(character_id)
	cs.live = false
	cs.terminal = true
	if not final_state.is_empty():
		_enqueue(cs, {"kind": "checkpoint", "state": final_state})
	_enqueue(cs, {"kind": "release"})


func _get_or_create(character_id: String) -> CharSync:
	var cs: CharSync = char_sync(character_id)
	if cs == null:
		cs = CharSync.new()
		cs.character_id = character_id
		_chars[character_id] = cs
	return cs


func _enqueue(cs: CharSync, op: Dictionary) -> void:
	cs.queue.append(op)
	_pump(cs)


func _pump(cs: CharSync) -> void:
	if cs.busy:
		return
	if cs.queue.is_empty():
		if cs.terminal and _chars.get(cs.character_id) == cs:
			_chars.erase(cs.character_id)
		return
	var op: Dictionary = cs.queue.pop_front()
	cs.busy = true
	cs.inflight_kind = String(op["kind"])
	var cid: String = cs.character_id
	match String(op["kind"]):
		"load":
			client.get_character(cid, _op_load_done.bind(cs, op))
		"checkpoint":
			client.checkpoint(cid, cs.revision, op["state"], _op_checkpoint_done.bind(cs, op))
		"reward":
			client.rewards(cid, String(op["key"]), int(op["xp"]), op["items"], _op_reward_done.bind(cs, op), String(op.get("quest_id", "")))
		"craft":
			client.craft(cid, String(op["key"]), String(op["recipe_id"]), _op_craft_done.bind(cs, op))
		"reload":
			client.get_character(cid, _op_conflict_reloaded.bind(cs))
		"disconnect":
			if session_id.is_empty():
				_op_finish(cs)
			else:
				client.disconnect_character(cid, session_id, _op_simple_done.bind(cs, "disconnect"))
		"release":
			if session_id.is_empty():
				_op_finish(cs)
			else:
				client.release_character(cid, session_id, _op_simple_done.bind(cs, "release"))
		_:
			_op_finish(cs)


func _op_finish(cs: CharSync) -> void:
	cs.busy = false
	cs.inflight_kind = ""
	_pump(cs)


func _adopt_revision(cs: CharSync, data: Dictionary) -> void:
	var ch: Variant = data.get("character", null)
	if typeof(ch) == TYPE_DICTIONARY and (ch as Dictionary).has("revision"):
		cs.revision = int((ch as Dictionary)["revision"])


func _op_load_done(r: Dictionary, cs: CharSync, op: Dictionary) -> void:
	var ch: Dictionary = {}
	if r["ok"] and typeof(r["data"].get("character", null)) == TYPE_DICTIONARY:
		ch = r["data"]["character"]
		cs.revision = int(ch.get("revision", 0))
	var cb: Callable = op["cb"]
	if cb.is_valid():
		cb.call({"ok": not ch.is_empty(), "status": r["status"], "code": r["code"], "character": ch})
	_op_finish(cs)


func _op_checkpoint_done(r: Dictionary, cs: CharSync, _op: Dictionary) -> void:
	if r["ok"]:
		_adopt_revision(cs, r["data"])
		_op_finish(cs)
		return
	if int(r["status"]) == 409 and String(r["code"]) == "revision_conflict":
		ServerLog.warn("[sync] conflito de revision no checkpoint de %s; recarregando do backend" % cs.character_id)
		client.get_character(cs.character_id, _op_conflict_reloaded.bind(cs))
		return
	ServerLog.warn("[sync] checkpoint de %s falhou (status %d, %s); proximo autosave reconcilia" % [cs.character_id, int(r["status"]), String(r["code"])])
	_op_finish(cs)


func _op_conflict_reloaded(r: Dictionary, cs: CharSync) -> void:
	if r["ok"] and typeof(r["data"].get("character", null)) == TYPE_DICTIONARY:
		var ch: Dictionary = r["data"]["character"]
		cs.revision = int(ch.get("revision", cs.revision))
		if conflict_handler.is_valid() and not cs.terminal:
			conflict_handler.call(cs.character_id, ch)
	else:
		ServerLog.warn("[sync] recarga apos conflito falhou (%s)" % String(r["code"]))
	_op_finish(cs)


func _op_reward_done(r: Dictionary, cs: CharSync, op: Dictionary) -> void:
	if r["ok"]:
		_adopt_revision(cs, r["data"])
		if bool(r["data"].get("replayed", false)):
			ServerLog.info("[sync] recompensa %s ja aplicada (replay)" % String(op["key"]))
	else:
		ServerLog.warn("[sync] recompensa %s falhou de forma permanente (status %d, %s); estado em memoria mantido" % [String(op["key"]), int(r["status"]), String(r["code"])])
	_op_finish(cs)


func _op_craft_done(r: Dictionary, cs: CharSync, op: Dictionary) -> void:
	if r["ok"]:
		_adopt_revision(cs, r["data"])
		if bool(r["data"].get("replayed", false)):
			ServerLog.info("[sync] craft %s ja aplicado (replay)" % String(op["key"]))
	else:
		ServerLog.warn("[sync] craft %s recusado/falhou (status %d, %s)" % [String(op["key"]), int(r["status"]), String(r["code"])])
	var cb: Callable = op["cb"]
	if cb.is_valid():
		cb.call({"ok": r["ok"], "status": r["status"], "code": r["code"], "replayed": bool(r["data"].get("replayed", false)) if r["ok"] else false})
	_op_finish(cs)


func _op_simple_done(r: Dictionary, cs: CharSync, what: String) -> void:
	if not r["ok"] and int(r["status"]) != 404:
		ServerLog.warn("[sync] %s de %s falhou (status %d, %s)" % [what, cs.character_id, int(r["status"]), String(r["code"])])
	_op_finish(cs)


# ------------------------------------------------------------------ encerramento

## Chame DEPOIS de enfileirar checkpoint+release dos jogadores. Quando as filas drenarem, envia
## close; `is_shutdown_complete()` vira true (ou ao estourar shutdown_timeout_sec).
func begin_shutdown() -> void:
	if _shutting_down:
		return
	_shutting_down = true
	_shutdown_elapsed = 0.0
	if client == null or not client.is_configured():
		_shutdown_done = true


func is_shutdown_complete() -> bool:
	return _shutdown_done


func _tick_shutdown(delta: float) -> void:
	if _shutdown_done:
		return
	_shutdown_elapsed += delta
	if _shutdown_elapsed >= shutdown_timeout_sec:
		ServerLog.warn("[sync] encerramento estourou %.0fs; abandonando %d operacoes pendentes" % [shutdown_timeout_sec, pending_ops()])
		client.cancel_all()
		_shutdown_done = true
		return
	if pending_ops() > 0:
		return
	if not _close_sent:
		_close_sent = true
		if _registered and not session_id.is_empty():
			client.close_session(session_id, _on_closed)
		else:
			_shutdown_done = true


func _on_closed(r: Dictionary) -> void:
	if not r["ok"]:
		ServerLog.warn("[sync] close da sessao falhou (status %d, %s)" % [int(r["status"]), String(r["code"])])
	else:
		ServerLog.info("[sync] sessao encerrada no backend")
	_shutdown_done = true
