#!/usr/bin/env python3
"""Integracao E5.6: aventura completa de Greenwood com BACKEND REAL (Node + PGlite em memoria), servidor Godot
`--world greenwood` e bots `adv_*` autenticados (cada bot = 1 processo Godot, 1 conta, 1 personagem). Reaproveita a
infraestrutura de tools/e4_integration.py (segredos aleatorios so por ambiente, limpeza de processos, checagem de logs).

Uso: python3 tools/e5_adventure_integration.py <cenario|all> [--godot CAMINHO] [--port N]
Cenarios (cada um cabe em um comando de 180 s na VM de 2 nucleos; rode um por vez):
  adventure     1 bot, hub+selvagem: falar, aceitar, abater, loot individual, craft, entregar, replay da entrega
  ruins         1 bot (personagem semeado): selvagem (mini-chefe) -> ruinas (puzzle, conjuradores, chefe) -> volta e entrega
  party         4 bots (4 contas): chefe com 4 jogadores, loot individual por jogador, quests por personagem, tamanho de snapshot
  zone_drop     cai no meio da transicao de zona e reconecta com o mesmo personagem (lock/ticket)
  server_crash  kill -9 do servidor Godot: progresso ate o ultimo checkpoint persistido, sem recompensa duplicada
  outage        backend congelado (SIGSTOP) durante a recompensa: reentrega idempotente, sem duplicar
Parametros SO DE TESTE (ELDERVALE_TEST_MODE=1 no servidor): --test-hp-mult e --test-speed-mult reduzem a vida dos inimigos e
aceleram os jogadores nos cenarios longos; documentado em docs/E5_GATE.md. Saida 0 = tudo PASS."""
import argparse, importlib.util, json, os, re, shutil, signal, sys, time, urllib.error, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
_spec = importlib.util.spec_from_file_location("e4i", os.path.join(ROOT, "tools", "e4_integration.py"))
e4 = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(e4)

QUEST_REWARDS = {  # espelho de data/quests/*.json (o backend valida contra o catalogo; qualquer divergencia = 400)
    "gw_welcome": (60, [("potion_minor", 2)]),
    "gw_clear_clearing": (150, [("scrap_material", 3)]),
    "gw_scrap_for_orla": (120, [("potion_minor", 3)]),
    "gw_ruins_expedition": (200, [("potion_minor", 2)]),
}


