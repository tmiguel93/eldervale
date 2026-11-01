class_name UiText
extends RefCounted
## E5.5: textos de apresentacao (nomes de itens, mensagens de erro dos codigos do servidor, rotulos).
## Funcoes puras/estaticas e testaveis. Os codigos vem do servidor; aqui so ha traducao para o jogador.

const ITEMS_DIR: String = "res://data/items/"
const MAX_TOAST: int = 120

static var _item_cache: Dictionary = {}


## Nome de exibicao do item (de data/items). Desconhecido: o id com espacos. Remove a marca "[PLACEHOLDER]".
static func item_name(item_id: String) -> String:
	if _item_cache.has(item_id):
		return String(_item_cache[item_id])
	var name: String = item_id.replace("_", " ")
	if Protocol.is_content_id(item_id):
		var path: String = ITEMS_DIR + item_id + ".tres"
		if ResourceLoader.exists(path):
			var it: ItemData = load(path) as ItemData
			if it != null and not it.display_name.is_empty():
				name = it.display_name
	name = name.replace("[PLACEHOLDER]", "").strip_edges()
	_item_cache[item_id] = name
	return name


## "2x Pocao Menor" (qty 1 => sem prefixo).
static func stack_text(item_id: String, qty: int) -> String:
	return item_name(item_id) if qty <= 1 else "%dx %s" % [qty, item_name(item_id)]


static func stacks_text(stacks: Array) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for s: Variant in stacks:
		if s is Dictionary and Protocol.is_content_id((s as Dictionary).get("item_id", null)):
			parts.append(stack_text(String(s["item_id"]), int(s.get("qty", 1))))
	return ", ".join(parts)


static func npc_name(npc_id: String) -> String:
	var n: Dictionary = NpcDirectory.shared().get_npc(npc_id)
	if n.is_empty():
		return npc_id.replace("npc_", "").replace("_", " ").capitalize() if not npc_id.is_empty() else ""
	return String(n["display_name"]).replace("[PLACEHOLDER]", "").strip_edges()


static func quest_title(quest_id: String) -> String:
	var def: QuestDef = QuestCatalog.shared().get_quest(quest_id)
	return def.title if def != null else quest_id


static func enemy_name(type_id: String) -> String:
	var d: EnemyData = EnemyCatalog.data_for(StringName(type_id))
	if d != null and not d.display_name.is_empty():
		return d.display_name.replace("[PLACEHOLDER]", "").strip_edges()
	return type_id.replace("_", " ").capitalize()


static func zone_name(zone_id: String) -> String:
	var z: ZoneDef = WorldDef.shared().get_zone(zone_id)
	return z.display_name if z != null else zone_id


static func clamp_text(text: String, max_len: int) -> String:
	var t: String = text.strip_edges()
	return t if t.length() <= max_len else t.substr(0, maxi(max_len - 3, 0)) + "..."


static func status_label(status: String) -> String:
	match status:
		"ready": return "Pronta para entregar"
		"active": return "Em andamento"
		"available": return "Disponivel"
		"completed": return "Concluida"
	return "Indisponivel"


## Linha de objetivo: "[x] Matar 5 grunts (5/5)".
static func objective_line(text: String, value: int, required: int) -> String:
	var done: bool = value >= required
	return "%s %s (%d/%d)" % ["[x]" if done else "[ ]", text, mini(value, required), required]


static func rewards_text(xp: int, items: Array) -> String:
	var parts: PackedStringArray = PackedStringArray()
	if xp > 0:
		parts.append("%d XP" % xp)
	var it: String = stacks_text(items)
	if not it.is_empty():
		parts.append(it)
	return ", ".join(parts) if not parts.is_empty() else "-"


## E6.2: texto de erro de talentos (codigos do servidor).
static func talent_error(code: String) -> String:
	match code:
		"no_points": return "Sem pontos de talento disponiveis."
		"max_rank": return "Este talento ja esta no maximo."
		"prerequisite": return "Requisitos do talento nao cumpridos."
		"level_too_low": return "Nivel insuficiente para este talento."
		"spec_not_chosen": return "Escolha uma especializacao antes."
		"wrong_spec": return "Talento de outra especializacao."
		"unknown_node": return "Talento desconhecido."
		"unknown_spec": return "Especializacao desconhecida."
		"spec_already_chosen": return "Especializacao ja escolhida (reset para trocar)."
		"nothing_to_reset": return "Nao ha talentos para resetar."
		"not_safe_zone": return "O reset so e permitido em zona segura (vila)."
		"insufficient_items": return "Itens insuficientes para o reset."
		"busy": return "Aguarde o pedido anterior terminar."
		"not_available": return "Indisponivel agora."
		"not_ready": return "Personagem ainda nao esta pronto."
		"duplicate_request": return "Pedido repetido ignorado."
		"backend_error": return "Falha ao salvar os talentos. Tente de novo."
		"session_fenced": return "Sessao invalida. Reconecte."
		"revision_conflict": return "Personagem mudou; tente de novo."
	return "Nao foi possivel (%s)." % clamp_text(code, 32)


static func craft_error(code: String) -> String:
	match code:
		"insufficient_ingredients": return "Ingredientes insuficientes."
		"inventory_full": return "Inventario cheio."
		"busy": return "Aguarde a fabricacao anterior terminar."
		"no_station": return "Nao ha bancada aqui."
		"too_far": return "Chegue mais perto da bancada."
		"unknown_recipe": return "Receita desconhecida."
		"not_available": return "Indisponivel agora."
		"not_ready": return "Personagem ainda nao esta pronto."
		"duplicate_request": return "Pedido repetido ignorado."
		"backend_error": return "Falha ao salvar a fabricacao. Tente de novo."
		"session_fenced": return "Sessao invalida. Reconecte."
	return "Nao foi possivel fabricar (%s)." % clamp_text(code, 32)


static func quest_error(code: String) -> String:
	match code:
		"unknown_quest": return "Quest desconhecida."
		"already_completed": return "Quest ja concluida."
		"already_active": return "Quest ja ativa."
		"level_too_low": return "Nivel insuficiente para esta quest."
		"prereq_missing": return "Falta concluir uma quest anterior."
		"quest_log_full": return "Diario cheio: abandone uma quest."
		"not_active": return "Quest nao esta ativa."
		"not_abandonable": return "Esta quest nao pode ser abandonada."
		"not_ready": return "Objetivos ainda nao concluidos."
		"wrong_npc": return "Fale com o NPC correto."
		"too_far": return "Chegue mais perto do NPC."
		"inventory_full": return "Inventario cheio: libere espaco."
		"no_player": return "Personagem indisponivel."
	return "Pedido de quest recusado (%s)." % clamp_text(code, 32)


static func dialogue_error(code: String) -> String:
	match code:
		"too_far": return "Voce esta longe demais do NPC."
		"unknown_npc": return "NPC desconhecido."
		"no_dialogue": return "Este NPC nao tem nada a dizer."
		"no_player": return "Personagem indisponivel."
	return "Dialogo indisponivel (%s)." % clamp_text(code, 32)
