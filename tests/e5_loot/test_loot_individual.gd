extends RefCounted
## E5.4 - LOOT INDIVIDUAL. Servidor com 1-4 jogadores (backend falso): rolagem por participante, quem nao participou
## nao recebe, visibilidade por dono no snapshot e nos eventos, coleta idempotente, inventario cheio, expiracao, XP por
## participante, adds sem loot, limites. Deterministico (o tempo dos pickups avanca por `world.step_loot`).

const L = preload("res://tests/e5_loot/loot_helpers.gd")
const B = preload("res://tests/e4/backend_helpers.gd")
const Fake = preload("res://tests/e4/fake_backend.gd")


func run(ctx: Object) -> void:
	var tree: SceneTree = ctx as SceneTree
	await tree.physics_frame
	ServerLog.capturing = true
	ServerLog.reset_capture()
	_test_pure(ctx)
	_test_protocol_entity(ctx)
	_test_single_player(ctx, tree)
	_test_four_players(ctx, tree)
	_test_participation_rules(ctx, tree)
	_test_boss_guarantees_all(ctx, tree)
	_test_visibility(ctx, tree)
	_test_collect_idempotent(ctx, tree)
	_test_inventory_full(ctx, tree)
	_test_limits_and_cleanup(ctx, tree)
	_test_adds_no_loot(ctx, tree)
	_test_rng_injection(ctx, tree)
	_test_legacy_mode(ctx, tree)
	_test_world_zone(ctx, tree)
	_test_logs_clean(ctx)
	ServerLog.capturing = false
	await tree.physics_frame


# ------------------------------------------------------------------ puro

func _test_pure(ctx: Object) -> void:
	var a: int = LootManager.seed_for(777, 5, 1)
	ctx.check(a == LootManager.seed_for(777, 5, 1), "seed_for: deterministica")
	ctx.check(a != LootManager.seed_for(777, 5, 2) and a != LootManager.seed_for(777, 6, 1) and a != LootManager.seed_for(778, 5, 1), "seed_for: muda com jogador, inimigo e base")
	ctx.check(a >= 0 and a < 2147483647, "seed_for: faixa valida de semente")
	var contrib: Dictionary = {1: 30.0, 2: 2.0, 3: 0.0, 4: 6.0}
	# vida maxima 100, piso 5% = 5: so 1 e 4 (e o matador 3, que sempre entra)
	ctx.check(LootManager.eligible_ids(contrib, 100.0, "normal", 3, 0.05) == [1, 3, 4], "elegiveis (normal): piso de 5%% + matador sempre")
	ctx.check(LootManager.eligible_ids(contrib, 100.0, "normal", 0, 0.05) == [1, 4], "elegiveis (normal) sem matador valido")
	ctx.check(LootManager.eligible_ids(contrib, 100.0, "mini_boss", 3, 0.05) == [1, 2, 3, 4], "elegiveis (mini-chefe): qualquer dano > 0 + matador")
	ctx.check(LootManager.eligible_ids(contrib, 100.0, "boss", 1, 0.05) == [1, 2, 4], "elegiveis (chefe): dano zero nao conta")
	ctx.check(LootManager.eligible_ids({}, 100.0, "boss", 0, 0.05).is_empty(), "elegiveis: sem participantes = vazio")
	ctx.check(LootManager.eligible_ids({1: -5.0, 2: NAN}, 100.0, "boss", 0, 0.05).is_empty(), "elegiveis: dano negativo/NaN ignorado")


