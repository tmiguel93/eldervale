class_name CharacterCodec
extends RefCounted
## Conversao entre o estado persistido do backend (CharacterState, docs/E4_CHARACTERS.md) e o
## PlayerLoadout do servidor (Inventory + Equipment + CharacterProgress + base_stats).
## O JSON do Godot devolve todo numero como float: aqui tudo vira int/float explicitamente.
## O backend guarda inventario por SLOT; o Inventory do jogo e compactado (sem indice): ao salvar,
## o slot e a posicao na lista (o backend aceita slots esparsos ou densos).

const SLOT_NAMES: Dictionary = {
	ItemData.Slot.WEAPON: "weapon", ItemData.Slot.ARMOR: "armor", ItemData.Slot.TRINKET: "trinket",
}
const STAT_KEYS: Array[String] = ["max_health", "max_resource", "resource_regen", "attack_power", "defense", "resistance", "move_speed"]
const SCHEMA_VERSION: int = 1


static func _is_num(v: Variant) -> bool:
	return Protocol.is_finite_number(v)


## Valida o personagem recebido ({id, name, level, xp, stats, inventory, equipment, revision,
## inventory_capacity, schema_version}). Devolve "" se OK, senao o motivo.
static func validate(ch: Dictionary, registry: ContentRegistry) -> String:
	for k: String in ["level", "xp", "stats", "inventory", "equipment", "revision"]:
		if not ch.has(k):
			return "campo ausente: " + k
	if not _is_num(ch["level"]) or not _is_num(ch["xp"]) or not _is_num(ch["revision"]):
		return "level/xp/revision invalidos"
	var level: int = int(ch["level"])
	if level < 1 or level > CharacterProgress.MAX_LEVEL or int(ch["xp"]) < 0 or int(ch["revision"]) < 0:
		return "level/xp/revision fora de faixa"
	if typeof(ch["stats"]) != TYPE_DICTIONARY:
		return "stats invalido"
	for key: String in STAT_KEYS:
		if not (ch["stats"] as Dictionary).has(key) or not _is_num((ch["stats"] as Dictionary)[key]):
			return "stat invalido: " + key
	if typeof(ch["inventory"]) != TYPE_ARRAY or typeof(ch["equipment"]) != TYPE_DICTIONARY:
		return "inventario/equipamento invalidos"
	# E6.1: `class_id` e opcional (backend/fake antigo = classe padrao); se presente, tem de existir no catalogo (senao o jogo recusa
	# a entrada em vez de inventar habilidades/stats para uma classe desconhecida).
	if ch.has("class_id") and not ClassCatalog.shared().has_class(ch["class_id"]):
		return "class_id desconhecido"
	# E6.2: `talents` e opcional (backend antigo/personagem pre-E6.2 = sem talentos); se presente, a FORMA deve ser valida.
	if ch.has("talents") and not TalentState.shape_error(ch["talents"]).is_empty():
		return "talents invalido"
	# E5.1: `quests` e opcional (backend antigo/personagem pre-E5.1 = sem quests); se presente, a FORMA deve ser valida.
	if ch.has("quests") and not QuestState.shape_error(ch["quests"]).is_empty():
		return "quests invalido"
	var cap: int = int(ch.get("inventory_capacity", 20))
	if cap < 1 or cap > 200 or (ch["inventory"] as Array).size() > cap:
		return "capacidade de inventario invalida"
	var uids: Dictionary = {}
	for e: Variant in ch["inventory"]:
		if typeof(e) != TYPE_DICTIONARY or typeof((e as Dictionary).get("item_id", null)) != TYPE_STRING or not _is_num((e as Dictionary).get("qty", null)):
			return "entrada de inventario invalida"
		var item: ItemData = registry.get_item(StringName((e as Dictionary)["item_id"]))
		if item == null:
			return "item desconhecido no inventario"
		var qty: int = int((e as Dictionary)["qty"])
		if qty < 1 or qty > item.effective_max_stack():
			return "quantidade invalida"
		# E6.3: `inst` e opcional (save antigo = item simples/Comum). Se presente: qty 1, base equipavel e instancia valida/unica.
		if (e as Dictionary).has("inst"):
			var why: String = _instance_error((e as Dictionary)["inst"], item, uids)
			if qty != 1 or not why.is_empty():
				return "instancia de inventario invalida"
	for slot_name: Variant in (ch["equipment"] as Dictionary):
		if not SLOT_NAMES.values().has(slot_name) or typeof(ch["equipment"][slot_name]) != TYPE_STRING:
			return "slot de equipamento invalido"
		var it: ItemData = registry.get_item(StringName(ch["equipment"][slot_name]))
		if it == null or SLOT_NAMES.get(int(it.slot), "") != slot_name:
			return "item equipado invalido"
	if ch.has("equipment_inst"):
		if typeof(ch["equipment_inst"]) != TYPE_DICTIONARY:
			return "equipment_inst invalido"
		for sn: Variant in (ch["equipment_inst"] as Dictionary):
			if not (ch["equipment"] as Dictionary).has(sn):
				return "equipment_inst sem item equipado"
			var eitem: ItemData = registry.get_item(StringName(ch["equipment"][sn]))
			if eitem == null or not _instance_error((ch["equipment_inst"] as Dictionary)[sn], eitem, uids).is_empty():
				return "instancia equipada invalida"
	return ""


