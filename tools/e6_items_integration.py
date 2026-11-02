#!/usr/bin/env python3
"""Integracao E6.3: itens com raridade/affixes com BACKEND REAL (Node + PGlite em memoria) + servidor Godot (arena, loot individual) + bots.
Reaproveita tools/e4_integration.py e tools/e5_adventure_integration.py.

Uso: python3 tools/e6_items_integration.py items [--godot CAMINHO] [--port N]
Cenario `items` (servidor + backend + 2 bots em UM comando):
  1. servidor em modo de TESTE (ELDERVALE_TEST_MODE=1, `--loot-test-force rare`: so garante raridade Rara e um equipamento por rolagem;
     os affixes, tiers e valores sao rolados pelo servidor com a semente normal). O bot `items` abate inimigos, recebe um item ROLADO
     (s_inventory com `inst`), PEDE para equipar, mede a vida maxima antes/depois e testa as recusas (indice ruim, base trocada).
  2. A vida maxima muda EXATAMENTE pela soma dos affixes de vida da instancia (+ diferenca de base), calculada aqui a partir do
     catalogo compartilhado (shared/content_schemas/items.json), nao do codigo do jogo.
  3. GET /v1/characters/:id: a instancia esta persistida (inventario/equipamento) e identica a que o bot recebeu; revision subiu.
  4. O backend recusa instancia forjada via recompensa/checkpoint internos (fora do loot:, valor fora da faixa, uid novo no checkpoint).
  5. bot `idle` reconecta com o MESMO personagem: a instancia equipada volta e a vida maxima mantem o bonus.
Saida 0 = tudo PASS."""
import argparse, importlib.util, json, os, re, signal, sys, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
_spec = importlib.util.spec_from_file_location("e4i", os.path.join(ROOT, "tools", "e4_integration.py"))
e4 = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(e4)
_spec5 = importlib.util.spec_from_file_location("e5i", os.path.join(ROOT, "tools", "e5_adventure_integration.py"))
e5 = importlib.util.module_from_spec(_spec5)
_spec5.loader.exec_module(e5)

CATALOG = json.load(open(os.path.join(ROOT, "shared", "content_schemas", "items.json")))
AFFIX = {a["id"]: a for a in CATALOG["affixes"]}


class T(e5.A):
    def __init__(self, name, godot, port):
        super().__init__(name, godot, port)
        self.dir = os.path.join(e4.SCR, f"e6_{name}_{int(time.time())}")
        os.makedirs(self.dir, exist_ok=True)


def base_max_health(item_id):
    """max_health do ItemData (.tres) - fonte do jogo; so usado para a diferenca entre a base equipada antes e depois."""
    p = os.path.join(ROOT, "data", "items", f"{item_id}.tres")
    m = re.search(r"^max_health = (-?[\d.]+)", open(p).read(), re.M) if os.path.exists(p) else None
    return float(m.group(1)) if m else 0.0


def affix_stat_sum(inst, stat):
    return sum(float(a["value"]) for a in inst.get("affixes", []) if AFFIX[a["id"]]["effect"].get("type") == "stat" and AFFIX[a["id"]]["effect"].get("stat") == stat)


def validate_against_catalog(inst, base_slot):
    """Regras do catalogo (raridade, orcamento, faixas) aplicadas por este script de forma independente do GDScript/TypeScript."""
    r = next(x for x in CATALOG["rarities"] if x["id"] == inst["rarity"])
    cost, groups = 0, set()
    for a in inst["affixes"]:
        d = AFFIX[a["id"]]
        t = next(x for x in d["tiers"] if x["tier"] == a["tier"])
        if base_slot not in d["slots"] or d["group"] in groups or inst["ilvl"] < t["ilvl_min"]:
            return False
        if not (t["min"] - 1e-6 <= a["value"] <= t["max"] + 1e-6):
            return False
        groups.add(d["group"])
        cost += t["cost"]
    return r["affix_min"] <= len(inst["affixes"]) <= r["affix_max"] and cost <= r["budget"]