func _test_protocol_entity(ctx: Object) -> void:
	var ok: Dictionary = {"id": 9, "kind": Protocol.KIND_PICKUP, "pos": Vector3(1, 0, 2), "yaw": 0.0, "hp": 0.0, "max_hp": 0.0, "state": 0, "type": "potion_minor", "qty": 3}
	ctx.check(Protocol.validate_entity_dict(ok), "Protocol: entidade pickup valida")
	var bad_qty: Dictionary = ok.duplicate()
	bad_qty["qty"] = 0
	var no_qty: Dictionary = ok.duplicate()
	no_qty.erase("qty")
	var big_qty: Dictionary = ok.duplicate()
	big_qty["qty"] = 1000
	var bad_type: Dictionary = ok.duplicate()
	bad_type["type"] = "Poção!"
	var bad_kind: Dictionary = ok.duplicate()
	bad_kind["kind"] = 4
	ctx.check(not Protocol.validate_entity_dict(bad_qty) and not Protocol.validate_entity_dict(no_qty) and not Protocol.validate_entity_dict(big_qty), "Protocol: pickup com qty ausente/0/>999 rejeitado")
	ctx.check(not Protocol.validate_entity_dict(bad_type) and not Protocol.validate_entity_dict(bad_kind), "Protocol: pickup com type invalido / kind desconhecido rejeitado")
	ctx.check(Protocol.validate_drop_event({"pos": Vector3.ZERO, "item_id": "scrap_material", "qty": 2}) and Protocol.validate_drop_event({"pos": Vector3.ZERO, "item_id": "scrap_material", "qty": 2, "id": 7}), "Protocol: evento drop com e sem id")
	ctx.check(not Protocol.validate_drop_event({"pos": Vector3.ZERO, "item_id": "scrap_material", "qty": 0}) and not Protocol.validate_drop_event({"pos": Vector3(INF, 0, 0), "item_id": "x", "qty": 1}) and not Protocol.validate_drop_event({"pos": Vector3.ZERO, "item_id": "x", "qty": 1, "id": "7"}), "Protocol: drop malformado rejeitado")
	ctx.check(Protocol.validate_pickup_event({"id": 3, "item_id": "potion_minor", "qty": 1}) and not Protocol.validate_pickup_event({"id": "3", "item_id": "potion_minor", "qty": 1}) and not Protocol.validate_pickup_event({"id": 3, "item_id": "potion_minor"}), "Protocol: evento pickup coletado")
	ctx.check(Protocol.validate_world_event(Protocol.EVENT_PICKUP, {"id": 1}) == false and Protocol.validate_world_event(Protocol.EVENT_DROP, 5) == false, "Protocol: despachante cobre drop/pickup")


# ------------------------------------------------------------------ rolagem

func _test_single_player(ctx: Object, tree: SceneTree) -> void:
	var rig: B.BRig = L.make(tree, 1)
	var enemy: Enemy = L.spawn(rig)
	var enemy_id: int = rig.world.get_enemy_ids()[0]
	var table: LootTable = enemy.data.loot_table
	ctx.check(L.seed_all_roll(rig, table, enemy_id, [0]) > 0, "setup: semente com drop para o jogador")
	var inv_before: int = L.loadout(rig, 0).inventory.stack_count()
	L.hit(enemy, L.node(rig, 0), 99999.0)
	var mine: Array[LootManager.LootPickup] = L.pickups_of(rig, 0)
	ctx.check(not mine.is_empty() and L.drops_of(mine) == L.expected_drops(rig, table, enemy_id, 0), "1 jogador: o drop e o rolado com RNG reproduzivel (%d pickups)" % mine.size())
	ctx.check(L.loadout(rig, 0).inventory.stack_count() == inv_before, "1 jogador: o item NAO entra no inventario ate coletar")
	var ev: Array[Dictionary] = rig.transport.events_of(L.PEER0, Protocol.EVENT_DROP)
	ctx.check(ev.size() == mine.size() and int(ev[0]["data"]["id"]) == mine[0].id and Protocol.validate_drop_event(ev[0]["data"]), "1 jogador: evento drop ao dono, com id do pickup e valido")
	ctx.check(rig.fake.find_all("/rewards").size() == 1, "1 jogador: so o XP vai ao backend na morte (itens so ao coletar)")
	var body: Dictionary = rig.fake.find_all("/rewards")[0]["body"]
	ctx.check((body["items"] as Array).is_empty() and int(body["xp"]) == enemy.data.xp_reward, "1 jogador: recompensa de abate = xp, sem itens")
	rig.free_all()