## E6.3: "" se `inst` e uma instancia valida da base `item` e o uid ainda nao apareceu em `uids` (que e atualizado).
static func _instance_error(inst: Variant, item: ItemData, uids: Dictionary) -> String:
	var why: String = ItemRules.shared().validate_instance(inst, item)
	if not why.is_empty():
		return why
	var uid: String = String((inst as Dictionary)["uid"])
	if uids.has(uid):
		return "uid duplicado"
	uids[uid] = true
	return ""


## Aplica o personagem (JA validado) ao loadout do jogador e recalcula os stats.
static func apply(loadout: PlayerLoadout, ch: Dictionary) -> void:
	var stats: Dictionary = ch["stats"]
	var base: StatBlock = StatBlock.new()
	base.max_health = float(stats["max_health"])
	base.max_resource = float(stats["max_resource"])
	base.resource_regen = float(stats["resource_regen"])
	base.attack_power = float(stats["attack_power"])
	base.defense = float(stats["defense"])
	base.resistance = float(stats["resistance"])
	base.move_speed = float(stats["move_speed"])
	loadout.base_stats = base
	var class_def: ClassDef = ClassCatalog.shared().get_def(String(ch.get("class_id", ClassCatalog.DEFAULT_CLASS_ID)))
	if class_def == null or not loadout.apply_class(class_def):
		ServerLog.warn("[state] classe indisponivel; mantendo a classe atual do jogador")
	loadout.progress.level = int(ch["level"])
	loadout.progress.total_xp = int(ch["xp"])
	# E6.2: talentos (estado do BACKEND; restauracao leniente) -> bonus de stats + modificadores de habilidade.
	for w: String in loadout.talents.restore(ch.get("talents", {}), loadout.talent_tree()):
		ServerLog.warn("[state] " + w)
	loadout.apply_talents()
	var inv: Inventory = loadout.inventory
	inv.capacity = int(ch.get("inventory_capacity", inv.capacity))
	inv.restore([] as Array[ItemStack])
	var entries: Array = (ch["inventory"] as Array).duplicate()
	entries.sort_custom(func(a: Variant, b: Variant) -> bool: return int((a as Dictionary).get("slot", 0)) < int((b as Dictionary).get("slot", 0)))
	for e: Variant in entries:
		if (e as Dictionary).has("inst"):
			if not inv.add_instance(StringName((e as Dictionary)["item_id"]), (e as Dictionary)["inst"] as Dictionary):
				ServerLog.warn("[state] inventario: instancia nao coube ao carregar")
			continue
		var left: int = inv.add(StringName((e as Dictionary)["item_id"]), int((e as Dictionary)["qty"]))
		if left > 0:
			ServerLog.warn("[state] inventario: %d unidades nao couberam ao carregar" % left)
	var eq: Equipment = loadout.equipment
	for slot: int in Equipment.SLOTS:
		eq.clear_slot(slot)
	var eq_inst: Dictionary = ch.get("equipment_inst", {}) as Dictionary
	for slot_value: int in SLOT_NAMES:
		var nm: String = SLOT_NAMES[slot_value]
		if (ch["equipment"] as Dictionary).has(nm):
			eq.set_equipped(slot_value, StringName(ch["equipment"][nm]), (eq_inst.get(nm, {}) as Dictionary))
	loadout.recalculate()
	# Quests: restauracao leniente (ids desconhecidos descartados) EM-PLACE, preservando a referencia do tracker.
	for w: String in loadout.quest_state.restore(ch.get("quests", {}), QuestCatalog.shared()):
		ServerLog.warn("[state] " + w)