class A(e4.Ctx):
    def __init__(self, name, godot, port):
        super().__init__(name, godot, port)
        self.dir = os.path.join(e4.SCR, f"e5_{name}_{int(time.time())}")
        os.makedirs(self.dir, exist_ok=True)
        self.accounts = {}  # email -> access token

    # ---- contas / personagens
    def make_char(self, email, char_name):
        self.http("POST", "/v1/auth/register", {"email": email, "password": self.password})
        st, d = self.http("POST", "/v1/auth/login", {"email": email, "password": self.password})
        tok = d["access_token"] if st == 200 else None
        self.accounts[email] = tok
        st, d = self.http("POST", "/v1/characters", {"name": char_name, "class_id": "warrior"}, token=tok)
        return d["character"]["id"] if st == 201 else None

    def char_of(self, email, cid):
        st, d = self.http("GET", f"/v1/characters/{cid}", token=self.accounts[email])
        return d["character"] if st == 200 else None

    def poll(self, email, cid, pred, timeout=15):
        t0, ch = time.time(), None
        while time.time() - t0 < timeout:
            ch = self.char_of(email, cid)
            if ch and pred(ch):
                return ch
            time.sleep(0.6)
        return ch

    def ihttp(self, method, path, body=None, session=None):
        req = urllib.request.Request(self.api_url + path, method=method, data=None if body is None else json.dumps(body).encode(),
                                     headers={"Content-Type": "application/json", "Authorization": "Bearer " + self.internal_secret})
        if session:
            req.add_header("X-Session-Id", session)
        try:
            with urllib.request.urlopen(req, timeout=10) as r:
                raw = r.read()
                return r.status, (json.loads(raw) if raw else None)
        except urllib.error.HTTPError as e:
            raw = e.read()
            try:
                return e.code, json.loads(raw)
            except Exception:
                return e.code, None
        except Exception:
            return 0, None

    def seed_quests(self, email, cid, quest_ids):
        """Conclui quests pelo caminho REAL de recompensas do backend (como o servidor de jogo faria): sessao + ticket + lock."""
        st, d = self.ihttp("POST", "/internal/sessions", {"region": "local", "capacity": 4, "protocol_version": 2, "endpoint": "127.0.0.1:1"})
        sid = d["session_id"] if st in (200, 201) and d else None
        if not sid:
            return False
        st, d = self.http("POST", f"/v1/sessions/{sid}/join-ticket", {"character_id": cid}, token=self.accounts[email])
        ticket = d.get("ticket") if d else None
        st2, _ = self.ihttp("POST", "/internal/tickets/redeem", {"ticket": ticket, "session_id": sid})
        ok = st in (200, 201) and st2 == 200
        for q in quest_ids:
            xp, items = QUEST_REWARDS[q]
            body = {"idempotency_key": f"quest:{q}:{cid}", "xp": xp, "items": [{"item_id": i, "qty": n} for i, n in items], "quest_id": q}
            s3, _ = self.ihttp("POST", f"/internal/characters/{cid}/rewards", body, session=sid)
            ok = ok and s3 == 200
        self.ihttp("POST", f"/internal/characters/{cid}/release", {"session_id": sid})
        self.ihttp("POST", f"/internal/sessions/{sid}/close", {})
        return ok

    # ---- servidor com mundo + parametros de teste
    def start_world_server(self, tag, max_seconds=150, knobs=None, extra=(), autosave=5, measure=False):
        sid_file = os.path.join(self.dir, f"session_{tag}.txt")
        env = e4.godot_env()
        env["ELDERVALE_INTERNAL_SECRET"] = self.internal_secret
        argv = [self.godot, "--headless", "--path", e4.ROOT, e4.SERVER_SCENE, "--", "--port", str(self.port), "--max-seconds", str(max_seconds),
                "--backend-url", self.api_url, "--public-endpoint", f"127.0.0.1:{self.port}", "--session-id-file", sid_file,
                "--world", "greenwood", "--autosave-interval", str(autosave)]
        if knobs:
            env["ELDERVALE_TEST_MODE"] = "1"
            argv += ["--test-hp-mult", str(knobs[0]), "--test-speed-mult", str(knobs[1])]
        if measure:
            argv += ["--measure-snapshots", "1"]
        argv += list(extra)
        p = e4.spawn("server_" + tag, argv, env, os.path.join(self.dir, f"server_{tag}.log"))
        return p, sid_file

    def bot(self, tag, script, character, seconds, sid, email=None, extra=()):
        return self.start_bot(tag, script, character, seconds, session_id=sid, extra=extra, email=email or self.email)

    def server_stats(self, tag):
        ms = re.findall(r"snapshots: (\{.*\})", self.server_log(tag))
        return json.loads(ms[-1]) if ms else None

    def total_items(self, ch):
        n = {}
        for e in ch.get("inventory", []):
            n[e["item_id"]] = n.get(e["item_id"], 0) + e["qty"]
        for v in (ch.get("equipment") or {}).values():
            n[v] = n.get(v, 0) + 1
        return n


def adv(r):
    return r.get("adventure", {})


def steps(r):
    return [s["step"] for s in adv(r).get("steps", [])]


def quests_of(ch):
    q = ch.get("quests") or {}
    return q.get("active", {}), q.get("completed", [])


def inv_matches(c, who, r, ch):
    """O inventario que o bot recebeu por s_inventory (estado FINAL sincronizado) tem de ser igual ao persistido no backend."""
    mine = adv(r).get("inventory", {})
    eq = adv(r).get("equipment", {})
    bot = dict(mine)
    for v in eq.values():
        bot[v] = bot.get(v, 0) + 1
    db = c.total_items(ch)
    c.check(bot == db, f"{who}: inventario sincronizado no cliente == persistido no backend (cliente={bot} backend={db})")


