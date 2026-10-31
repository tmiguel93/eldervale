class_name DialogueRunner
extends RefCounted
## Execucao de UM dialogo para UM jogador (logica pura). Fluxo:
##   start(ctx)                    -> escolhe o no de entrada (primeira `entries` cuja condicao passa)
##   take_enter_effects()          -> efeitos `on_enter` do no recem-entrado (one-shot; o chamador aplica)
##   view(ctx)                     -> fala + escolhas VISIVEIS (condicao `if` avaliada com `ctx`)
##   choose(index, ctx)            -> valida o indice contra a ULTIMA view, reavalia a condicao com o
##                                    contexto atual, devolve os efeitos da escolha e avanca (ou encerra)
## Um no sem escolhas e terminal: depois de `view`, o dialogo termina (`is_finished`).
## Indices sao os da lista VISIVEL mostrada na ultima `view` (o cliente nunca ve escolhas ocultas).

var def: DialogueDef
var node_id: String = ""
var finished: bool = false

var _visible: Array[int] = []     ## indices (no array bruto de choices) das escolhas da ultima view
var _enter_pending: Array = []


func _init(p_def: DialogueDef) -> void:
	def = p_def


func is_finished() -> bool:
	return finished


## Entra no no inicial. Devolve false se nenhuma entrada vale (nao ocorre com fallback).
func start(ctx: Dictionary) -> bool:
	finished = false
	for e: Dictionary in def.entries:
		if DialogueCondition.check(e["if"], ctx):
			_enter(String(e["node"]))
			return true
	finished = true
	return false


func _enter(nid: String) -> void:
	node_id = nid
	_enter_pending = (def.nodes[nid]["on_enter"] as Array).duplicate(true)
	_visible = []


func take_enter_effects() -> Array:
	var out: Array = _enter_pending
	_enter_pending = []
	return out


## Fala atual + escolhas visiveis. Dicionario pronto para a rede (so tipos primitivos).
func view(ctx: Dictionary) -> Dictionary:
	if finished or node_id.is_empty():
		return {}
	var node: Dictionary = def.nodes[node_id]
	var choices: Array = []
	_visible = []
	var raw: Array = node["choices"]
	for i: int in raw.size():
		if DialogueCondition.check((raw[i] as Dictionary)["if"], ctx):
			_visible.append(i)
			choices.append({"index": choices.size(), "text": raw[i]["text"], "text_key": raw[i]["text_key"]})
	var terminal: bool = raw.is_empty()
	if terminal or choices.is_empty():
		# no sem escolhas (ou todas ocultas): nada a escolher, o dialogo acaba apos mostrar a fala
		terminal = true
		finished = true
	return {
		"npc_id": def.npc_id, "dialogue_id": def.id, "node_id": node_id, "speaker": node["speaker"],
		"text": node["text"], "text_key": node["text_key"], "choices": choices, "terminal": terminal,
	}


## Escolhe (indice da ULTIMA view). Devolve {ok, code, effects, ended}.
## Codigos: finished, bad_choice, choice_unavailable.
func choose(index: int, ctx: Dictionary) -> Dictionary:
	if finished or node_id.is_empty():
		return {"ok": false, "code": "finished", "effects": [], "ended": true}
	if index < 0 or index >= _visible.size():
		return {"ok": false, "code": "bad_choice", "effects": [], "ended": false}
	var choice: Dictionary = (def.nodes[node_id]["choices"] as Array)[_visible[index]]
	if not DialogueCondition.check(choice["if"], ctx):
		return {"ok": false, "code": "choice_unavailable", "effects": [], "ended": false}
	var effects: Array = (choice["effects"] as Array).duplicate(true)
	var nxt: Variant = choice["next"]
	if nxt == null:
		finished = true
		return {"ok": true, "code": "", "effects": effects, "ended": true}
	_enter(String(nxt))
	return {"ok": true, "code": "", "effects": effects, "ended": false}


func close() -> void:
	finished = true