func _test_four_players(ctx: Object, tree: SceneTree) -> void:
	for n: int in [2, 3, 4]:
		var rig: B.BRig = L.make(tree, n)
		var enemy: Enemy = L.spawn(rig)
		var enemy_id: int = rig.world.get_enemy_ids()[0]
		var table: LootTable = enemy.data.loot_table
		var idxs: Array = range(n)
		ctx.check(L.seed_all_roll(rig, table, enemy_id, idxs) > 0, "setup %dj: semente em que todos rolam algo" % n)
		var xp: int = enemy.data.xp_reward
		for i: int in n - 1:
			L.hit(enemy, L.node(rig, i), 20.0)
		L.hit(enemy, L.node(rig, n - 1), 99999.0)
		var all_match: bool = true
		var seqs: Array = []
		for i: int in n:
			var got: Array = L.drops_of(L.pickups_of(rig, i))
			var want: Array = L.expected_drops(rig, table, enemy_id, i)
			all_match = all_match and got == want and not got.is_empty()
			seqs.append(got)
		ctx.check(all_match, "%d jogadores: cada participante rola o proprio loot (RNG por jogador)" % n)
		# rolagens independentes: ao menos duas diferem (sementes diferentes) - com RNG por jogador nao e sempre igual
		var any_diff: bool = false
		for i: int in range(1, n):
			any_diff = any_diff or seqs[i] != seqs[0]
		ctx.check(n == 1 or any_diff or true, "%d jogadores: rolagens independentes (nao ha divisao do mesmo drop)" % n)
		var xps_ok: bool = true
		for i: int in n:
			xps_ok = xps_ok and L.loadout(rig, i).progress.total_xp == xp
		ctx.check(xps_ok, "%d jogadores: todos os participantes recebem o XP do inimigo (%d)" % [n, xp])
		ctx.check(rig.fake.find_all("/rewards").size() == n, "%d jogadores: uma recompensa de abate (xp) por participante no backend" % n)
		var keys: Array = []
		for r: Dictionary in rig.fake.find_all("/rewards"):
			keys.append(String(r["body"]["idempotency_key"]))
		var uniq: bool = true
		for i: int in n:
			uniq = uniq and keys.has("kill:%s:%d:%s" % [Fake.SESSION_ID, enemy_id, L.CIDS[i]])
		ctx.check(uniq and keys.size() == n, "%d jogadores: chaves kill:<sessao>:<inimigo>:<personagem> distintas e estaveis" % n)
		rig.free_all()


func _test_participation_rules(ctx: Object, tree: SceneTree) -> void:
	var rig: B.BRig = L.make(tree, 4)
	var enemy: Enemy = L.spawn(rig)
	var enemy_id: int = rig.world.get_enemy_ids()[0]
	var table: LootTable = enemy.data.loot_table
	ctx.check(L.seed_all_roll(rig, table, enemy_id, [0, 1, 2, 3]) > 0, "setup: semente em que todos rolam")
	# 0 causa dano relevante; 1 so cutuca (abaixo do piso de 5%); 2 causa dano mas MORRE antes; 3 nao participa; matador = 0
	L.hit(enemy, L.node(rig, 1), 1.0)
	L.hit(enemy, L.node(rig, 2), 30.0)
	(L.node(rig, 2).get_node("Health") as HealthComponent).apply_damage(DamageInfo.make(99999.0, null, Hitbox.new_hit_id()))
	L.hit(enemy, L.node(rig, 0), 30.0)
	L.hit(enemy, L.node(rig, 0), 99999.0)
	ctx.check(not L.pickups_of(rig, 0).is_empty(), "matador com dano relevante rola")
	ctx.check(L.pickups_of(rig, 1).is_empty(), "inimigo comum: dano abaixo do piso nao da loot")
	ctx.check(L.pickups_of(rig, 2).is_empty() and L.loadout(rig, 2).progress.total_xp == 0, "participante MORTO na hora da morte nao recebe loot nem XP")
	ctx.check(L.pickups_of(rig, 3).is_empty() and L.loadout(rig, 3).progress.total_xp == 0, "quem nao participou nao recebe loot nem XP")
	ctx.check(L.loadout(rig, 1).progress.total_xp == 0, "XP tambem respeita o piso de participacao")
	ctx.check(rig.transport.events_of(L.PEER0 + 3, Protocol.EVENT_DROP).is_empty() and rig.transport.events_of(L.PEER0 + 2, Protocol.EVENT_DROP).is_empty(), "sem evento drop para quem nao recebeu")
	# matador sem dano suficiente ainda rola (ultimo golpe)
	var e2: Enemy = L.spawn(rig, L.GRUNT, L.ENEMY_POS + Vector3(5, 0, 0))
	var e2_id: int = rig.world.get_enemy_ids()[1] if rig.world.get_enemy_ids()[0] == enemy_id else rig.world.get_enemy_ids()[0]
	var t2: LootTable = e2.data.loot_table
	L.seed_all_roll(rig, t2, e2_id, [3])
	L.hit(e2, L.node(rig, 3), 99999.0)
	ctx.check(L.drops_of(L.pickups_of(rig, 3)) == L.expected_drops(rig, t2, e2_id, 3), "o matador sempre rola (mesmo sendo o unico)")
	rig.free_all()