def common_end(c, tags):
    c.no_errors_in(tags)
    c.no_secrets_in_logs()


# ======================================================================= cenarios

def sc_adventure(c):
    c.start_api()
    cid = c.make_char(c.email, "Aventureiro")
    srv, sf = c.start_world_server("a", max_seconds=165, knobs=(0.2, 1.5), measure=True)
    sid = c.wait_session(sf, srv)
    c.check(sid is not None and cid is not None, "API, conta, personagem e sessao prontos")
    if not sid:
        return
    bot, out = c.bot("a", "adv_hub_wild", "Aventureiro", 150, sid)
    r = c.finish_bot(bot, out, 165)
    q = adv(r).get("quests", {})
    print("  INFO  passos:", [(s["step"], s["t"]) for s in adv(r).get("steps", [])])
    print("  INFO  quests:", json.dumps(q)[:400], "pickups:", adv(r).get("pickups"), "mortes:", adv(r).get("deaths"))
    c.check(r.get("_exit") == 0 and r.get("connected") is True and r.get("ticket_used_ok") is True, f"bot conectou com ticket e saiu 0 (exit={r.get('_exit')}, erros={r.get('errors')})")
    c.check(not q.get("timeouts"), f"nenhum passo estourou o tempo ({q.get('timeouts')})")
    c.check(set(q.get("completed", [])) >= {"gw_welcome", "gw_scrap_for_orla", "gw_clear_clearing"}, f"3 quests entregues no cliente ({q.get('completed')})")
    c.check(any(e in ("already_completed", "not_active", "not_ready", "not_active_or_ready") or e for e in q.get("errors", [])), f"replay da entrega recusado pelo servidor ({q.get('errors')})")
    c.check(adv(r).get("inventory_updates", 0) >= 3, f"s_inventory recebido varias vezes ({adv(r).get('inventory_updates')})")
    c.check(q.get("kills", {}).get("melee_grunt", 0) >= 5, f"abateu os brutos da selvagem ({q.get('kills')})")
    ch = c.poll(c.email, cid, lambda x: "gw_clear_clearing" in quests_of(x)[1] and x.get("revision", 0) > 0, 25)
    active, completed = quests_of(ch)
    c.check(set(completed) >= {"gw_welcome", "gw_scrap_for_orla", "gw_clear_clearing"} and not active, f"GET backend: quests persistidas por personagem (completed={completed}, active={list(active)})")
    grunts = q.get("kills", {}).get("melee_grunt", 0)
    c.check(int(ch["xp"]) >= 330 + 40 * min(grunts, 6), f"xp persistido >= quests (330) + abates de bruto (40 cada) ({ch['xp']})")
    inv_matches(c, "bot", r, ch)
    if q.get("crafts"):
        c.check(q["crafts"][0].get("ok") is True, f"craft concluido no servidor ({q['crafts']})")
    # replay no backend: mesma chave => replayed, sem dobrar; chave igual com corpo diferente => 409
    before = c.char_of(c.email, cid)
    xp0, rev0 = int(before["xp"]), int(before["revision"])
    body = {"idempotency_key": f"quest:gw_welcome:{cid}", "xp": 60, "items": [{"item_id": "potion_minor", "qty": 2}], "quest_id": "gw_welcome"}
    st, d = c.ihttp("POST", f"/internal/characters/{cid}/rewards", body, session=sid)
    after = c.char_of(c.email, cid)
    c.check(st == 200 and d and d.get("replayed") is True and int(after["xp"]) == xp0 and c.total_items(after) == c.total_items(before), f"replay da recompensa no backend: replayed=true, nada duplicado (status={st})")
    body2 = dict(body, xp=61)
    st2, _ = c.ihttp("POST", f"/internal/characters/{cid}/rewards", body2, session=sid)
    c.check(st2 in (400, 409) and int(c.char_of(c.email, cid)["xp"]) == xp0, f"mesma chave com corpo diferente recusada ({st2}) e xp intacto")
    st3, _ = c.ihttp("POST", f"/internal/characters/{cid}/rewards", body, session=None)
    c.check(st3 == 400, f"sem X-Session-Id => 400 ({st3})")
    stats = c.server_stats("a")
    common_end(c, ["a"])


