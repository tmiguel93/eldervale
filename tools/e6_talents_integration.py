#!/usr/bin/env python3
"""Integracao E6.2: talentos com BACKEND REAL (Node + PGlite em memoria) + servidor Godot + bots. Reaproveita tools/e4_integration.py.

Uso: python3 tools/e6_talents_integration.py talents [--godot CAMINHO] [--port N]
Cenario `talents` (servidor + backend + 2 bots em UM comando):
  1. bot `talents`: abate inimigos ate o servidor informar 1 ponto de talento, PEDE choose_spec(berserker) e allocate(w_vigor), mede a vida
     maxima antes/depois (o efeito vem do servidor) e pede um allocate sem pontos (deve voltar no_points). O cliente so pede.
  2. GET /v1/characters/:id: talentos persistidos pelo endpoint interno (nao pelo checkpoint), revision subiu.
  3. replay no backend: mesma chave => replayed, nada duplicado; mesma chave com corpo diferente => 409.
  4. bot `idle` reconecta com o MESMO personagem: s_talents do join traz a build persistida e a vida maxima ja inclui o bonus.
Saida 0 = tudo PASS."""
import argparse, importlib.util, json, os, signal, sys, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
_spec = importlib.util.spec_from_file_location("e4i", os.path.join(ROOT, "tools", "e4_integration.py"))
e4 = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(e4)
_spec5 = importlib.util.spec_from_file_location("e5i", os.path.join(ROOT, "tools", "e5_adventure_integration.py"))
e5 = importlib.util.module_from_spec(_spec5)
_spec5.loader.exec_module(e5)


class T(e5.A):
    def __init__(self, name, godot, port):
        super().__init__(name, godot, port)
        self.dir = os.path.join(e4.SCR, f"e6_{name}_{int(time.time())}")
        os.makedirs(self.dir, exist_ok=True)


def sc_talents(c):
    c.start_api()
    cid = c.prepare_account("Talentoso", "warrior")
    c.accounts[c.email] = c.access
    srv, sf = c.start_server("a", max_seconds=165)
    sid = c.wait_session(sf, srv)
    c.check(sid is not None and cid is not None, "API, conta, personagem e sessao prontos")
    if not sid:
        return
    bot, out = c.start_bot("a", "talents", "Talentoso", 130, session_id=sid)
    r = c.finish_bot(bot, out, 150)
    tl = (r.get("talents") or {})
    tb = tl.get("bot") or {}
    print("  INFO  bot:", json.dumps(tb)[:400], "| updates:", tl.get("updates"), "| erros:", tl.get("errors"))
    c.check(r.get("_exit") == 0 and r.get("connected") is True, f"bot conectou e saiu 0 (exit={r.get('_exit')}, erros={r.get('errors')})")
    c.check(tb.get("points_before", 0) >= 1, f"servidor concedeu ponto de talento ao subir de nivel (pontos={tb.get('points_before')}, nivel={tb.get('level_before')})")
    c.check(tb.get("spec_after") == "berserker" and (tb.get("ranks_after") or {}).get("w_vigor") == 1, f"build aplicada no servidor e informada ao dono ({tb.get('spec_after')}, {tb.get('ranks_after')})")
    c.check(tb.get("max_hp_after", 0) > tb.get("max_hp_before", 1e9), f"vida maxima MUDOU por efeito do talento ({tb.get('max_hp_before')} -> {tb.get('max_hp_after')})")
    codes = [e.get("code") for e in (tl.get("errors") or [])]
    c.check("no_points" in codes, f"alocar sem pontos recusado pelo servidor (erros recebidos={codes})")
    ch = c.poll_character(cid, lambda x: (x.get("talents") or {}).get("ranks", {}).get("w_vigor") == 1, 20)
    t = (ch or {}).get("talents") or {}
    c.check(t.get("spec") == "berserker" and t.get("ranks") == {"w_vigor": 1} and t.get("respecs") == 0, f"GET backend: talentos persistidos ({t})")
    rev0 = int((ch or {}).get("revision", 0))
    # backend e a autoridade: tentativa fora das regras via endpoint interno (chave reservada talent:<sessao>:<n>:<personagem>)
    key = f"talent:{sid}:9001:{cid}"
    body = {"idempotency_key": key, "op": "allocate", "arg": "w_might"}
    st, d = c.ihttp("POST", f"/internal/characters/{cid}/talents", body, session=sid)
    c.check(st == 409 and d and (d.get("error") or {}).get("code") == "no_points", f"backend recusa alocar sem pontos (status={st})")
    st, _ = c.ihttp("POST", f"/internal/characters/{cid}/talents", {"idempotency_key": "talent:x", "op": "allocate", "arg": "w_might"}, session=sid)
    c.check(st == 400, f"chave fora do formato reservado recusada ({st})")
    st, _ = c.ihttp("POST", f"/internal/characters/{cid}/talents", {"idempotency_key": f"talent:{sid}:9002:{cid}", "op": "allocate", "arg": "w_might"}, session=None)
    c.check(st in (400, 401, 403, 409), f"sem X-Session-Id (fencing) recusado ({st})")
    after = c.poll_character(cid, lambda x: True)
    c.check((after.get("talents") or {}).get("ranks") == {"w_vigor": 1}, "tentativas invalidas nao alteraram os talentos")
    # reconexao com o mesmo personagem: join traz a build persistida
    rev1 = int(after.get("revision", 0))
    bot2, out2 = c.start_bot("b", "idle", "Talentoso", 8, session_id=sid)
    r2 = c.finish_bot(bot2, out2, 60)
    last = (r2.get("talents") or {}).get("last") or {}
    c.check(r2.get("_exit") == 0 and r2.get("connected") is True, f"bot2 reconectou com o mesmo personagem (exit={r2.get('_exit')}, erros={r2.get('errors')})")
    c.check(last.get("spec") == "berserker" and (last.get("ranks") or {}).get("w_vigor") == 1, f"reconexao: s_talents do join traz a build persistida ({last})")
    c.check(last.get("points_total", 0) >= 1 and last.get("points_available") == last.get("points_total") - last.get("points_spent", 0), f"pontos coerentes no join ({last.get('points_total')}/{last.get('points_spent')}/{last.get('points_available')})")
    c.check(r2.get("max_hp", 0) >= tb.get("max_hp_after", 1e9) - 0.01, f"vida maxima apos reconectar mantem o bonus ({r2.get('max_hp')} >= {tb.get('max_hp_after')})")
    c.check(int(c.character(cid).get("revision", 0)) >= rev0 and rev1 >= rev0, "revision so avanca")
    c.no_errors_in(["a"])
    c.no_secrets_in_logs()


SCEN = {"talents": sc_talents}


def main():
    signal.signal(signal.SIGTERM, lambda s, f: (e4.cleanup(), sys.exit(130)))
    ap = argparse.ArgumentParser()
    ap.add_argument("scenario", choices=list(SCEN))
    ap.add_argument("--godot", default=e4.default_godot())
    ap.add_argument("--port", type=int, default=25100)
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
