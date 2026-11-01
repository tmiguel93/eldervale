class_name SnapshotAssembler
extends RefCounted
## E5.7 - mescla, no cliente, as PARTES de um snapshot compacto (s_snapshot_c). Puro. Regras:
## - um snapshot so e entregue COMPLETO (todas as `parts` partes do mesmo tick); parte perdida => o tick e descartado
##   (mesma semantica do snapshot legado, onde perder um fragmento descarta tudo), nunca entregue pela metade;
## - partes duplicadas e de tick ja entregue/anterior sao ignoradas e contadas; ordem das partes e livre;
## - ao completar o tick T, montagens incompletas de ticks <= T sao descartadas (contadas); no maximo MAX_PENDING_TICKS
##   montagens simultaneas (a mais antiga e descartada);
## - cabecalho divergente entre partes do mesmo tick (parts/last_input_seq), blob invalido, id repetido entre partes ou mais
##   de NetRpc.MAX_ENTITIES entidades => parte descartada e contada em `parts_malformed`.

const MAX_PENDING_TICKS: int = 4
const MAX_ENTITIES: int = 256

var last_tick: int = -1
var parts_accepted: int = 0
var parts_duplicate: int = 0
var parts_stale: int = 0
var parts_malformed: int = 0
var snapshots_completed: int = 0
var snapshots_dropped_incomplete: int = 0

var _pending: Dictionary = {} ## tick -> {parts:int, last_seq:int, got:Dictionary(part -> Array), ids:Dictionary, count:int}


func reset() -> void:
	last_tick = -1
	_pending.clear()


func pending_count() -> int:
	return _pending.size()


## Alimenta uma parte. Retorna {"complete": false} ou {"complete": true, "tick", "last_seq", "entities"}.
func push(server_tick: Variant, last_input_seq: Variant, part: Variant, parts: Variant, blob: Variant) -> Dictionary:
	var none: Dictionary = {"complete": false}
	if not Protocol.validate_snapshot_part(server_tick, last_input_seq, part, parts, blob):
		parts_malformed += 1
		return none
	var tick: int = server_tick
	if tick <= last_tick:
		parts_stale += 1
		return none
	var dec: Dictionary = SnapshotCodec.decode_part(blob)
	if not bool(dec["ok"]):
		parts_malformed += 1
		return none
	var n_parts: int = parts
	var idx: int = part
	var asm: Dictionary = _pending.get(tick, {})
	if asm.is_empty():
		asm = {"parts": n_parts, "last_seq": int(last_input_seq), "got": {}, "ids": {}, "count": 0}
	elif int(asm["parts"]) != n_parts or int(asm["last_seq"]) != int(last_input_seq):
		parts_malformed += 1
		return none
	var got: Dictionary = asm["got"]
	if got.has(idx):
		parts_duplicate += 1
		return none
	var ents: Array = dec["entities"]
	var ids: Dictionary = asm["ids"]
	if int(asm["count"]) + ents.size() > MAX_ENTITIES:
		parts_malformed += 1
		return none
	for e: Variant in ents:
		if ids.has(int((e as Dictionary)["id"])):
			parts_malformed += 1
			return none
	for e: Variant in ents:
		ids[int((e as Dictionary)["id"])] = true
	asm["count"] = int(asm["count"]) + ents.size()
	got[idx] = ents
	parts_accepted += 1
	_pending[tick] = asm
	if got.size() == n_parts:
		var merged: Array = []
		for i: int in n_parts:
			merged.append_array(got[i])
		last_tick = tick
		snapshots_completed += 1
		for t: int in _pending.keys():
			if t <= tick:
				_pending.erase(t)
				if t != tick:
					snapshots_dropped_incomplete += 1
		return {"complete": true, "tick": tick, "last_seq": int(asm["last_seq"]), "entities": merged}
	while _pending.size() > MAX_PENDING_TICKS:
		var oldest: int = _pending.keys().min()
		_pending.erase(oldest)
		snapshots_dropped_incomplete += 1
	return none