def sc_ruins(c):
    c.start_api()
    cid = c.make_char(c.email, "Explorador")
    c.check(c.seed_quests(c.email, cid, ["gw_welcome", "gw_clear_clearing", "gw_scrap_for_orla"]), "semeadura via backend real (3 quests concluidas por recompensa idempotente)")
    srv, sf = c.start_world_server("a", max_seconds=160, knobs=(0.12, 1.6), measure=True)
    sid = c.wait_session(sf, srv)
    if not sid:
        c.check(False, "sessao")
        return
    bot, out = c.bot("a", "adv_ruins", "Explorador", 150, sid)
    r = c.finish_bot(bot, out, 170)
    q = adv(r).get("quests", {})
    print("  INFO  passos:", [(s["step"], s["t"]) for s in adv(r).get("steps", [])])
    print("  INFO  quests:", json.dumps(q)[:500], "mortes:", adv(r).get("deaths"), "chefe:", r.get("world", {}).get("boss_states"))
    c.check(r.get("_exit") == 0 and r.get("connected") is True, f"bot saiu 0 e conectou (exit={r.get('_exit')}, erros={r.get('errors')})")
    w = r.get("world", {})
    c.check(w.get("zones", [])[:3] == ["zone_hub", "zone_wild", "zone_ruins"], f"zonas em ordem {w.get('zones')}")
    c.check(w.get("puzzle_open") is True, "puzzle aberto")
    c.check(1 in w.get("boss_states", []) and 2 in w.get("boss_states", []), f"chefe: ativo e derrotado ({w.get('boss_states')})")
    c.check(q.get("kills", {}).get("thorn_alpha", 0) >= 1 and q.get("kills", {}).get("blight_treant", 0) >= 1, f"mini-chefe e chefe abatidos ({q.get('kills')})")
    c.check(not q.get("timeouts"), f"nenhum passo estourou o tempo ({q.get('timeouts')})")
    ch = c.poll(c.email, cid, lambda x: int(x.get("xp", 0)) >= 330 + 1200, 25)
    active, completed = quests_of(ch)
    print("  INFO  backend: xp", ch.get("xp"), "nivel", ch.get("level"), "quests", json.dumps(ch.get("quests"))[:300])
    c.check("gw_ruins_expedition" in completed or ("gw_ruins_expedition" in active and all(int(v) >= 1 for v in active["gw_ruins_expedition"]["objectives"].values())),
            "expedicao concluida ou com os 2 objetivos de area cumpridos e persistidos")
    c.check(int(ch["xp"]) >= 330 + 400 + 1200, f"xp de mini-chefe (400) e chefe (1200) persistido ({ch['xp']})")
    inv_matches(c, "bot", r, ch)
    st = c.server_stats("a")
    print("  INFO  snapshots (1 jogador):", st)
    common_end(c, ["a"])


