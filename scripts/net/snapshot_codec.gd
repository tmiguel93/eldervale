class_name SnapshotCodec
extends RefCounted
## E5.7 - codificacao COMPACTA de snapshot (capacidade `Protocol.CAP_SNAPSHOT_COMPACT`; contrato em
## shared/contracts/network_protocol.md, "Extensao E5.7"). Puro (sem nos, sem rede): o servidor chama `encode`, o cliente
## `decode_part` (via `SnapshotAssembler`). Cada PARTE e autocontida (tabela de strings e origem propria): perder uma parte
## nao impede ler as outras, e nada depende de estado enviado antes (os pacotes sao unreliable).
##
## Layout da parte (little-endian):
##   u8 FORMAT | u8 n_strings | n_strings x (u8 len, bytes ASCII 0x21..0x7E) | 3 x s32 base (cm) | varint n_entidades | entidades
## Entidade:
##   u8 flags (bits0-1 kind 1..3; bit2 extras; bit3 pos larga; bit4 hp cheio; bits5-7 = 0) | varint id | u8 idx_type | u8 state
##   | pos: 3 x s16 (cm relativos a `base`) OU, se bit3, 3 x float32 | u16 yaw | varint max_hp | [varint hp se !bit4]
##   | [u8 phase, u8 atk (0 = nenhum, i+1 = tabela) se bit2; so kind 2] | [varint qty se kind 3]
## Quantizacao: posicao 1 cm (erro <= 0,5 cm por eixo; <= 0,87 cm euclidiano); yaw 2*PI/65536 (erro <= 4,8e-5 rad);
## hp e max_hp inteiros (arredondados; hp > 0 nunca vira 0, entao "vivo" e preservado).

const FORMAT: int = 1
## Orcamento do blob por mensagem. O MTU de payload e 1392 B; sobram ~190 B para o cabecalho do RPC e os 4 inteiros
## (tick, last_input_seq, part, parts) + cabecalho Variant do blob.
const MAX_PART_BYTES: int = 1200
const MAX_STRINGS: int = 254
const MAX_STRING_BYTES: int = 32
const MAX_VARINT: int = 0x0FFFFFFF
const MAX_ENTITIES_PER_PART: int = 256
const FLAG_KIND_MASK: int = 3
const FLAG_EXTRAS: int = 4
const FLAG_WIDE: int = 8
const FLAG_FULL_HP: int = 16
const FLAG_RESERVED: int = 0xE0
const HEADER_BYTES: int = 16     ## FORMAT + n_strings + base(12) + varint de contagem (<= 2)
const MIN_ENTITY_BYTES: int = 13 ## flags,id,type,state,pos(6),yaw(2),max_hp
const NARROW_LIMIT: int = 32767
const INT_LIMIT_CM: float = 2000000000.0


## Codifica `entities` (formato Dictionary do snapshot legado) em partes <= `max_part_bytes`. Entidades invalidas (campos
## ausentes/tipos errados/nao finitas/strings nao ASCII) sao PULADAS e contadas. Retorna {parts:Array[PackedByteArray],
## skipped:int, encoded:int}. Lista vazia -> 1 parte vazia (o cliente precisa do tick e do last_input_seq).
static func encode(entities: Array, max_part_bytes: int = MAX_PART_BYTES) -> Dictionary:
	var parts: Array[PackedByteArray] = []
	var skipped: int = 0
	var encoded: int = 0
	var cur: Array[Dictionary] = []
	var strings: Array[String] = []
	var str_idx: Dictionary = {}
	var base: Vector3i = Vector3i.ZERO
	var size: int = 0
	for e: Variant in entities:
		var r: Dictionary = _record(e)
		if r.is_empty():
			skipped += 1
			continue
		for attempt: int in 2:
			if cur.is_empty():
				base = _base_for(r)
				size = HEADER_BYTES
				strings = []
				str_idx = {}
			var fresh: Array[String] = _fresh_strings(r, str_idx)
			var cost: int = _entity_size(r, base)
			for s: String in fresh:
				cost += 1 + s.length()
			var fits: bool = size + cost <= max_part_bytes and strings.size() + fresh.size() <= MAX_STRINGS and cur.size() < MAX_ENTITIES_PER_PART
			if fits or cur.is_empty():
				for s: String in fresh:
					str_idx[s] = strings.size()
					strings.append(s)
				r["wide"] = _is_wide(r, base)
				cur.append(r)
				size += cost
				encoded += 1
				break
			parts.append(_write_part(cur, strings, str_idx, base))
			cur = []
	if not cur.is_empty() or parts.is_empty():
		parts.append(_write_part(cur, strings, str_idx, base))
	return {"parts": parts, "skipped": skipped, "encoded": encoded}