## Estado completo para checkpoint (so o servidor decide; nada vem do cliente). NAO inclui `talents` (nem `class_id`): os talentos
## pertencem ao backend e so mudam por comandos validados (/talents); o backend rejeita campo desconhecido no estado.
static func capture(loadout: PlayerLoadout) -> Dictionary:
	var b: StatBlock = loadout.base_stats
	var inventory: Array = []
	var slot_index: int = 0
	for s: Dictionary in loadout.inventory.contents():
		var entry: Dictionary = {"slot": slot_index, "item_id": String(s["id"]), "qty": int(s["qty"])}
		if s.has("inst"):
			entry["inst"] = s["inst"]
		inventory.append(entry)
		slot_index += 1
	var equipment: Dictionary = {}
	var equipment_inst: Dictionary = {}
	for slot_value: int in SLOT_NAMES:
		var id: StringName = loadout.equipment.get_equipped(slot_value)
		if id != &"":
			equipment[SLOT_NAMES[slot_value]] = String(id)
			var einst: Dictionary = loadout.equipment.get_equipped_instance(slot_value)
			if not einst.is_empty():
				equipment_inst[SLOT_NAMES[slot_value]] = einst
	var state: Dictionary = {
		"schema_version": SCHEMA_VERSION,
		"level": loadout.progress.level,
		"xp": loadout.progress.total_xp,
		"stats": {
			"max_health": b.max_health, "max_resource": b.max_resource, "resource_regen": b.resource_regen,
			"attack_power": b.attack_power, "defense": b.defense, "resistance": b.resistance, "move_speed": b.move_speed,
		},
		"inventory": inventory,
		"equipment": equipment,
		"quests": loadout.quest_state.to_dict(),
	}
	if not equipment_inst.is_empty():
		state["equipment_inst"] = equipment_inst # E6.3: so presente quando ha instancia equipada (backend aceita ausente)
	return state


## E5.6: payload de `s_inventory` (inventario + equipamento COMPLETOS do personagem; Protocol.validate_inventory_update).
## Uma entrada por pilha, na ordem do inventario; sem identidade de instancia.
static func inventory_payload(loadout: PlayerLoadout) -> Dictionary:
	var slots: Array = []
	for s: Dictionary in loadout.inventory.contents():
		var entry: Dictionary = {"item_id": String(s["id"]), "qty": int(s["qty"])}
		if s.has("inst"):
			entry["inst"] = s["inst"] # E6.3: instancia completa SO aqui (dono), nunca no snapshot
		slots.append(entry)
	var equipment: Dictionary = {}
	var equipment_inst: Dictionary = {}
	for slot_value: int in SLOT_NAMES:
		var id: StringName = loadout.equipment.get_equipped(slot_value)
		if id != &"":
			equipment[SLOT_NAMES[slot_value]] = String(id)
			var einst: Dictionary = loadout.equipment.get_equipped_instance(slot_value)
			if not einst.is_empty():
				equipment_inst[SLOT_NAMES[slot_value]] = einst
	var payload: Dictionary = {"capacity": clampi(loadout.inventory.capacity, 1, Protocol.MAX_INVENTORY_SLOTS), "slots": slots, "equipment": equipment}
	if not equipment_inst.is_empty():
		payload["equipment_inst"] = equipment_inst
	return payload