def sc_party(c):
    c.start_api()
    names = ["Alfa", "Bravo", "Carlos", "Delta"]
    emails = [f"e5p{i}-{c.email}" for i in range(4)]
    cids = [c.make_char(e, n) for e, n in zip(emails, names)]
    c.check(all(cids), "4 contas e 4 personagens criados")
    ok = all(c.seed_quests(e, cid, ["gw_welcome", "gw_clear_clearing", "gw_scrap_for_orla", "gw_ruins_expedition"]) for e, cid in zip(emails, cids))
    c.check(ok, "4 personagens semeados (nivel 3, pre-requisitos concluidos pelo backend real)")
    srv, sf = c.start_world_server("a", max_seconds=125, knobs=(0.15, 1.7), measure=True)
    sid = c.wait_session(sf, srv)
    if not sid:
        c.check(False, "sessao")
        return
    bots = []
    for i in range(4):
        # entrada sequencial e com repeticao: login (scrypt) + 4 clientes Godot + servidor num VM de 2 nucleos as vezes
        # estouram o timeout de 15 s do cliente (network_error ainda no fluxo de backend, antes de entrar no jogo)
        for attempt in range(3):
            b_, o_ = c.bot(f"p{i}", "adv_party", names[i], 105, sid, email=emails[i])
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
        print(f"  INFO  {names[i]}: passos={[s['step'] for s in adv(r).get('steps', [])]} kills={adv(r).get('quests', {}).get('kills')} timeouts={adv(r).get('quests', {}).get('timeouts')} mortes={adv(r).get('deaths')}")
    for i, r in enumerate(res):
        c.check(r.get("_exit") == 0 and r.get("connected") is True, f"{names[i]}: conectou e saiu 0 (exit={r.get('_exit')}, erros={r.get('errors')})")
    states = [r.get("world", {}).get("boss_states", []) for r in res]
    c.check(all(1 in s and 2 in s for s in states), f"os 4 jogadores viram o chefe ativo e derrotado ({states})")
    chs = [c.poll(emails[i], cids[i], lambda x: int(x.get("xp", 0)) > 530, 25) for i in range(4)]
    kill_credit = 0
    rewarded = []
    for i, ch in enumerate(chs):
        active, completed = quests_of(ch)
        g = active.get("gw_ruin_guardian") or {}
        obj = g.get("objectives", {}) if g else {}
        if int(obj.get("kill_guardian", 0)) >= 1:
            kill_credit += 1
        print(f"  INFO  {names[i]}: xp={ch['xp']} nivel={ch['level']} guardian={json.dumps(g)[:120]} itens={c.total_items(ch)} pickups={adv(res[i]).get('pickups')}")
        c.check("gw_ruin_guardian" in active or "gw_ruin_guardian" in completed, f"{names[i]}: quest do guardiao persistida no PROPRIO personagem")
        rewarded.append(int(ch["xp"]) >= 530 + 1200)
        inv_matches(c, names[i], res[i], ch)
    c.check(kill_credit == 1, f"credito de abate da quest so para o matador: {kill_credit} personagem(ns) com kill_guardian=1")
    drops = [adv(r).get("drops_seen", 0) for r in res]
    # participacao exige dano minimo (loot_min_share): quem nao atingiu o minimo nao recebe xp NEM loot do chefe (consistencia)
    c.check(sum(rewarded) >= 3, f"pelo menos 3 dos 4 jogadores receberam o xp do chefe como participantes ({rewarded})")
    c.check(all(d >= 1 for d, r in zip(drops, rewarded) if r) and all(d == 0 for d, r in zip(drops, rewarded) if not r),
            f"loot individual: quem participou recebeu o proprio drop do chefe e quem nao participou nao recebeu ({drops} x {rewarded})")
    c.check(max(adv(r).get("snapshot_entities_max", 0) for r in res) > 0, "snapshots recebidos com entidades")
    st = c.server_stats("a")
    print("  INFO  snapshots (4 jogadores, luta de chefe; bytes ~ codificacao Variant dos 3 argumentos):", st)
    c.check(st is not None and st["samples"] > 50, "estatisticas de snapshot medidas no servidor")
    common_end(c, ["a"])


