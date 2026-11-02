#!/usr/bin/env python3
"""Integracao E6.4: quests novas + exploracao com BACKEND REAL (Node + PGlite em memoria), servidor Godot `--world greenwood` e bots.
Reaproveita tools/e4_integration.py e tools/e5_adventure_integration.py.

Uso: python3 tools/e6_quests_integration.py quests [--godot CAMINHO] [--port N]
Cenario `quests` (servidor + backend + 2 bots em UM comando):
  1. bot `adv_e6` (hub -> selvagem -> hub -> selvagem -> hub, por DADOS do mundo) cumpre 3 quests (gw_welcome + as NOVAS gw_wild_survey [objetivos
     `discover`] e gw_whispers [objetivos `talk` em NPCs novos]) e descobre 4 pontos de exploracao (segredo no hub; marcos, bau e esconderijo na selvagem);
     a descoberta e decidida pelo SERVIDOR pela posicao autoritativa (o bot so anda).
  2. O backend guarda quests concluidas e pontos descobertos; xp persistido == soma EXATA das recompensas do catalogo (calculada aqui, a partir
     dos JSON gerados, de forma independente do codigo do jogo); inventario do cliente == persistido.
  3. Recompensa unica/idempotente no backend: mesma chave => replayed; OUTRA chave para o mesmo ponto => 409; valor adulterado => 400; chave
     `explore:` sem poi_id => 400; checkpoint nao apaga nem cria `discovered`.
  4. Reconexao com o MESMO personagem (`adv_check`): descobertas e quests voltam no sync; nada e pago de novo.
Saida 0 = tudo PASS."""
import argparse, importlib.util, json, os, signal, sys, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
_spec = importlib.util.spec_from_file_location("e4i", os.path.join(ROOT, "tools", "e4_integration.py"))
e4 = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(e4)
_spec5 = importlib.util.spec_from_file_location("e5i", os.path.join(ROOT, "tools", "e5_adventure_integration.py"))
e5 = importlib.util.module_from_spec(_spec5)
_spec5.loader.exec_module(e5)

QUESTS = {q["id"]: q for q in json.load(open(os.path.join(ROOT, "shared", "content_schemas", "quests.json")))["quests"]}
POIS = {p["id"]: p for p in json.load(open(os.path.join(ROOT, "shared", "content_schemas", "exploration.json")))["points"]}
DONE_QUESTS = ["gw_welcome", "gw_wild_survey", "gw_whispers"]
DONE_POIS = ["poi_hub_hollow_stump", "poi_wild_fallen_oak", "poi_wild_old_milestone", "poi_wild_hunter_cache"]


class T(e5.A):
    def __init__(self, name, godot, port):
        super().__init__(name, godot, port)
        self.dir = os.path.join(e4.SCR, f"e6q_{name}_{int(time.time())}")
        os.makedirs(self.dir, exist_ok=True)


