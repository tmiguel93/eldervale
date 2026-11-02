#!/usr/bin/env python3
"""Integracao E7.1: falha e carga leve com BACKEND REAL (Node + PGlite) + servidor Godot + bots, tudo em 127.0.0.1.
Reaproveita tools/e5_adventure_integration.py (segredos aleatorios so por ambiente, limpeza de processos, checagem de logs).

Uso: python3 tools/e7_integration.py <cenario|all> [--godot CAMINHO] [--port N]
  party_base    4 bots (4 contas), chefe de Greenwood, SEM rede simulada (referencia para comparar)
  party_net     o mesmo com --sim-latency-ms 50 --sim-jitter-ms 40 --sim-loss-pct 4 no servidor E nos 4 clientes
  client_crash  kill -9 do cliente no meio da sessao e reconexao com o mesmo personagem (janela de reconexao do backend)
Cada cenario cabe em um comando de 180 s na VM de 2 nucleos. Os numeros de tick/snapshot/reconexao saem da linha `[metrics]`
do servidor (ServerMetrics, E7.1). Saida 0 = tudo PASS."""
import argparse, importlib.util, json, os, re, signal, sys, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
_spec = importlib.util.spec_from_file_location("e5i", os.path.join(ROOT, "tools", "e5_adventure_integration.py"))
e5 = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(e5)
e4 = e5.e4

NET = ["--sim-latency-ms", "50", "--sim-jitter-ms", "40", "--sim-loss-pct", "4"]


def last_metrics(c, tag):
    """Ultima linha `[metrics] {...}` do log do servidor (periodica ou a final)."""
    ms = re.findall(r"\[metrics\] (\{.*\})", c.server_log(tag))
    return json.loads(ms[-1]) if ms else None


def report_metrics(c, tag):
    m = last_metrics(c, tag)
    if not m:
        c.check(False, "linha [metrics] do servidor encontrada")
        return None
    t = m.get("timings", {})
    g = m.get("gauges", {})
    cn = m.get("counters", {})
    def row(k):
        s = t.get(k, {})
        return f"n={s.get('count')} p50={s.get('p50')} p95={s.get('p95')} max={s.get('max')}"
    print(f"  INFO  [metrics] tick_ms: {row('tick_ms')} | tick_dt_ms: {row('tick_dt_ms')} | snapshot_bytes: {row('snapshot_bytes')}")
    print(f"  INFO  [metrics] gauges={g} rejects={cn.get('rejects')} reconnects={cn.get('reconnects')} disconnects={cn.get('disconnects')} joins={cn.get('joins')}")
    return m


def party(c, net):
    c.start_api()
    names = ["Alfa", "Bravo", "Carlos", "Delta"]
    emails = [f"e7p{i}-{c.email}" for i in range(4)]
    cids = [c.make_char(e, n) for e, n in zip(emails, names)]
    c.check(all(cids), "4 contas e 4 personagens criados")
    ok = all(c.seed_quests(e, cid, ["gw_welcome", "gw_clear_clearing", "gw_scrap_for_orla", "gw_ruins_expedition"]) for e, cid in zip(emails, cids))
    c.check(ok, "4 personagens semeados (nivel 3, pre-requisitos concluidos pelo backend real, com X-Session-Key)")
    extra = ["--metrics-interval", "10"] + (NET if net else [])
    srv, sf = c.start_world_server("a", max_seconds=125, knobs=(0.15, 1.7), measure=True, extra=extra)
    sid = c.wait_session(sf, srv)
    if not sid:
        c.check(False, "sessao")
        return
    bots = []
    for i in range(4):
        for attempt in range(3):
            b_, o_ = c.bot(f"p{i}", "adv_party", names[i], 105, sid, email=emails[i], extra=NET if net else ())
            t_in = time.time()
            logp = os.path.join(c.dir, f"bot_p{i}.log")
            while time.time() - t_in < 40 and b_.poll() is None:
                try:
                    if "passo 1/" in open(logp, errors="replace").read():
                        break
                except OSError:
                    pass
                time.sleep(0.5)
            if b_.poll() is None or b_.returncode == 0:
                break
            print(f"  INFO  {names[i]}: entrada falhou (exit={b_.returncode}); tentando de novo")
        bots.append((b_, o_))
    res = [c.finish_bot(b, o, 115) for b, o in bots]
    for i, r in enumerate(res):
        a = e5.adv(r)
        print(f"  INFO  {names[i]}: passos={[s['step'] for s in a.get('steps', [])]} kills={a.get('quests', {}).get('kills')} mortes={a.get('deaths')} snapshots_max_entidades={a.get('snapshot_entities_max')}")
    for i, r in enumerate(res):
        c.check(r.get("_exit") == 0 and r.get("connected") is True, f"{names[i]}: conectou e saiu 0 (exit={r.get('_exit')}, erros={r.get('errors')})")
    states = [r.get("world", {}).get("boss_states", []) for r in res]
    c.check(all(1 in s and 2 in s for s in states), f"os 4 jogadores viram o chefe ativo e derrotado ({states})")
    chs = [c.poll(emails[i], cids[i], lambda x: int(x.get("xp", 0)) > 530, 25) for i in range(4)]
    rewarded = [int(ch["xp"]) >= 530 + 1200 for ch in chs]
    c.check(sum(rewarded) >= 3, f"pelo menos 3 dos 4 receberam o xp do chefe ({rewarded}) xp={[ch['xp'] for ch in chs]}")
    for i, ch in enumerate(chs):
        e5.inv_matches(c, names[i], res[i], ch)
    # nenhuma recompensa duplicada: o xp de cada um e exatamente semente(530) + chefe(1200) [+ abates], nunca o dobro do chefe
    c.check(all(int(ch["xp"]) < 530 + 2 * 1200 for ch in chs), f"nenhum xp duplicado ({[ch['xp'] for ch in chs]})")
    st = c.server_stats("a")
    print("  INFO  snapshots medidos (Variant, aproximado):", st)
    time.sleep(1)
    m = report_metrics(c, "a")
    if m:
        g = m.get("gauges", {})
        c.check(int(m["timings"]["tick_ms"]["count"]) > 100, "metricas de tick coletadas (>100 amostras)")
        c.check(float(m["timings"]["tick_ms"]["p95"]) < 33.0, f"tick_ms p95 < 33 ms (orcamento de 1 tick a 30 Hz): {m['timings']['tick_ms']['p95']}")
        c.check(int(m["timings"]["snapshot_bytes"]["count"]) > 50, "tamanho de snapshot coletado")
        c.check(int(m["timings"]["snapshot_bytes"]["max"]) <= 1392 * 4, f"snapshot compacto <= 4 mensagens MTU no pior caso ({m['timings']['snapshot_bytes']['max']} bytes)")
    c.check(st is not None and st["samples"] > 50, "estatisticas de snapshot medidas no servidor")
    e5.common_end(c, ["a"])