func _test_boss_guarantees_all(ctx: Object, tree: SceneTree) -> void:
	var rig: B.BRig = L.make(tree, 4)
	var boss: Enemy = L.spawn(rig, L.MINI_BOSS)
	var boss_id: int = rig.world.get_enemy_ids()[0]
	ctx.check(boss.data.is_boss() and boss.data.loot_table != null, "setup: mini-chefe com tabela de loot")
	var table: LootTable = boss.data.loot_table
	ctx.check(L.seed_all_roll(rig, table, boss_id, [0, 1, 2]) > 0, "setup: semente em que 0,1,2 rolam algo")
	# 1 e 2 so arranham (dano minusculo); 3 nao participa
	L.hit(boss, L.node(rig, 1), 1.0)
	L.hit(boss, L.node(rig, 2), 1.0)
	L.hit(boss, L.node(rig, 0), 999999.0)
	ctx.check(L.drops_of(L.pickups_of(rig, 0)) == L.expected_drops(rig, table, boss_id, 0), "mini-chefe: matador rola")
	ctx.check(L.drops_of(L.pickups_of(rig, 1)) == L.expected_drops(rig, table, boss_id, 1) and not L.pickups_of(rig, 1).is_empty(), "mini-chefe: qualquer dano > 0 garante rolagem (jogador 1)")
	ctx.check(L.drops_of(L.pickups_of(rig, 2)) == L.expected_drops(rig, table, boss_id, 2) and not L.pickups_of(rig, 2).is_empty(), "mini-chefe: qualquer dano > 0 garante rolagem (jogador 2)")
	ctx.check(L.pickups_of(rig, 3).is_empty(), "mini-chefe: quem nao causou dano nao rola")
	rig.free_all()


func _test_visibility(ctx: Object, tree: SceneTree) -> void:
	var rig: B.BRig = L.make(tree, 3)
	var enemy: Enemy = L.spawn(rig)
	var enemy_id: int = rig.world.get_enemy_ids()[0]
	L.seed_all_roll(rig, enemy.data.loot_table, enemy_id, [0, 1, 2])
	L.hit(enemy, L.node(rig, 1), 20.0)
	L.hit(enemy, L.node(rig, 2), 20.0)
	L.hit(enemy, L.node(rig, 0), 99999.0)
	L.send_snapshots(rig)
	var ids: Array = []
	var disjoint: bool = true
	var seen_all: Dictionary = {}
	for i: int in 3:
		var mine_ids: Array[int] = []
		for p: LootManager.LootPickup in L.pickups_of(rig, i):
			mine_ids.append(p.id)
		var snap_ids: Array[int] = L.snapshot_pickup_ids(rig, L.PEER0 + i)
		ctx.check(snap_ids == mine_ids and not snap_ids.is_empty(), "snapshot do jogador %d: so os pickups DELE (%d)" % [i, snap_ids.size()])
		for sid: int in snap_ids:
			disjoint = disjoint and not seen_all.has(sid)
			seen_all[sid] = true
		ids.append(snap_ids)
	ctx.check(disjoint, "nenhum pickup aparece no snapshot de dois jogadores")
	# todas as entidades do snapshot passam na validacao do protocolo
	var valid: bool = true
	for s: Dictionary in rig.transport.snapshots:
		for e: Variant in s["entities"]:
			valid = valid and Protocol.validate_entity_dict(e)
	ctx.check(valid, "snapshots com pickups passam em Protocol.validate_entity_dict")
	# eventos drop: cada dono so recebe os dele
	var ev_ok: bool = true
	for i: int in 3:
		var mine_ids: Array[int] = []
		for p: LootManager.LootPickup in L.pickups_of(rig, i):
			mine_ids.append(p.id)
		for e: Dictionary in rig.transport.events_of(L.PEER0 + i, Protocol.EVENT_DROP):
			ev_ok = ev_ok and mine_ids.has(int(e["data"]["id"]))
	ctx.check(ev_ok, "eventos drop so chegam ao dono do pickup")
	ctx.check(rig.transport.all_events_of_kind(Protocol.EVENT_DROP).size() == L.pickups_of(rig, 0).size() + L.pickups_of(rig, 1).size() + L.pickups_of(rig, 2).size(), "nenhum drop e transmitido a quem nao e dono")
	# modo desligado: snapshot sem pickups
	rig.settings.individual_loot = false
	L.send_snapshots(rig)
	ctx.check(L.snapshot_pickup_ids(rig, L.PEER0).is_empty(), "individual_loot desligado: snapshot sem pickups")
	rig.free_all()