## Decodifica UMA parte. Retorna {ok:bool, entities:Array[Dictionary], error:String}. Estrito: qualquer truncamento, byte
## sobrando, flag reservada, indice fora da tabela, valor fora de faixa ou id repetido invalida a parte inteira.
static func decode_part(blob: PackedByteArray) -> Dictionary:
	var rd: Reader = Reader.new(blob)
	if rd.u8() != FORMAT:
		return _bad("formato desconhecido")
	var n_str: int = rd.u8()
	if n_str > MAX_STRINGS:
		return _bad("tabela de strings grande demais")
	var table: Array[String] = []
	for i: int in n_str:
		var slen: int = rd.u8()
		if slen > MAX_STRING_BYTES:
			return _bad("string longa demais")
		var raw: PackedByteArray = rd.bytes(slen)
		if not rd.ok:
			return _bad("tabela truncada")
		for b: int in raw:
			if b < 0x21 or b > 0x7E:
				return _bad("string nao ASCII")
		table.append(raw.get_string_from_ascii())
	var base: Vector3i = Vector3i(rd.s32(), rd.s32(), rd.s32())
	var count: int = rd.varint()
	if not rd.ok:
		return _bad("cabecalho truncado")
	if count > MAX_ENTITIES_PER_PART or count * MIN_ENTITY_BYTES > rd.remaining():
		return _bad("contagem de entidades inconsistente")
	var out: Array[Dictionary] = []
	var seen: Dictionary = {}
	for i: int in count:
		var flags: int = rd.u8()
		if (flags & FLAG_RESERVED) != 0:
			return _bad("flags reservadas")
		var kind: int = flags & FLAG_KIND_MASK
		if kind < Protocol.KIND_PLAYER or kind > Protocol.KIND_PICKUP:
			return _bad("kind invalido")
		var id: int = rd.varint()
		var type_idx: int = rd.u8()
		var state: int = rd.u8()
		var pos: Vector3
		if (flags & FLAG_WIDE) != 0:
			pos = Vector3(rd.f32(), rd.f32(), rd.f32())
		else:
			pos = Vector3(float(base.x + rd.s16()) / 100.0, float(base.y + rd.s16()) / 100.0, float(base.z + rd.s16()) / 100.0)
		var yaw_q: int = rd.u16()
		var max_hp: int = rd.varint()
		var hp: int = max_hp if (flags & FLAG_FULL_HP) != 0 else rd.varint()
		var phase: int = 0
		var atk_idx: int = 0
		if (flags & FLAG_EXTRAS) != 0:
			if kind != Protocol.KIND_ENEMY:
				return _bad("extras so em inimigo")
			phase = rd.u8()
			atk_idx = rd.u8()
		var qty: int = rd.varint() if kind == Protocol.KIND_PICKUP else 0
		if not rd.ok:
			return _bad("entidade truncada")
		if type_idx >= table.size() or atk_idx > table.size() or phase > Protocol.MAX_PHASE:
			return _bad("indice/fase fora de faixa")
		if kind == Protocol.KIND_PICKUP and (qty < 1 or qty > Protocol.MAX_PICKUP_QTY):
			return _bad("qty fora de faixa")
		if not (is_finite(pos.x) and is_finite(pos.y) and is_finite(pos.z)):
			return _bad("posicao nao finita")
		if seen.has(id):
			return _bad("id repetido")
		seen[id] = true
		var ent: Dictionary = {
			"id": id, "kind": kind, "pos": pos, "yaw": float(yaw_q) / 65536.0 * TAU - PI,
			"hp": float(hp), "max_hp": float(max_hp), "state": state, "type": table[type_idx],
		}
		if kind == Protocol.KIND_ENEMY:
			ent["phase"] = phase
			ent["atk"] = table[atk_idx - 1] if atk_idx > 0 else ""
		elif kind == Protocol.KIND_PICKUP:
			ent["qty"] = qty
		out.append(ent)
	if not rd.ok or rd.remaining() != 0:
		return _bad("bytes sobrando ou truncado")
	return {"ok": true, "entities": out, "error": ""}


static func _bad(why: String) -> Dictionary:
	return {"ok": false, "entities": [] as Array[Dictionary], "error": why}


# ---------------------------------------------------------------- escrita

