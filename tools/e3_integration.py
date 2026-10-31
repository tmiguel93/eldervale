#!/usr/bin/env python3
"""Integracao E3: sobe 1 servidor headless + bots como processos separados e valida criterios.
Uso: python3 tools/e3_integration.py <cenario> [--godot CAMINHO] [--port N]
Cenarios: baseline | latency | cheat | flood | badversion | all
Requer o binario do Godot 4.7.2 (padrao: .tools/godot-linux/...). Saida 0 = tudo OK."""
import argparse, json, math, os, subprocess, sys, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCR = os.path.join(ROOT, ".tools", "scratch")
SERVER_SCENE = "res://scenes/server/server_boot.tscn"
CLIENT_SCENE = "res://scenes/client/client_boot.tscn"
SERVER_SPEED = 6.0


def run(godot, port, server_extra, bots, secs, client_extra=()):
    os.makedirs(SCR, exist_ok=True)
    env = dict(os.environ)
    for k in ("XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"):
        d = os.path.join(ROOT, ".tools", "xdg", k.split("_")[1].lower())
        os.makedirs(d, exist_ok=True); env[k] = d
    base = [godot, "--headless", "--path", ROOT]
    srv_log = open(os.path.join(SCR, f"srv_{port}.log"), "w")
    srv = subprocess.Popen(base + [SERVER_SCENE, "--", "--port", str(port), "--max-seconds", str(secs + 8), "--dev-mode", "1"] + list(server_extra),
                           stdout=srv_log, stderr=subprocess.STDOUT, env=env)
    time.sleep(2.5)
    procs, outs = [], []
    for name, script in bots:
        out = os.path.join(SCR, f"{name}_{port}.json")
        if os.path.exists(out): os.remove(out)
        outs.append(out)
        log = open(os.path.join(SCR, f"{name}_{port}.log"), "w")
        procs.append(subprocess.Popen(base + [CLIENT_SCENE, "--", "--host", "127.0.0.1", "--port", str(port), "--name", name,
                     "--bot", script, "--bot-seconds", str(secs), "--out", out] + list(client_extra),
                     stdout=log, stderr=subprocess.STDOUT, env=env))
    for p in procs: p.wait(timeout=secs + 30)
    srv.wait(timeout=secs + 30)
    res = []
    for o in outs:
        res.append(json.load(open(o)) if os.path.exists(o) else {"errors": ["sem json"]})
    srv_log.close()
    errs = sum(1 for l in open(os.path.join(SCR, f"srv_{port}.log"), errors="ignore") if "ERROR" in l)
    return res, errs


def max_speed(d):
    p = d.get("positions", [])
    best = 0.0
    for a, b in zip(p, p[1:]):
        dt = b["t"] - a["t"]
        if dt > 0.2:
            best = max(best, math.hypot(b["x"] - a["x"], b["z"] - a["z"]) / dt)
    return best


def check(cond, msg, fails):
    print(("  PASS  " if cond else "  FAIL  ") + msg)
    if not cond: fails.append(msg)


def sc_baseline(godot, port, lat=False):
    fails = []
    extra = ["--sim-latency-ms", "120", "--sim-jitter-ms", "30", "--sim-loss-pct", "5"] if lat else []
    res, errs = run(godot, port, extra, [("Alice", "walk_square"), ("Bob", "walk_square")], 7, extra)
    check(errs == 0, "servidor sem ERROR no log", fails)
    ids = [r.get("welcome", {}).get("player_id") for r in res]
    for r, n in zip(res, ("Alice", "Bob")):
        check(r.get("connected") is True and not r.get("errors"), f"{n} conectou sem erros", fails)
        check(r.get("snapshots_received", 0) >= (30 if lat else 60), f"{n} recebeu snapshots ({r.get('snapshots_received')})", fails)
        check(r.get("max_snapshot_gap_ms", 9e9) < (1500 if lat else 250), f"{n} maior intervalo entre snapshots {r.get('max_snapshot_gap_ms')} ms", fails)
        check(max_speed(r) <= SERVER_SPEED * 1.25, f"{n} velocidade observada {max_speed(r):.2f} m/s <= limite do servidor", fails)
    check(len(set(ids)) == 2 and None not in ids, f"ids distintos {ids}", fails)
    for r, other, n in ((res[0], ids[1], "Alice"), (res[1], ids[0], "Bob")):
        seen = r.get("entities_seen", {})
        check(str(other) in seen and seen[str(other)].get("kind") == 1, f"{n} viu o outro jogador (id {other})", fails)
    if lat:
        for r, n in zip(res, ("Alice", "Bob")):
            check(r.get("rtt_avg_ms", 0) >= 100, f"{n} RTT medio {r.get('rtt_avg_ms'):.0f} ms reflete latencia simulada", fails)
    return fails


def sc_cheat(godot, port):
    fails = []
    res, errs = run(godot, port, [], [("Cheat", "cheat_speed")], 6)
    r = res[0]
    check(r.get("connected") is True, "bot trapaceiro conectou", fails)
    check(max_speed(r) <= SERVER_SPEED * 1.25, f"servidor limitou a velocidade: {max_speed(r):.2f} m/s (enviado modulo 10)", fails)
    check(errs == 0, "servidor sem ERROR no log", fails)
    return fails


def sc_flood(godot, port):
    fails = []
    res, errs = run(godot, port, [], [("Flood", "invalid_flood")], 6)
    r = res[0]
    check(r.get("rejected", {}).get("code") == 4 or r.get("disconnected") is True, f"flood rejeitado/desconectado ({r.get('rejected')})", fails)
    check(errs == 0, "servidor sem ERROR no log", fails)
    return fails


def sc_badversion(godot, port):
    fails = []
    res, errs = run(godot, port, [], [("Old", "bad_version")], 4)
    check(res[0].get("rejected", {}).get("code") == 1, f"versao errada recusada ({res[0].get('rejected')})", fails)
    check(errs == 0, "servidor sem ERROR no log", fails)
    return fails


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("scenario")
    ap.add_argument("--godot", default=os.path.join(ROOT, ".tools", "godot-linux", "Godot_v4.7.2-stable_linux.x86_64"))
    ap.add_argument("--port", type=int, default=24710)
    a = ap.parse_args()
    table = {"baseline": lambda p: sc_baseline(a.godot, p), "latency": lambda p: sc_baseline(a.godot, p, True),
             "cheat": lambda p: sc_cheat(a.godot, p), "flood": lambda p: sc_flood(a.godot, p),
             "badversion": lambda p: sc_badversion(a.godot, p)}
    names = list(table) if a.scenario == "all" else [a.scenario]
    allf = []
    for i, n in enumerate(names):
        print(f"== {n}")
        allf += table[n](a.port + i)
    print("RESULTADO:", "OK" if not allf else f"{len(allf)} falha(s)")
    sys.exit(1 if allf else 0)


main()