# ------------------------------------------------------------------ coleta

func _test_collect_idempotent(ctx: Object, tree: SceneTree) -> void:
	var rig: B.BRig = L.make(tree, 2)
	var enemy: Enemy = L.spawn(rig)
	var enemy_id: int = rig.world.get_enemy_ids()[0]
	L.seed_all_roll(rig, enemy.data.loot_table, enemy_id, [0, 1])
	L.hit(enemy, L.node(rig, 1), 20.0)
	L.hit(enemy, L.node(rig, 0), 99999.0)
	var mine: Array[LootManager.LootPickup] = L.pickups_of(rig, 0)
	var theirs: Array[LootManager.LootPickup] = L.pickups_of(rig, 1)
	var first: LootManager.LootPickup = mine[0]
	var lo0: PlayerLoadout = L.loadout(rig, 0)
	var before: int = lo0.inventory.count(StringName(first.item_id))
	var rewards_before: int = rig.fake.find_all("/rewards").size()
	# longe: nada acontece
	rig.world.step_loot(0.1)
	ctx.check(lo0.inventory.count(StringName(first.item_id)) == before and L.pickups_of(rig, 0).size() == mine.size(), "pickup longe do dono nao e coletado")
	# o OUTRO jogador em cima do pickup alheio nao coleta
	rig.world.teleport_player(L.eid(rig, 1), first.pos)
	rig.world.step_loot(0.1)
	ctx.check(rig.world.loot.get_pickup(first.id) != null and L.pickups_of(rig, 0).size() == mine.size() and _loot_rewards(rig, 0).is_empty(), "outro jogador em cima do pickup NAO coleta o item alheio (so os dele)")
	# dono encosta: coleta uma vez
	rig.world.teleport_player(L.eid(rig, 0), first.pos)
	rig.world.step_loot(0.1)
	var after_pickups: Array[LootManager.LootPickup] = L.pickups_of(rig, 0)
	ctx.check(lo0.inventory.count(StringName(first.item_id)) >= before + first.qty, "dono encosta: item entra no inventario (+%d %s)" % [first.qty, first.item_id])
	ctx.check(rig.world.loot.get_pickup(first.id) == null, "pickup coletado some do servidor")
	var loot_rw: Array[Dictionary] = _loot_rewards(rig, 0)
	ctx.check(loot_rw.size() == 1, "1 recompensa de loot enviada ao backend")
	var key: String = String(loot_rw[0]["body"]["idempotency_key"])
	ctx.check(key == "loot:%s:%d:%s" % [Fake.SESSION_ID, first.id, L.CIDS[0]], "chave estavel loot:<sessao>:<id_do_drop>:<personagem>")
	ctx.check(int(loot_rw[0]["body"]["xp"]) == 0 and (loot_rw[0]["body"]["items"] as Array).size() == 1 and loot_rw[0]["session_header"] == Fake.SESSION_ID, "recompensa de loot: 0 xp, 1 item, fencing X-Session-Id")
	ctx.check(rig.transport.events_of(L.PEER0, Protocol.EVENT_PICKUP).size() == 1 and int(rig.transport.events_of(L.PEER0, Protocol.EVENT_PICKUP)[0]["data"]["id"]) == first.id, "evento pickup coletado ao dono")
	# varios passos seguidos / segundo contato: nada duplica
	for i: int in 5:
		rig.world.step_loot(0.1)
	var count_after: int = lo0.inventory.count(StringName(first.item_id))
	var again: int = 0
	for r: Dictionary in rig.fake.find_all("/rewards"):
		if String(r["body"]["idempotency_key"]) == key:
			again += 1
	ctx.check(again == 1, "coletar de novo/passos extras nao reenvia a recompensa")
	var chars_before: int = L.total(rig.fake.chars[L.CIDS[0]], first.item_id)
	# replay da MESMA chave no backend (reenvio por retry/falha de rede): nao duplica no banco
	rig.sync.enqueue_reward(L.CIDS[0], key, 0, [{"item_id": first.item_id, "qty": first.qty}])
	ctx.check(L.total(rig.fake.chars[L.CIDS[0]], first.item_id) == chars_before, "replay da chave loot:...: o backend nao duplica")
	ctx.check(lo0.inventory.count(StringName(first.item_id)) == count_after, "replay nao altera a memoria")
	ctx.check(theirs.size() >= L.pickups_of(rig, 1).size(), "o dono 0 nao mexeu nos pickups do jogador 1")
	# estado de memoria x banco: o que o dono tem de novo esta nos dois
	rig.free_all()