def sc_items(c):
    c.start_api()
    cid = c.prepare_account("Itemizado", "warrior")
    c.accounts[c.email] = c.access
    before = c.character(cid) or {}
    os.environ["ELDERVALE_TEST_MODE"] = "1"  # parametros SO DE TESTE do servidor (ignorados sem isto)
    srv, sf = c.start_server("a", max_seconds=170, extra=["--individual-loot", "1", "--autosave-interval", "4", "--test-hp-mult", "0.2",
                                                          "--test-speed-mult", "1.5", "--loot-test-force", "rare"])
    sid = c.wait_session(sf, srv)
    c.check(sid is not None and cid is not None, "API, conta, personagem e sessao prontos")
    if not sid:
        return
    bot, out = c.start_bot("a", "items", "Itemizado", int(os.environ.get("E6_BOT_SECONDS", "140")), session_id=sid)
    r = c.finish_bot(bot, out, int(os.environ.get("E6_BOT_SECONDS", "140")) + 20)
    ib = r.get("item_bot") or {}
    adv = r.get("adventure") or {}
    inst = ib.get("inst") or {}
    print("  INFO  item_bot:", json.dumps(ib)[:600], "| erros:", r.get("errors"))
    c.check(r.get("_exit") == 0 and r.get("connected") is True, f"bot conectou e saiu 0 (exit={r.get('_exit')}, erros={r.get('errors')})")
    c.check(bool(inst) and inst.get("rarity") == "rare" and len(inst.get("affixes", [])) >= 3, f"item ROLADO recebido do servidor (raridade={inst.get('rarity')}, affixes={len(inst.get('affixes', []))})")
    base = ib.get("base", "")
    slot = {"sword_basic": "weapon", "sword_rare": "weapon", "armor_leather": "armor", "armor_heavy": "armor", "amulet_vigor": "trinket"}.get(base, "")
    c.check(bool(inst) and slot != "" and validate_against_catalog(inst, slot), f"instancia respeita o catalogo (orcamento/faixas/slot/ilvl): {base} ilvl {inst.get('ilvl')}")
    c.check(ib.get("equipped_uid") == inst.get("uid") and ib.get("slot") == slot, f"servidor equipou a instancia pedida (slot={ib.get('slot')}, uid={ib.get('equipped_uid')})")
    c.check(ib.get("inst_in_bag_after") is False, "a instancia saiu do inventario ao equipar (sem duplicar)")
    old_base = (before.get("equipment") or {}).get(slot, "")
    expected = affix_stat_sum(inst, "max_health") + base_max_health(base) - base_max_health(old_base)
    delta = float(ib.get("max_hp_after", -1)) - float(ib.get("max_hp_before", -1))
    c.check(abs(delta - expected) <= 1.0 and ib.get("max_hp_before", -1) > 0, f"vida maxima mudou EXATAMENTE pelos affixes: delta={delta:.1f} esperado={expected:.1f} ({ib.get('max_hp_before')} -> {ib.get('max_hp_after')})")
    c.check(ib.get("bad_index_code") == "bad_index", f"indice inexistente recusado (code={ib.get('bad_index_code')})")
    c.check(ib.get("mismatch_code") == "item_mismatch", f"base trocada recusada (code={ib.get('mismatch_code')})")
    eq_inst = adv.get("equipment_inst") or {}
    c.check((eq_inst.get(slot) or {}).get("uid") == inst.get("uid"), "s_inventory final traz equipment_inst com a mesma instancia")
    # persistencia: o backend guardou a MESMA instancia
    ch = c.poll_character(cid, lambda x: ((x.get("equipment_inst") or {}).get(slot) or {}).get("uid") == inst.get("uid"), 25)
    pe = ((ch or {}).get("equipment_inst") or {}).get(slot) or {}
    norm = lambda i: json.dumps(i, sort_keys=True)
    c.check(norm(pe) == norm(inst), "GET backend: equipment_inst persistido e IDENTICO ao que o servidor rolou")
    c.check((ch or {}).get("equipment", {}).get(slot) == base, f"GET backend: equipment.{slot} = {base}")
    uids = [e["inst"]["uid"] for e in (ch or {}).get("inventory", []) if e.get("inst")] + [i["uid"] for i in ((ch or {}).get("equipment_inst") or {}).values()]
    c.check(len(uids) == len(set(uids)) and uids.count(inst.get("uid")) == 1, f"uid unico no banco (sem duplicar): {uids}")
    rev = int((ch or {}).get("revision", 0))
    # o backend e a autoridade: instancia forjada e recusada
    forged = dict(inst)
    forged["uid"] = "00000000deadbeef"
    forged["affixes"] = [dict(a) for a in inst["affixes"]]
    forged["affixes"][0]["value"] = 99999.0
    key = f"loot:{sid}:777001:{cid}"
    st, d = c.ihttp("POST", f"/internal/characters/{cid}/rewards", {"idempotency_key": key, "xp": 0, "items": [{"item_id": base, "qty": 1, "inst": forged}]}, session=sid)
    c.check(st in (400, 422), f"recompensa com valor fora da faixa recusada ({st})")
    ok_forged = dict(inst)
    ok_forged["uid"] = "00000000cafe0001"
    st, d = c.ihttp("POST", f"/internal/characters/{cid}/rewards", {"idempotency_key": f"quest:q:{cid}", "xp": 0, "items": [{"item_id": base, "qty": 1, "inst": ok_forged}]}, session=sid)
    c.check(st in (400, 409, 422), f"instancia fora de uma chave loot: recusada ({st})")
    st, d = c.ihttp("POST", f"/internal/characters/{cid}/rewards", {"idempotency_key": key, "xp": 0, "items": [{"item_id": base, "qty": 1, "inst": ok_forged}]}, session=None)
    c.check(st in (400, 401, 403, 409), f"sem X-Session-Id (fencing) recusado ({st})")
    cur = c.character(cid) or {}
    st, d = c.ihttp("POST", f"/internal/characters/{cid}/checkpoint", {"expected_revision": int(cur.get("revision", 0)), "state": {
        "schema_version": 1, "level": cur["level"], "xp": cur["xp"], "stats": cur["stats"], "equipment": cur["equipment"],
        "inventory": cur["inventory"] + [{"slot": len(cur["inventory"]), "item_id": base, "qty": 1, "inst": ok_forged}]}}, session=sid)
    c.check(st in (400, 409, 422), f"checkpoint NAO cria instancia nova ({st})")
    after = c.character(cid) or {}
    after_uids = [e["inst"]["uid"] for e in after.get("inventory", []) if e.get("inst")] + [i["uid"] for i in (after.get("equipment_inst") or {}).values()]
    c.check("00000000cafe0001" not in after_uids and "00000000deadbeef" not in after_uids and after_uids.count(inst.get("uid")) == 1, "tentativas forjadas nao deixaram rastro no personagem")
    # reconexao
    bot2, out2 = c.start_bot("b", "idle", "Itemizado", 8, session_id=sid)
    r2 = c.finish_bot(bot2, out2, 60)
    a2 = r2.get("adventure") or {}
    c.check(r2.get("_exit") == 0 and r2.get("connected") is True, f"bot2 reconectou com o mesmo personagem (exit={r2.get('_exit')}, erros={r2.get('errors')})")
    c.check(((a2.get("equipment_inst") or {}).get(slot) or {}).get("uid") == inst.get("uid"), "reconexao: s_inventory traz a instancia equipada")
    c.check(r2.get("max_hp", 0) >= float(ib.get("max_hp_after", 1e9)) - 1.0, f"reconexao: vida maxima mantem o bonus ({r2.get('max_hp')} >= {ib.get('max_hp_after')})")
    c.check(int(c.character(cid).get("revision", 0)) >= rev, "revision so avanca")
    c.no_errors_in(["a"])
    c.no_secrets_in_logs()


SCEN = {"items": sc_items}


def main():
    signal.signal(signal.SIGTERM, lambda s, f: (e4.cleanup(), sys.exit(130)))
    ap = argparse.ArgumentParser()
    ap.add_argument("scenario", choices=list(SCEN))
    ap.add_argument("--godot", default=e4.default_godot())
    ap.add_argument("--port", type=int, default=25200)
    a = ap.parse_args()
    os.makedirs(e4.SCR, exist_ok=True)
    allf = []
    try:
        print(f"== {a.scenario}", flush=True)
        c = T(a.scenario, a.godot, a.port)
        t0 = time.time()
        try:
            SCEN[a.scenario](c)
        finally:
            e4.cleanup()
            e4._children.clear()
        print(f"  ({time.time() - t0:.0f} s; logs em {os.path.relpath(c.dir, e4.ROOT)})")
        allf += [f"{a.scenario}: {m}" for m in c.fails]
    finally:
        e4.cleanup()
    print("RESULTADO:", "OK" if not allf else f"{len(allf)} falha(s)")
    for f in allf:
        print("  -", f)
    sys.exit(1 if allf else 0)


if __name__ == "__main__":
    main()