def sc_party_base(c):
    party(c, net=False)


def sc_party_net(c):
    party(c, net=True)


def sc_client_crash(c):
    c.start_api()
    cid = c.make_char(c.email, "Cai")
    srv, sf = c.start_world_server("a", max_seconds=100, autosave=3, extra=["--metrics-interval", "5"])
    sid = c.wait_session(sf, srv)
    if not sid:
        c.check(False, "sessao")
        return
    a, outa = c.bot("a", "adv_prep", "Cai", 90, sid)
    ch = c.poll(c.email, cid, lambda x: "gw_welcome" in e5.quests_of(x)[0], 60)
    ok = bool(ch) and "gw_welcome" in e5.quests_of(ch)[0]
    c.check(ok, "quest aceita e persistida (checkpoint) antes da queda do cliente")
    if not ok:
        return
    xp0, rev0, inv0 = int(ch["xp"]), int(ch["revision"]), c.total_items(ch)
    e4.kill_tree(a)
    t_kill = time.time()
    c.check(a.poll() is not None, "cliente encerrado com SIGKILL (sem logout, sem fechar a conexao ENet)")
    # o servidor detecta a queda (timeout do ENet) e aciona disconnect no backend (janela de reconexao)
    seen = False
    for _ in range(80):
        if re.search(r"peer \d+ desconectou", c.server_log("a")):
            seen = True
            break
        time.sleep(0.5)
    print(f"  INFO  servidor detectou a queda do cliente em {time.time() - t_kill:.1f} s")
    c.check(seen, "servidor detectou a queda do cliente")
    b, outb = c.bot("b", "adv_check", "Cai", 12, sid)
    rb = c.finish_bot(b, outb, 60)
    qb = e5.adv(rb).get("quests", {})
    c.check(rb.get("connected") is True and rb.get("ticket_used_ok") is True, f"reconectou com NOVO ticket na mesma sessao (rejected={rb.get('rejected')}, flow={rb.get('flow_error')!r})")
    c.check("gw_welcome" in qb.get("active", {}), f"cliente ve a quest persistida apos a reconexao ({list(qb.get('active', {}))})")
    fin = c.char_of(c.email, cid)
    c.check(int(fin["xp"]) == xp0 and c.total_items(fin) == inv0, f"sem perda e sem duplicacao: xp {xp0}->{fin['xp']}, itens iguais ({c.total_items(fin) == inv0})")
    c.check(int(fin["revision"]) >= rev0, f"revision nao regrediu ({rev0}->{fin['revision']})")
    time.sleep(6)
    m = report_metrics(c, "a")
    if m:
        cn = m.get("counters", {})
        c.check(int(cn.get("reconnects", {}).get("player", 0)) >= 1, f"metrica reconnects contou a reconexao ({cn.get('reconnects')})")
        c.check(int(cn.get("disconnects", {}).get("player", 0)) >= 1, f"metrica disconnects contou a queda ({cn.get('disconnects')})")
    e5.common_end(c, ["a"])


SCEN = {"party_base": sc_party_base, "party_net": sc_party_net, "client_crash": sc_client_crash}


def main():
    signal.signal(signal.SIGTERM, lambda s, f: (e4.cleanup(), sys.exit(130)))
    ap = argparse.ArgumentParser()
    ap.add_argument("scenario", choices=list(SCEN) + ["all"])
    ap.add_argument("--godot", default=e4.default_godot())
    ap.add_argument("--port", type=int, default=25100)
    a = ap.parse_args()
    os.makedirs(e4.SCR, exist_ok=True)
    names = list(SCEN) if a.scenario == "all" else [a.scenario]
    allf = []
    try:
        for i, n in enumerate(names):
            print(f"== {n}", flush=True)
            c = e5.A(n, a.godot, a.port + i * 2)
            c.dir = os.path.join(e4.SCR, f"e7_{n}_{int(time.time())}")
            os.makedirs(c.dir, exist_ok=True)
            t0 = time.time()
            try:
                SCEN[n](c)
            finally:
                e4.cleanup()
                e4._children.clear()
            print(f"  ({time.time() - t0:.0f} s; logs em {os.path.relpath(c.dir, e4.ROOT)})")
            allf += [f"{n}: {m}" for m in c.fails]
    finally:
        e4.cleanup()
    print("RESULTADO:", "OK" if not allf else f"{len(allf)} falha(s)")
    for f in allf:
        print("  -", f)
    sys.exit(1 if allf else 0)


if __name__ == "__main__":
    main()
