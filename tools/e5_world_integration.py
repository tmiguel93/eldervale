#!/usr/bin/env python3
"""Integracao E5.3: servidor headless em modo mundo (--world greenwood) + 1 ou 4 bots `world_tour` como
processos separados. Cada bot percorre hub -> selvagem -> ruinas (placas, portao) -> salao do chefe.
Uso: python3 tools/e5_world_integration.py <1bot|4bots|all> [--godot CAMINHO] [--port N] [--secs N]
Saida 0 = tudo OK. Relatorios/logs em .tools/scratch/. Requer o Godot 4.7.2 (padrao .tools/godot-linux/...)."""
import argparse, json, os, subprocess, sys, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCR = os.path.join(ROOT, ".tools", "scratch")
SERVER_SCENE = "res://scenes/server/server_boot.tscn"
CLIENT_SCENE = "res://scenes/client/client_boot.tscn"
ZONES = ["zone_hub", "zone_wild", "zone_ruins"]


def run(godot, port, n_bots, secs):
    os.makedirs(SCR, exist_ok=True)
    env = dict(os.environ)
    for k in ("XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"):
        d = os.path.join(ROOT, ".tools", "xdg", k.split("_")[1].lower())
        os.makedirs(d, exist_ok=True)
        env[k] = d
    base = [godot, "--headless", "--path", ROOT]
    srv_log_path = os.path.join(SCR, f"world_srv_{port}.log")
    srv_log = open(srv_log_path, "w")
    srv = subprocess.Popen(base + [SERVER_SCENE, "--", "--port", str(port), "--max-seconds", str(secs + 8),
                                   "--dev-mode", "1", "--world", "greenwood"],
                           stdout=srv_log, stderr=subprocess.STDOUT, env=env)
    time.sleep(2.5)
    procs, outs = [], []
    for i in range(n_bots):
        name = f"Tour{i + 1}"
        out = os.path.join(SCR, f"world_{name}_{port}.json")
        if os.path.exists(out):
            os.remove(out)
        outs.append(out)
        log = open(os.path.join(SCR, f"world_{name}_{port}.log"), "w")
        procs.append(subprocess.Popen(base + [CLIENT_SCENE, "--", "--host", "127.0.0.1", "--port", str(port), "--name", name,
                                              "--bot", "world_tour", "--bot-seconds", str(secs), "--out", out],
                                      stdout=log, stderr=subprocess.STDOUT, env=env))
    for p in procs:
        p.wait(timeout=secs + 40)
    srv.wait(timeout=secs + 40)
    srv_log.close()
    res = [json.load(open(o)) if os.path.exists(o) else {"errors": ["sem json"]} for o in outs]
    errs = [l.strip() for l in open(srv_log_path, errors="ignore") if "ERROR" in l or "SCRIPT ERROR" in l]
    return res, errs


def check(cond, msg, fails):
    print(("  PASS  " if cond else "  FAIL  ") + msg)
    if not cond:
        fails.append(msg)


def scenario(godot, port, n_bots, secs):
    fails = []
    res, errs = run(godot, port, n_bots, secs)
    check(not errs, f"servidor sem ERROR no log ({errs[:2]})", fails)
    for i, r in enumerate(res):
        n = f"Tour{i + 1}"
        w = r.get("world", {})
        check(r.get("connected") is True and not r.get("errors"), f"{n}: conectou sem erros ({r.get('errors')})", fails)
        check(w.get("zones") == ZONES or w.get("zones", [])[:3] == ZONES, f"{n}: passou pelas 3 zonas em ordem {w.get('zones')}", fails)
        check(w.get("puzzle_open") is True, f"{n}: viu o portao do puzzle abrir", fails)
        check(w.get("tour_done") is True, f"{n}: chegou ao salao do chefe", fails)
        check(r.get("snapshots_received", 0) >= 100, f"{n}: snapshots recebidos ({r.get('snapshots_received')})", fails)
        # 1 bot: < 400 ms. 4 bots: 5 processos Godot disputam poucos nucleos (ambiente de CI/VM): limite 1000 ms.
        gap_limit = 400 if n_bots == 1 else 1000
        check(r.get("max_snapshot_gap_ms", 9e9) < gap_limit, f"{n}: maior intervalo entre snapshots {r.get('max_snapshot_gap_ms'):.0f} ms (limite {gap_limit})", fails)
        check(r.get("events_by_kind", {}).get("8", 0) >= 5, f"{n}: eventos de zona recebidos ({r.get('events_by_kind', {}).get('8')})", fails)
    ids = [r.get("welcome", {}).get("player_id") for r in res]
    check(len(set(ids)) == n_bots and None not in ids, f"ids de jogador distintos {ids}", fails)
    return fails


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("scenario", choices=["1bot", "4bots", "all"])
    ap.add_argument("--godot", default=os.path.join(ROOT, ".tools", "godot-linux", "Godot_v4.7.2-stable_linux.x86_64"))
    ap.add_argument("--port", type=int, default=24730)
    ap.add_argument("--secs", type=int, default=60)
    a = ap.parse_args()
    plan = {"1bot": [1], "4bots": [4], "all": [1, 4]}[a.scenario]
    allf = []
    for i, n in enumerate(plan):
        print(f"== {n} bot(s)")
        allf += scenario(a.godot, a.port + i, n, a.secs)
    print("RESULTADO:", "OK" if not allf else f"{len(allf)} falha(s)")
    sys.exit(1 if allf else 0)


main()
