extends RefCounted
## E6.3 - UI do cliente: cor de raridade, nome composto, tooltip com linhas de affix, comparacao com o equipado, teclas de equipar/desequipar,
## erros de equipar com texto, estado vazio/legado. Controles so em scripts/ui/client.

const U = preload("res://tests/e5_ui/ui_helpers.gd")


func run(ctx: Object) -> void:
	var tree: SceneTree = ctx as SceneTree
	await tree.physics_frame
	var rules: ItemRules = ItemRules.shared()
	var inst: Dictionary = {"uid": "0123456789abcdef", "rarity": "epic", "ilvl": 30, "affixes": [
		{"id": "pre_brutal", "tier": 2, "value": 4.0}, {"id": "suf_of_titan", "tier": 2, "value": 12.0}, {"id": "suf_of_fury", "tier": 3, "value": 0.03},
	]}
	# texto
	ctx.check(UiText.rarity_of("sword_basic") == "common" and UiText.rarity_of("sword_basic", inst) == "epic", "raridade: Comum sem instancia, Epica com")
	ctx.check(UiText.rarity_of("unique_emberfang") == "legendary", "unico usa a raridade do ItemData")
	ctx.check(UiText.rarity_color("sword_basic", inst) == rules.rarity_color("epic") and UiText.rarity_color("sword_basic") != UiText.rarity_color("sword_basic", inst), "cor por raridade")
	var colors: Dictionary = {}
	for rid: String in rules.rarity_order:
		colors[rules.rarity_color(rid).to_html()] = true
	ctx.check(colors.size() == 6, "6 raridades, 6 cores distintas")
	ctx.check(UiText.item_display("sword_basic") == UiText.item_name("sword_basic") and UiText.item_display("sword_basic", inst) != UiText.item_name("sword_basic") and UiText.item_display("sword_basic", inst).contains(UiText.item_name("sword_basic")), "nome composto com affixes: '%s'" % UiText.item_display("sword_basic", inst))
	var tip: String = UiText.item_tooltip("sword_basic", 1, inst)
	var lines: PackedStringArray = tip.split("\n")
	ctx.check(lines.size() == 2 + 3 and lines[1].contains("ilvl 30") and lines[1].contains(rules.rarity_name("epic")), "tooltip: nome, raridade/ilvl e 3 linhas de affix (%d linhas)" % lines.size())
	ctx.check(tip.contains("Vida maxima") or tip.contains("vida"), "linha de affix de stat legivel")
	ctx.check(tip.contains("dano das habilidades"), "linha de affix de modificador de habilidade legivel")
	ctx.check(not tip.contains("pre_brutal") and not tip.contains("tier"), "tooltip sem ids internos")
	var utip: String = UiText.item_tooltip("unique_emberfang", 1)
	ctx.check(utip.contains("Unico") and utip.contains("40%"), "tooltip de unico traz a descricao do efeito")
	ctx.check(UiText.item_tooltip("potion_minor", 3) == UiText.stack_text("potion_minor", 3), "item simples: tooltip e so o nome/qty")
	for code: String in ["inventory_full", "busy", "bad_index", "item_mismatch", "not_equippable", "invalid_instance", "empty_slot", "not_available", "duplicate_request", "qualquer"]:
		ctx.check(not UiText.equip_error(code).is_empty(), "erro de equipar '%s' tem texto" % code)
	ctx.check(UiText.equip_error("inventory_full") != UiText.equip_error("busy"), "erros de equipar distintos")
	# inventario do cliente
	var inv: ClientInventory = ClientInventory.new()
	inv.apply_full([{"item_id": "sword_basic", "qty": 1, "inst": inst}, {"item_id": "potion_minor", "qty": 3}, {"item_id": "unique_emberfang", "qty": 1}], {"weapon": "sword_basic", "armor": "armor_leather"}, {})
	var se: Array[Dictionary] = inv.slot_entries()
	ctx.check(se.size() == 3 and se[0]["item_id"] == "sword_basic" and (se[0]["inst"] as Dictionary)["uid"] == "0123456789abcdef" and not se[1].has("inst"), "slot_entries na ordem do servidor, com inst so onde ha")
	inv.apply_full([{"item_id": "sword_basic", "qty": 1, "inst": "lixo"}], {})
	ctx.check(inv.slot_entries().size() == 1 and not (inv.slot_entries()[0].get("inst", {}) as Dictionary).has("uid"), "inst malformada nao quebra o cliente")
	# painel
	inv.apply_full([{"item_id": "sword_basic", "qty": 1, "inst": inst}, {"item_id": "potion_minor", "qty": 3}, {"item_id": "unique_emberfang", "qty": 1}], {"weapon": "sword_basic"}, {"weapon": {"uid": "fedcba9876543210", "rarity": "uncommon", "ilvl": 5, "affixes": [{"id": "suf_of_titan", "tier": 3, "value": 5.0}]}})
	var p: InventoryPanel = InventoryPanel.new()
	p.open()
	var req: Array = []
	var unreq: Array = []
	p.equip_requested.connect(func(i: int, id: String) -> void: req.append([i, id]))
	p.unequip_requested.connect(func(s: int) -> void: unreq.append(s))
	p.refresh(inv)
	ctx.check(p.slot_text(0) == UiText.item_display("sword_basic", inst), "slot 1 mostra o nome composto")
	ctx.check(p.slot_buttons[0].tooltip_text.contains("Epico") or p.slot_buttons[0].tooltip_text.contains(rules.rarity_name("epic")), "tooltip do botao com raridade")
	ctx.check(p.detail.text.contains("ilvl 30") and p.detail.text.contains("Equipado:"), "detalhe do cursor com affixes e linha 'Equipado:' (comparacao)")
	ctx.check(p.detail.text.contains(UiText.item_display("sword_basic", inv.equipment_inst["weapon"])), "comparacao cita o item equipado com seus affixes")
	ctx.check(p.detail.get_theme_color("font_color") == rules.rarity_color("epic"), "detalhe na cor da raridade")
	var wl: Label = p.equip_labels["weapon"]
	ctx.check(wl.text.contains(UiText.item_display("sword_basic", inv.equipment_inst["weapon"])) and wl.get_theme_color("font_color") == rules.rarity_color("uncommon"), "slot equipado com nome e cor da raridade")
	ctx.check(wl.tooltip_text.contains("ilvl 5"), "tooltip do equipado")
	# teclas
	p.handle_key(U.key(KEY_ENTER))
	ctx.check(req == [[0, "sword_basic"]], "Enter pede equipar o indice do cursor (%s)" % str(req))
	p.handle_key(U.key(KEY_1))
	p.handle_key(U.key(KEY_3))
	ctx.check(unreq == [0, 2], "teclas 1/3 pedem desequipar os slots 0 e 2")
	p.handle_key(U.key(KEY_RIGHT))
	p.handle_key(U.key(KEY_RIGHT))
	ctx.check(p.detail.text.contains("Unico") and p.detail.text.contains("40%"), "detalhe do unico mostra o efeito autorado")
	# nao equipa antes do inventario completo do servidor (estimativa)
	var est: ClientInventory = ClientInventory.new()
	est.add("sword_basic", 1)
	p.refresh(est)
	req.clear()
	p.handle_key(U.key(KEY_ENTER))
	ctx.check(req.is_empty(), "sem inventario completo do servidor, Enter nao envia comando")
	p.free()