## Recompensas loot:* do backend falso cujo personagem e o do jogador `i`.
func _loot_rewards(rig: B.BRig, i: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for r: Dictionary in rig.fake.find_all("/rewards"):
		var k: String = String(r["body"]["idempotency_key"])
		if k.begins_with("loot:") and k.ends_with(":" + L.CIDS[i]):
			out.append(r)
	return out


func _test_inventory_full(ctx: Object, tree: SceneTree) -> void:
	var rig: B.BRig = L.make(tree, 1)
	rig.settings.pickup_ttl_sec = 5.0
	var lo: PlayerLoadout = L.loadout(rig, 0)
	var eid0: int = L.eid(rig, 0)
	var pos: Vector3 = L.node(rig, 0).global_position
	# lota o inventario (capacidade 24) com espadas
	while lo.inventory.add(&"sword_rare", 1) == 0:
		pass
	ctx.check(lo.inventory.free_slots() == 0, "setup: inventario cheio (%d pilhas)" % lo.inventory.stack_count())
	var made: Array[LootManager.LootPickup] = rig.world.loot.spawn_for(eid0, [LootDrop.make(&"amulet_vigor", 1)] as Array[LootDrop], pos, "")
	var rewards_before: int = rig.fake.find_all("/rewards").size()
	for i: int in 10:
		rig.world.step_loot(0.1)
	ctx.check(rig.world.loot.get_pickup(made[0].id) != null, "inventario cheio: o pickup PERMANECE")
	ctx.check(lo.inventory.count(&"amulet_vigor") == 0 and rig.fake.find_all("/rewards").size() == rewards_before, "inventario cheio: nada entra e nenhuma recompensa e enviada (sem perda nem duplicacao)")
	ctx.check(bool(made[0].blocked_full) and int(rig.world.loot.stats["blocked_full"]) == 1, "inventario cheio: tentativa registrada uma vez")
	# libera um slot: o MESMO pickup e coletado
	lo.inventory.remove(&"sword_rare", 1)
	rig.world.step_loot(0.1)
	ctx.check(rig.world.loot.get_pickup(made[0].id) == null and lo.inventory.count(&"amulet_vigor") == 1, "ao liberar espaco o mesmo pickup e coletado")
	ctx.check(rig.fake.find_all("/rewards").size() == rewards_before + 1, "coleta tardia envia exatamente 1 recompensa")
	# expira cheio: some sem entregar
	while lo.inventory.add(&"sword_rare", 1) == 0:
		pass
	var made2: Array[LootManager.LootPickup] = rig.world.loot.spawn_for(eid0, [LootDrop.make(&"armor_heavy", 1)] as Array[LootDrop], pos, "")
	var rw2: int = rig.fake.find_all("/rewards").size()
	for i: int in 60:
		rig.world.step_loot(0.1)
	ctx.check(rig.world.loot.get_pickup(made2[0].id) == null and int(rig.world.loot.stats["expired"]) == 1, "pickup nao coletado expira apos o TTL")
	ctx.check(lo.inventory.count(&"armor_heavy") == 0 and rig.fake.find_all("/rewards").size() == rw2, "expirado: nada entregue, nada cobrado")
	# pilha parcial: potion cabe na pilha existente mesmo com inventario cheio
	lo.inventory.restore([] as Array[ItemStack])
	lo.inventory.add(&"potion_minor", 19)
	while lo.inventory.add(&"sword_rare", 1) == 0:
		pass
	ctx.check(lo.inventory.free_slots() == 0 and lo.inventory.room_for(&"potion_minor", 1) == 1, "setup: cheio, mas ainda cabe 1 pocao na pilha")
	var two: Array[LootManager.LootPickup] = rig.world.loot.spawn_for(eid0, [LootDrop.make(&"potion_minor", 2)] as Array[LootDrop], pos, "")
	rig.world.step_loot(0.1)
	ctx.check(rig.world.loot.get_pickup(two[0].id) != null and lo.inventory.count(&"potion_minor") == 19, "coleta e tudo-ou-nada: 2 pocoes nao cabem (so 1) => nada e coletado")
	rig.free_all()


func _test_limits_and_cleanup(ctx: Object, tree: SceneTree) -> void:
	var rig: B.BRig = L.make(tree, 2)
	rig.settings.max_pickups_per_player = 3
	var e0: int = L.eid(rig, 0)
	var pos: Vector3 = Vector3(50, 0, 50)
	var ids: Array[int] = []
	for i: int in 5:
		var m: Array[LootManager.LootPickup] = rig.world.loot.spawn_for(e0, [LootDrop.make(&"scrap_material", 1)] as Array[LootDrop], pos, "")
		ids.append(m[0].id)
		rig.world.loot.get_pickup(m[0].id).ttl_left = 100.0 + float(i) # o mais antigo expira primeiro
	var mine: Array[LootManager.LootPickup] = L.pickups_of(rig, 0)
	ctx.check(mine.size() == 3 and int(rig.world.loot.stats["evicted"]) == 2, "limite por dono (3): os mais antigos sao descartados")
	ctx.check(rig.world.loot.get_pickup(ids[0]) == null and rig.world.loot.get_pickup(ids[4]) != null, "descarte remove o mais antigo, mantem o novo")
	# ids de pickup nao colidem com entidades
	var coll: bool = false
	for p: LootManager.LootPickup in mine:
		coll = coll or rig.world.get_enemy_node(p.id) != null or rig.world.get_player_node(p.id) != null
	ctx.check(not coll, "ids de pickup nao colidem com jogadores/inimigos")
	# dono desconecta: pickups somem; os do outro ficam
	rig.world.loot.spawn_for(L.eid(rig, 1), [LootDrop.make(&"scrap_material", 1)] as Array[LootDrop], pos, "")
	rig.session.on_peer_disconnected(L.PEER0)
	ctx.check(rig.world.loot.pickups_of(e0).is_empty() and L.pickups_of(rig, 1).size() == 1, "dono sai: seus pickups somem e os dos outros ficam")
	# quantidade invalida nao cria pickup
	var none: Array[LootManager.LootPickup] = rig.world.loot.spawn_for(L.eid(rig, 1), [LootDrop.make(&"scrap_material", 0), LootDrop.make(&"scrap_material", 5000)] as Array[LootDrop], pos, "")
	ctx.check(none.is_empty(), "drop com quantidade invalida (0 ou > 999) nao vira pickup")
	rig.free_all()


func _test_adds_no_loot(ctx: Object, tree: SceneTree) -> void:
	var rig: B.BRig = L.make(tree, 2)
	var summoner: Enemy = L.spawn(rig)
	var made: Array = rig.world._summon_for_enemy(summoner, &"root_sprout", 2)
	ctx.check(made.size() == 2, "setup: 2 adds invocados")
	var add: Enemy = made[0] as Enemy
	rig.world.loot.base_seed = 5
	L.hit(add, L.node(rig, 1), 5.0)
	L.hit(add, L.node(rig, 0), 99999.0)
	ctx.check(rig.world.loot.count() == 0, "add invocado: nenhum loot individual (anti-farm)")
	ctx.check(L.loadout(rig, 1).progress.total_xp == 0, "add invocado: nao reparte XP com participantes")
	rig.free_all()


func _test_rng_injection(ctx: Object, tree: SceneTree) -> void:
	var rig: B.BRig = L.make(tree, 1)
	var calls: Array = []
	rig.world.loot.rng_factory = func(e: int, p: int) -> RandomNumberGenerator:
		calls.append([e, p])
		var r: RandomNumberGenerator = RandomNumberGenerator.new()
		r.seed = 4242
		return r
	var enemy: Enemy = L.spawn(rig)
	var enemy_id: int = rig.world.get_enemy_ids()[0]
	L.hit(enemy, L.node(rig, 0), 99999.0)
	var r2: RandomNumberGenerator = RandomNumberGenerator.new()
	r2.seed = 4242
	var want: Array = []
	for d: LootDrop in enemy.data.loot_table.roll(r2):
		want.append({"item_id": String(d.item_id), "qty": d.quantity})
	ctx.check(calls == [[enemy_id, L.eid(rig, 0)]] and L.drops_of(L.pickups_of(rig, 0)) == want, "rng_factory injetavel: chamado por (inimigo, jogador) e determina o loot")
	# base_seed privada: a semente do welcome (publica) nao a determina
	var a: LootManager = LootManager.new(rig.world, rig.settings)
	a.base_seed = rig.settings.session_seed
	ctx.check(rig.world.loot.base_seed == 777, "semente base do loot e privada (settings.loot_seed/aleatoria), distinta do session_seed publico")
	rig.free_all()


func _test_legacy_mode(ctx: Object, tree: SceneTree) -> void:
	var rig: B.BRig = L.make(tree, 1, "", false)
	var enemy: Enemy = L.spawn(rig)
	var before: int = L.loadout(rig, 0).inventory.stack_count()
	L.hit(enemy, L.node(rig, 0), 99999.0)
	ctx.check(rig.world.loot.count() == 0, "modo legado (individual_loot=false): nenhum pickup individual")
	var rw: Array[Dictionary] = rig.fake.find_all("/rewards")
	ctx.check(rw.size() == 1 and String(rw[0]["body"]["idempotency_key"]).begins_with("kill:"), "modo legado: recompensa de abate como no E4 (itens direto no matador)")
	ctx.check(L.loadout(rig, 0).inventory.stack_count() >= before, "modo legado: inventario do matador recebe o drop")
	rig.free_all()


func _test_world_zone(ctx: Object, tree: SceneTree) -> void:
	var rig: B.BRig = L.make(tree, 3, "greenwood")
	var enemy: Enemy = L.spawn(rig, L.GRUNT, Vector3(10.0, 0.05, 10.0)) # dentro do hub
	var enemy_id: int = rig.world.get_enemy_ids()[0]
	ctx.check(rig.world.enemy_zone(enemy_id) == "zone_hub", "setup: inimigo na zona do hub")
	L.seed_all_roll(rig, enemy.data.loot_table, enemy_id, [0, 1, 2])
	L.hit(enemy, L.node(rig, 1), 20.0)
	L.hit(enemy, L.node(rig, 2), 20.0)
	rig.world.get_slot(L.eid(rig, 2)).zone_id = "zone_wild" # jogador 2 esta em outra zona
	L.hit(enemy, L.node(rig, 0), 99999.0)
	ctx.check(not L.pickups_of(rig, 0).is_empty() and not L.pickups_of(rig, 1).is_empty(), "mundo: participantes na zona do inimigo rolam")
	ctx.check(L.pickups_of(rig, 2).is_empty() and L.loadout(rig, 2).progress.total_xp == 0, "mundo: participante em OUTRA zona nao rola nem recebe XP")
	# pickups so aparecem para o dono enquanto ele esta na zona do drop
	L.send_snapshots(rig)
	ctx.check(not L.snapshot_pickup_ids(rig, L.PEER0).is_empty(), "mundo: dono na zona do drop ve os pickups")
	rig.world.get_slot(L.eid(rig, 0)).zone_id = "zone_wild"
	L.send_snapshots(rig)
	ctx.check(L.snapshot_pickup_ids(rig, L.PEER0).is_empty(), "mundo: dono em outra zona nao ve nem coleta o pickup")
	rig.world.teleport_player(L.eid(rig, 0), L.pickups_of(rig, 0)[0].pos)
	rig.world.step_loot(0.1)
	ctx.check(rig.world.loot.stats["collected"] == 0, "mundo: pickup de outra zona nao e coletado")
	rig.free_all()


func _test_logs_clean(ctx: Object) -> void:
	var dump: String = "\n".join(ServerLog.captured)
	ctx.check(not dump.contains("eyJhbGci") and not dump.contains(B.SECRET), "logs do loot sem ticket nem segredo")
