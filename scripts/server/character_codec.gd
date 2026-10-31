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
	# E5.1: `quests` e opcional (backend antigo/personagem pre-E5.1 = sem quests); se presente, a FORMA deve ser valida.
	if ch.has("quests") and not QuestState.shape_error(ch["quests"]).is_empty():
		return "quests invalido"
	var cap: int = int(ch.get("inventory_capacity", 20))
	if cap < 1 or cap > 200 or (ch["inventory"] as Array).size() > cap:
		return "capacidade de inventario invalida"
	for e: Variant in ch["inventory"]:
		if typeof(e) != TYPE_DICTIONARY or typeof((e as Dictionary).get("item_id", null)) != TYPE_STRING or not _is_num((e as Dictionary).get("qty", null)):
			return "entrada de inventario invalida"
		var item: ItemData = registry.get_item(StringName((e as Dictionary)["item_id"]))
		if item == null:
			return "item desconhecido no inventario"
		var qty: int = int((e as Dictionary)["qty"])
		if qty < 1 or qty > item.effective_max_stack():
			return "quantidade invalida"
	for slot_name: Variant in (ch["equipment"] as Dictionary):
		if not SLOT_NAMES.values().has(slot_name) or typeof(ch["equipment"][slot_name]) != TYPE_STRING:
			return "slot de equipamento invalido"
		var it: ItemData = registry.get_item(StringName(ch["equipment"][slot_name]))
		if it == null or SLOT_NAMES.get(int(it.slot), "") != slot_name:
			return "item equipado invalido"
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
	loadout.progress.level = int(ch["level"])
	loadout.progress.total_xp = int(ch["xp"])
	var inv: Inventory = loadout.inventory
	inv.capacity = int(ch.get("inventory_capacity", inv.capacity))
	inv.restore([] as Array[ItemStack])
	var entries: Array = (ch["inventory"] as Array).duplicate()
	entries.sort_custom(func(a: Variant, b: Variant) -> bool: return int((a as Dictionary).get("slot", 0)) < int((b as Dictionary).get("slot", 0)))
	for e: Variant in entries:
		var left: int = inv.add(StringName((e as Dictionary)["item_id"]), int((e as Dictionary)["qty"]))
		if left > 0:
			ServerLog.warn("[state] inventario: %d unidades nao couberam ao carregar" % left)
	var eq: Equipment = loadout.equipment
	for slot: int in Equipment.SLOTS:
		eq._equipped.erase(slot)
	for slot_value: int in SLOT_NAMES:
		var nm: String = SLOT_NAMES[slot_value]
		if (ch["equipment"] as Dictionary).has(nm):
			eq._equipped[slot_value] = StringName(ch["equipment"][nm])
	loadout.recalculate()
	# Quests: restauracao leniente (ids desconhecidos descartados) EM-PLACE, preservando a referencia do tracker.
	for w: String in loadout.quest_state.restore(ch.get("quests", {}), QuestCatalog.shared()):
		ServerLog.warn("[state] " + w)


## Estado completo para checkpoint (so o servidor decide; nada vem do cliente).
static func capture(loadout: PlayerLoadout) -> Dictionary:
	var b: StatBlock = loadout.base_stats
	var inventory: Array = []
	var slot_index: int = 0
	for s: Dictionary in loadout.inventory.contents():
		inventory.append({"slot": slot_index, "item_id": String(s["id"]), "qty": int(s["qty"])})
		slot_index += 1
	var equipment: Dictionary = {}
	for slot_value: int in SLOT_NAMES:
		var id: StringName = loadout.equipment.get_equipped(slot_value)
		if id != &"":
			equipment[SLOT_NAMES[slot_value]] = String(id)
	return {
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