def sc_zone_drop(c):
    c.start_api()
    cid = c.make_char(c.email, "Cai")
    srv, sf = c.start_world_server("a", max_seconds=100)
    sid = c.wait_session(sf, srv)
    if not sid:
        c.check(False, "sessao")
        return
    a, outa = c.bot("a", "adv_zone_drop", "Cai", 60, sid)
    ra = c.finish_bot(a, outa, 110)
    c.check(ra.get("connected") is True and ra.get("_exit") == 0, f"bot A conectou e derrubou a conexao ao iniciar a transicao (exit={ra.get('_exit')}, erros={ra.get('errors')})")
    c.check(ra.get("elapsed_s", 99) < 55, f"o bot A saiu quando a transicao comecou ({ra.get('elapsed_s'):.0f} s)")
    time.sleep(1.5)
    b, outb = c.bot("b", "adv_check", "Cai", 12, sid)
    rb = c.finish_bot(b, outb, 60)
    c.check(rb.get("connected") is True and rb.get("ticket_used_ok") is True and not rb.get("rejected"), f"reconectou no mesmo personagem com NOVO ticket dentro da janela (rejected={rb.get('rejected')}, flow={rb.get('flow_error')!r})")
    c.check(rb.get("world", {}).get("zones", [None])[0] == "zone_hub", f"posicao nao persistida: volta ao hub ({rb.get('world', {}).get('zones')})")
    c.check(adv(rb).get("inventory_updates", 0) >= 1, "inventario sincronizado apos reconectar")
    # terceira conexao simultanea do MESMO personagem enquanto B esta de pe e recusada
    b2, outb2 = c.bot("b2", "adv_check", "Cai", 25, sid)
    time.sleep(10)
    d, outd = c.bot("d", "adv_check", "Cai", 6, sid)
    rd = c.finish_bot(d, outd, 60)
    c.check(rd.get("connected") is not True and ((rd.get("rejected") or {}).get("code") == 5 or bool(rd.get("flow_error"))), f"conexao duplicada do mesmo personagem recusada (rejected={rd.get('rejected')}, flow={rd.get('flow_error')!r})")
    c.finish_bot(b2, outb2, 60)
    log = c.server_log("a")
    c.check("transicao" not in log.lower() or "ERROR" not in log, "servidor sem ERROR apos queda na transicao")
    common_end(c, ["a"])


def sc_server_crash(c):
    c.start_api()
    cid = c.make_char(c.email, "Fenix")
    srv1, sf1 = c.start_world_server("a", max_seconds=150, autosave=3)
    sid1 = c.wait_session(sf1, srv1)
    if not sid1:
        c.check(False, "sessao 1")
        return
    a, outa = c.bot("a", "adv_prep", "Fenix", 100, sid1)
    # aguarda: welcome concluida (recompensa) E scrap aceita (checkpoint imediato) no backend
    ch = c.poll(c.email, cid, lambda x: "gw_welcome" in quests_of(x)[1] and "gw_scrap_for_orla" in quests_of(x)[0], 60)
    active, completed = quests_of(ch) if ch else ({}, [])
    c.check("gw_welcome" in completed and "gw_scrap_for_orla" in active, f"progresso persistido antes do crash (completed={completed}, active={list(active)})")
    xp0, rev0 = int(ch["xp"]), int(ch["revision"])
    inv0 = c.total_items(ch)
    e4.kill_tree(srv1)
    c.check(srv1.poll() is not None, "servidor 1 encerrado com SIGKILL (sem checkpoint final, sem release)")
    ra = c.finish_bot(a, outa, 40)
    c.check(ra.get("connected") is True, "bot A estava conectado quando o servidor morreu")
    after = c.char_of(c.email, cid)
    c.check(int(after["xp"]) == xp0 and c.total_items(after) == inv0, f"estado apos o crash == ultimo checkpoint (xp={after['xp']}, itens={c.total_items(after)})")
    time.sleep(e4.HB_TIMEOUT + 2.5)
    srv2, sf2 = c.start_world_server("b", max_seconds=60, autosave=3)
    sid2 = c.wait_session(sf2, srv2)
    c.check(sid2 is not None and sid2 != sid1, "novo servidor registrou NOVA sessao")
    if not sid2:
        return
    b, outb = c.bot("b", "adv_check", "Fenix", 12, sid2)
    rb = c.finish_bot(b, outb, 60)
    qb = adv(rb).get("quests", {})
    c.check(rb.get("connected") is True and rb.get("ticket_used_ok") is True, f"reconectou apos o crash com NOVO ticket (rejected={rb.get('rejected')}, flow={rb.get('flow_error')!r})")
    c.check("gw_welcome" in qb.get("completed", []) and "gw_scrap_for_orla" in qb.get("active", {}), f"cliente ve as quests persistidas (completed={qb.get('completed')}, active={list(qb.get('active', {}))})")
    c.check(adv(rb).get("inventory", {}).get("potion_minor") == inv0.get("potion_minor"), f"inventario sincronizado = persistido ({adv(rb).get('inventory')})")
    c.check(len(qb.get("errors", [])) >= 1, f"nova tentativa de entregar gw_welcome recusada ({qb.get('errors')})")
    fin = c.char_of(c.email, cid)
    c.check(int(fin["xp"]) == xp0 and c.total_items(fin) == inv0, f"sem recompensa duplicada apos crash + reconexao (xp {xp0}->{fin['xp']})")
    common_end(c, ["a", "b"])