static func _ascii_ok(s: String) -> bool:
	if s.length() > MAX_STRING_BYTES:
		return false
	for i: int in s.length():
		var c: int = s.unicode_at(i)
		if c < 0x21 or c > 0x7E:
			return false
	return true


static func _q_hp(v: float) -> int:
	if v <= 0.0:
		return 0
	if v >= float(MAX_VARINT):
		return MAX_VARINT
	return maxi(1, roundi(v))


## Entidade legada -> registro quantizado; {} se invalida.
static func _record(e: Variant) -> Dictionary:
	if typeof(e) != TYPE_DICTIONARY:
		return {}
	var d: Dictionary = e
	for key: String in ["id", "kind", "pos", "yaw", "hp", "max_hp", "state", "type"]:
		if not d.has(key):
			return {}
	if typeof(d["id"]) != TYPE_INT or typeof(d["kind"]) != TYPE_INT or typeof(d["state"]) != TYPE_INT:
		return {}
	var id: int = d["id"]
	var kind: int = d["kind"]
	var state: int = d["state"]
	if id < 0 or id > MAX_VARINT or kind < Protocol.KIND_PLAYER or kind > Protocol.KIND_PICKUP or state < 0 or state > 255:
		return {}
	if typeof(d["pos"]) != TYPE_VECTOR3:
		return {}
	var pos: Vector3 = d["pos"]
	if not (is_finite(pos.x) and is_finite(pos.y) and is_finite(pos.z)):
		return {}
	if not (Protocol.is_finite_number(d["yaw"]) and Protocol.is_finite_number(d["hp"]) and Protocol.is_finite_number(d["max_hp"])):
		return {}
	if typeof(d["type"]) != TYPE_STRING or not _ascii_ok(d["type"]):
		return {}
	var phase: int = 0
	var atk: String = ""
	if kind == Protocol.KIND_ENEMY:
		if d.has("phase"):
			if typeof(d["phase"]) != TYPE_INT or int(d["phase"]) < 0 or int(d["phase"]) > Protocol.MAX_PHASE:
				return {}
			phase = d["phase"]
		if d.has("atk"):
			if typeof(d["atk"]) != TYPE_STRING or not _ascii_ok(d["atk"]):
				return {}
			atk = d["atk"]
	var qty: int = 0
	if kind == Protocol.KIND_PICKUP:
		if typeof(d.get("qty", null)) != TYPE_INT or int(d["qty"]) < 1 or int(d["qty"]) > Protocol.MAX_PICKUP_QTY:
			return {}
		qty = d["qty"]
	var cm: Vector3 = pos * 100.0
	var fits: bool = absf(cm.x) <= INT_LIMIT_CM and absf(cm.y) <= INT_LIMIT_CM and absf(cm.z) <= INT_LIMIT_CM
	var yaw_t: float = fposmod(float(d["yaw"]) + PI, TAU) / TAU
	var hp_i: int = _q_hp(float(d["hp"]))
	var max_i: int = _q_hp(float(d["max_hp"]))
	return {
		"id": id, "kind": kind, "state": state, "type": d["type"], "pos": pos, "fits": fits,
		"cm": Vector3i(roundi(cm.x), roundi(cm.y), roundi(cm.z)) if fits else Vector3i.ZERO,
		"yaw_q": int(roundf(yaw_t * 65536.0)) & 0xFFFF, "hp": hp_i, "max_hp": max_i,
		"phase": phase, "atk": atk, "qty": qty, "wide": false,
	}


static func _base_for(r: Dictionary) -> Vector3i:
	return r["cm"] if bool(r["fits"]) else Vector3i.ZERO


static func _is_wide(r: Dictionary, base: Vector3i) -> bool:
	if not bool(r["fits"]):
		return true
	var c: Vector3i = r["cm"]
	return absi(c.x - base.x) > NARROW_LIMIT or absi(c.y - base.y) > NARROW_LIMIT or absi(c.z - base.z) > NARROW_LIMIT


static func _has_extras(r: Dictionary) -> bool:
	return int(r["kind"]) == Protocol.KIND_ENEMY and (int(r["phase"]) != 0 or not String(r["atk"]).is_empty())


static func _varlen(v: int) -> int:
	if v < 0x80:
		return 1
	if v < 0x4000:
		return 2
	if v < 0x200000:
		return 3
	return 4