def sc_quests(c):
    c.start_api()
    cid = c.make_char(c.email, "Cartografo")
    srv, sf = c.start_world_server("a", max_seconds=170, knobs=(0.2, 2.0), autosave=4)
    sid = c.wait_session(sf, srv)
    c.check(sid is not None and cid is not None, "API, conta, personagem e sessao prontos")
    if not sid:
        return
    secs = int(os.environ.get("E6Q_BOT_SECONDS", "150"))
    bot, out = c.bot("a", "adv_e6", "Cartografo", secs, sid)
    r = c.finish_bot(bot, out, secs + 20)
    q = e5.adv(r).get("quests", {})
    print("  INFO  passos:", [(s["step"], s["t"]) for s in e5.adv(r).get("steps", [])])
    print("  INFO  quests:", json.dumps(q)[:500])
    c.check(r.get("_exit") == 0 and r.get("connected") is True, f"bot conectou e saiu 0 (exit={r.get('_exit')}, erros={r.get('errors')})")
    c.check(not q.get("timeouts"), f"nenhum passo estourou o tempo ({q.get('timeouts')})")
    c.check(set(q.get("completed", [])) >= set(DONE_QUESTS), f"3 quests (2 NOVAS) entregues no cliente ({q.get('completed')})")
    c.check(set(q.get("discovered", [])) >= set(DONE_POIS), f"4 pontos de exploracao descobertos no cliente ({q.get('discovered')})")
    ch = c.poll(c.email, cid, lambda x: set(DONE_QUESTS) <= set(e5.quests_of(x)[1]) and len((x.get("quests") or {}).get("discovered", [])) >= len(DONE_POIS), 30)
    active, completed = e5.quests_of(ch)
    disc = (ch.get("quests") or {}).get("discovered", [])
    c.check(set(DONE_QUESTS) <= set(completed) and not active, f"GET backend: quests concluidas persistidas (completed={completed}, active={list(active)})")
    c.check(set(DONE_POIS) <= set(disc) and len(disc) == len(set(disc)), f"GET backend: pontos descobertos persistidos sem repeticao ({disc})")
    expected_xp = sum(QUESTS[x]["rewards"]["xp"] for x in DONE_QUESTS) + sum(POIS[p]["rewards"]["xp"] for p in disc)
    c.check(int(ch["xp"]) == expected_xp, f"xp persistido == soma exata das recompensas do catalogo ({ch['xp']} == {expected_xp})")
    # itens: soma das recompensas (quests + pontos) == itens no personagem (nenhum consumo no roteiro)
    want = {}
    for x in DONE_QUESTS:
        for it in QUESTS[x]["rewards"]["items"]:
            want[it["item_id"]] = want.get(it["item_id"], 0) + it["qty"]
    for p in disc:
        for it in POIS[p]["rewards"]["items"]:
            want[it["item_id"]] = want.get(it["item_id"], 0) + it["qty"]
    have = c.total_items(ch)
    c.check(all(have.get(k, 0) >= v for k, v in want.items()), f"itens das recompensas presentes (esperado>= {want}, backend {have})")
    e5.inv_matches(c, "bot", r, ch)
    # ---- idempotencia / adulteracao no backend
    before = c.char_of(c.email, cid)
    xp0, rev0 = int(before["xp"]), int(before["revision"])
    poi = "poi_wild_fallen_oak"
    body = {"idempotency_key": f"explore:{poi}:{cid}", "poi_id": poi, "xp": POIS[poi]["rewards"]["xp"], "items": POIS[poi]["rewards"]["items"]}
    st, d = c.ihttp("POST", f"/internal/characters/{cid}/rewards", body, session=sid)
    after = c.char_of(c.email, cid)
    c.check(st == 200 and d and d.get("replayed") is True and int(after["xp"]) == xp0 and c.total_items(after) == c.total_items(before), f"mesma chave de exploracao: replayed=true, nada duplicado (status={st})")
    st, d = c.ihttp("POST", f"/internal/characters/{cid}/rewards", dict(body, idempotency_key=f"explore:{poi}:{cid}", xp=body["xp"] + 1), session=sid)
    c.check(st in (400, 409) and int(c.char_of(c.email, cid)["xp"]) == xp0, f"valor adulterado recusado ({st})")
    # ponto com nivel minimo (3): o backend decide pelo NIVEL do banco (409 se baixo; senao paga UMA vez e um replay nao dobra)
    other = "poi_wild_thorn_relic"
    obody = {"idempotency_key": f"explore:{other}:{cid}", "poi_id": other, "xp": POIS[other]["rewards"]["xp"], "items": POIS[other]["rewards"]["items"]}
    lvl = int(c.char_of(c.email, cid)["level"])
    st, d = c.ihttp("POST", f"/internal/characters/{cid}/rewards", obody, session=sid)
    if lvl < POIS[other]["min_level"]:
        c.check(st == 409 and int(c.char_of(c.email, cid)["xp"]) == xp0, f"nivel {lvl} < {POIS[other]['min_level']}: backend recusa o ponto ({st})")
    else:
        c.check(st == 200 and int(c.char_of(c.email, cid)["xp"]) == xp0 + POIS[other]["rewards"]["xp"], f"nivel {lvl}: backend paga o ponto de nivel {POIS[other]['min_level']} uma vez ({st})")
        st2, d2 = c.ihttp("POST", f"/internal/characters/{cid}/rewards", obody, session=sid)
        c.check(st2 == 200 and d2 and d2.get("replayed") is True and int(c.char_of(c.email, cid)["xp"]) == xp0 + POIS[other]["rewards"]["xp"], f"replay do ponto extra nao dobra ({st2})")
        disc = (c.char_of(c.email, cid).get("quests") or {}).get("discovered", [])
    st, _ = c.ihttp("POST", f"/internal/characters/{cid}/rewards", {"idempotency_key": f"explore:{poi}:{cid}x1", "xp": 5, "items": []}, session=sid)
    c.check(st == 400, f"chave explore: sem poi_id recusada ({st})")
    st, _ = c.ihttp("POST", f"/internal/characters/{cid}/rewards", dict(body, idempotency_key=f"explore:{poi}:{cid}"), session=None)
    c.check(st == 400, f"sem X-Session-Id => 400 ({st})")
    cur = c.character(cid) or {}
    st, _ = c.ihttp("POST", f"/internal/characters/{cid}/checkpoint", {"expected_revision": int(cur.get("revision", 0)), "state": {
        "schema_version": 1, "level": cur["level"], "xp": cur["xp"], "stats": cur["stats"], "equipment": cur["equipment"], "inventory": cur["inventory"],
        "quests": {"active": {}, "completed": cur["quests"]["completed"], "discovered": []}}}, session=sid)
    now = c.char_of(c.email, cid)
    c.check(set((now.get("quests") or {}).get("discovered", [])) == set(disc), f"checkpoint (status {st}) nao apaga descobertas")
    # ---- reconexao: nada paga de novo
    xp1 = int(now["xp"])
    bot2, out2 = c.bot("b", "adv_check", "Cartografo", 12, sid)
    r2 = c.finish_bot(bot2, out2, 60)
    q2 = e5.adv(r2).get("quests", {})
    c.check(r2.get("_exit") == 0 and r2.get("connected") is True, f"bot2 reconectou com o mesmo personagem (exit={r2.get('_exit')}, erros={r2.get('errors')})")
    c.check(set(q2.get("completed", [])) >= set(DONE_QUESTS) and set(q2.get("discovered", [])) >= set(DONE_POIS), f"reconexao: sync traz quests e descobertas ({q2.get('completed')}, {q2.get('discovered')})")
    c.check(int(c.char_of(c.email, cid)["xp"]) == xp1, "reconexao: xp inalterado (sem recompensa duplicada)")
    c.check(int(c.char_of(c.email, cid)["revision"]) >= rev0, "revision so avanca")
    e5.common_end(c, ["a"])


SCEN = {"quests": sc_quests}


def main():
    signal.signal(signal.SIGTERM, lambda s, f: (e4.cleanup(), sys.exit(130)))
    ap = argparse.ArgumentParser()
    ap.add_argument("scenario", choices=list(SCEN))
    ap.add_argument("--godot", default=e4.default_godot())
    ap.add_argument("--port", type=int, default=25300)
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