def sc_outage(c):
    e4.HB_TIMEOUT = 60  # backend congelado ~32 s: o lock nao pode expirar por heartbeat (padrao de producao: 30 s)
    c.start_api()
    cid = c.make_char(c.email, "Resiliente")
    srv, sf = c.start_world_server("a", max_seconds=130, autosave=60)  # sem autosave no caminho: a fila so tem a recompensa
    sid = c.wait_session(sf, srv)
    if not sid:
        c.check(False, "sessao")
        return
    a, outa = c.bot("a", "adv_prep", "Resiliente", 110, sid)
    # a quest aceita e persistida na hora (checkpoint imediato); a entrega do bot vem ~10 s depois (passo de espera)
    ch = c.poll(c.email, cid, lambda x: "gw_welcome" in quests_of(x)[0], 40)
    ok = bool(ch) and "gw_welcome" in quests_of(ch)[0]
    c.check(ok, "quest aceita e persistida antes da queda do backend")
    os.killpg(os.getpgid(c.api.pid), signal.SIGSTOP)  # tsx cria um processo filho: congela o grupo todo
    t_stop = time.time()
    print("  INFO  backend CONGELADO (SIGSTOP) por 32 s; o bot entrega a quest durante a queda")
    time.sleep(32)
    os.killpg(os.getpgid(c.api.pid), signal.SIGCONT)
    print(f"  INFO  backend de volta apos {time.time() - t_stop:.0f} s")
    ch2 = c.poll(c.email, cid, lambda x: "gw_welcome" in quests_of(x)[1], 40)
    active, completed = quests_of(ch2)
    c.check("gw_welcome" in completed, f"recompensa da quest chegou ao banco depois da volta do backend (completed={completed})")
    ra = c.finish_bot(a, outa, 110)
    time.sleep(2)
    fin = c.char_of(c.email, cid)
    inv = c.total_items(fin)
    c.check(int(fin["xp"]) == 60, f"xp aplicado EXATAMENTE uma vez (xp={fin['xp']})")
    c.check(inv.get("potion_minor", 0) == 2, f"itens da recompensa aplicados exatamente uma vez ({inv})")
    log = c.server_log("a")
    c.check("reentrega" in log, "servidor reentregou a recompensa com a mesma chave (log)")
    c.check(ra.get("connected") is True and ra.get("_exit") == 0, f"bot manteve a conexao durante a queda do backend (exit={ra.get('_exit')})")
    c.check(adv(ra).get("inventory", {}).get("potion_minor") == 2, f"inventario sincronizado ao cliente mesmo com o backend fora ({adv(ra).get('inventory')})")
    common_end(c, ["a"])


SCEN = {"adventure": sc_adventure, "ruins": sc_ruins, "party": sc_party, "zone_drop": sc_zone_drop, "server_crash": sc_server_crash, "outage": sc_outage}


def main():
    signal.signal(signal.SIGTERM, lambda s, f: (e4.cleanup(), sys.exit(130)))
    ap = argparse.ArgumentParser()
    ap.add_argument("scenario", choices=list(SCEN) + ["all"])
    ap.add_argument("--godot", default=e4.default_godot())
    ap.add_argument("--port", type=int, default=24900)
    a = ap.parse_args()
    os.makedirs(e4.SCR, exist_ok=True)
    names = list(SCEN) if a.scenario == "all" else [a.scenario]
    allf = []
    try:
        for i, n in enumerate(names):
            print(f"== {n}", flush=True)
            c = A(n, a.godot, a.port + i * 2)
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