static func _entity_size(r: Dictionary, base: Vector3i) -> int:
	var n: int = 1 + _varlen(int(r["id"])) + 1 + 1 + (12 if _is_wide(r, base) else 6) + 2 + _varlen(int(r["max_hp"]))
	if int(r["hp"]) != int(r["max_hp"]):
		n += _varlen(int(r["hp"]))
	if _has_extras(r):
		n += 2
	if int(r["kind"]) == Protocol.KIND_PICKUP:
		n += _varlen(int(r["qty"]))
	return n


static func _fresh_strings(r: Dictionary, idx: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var t: String = r["type"]
	if not idx.has(t):
		out.append(t)
	var a: String = r["atk"]
	if _has_extras(r) and not a.is_empty() and not idx.has(a) and not out.has(a):
		out.append(a)
	return out


static func _put_varint(sp: StreamPeerBuffer, value: int) -> void:
	var v: int = clampi(value, 0, MAX_VARINT)
	while v >= 0x80:
		sp.put_u8((v & 0x7F) | 0x80)
		v >>= 7
	sp.put_u8(v)


static func _write_part(recs: Array[Dictionary], strings: Array[String], idx: Dictionary, base: Vector3i) -> PackedByteArray:
	var sp: StreamPeerBuffer = StreamPeerBuffer.new()
	sp.put_u8(FORMAT)
	sp.put_u8(strings.size())
	for s: String in strings:
		sp.put_u8(s.length())
		sp.put_data(s.to_ascii_buffer())
	sp.put_32(base.x)
	sp.put_32(base.y)
	sp.put_32(base.z)
	_put_varint(sp, recs.size())
	for r: Dictionary in recs:
		var full: bool = int(r["hp"]) == int(r["max_hp"])
		var extras: bool = _has_extras(r)
		var wide: bool = bool(r["wide"])
		sp.put_u8(int(r["kind"]) | (FLAG_EXTRAS if extras else 0) | (FLAG_WIDE if wide else 0) | (FLAG_FULL_HP if full else 0))
		_put_varint(sp, int(r["id"]))
		sp.put_u8(int(idx[r["type"]]))
		sp.put_u8(int(r["state"]))
		if wide:
			var p: Vector3 = r["pos"]
			sp.put_float(p.x)
			sp.put_float(p.y)
			sp.put_float(p.z)
		else:
			var c: Vector3i = r["cm"]
			sp.put_16(c.x - base.x)
			sp.put_16(c.y - base.y)
			sp.put_16(c.z - base.z)
		sp.put_u16(int(r["yaw_q"]))
		_put_varint(sp, int(r["max_hp"]))
		if not full:
			_put_varint(sp, int(r["hp"]))
		if extras:
			sp.put_u8(int(r["phase"]))
			var a: String = r["atk"]
			sp.put_u8(0 if a.is_empty() else int(idx[a]) + 1)
		if int(r["kind"]) == Protocol.KIND_PICKUP:
			_put_varint(sp, int(r["qty"]))
	return sp.data_array


## Leitor com checagem de limites: depois de qualquer leitura alem do fim `ok` fica false (e os valores sao 0).
class Reader extends RefCounted:
	var data: PackedByteArray
	var pos: int = 0
	var ok: bool = true

	func _init(p_data: PackedByteArray) -> void:
		data = p_data

	func remaining() -> int:
		return data.size() - pos

	func _need(n: int) -> bool:
		if not ok or pos + n > data.size():
			ok = false
			return false
		return true

	func u8() -> int:
		if not _need(1):
			return 0
		pos += 1
		return data.decode_u8(pos - 1)

	func u16() -> int:
		if not _need(2):
			return 0
		pos += 2
		return data.decode_u16(pos - 2)

	func s16() -> int:
		if not _need(2):
			return 0
		pos += 2
		return data.decode_s16(pos - 2)

	func s32() -> int:
		if not _need(4):
			return 0
		pos += 4
		return data.decode_s32(pos - 4)

	func f32() -> float:
		if not _need(4):
			return 0.0
		pos += 4
		return data.decode_float(pos - 4)

	func bytes(n: int) -> PackedByteArray:
		if not _need(n):
			return PackedByteArray()
		pos += n
		return data.slice(pos - n, pos)

	## varint LEB128 de ate 4 bytes (28 bits); um 5o byte de continuacao invalida.
	func varint() -> int:
		var v: int = 0
		for i: int in 4:
			var b: int = u8()
			if not ok:
				return 0
			v |= (b & 0x7F) << (7 * i)
			if (b & 0x80) == 0:
				return v
		ok = false
		return 0
