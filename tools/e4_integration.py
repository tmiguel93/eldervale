#!/usr/bin/env python3
"""Integracao E2E E4: API Node local (PGlite temporario) + servidor Godot headless + bots, tudo em processos
separados em 127.0.0.1. Segredos aleatorios gerados a cada execucao e passados SO por ambiente.
Uso: python3 tools/e4_integration.py <happy|replay|double|crash|badticket|nobackendsecret|all> [--godot CAMINHO] [--port N]
Requer: python3 (stdlib), node >= 22 e `npm ci` em backend/, binario Godot 4.7.2. Saida 0 = tudo PASS.
Cada cenario leva < 170 s; `all` soma todos (rode um por vez se o seu shell tem limite de tempo)."""
import argparse, glob, json, os, re, secrets, shutil, signal, subprocess, sys, time, urllib.error, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCR = os.path.join(ROOT, ".tools", "scratch")
SERVER_SCENE = "res://scenes/server/server_boot.tscn"
CLIENT_SCENE = "res://scenes/client/client_boot.tscn"
IS_WIN = os.name == "nt"
PERSIST_DB = False  # --persist-db: PGlite em diretorio temporario do projeto (lento em alguns discos: ~50 s so para criar)
HB_TIMEOUT = 5  # menor valor aceito pelo backend (SESSION_HEARTBEAT_TIMEOUT_SECONDS 5..3600)

_children = []  # (Popen, nome) iniciados por este script: SO eles sao encerrados no fim


def default_godot():
    if os.environ.get("GODOT"):
        return os.environ["GODOT"]
    for c in (os.path.join(ROOT, ".tools", "godot-linux", "Godot_v4.7.2-stable_linux.x86_64"),
              os.path.join(ROOT, ".tools", "godot-win", "Godot_v4.7.2-stable_win64_console.exe")):
        if os.path.exists(c):
            return c
    return "godot"


def godot_env():
    env = dict(os.environ)
    for k in ("XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"):
        d = os.path.join(ROOT, ".tools", "xdg", k.split("_")[1].lower())
        os.makedirs(d, exist_ok=True)
        env[k] = d
    return env


def spawn(name, argv, env, log_path, cwd=None):
    log = open(log_path, "w")
    kw = {}
    if IS_WIN:
        kw["creationflags"] = subprocess.CREATE_NEW_PROCESS_GROUP
    else:
        kw["start_new_session"] = True
    p = subprocess.Popen(argv, env=env, cwd=cwd, stdout=log, stderr=subprocess.STDOUT, **kw)
    _children.append((p, name))
    return p


def kill_tree(p, sig_kill=True):
    if p.poll() is not None:
        return
    try:
        if IS_WIN:
            subprocess.run(["taskkill", "/F", "/T", "/PID", str(p.pid)], capture_output=True)
        else:
            os.killpg(os.getpgid(p.pid), signal.SIGKILL if sig_kill else signal.SIGTERM)
    except (ProcessLookupError, PermissionError):
        pass
    try:
        p.wait(timeout=10)
    except subprocess.TimeoutExpired:
        pass


def cleanup():
    for p, _ in _children:
        kill_tree(p)


class Ctx:
    """Estado de um cenario: segredos, diretorio de trabalho, API, servidores, bots."""

    def __init__(self, name, godot, port):
        self.name, self.godot, self.port = name, godot, port
        self.dir = os.path.join(SCR, f"e4_{name}_{int(time.time())}")
        os.makedirs(self.dir, exist_ok=True)
        self.auth_secret = secrets.token_urlsafe(48)
        self.internal_secret = secrets.token_urlsafe(48)
        self.password = "Pw-" + secrets.token_urlsafe(18)
        self.email = f"e4-{secrets.token_hex(4)}@example.test"
        self.api_port = self.port + 100
        self.api_url = f"http://127.0.0.1:{self.api_port}"
        self.api = None
        self.secret_values = [self.auth_secret, self.internal_secret, self.password]
        self.fails = []
        self.access = None

    # ---- relatorio
    def check(self, cond, msg):
        print(("  PASS  " if cond else "  FAIL  ") + msg, flush=True)
        if not cond:
            self.fails.append(msg)

    # ---- API
    def start_api(self):
        env = dict(os.environ)
        env.update({"NODE_ENV": "development", "PORT": str(self.api_port), "AUTH_SECRET": self.auth_secret,
                    "GAME_SESSION_INTERNAL_SECRET": self.internal_secret, "LOG_LEVEL": "warn",
                    "SESSION_HEARTBEAT_TIMEOUT_SECONDS": str(HB_TIMEOUT),
                    "ELDERVALE_E4_DATA_DIR": os.path.join(self.dir, "pglite") if PERSIST_DB else "memory"})
        tsx = os.path.join(ROOT, "backend", "node_modules", "tsx", "dist", "cli.mjs")
        if not os.path.exists(tsx):
            sys.exit("backend/node_modules ausente: rode `npm ci` em backend/")
        self.api = spawn("api", ["node", tsx, os.path.join(ROOT, "tools", "e4_api_server.mts")], env,
                         os.path.join(self.dir, "api.log"), cwd=os.path.join(ROOT, "backend"))
        for _ in range(120):
            if self.api.poll() is not None:
                sys.exit("API terminou ao subir; veja " + os.path.join(self.dir, "api.log"))
            st, _ = self.http("GET", "/v1/health")
            if st == 200:
                return
            time.sleep(0.5)
        sys.exit("API nao respondeu em 60 s")

    def http(self, method, path, body=None, token=None):
        req = urllib.request.Request(self.api_url + path, method=method,
                                     data=None if body is None else json.dumps(body).encode(),
                                     headers={"Content-Type": "application/json"})
        if token:
            req.add_header("Authorization", "Bearer " + token)
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

    def login_http(self):
        st, d = self.http("POST", "/v1/auth/login", {"email": self.email, "password": self.password})
        self.access = d["access_token"] if st == 200 else None
        return st == 200

    def characters(self):
        if not self.access and not self.login_http():
            return []
        st, d = self.http("GET", "/v1/characters", token=self.access)
        if st == 401 and self.login_http():
            st, d = self.http("GET", "/v1/characters", token=self.access)
        return d["characters"] if st == 200 else []

    def character(self, cid):
        if not self.access and not self.login_http():
            return None
        st, d = self.http("GET", f"/v1/characters/{cid}", token=self.access)
        return d["character"] if st == 200 else None

    def open_sessions(self):
        if not self.access and not self.login_http():
            return None
        st, d = self.http("GET", "/v1/sessions", token=self.access)
        return d["sessions"] if st == 200 else None

    def prepare_account(self, char_name):
        """Registra e cria o personagem por HTTP (os bots tambem sabem fazer isso sozinhos)."""
        self.http("POST", "/v1/auth/register", {"email": self.email, "password": self.password})
        self.login_http()
        st, d = self.http("POST", "/v1/characters", {"name": char_name, "class_id": "warrior"}, token=self.access)
        return d["character"]["id"] if st == 201 else None

    # ---- servidor Godot
    def start_server(self, tag, secret=None, max_seconds=120, extra=()):
        sid_file = os.path.join(self.dir, f"session_{tag}.txt")
        env = godot_env()
        env["ELDERVALE_INTERNAL_SECRET"] = secret or self.internal_secret
        argv = [self.godot, "--headless", "--path", ROOT, SERVER_SCENE, "--", "--port", str(self.port),
                "--max-seconds", str(max_seconds), "--backend-url", self.api_url,
                "--public-endpoint", f"127.0.0.1:{self.port}", "--session-id-file", sid_file] + list(extra)
        p = spawn("server_" + tag, argv, env, os.path.join(self.dir, f"server_{tag}.log"))
        return p, sid_file

    def wait_session(self, sid_file, proc, timeout=30):
        t0 = time.time()
        while time.time() - t0 < timeout:
            if os.path.exists(sid_file):
                v = open(sid_file).read().strip()
                if v:
                    return v
            if proc.poll() is not None:
                return None
            time.sleep(0.3)
        return None

    # ---- bots
    def start_bot(self, tag, script, character, seconds, session_id=None, extra=(), email=None, password=None):
        out = os.path.join(self.dir, f"bot_{tag}.json")
        if os.path.exists(out):
            os.remove(out)
        env = godot_env()
        env["ELDERVALE_PASSWORD"] = password or self.password  # segredo por ambiente, nunca por argumento
        argv = [self.godot, "--headless", "--path", ROOT, CLIENT_SCENE, "--", "--backend-url", self.api_url,
                "--email", email or self.email, "--character", character, "--bot", script,
                "--bot-seconds", str(seconds), "--out", out]
        if session_id:
            argv += ["--session-id", session_id]
        argv += list(extra)
        p = spawn("bot_" + tag, argv, env, os.path.join(self.dir, f"bot_{tag}.log"))
        return p, out

    def finish_bot(self, p, out, timeout=120):
        try:
            code = p.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            kill_tree(p)
            code = -9
        res = {}
        if os.path.exists(out):
            try:
                res = json.load(open(out))
            except Exception:
                res = {"errors": ["json invalido"]}
        else:
            res = {"errors": ["sem json"]}
        res["_exit"] = code
        return res

    def server_log(self, tag):
        try:
            return open(os.path.join(self.dir, f"server_{tag}.log"), errors="ignore").read()
        except OSError:
            return ""

    def no_errors_in(self, tags, label="servidor"):
        bad = []
        for t in tags:
            bad += [l for l in self.server_log(t).splitlines() if "ERROR" in l or "SCRIPT ERROR" in l]
        self.check(not bad, f"{label} sem ERROR no log" + (f" ({bad[:2]})" if bad else ""))

    def no_secrets_in_logs(self):
        jwt = re.compile(r"eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}")
        leaked = []
        for f in glob.glob(os.path.join(self.dir, "*.log")) + glob.glob(os.path.join(self.dir, "*.json")):
            txt = open(f, errors="ignore").read()
            for s in self.secret_values:
                if s and s in txt:
                    leaked.append(os.path.basename(f))
            if jwt.search(txt):
                leaked.append(os.path.basename(f) + "(jwt)")
        self.check(not leaked, "nenhum segredo/token/ticket nos logs e JSONs" + (f" (vazou em {sorted(set(leaked))})" if leaked else ""))

    def poll_character(self, cid, pred, timeout=15):
        t0 = time.time()
        c = None
        while time.time() - t0 < timeout:
            c = self.character(cid)
            if c and pred(c):
                return c
            time.sleep(0.7)
        return c


# ======================================================================= cenarios

def sc_happy(c):
    c.start_api()
    srv, sf = c.start_server("a")
    sid = c.wait_session(sf, srv)
    c.check(sid is not None, "servidor registrou sessao no backend (session-id-file)")
    if not sid:
        return
    bot, out = c.start_bot("a", "kill_enemy", "Heroi", 45)
    r = c.finish_bot(bot, out, 110)
    c.check(r.get("_exit") == 0, f"bot saiu com 0 (codigo {r.get('_exit')}, erros {r.get('errors')})")
    c.check(r.get("login_ok") is True and bool(r.get("character_id")), "bot: registro -> login -> personagem criado (login_ok, character_id)")
    c.check(r.get("session_id") == sid, "bot entrou na sessao registrada pelo servidor")
    c.check(r.get("connected") is True and r.get("ticket_used_ok") is True and not r.get("rejected"), f"ticket aceito pelo servidor (rejected={r.get('rejected')})")
    c.check(r.get("kills", 0) >= 1, f"bot matou um inimigo (kills={r.get('kills')}, eventos={r.get('events_by_kind')})")
    cid = r.get("character_id")
    ch = c.poll_character(cid, lambda x: x.get("xp", 0) > 0 and x.get("revision", 0) > 0)
    c.check(bool(ch) and int(ch.get("xp", 0)) > 0, f"GET /v1/characters/:id mostra XP persistido (xp={ch and ch.get('xp')})")
    c.check(bool(ch) and int(ch.get("revision", 0)) > 0, f"revision > 0 (revision={ch and ch.get('revision')})")
    if ch:
        print(f"  INFO  nivel={ch.get('level')} xp={ch.get('xp')} itens={[(i['item_id'], i['qty']) for i in ch.get('inventory', [])]} bot_xp_final={r.get('xp')}")
    c.check(r.get("xp", -1) >= 0, f"bot leu xp/nivel no GET final (xp={r.get('xp')}, level={r.get('level')})")
    c.no_errors_in(["a"])
    c.no_secrets_in_logs()


def sc_replay(c):
    c.start_api()
    cid = c.prepare_account("Replay")
    srv, sf = c.start_server("a")
    sid = c.wait_session(sf, srv)
    c.check(sid is not None and cid is not None, "API, conta, personagem e sessao prontos")
    bot, out = c.start_bot("a", "replay_ticket", "Replay", 20, session_id=sid)
    r = c.finish_bot(bot, out, 90)
    at = r.get("attempts", [])
    c.check(len(at) == 2, f"duas conexoes com o MESMO ticket registradas ({len(at)})")
    if len(at) == 2:
        c.check(at[0].get("connected") is True and at[0].get("ticket_used_ok") is True, "1a conexao aceita")
        c.check(at[1].get("connected") is False and (at[1].get("rejected") or {}).get("code") == 5, f"2a conexao recusada com reject 5 ({at[1].get('rejected')})")
    c.check((r.get("rejected") or {}).get("code") == 5, "rejected.code == 5 no relatorio")
    c.no_errors_in(["a"])
    c.no_secrets_in_logs()


def sc_double(c):
    c.start_api()
    cid = c.prepare_account("Gemeo")
    srv, sf = c.start_server("a")
    sid = c.wait_session(sf, srv)
    c.check(sid is not None and cid is not None, "API, conta, personagem e sessao prontos")
    a, outa = c.start_bot("a", "walk_square", "Gemeo", 22, session_id=sid)
    # espera a conexao de A ficar de pe (login + ticket + ENet): o lock do personagem aparece no backend
    time.sleep(9)
    b, outb = c.start_bot("b", "walk_square", "Gemeo", 6, session_id=sid)
    rb = c.finish_bot(b, outb, 60)
    ra = c.finish_bot(a, outa, 90)
    c.check(ra.get("connected") is True and ra.get("ticket_used_ok") is True, "1a conexao do personagem aceita")
    c.check(rb.get("connected") is not True, "2a conexao do MESMO personagem nao entrou")
    refused = (rb.get("rejected") or {}).get("code") == 5 or bool(rb.get("flow_error"))
    c.check(refused, f"2a conexao recusada (reject={rb.get('rejected')}, flow_error={rb.get('flow_error')!r})")
    c.no_errors_in(["a"])
    c.no_secrets_in_logs()


def sc_badticket(c):
    c.start_api()
    cid = c.prepare_account("Falso")
    srv, sf = c.start_server("a")
    sid = c.wait_session(sf, srv)
    c.check(sid is not None and cid is not None, "API, conta, personagem e sessao prontos")
    bot, out = c.start_bot("a", "bad_ticket", "Falso", 10, session_id=sid)
    r = c.finish_bot(bot, out, 60)
    c.check(r.get("connected") is not True and (r.get("rejected") or {}).get("code") == 5, f"ticket adulterado -> reject 5 ({r.get('rejected')})")
    # o ticket legitimo ainda nao foi gasto: um bot normal entra em seguida
    bot2, out2 = c.start_bot("b", "walk_square", "Falso", 4, session_id=sid)
    r2 = c.finish_bot(bot2, out2, 60)
    c.check(r2.get("connected") is True, "depois da tentativa adulterada, um login legitimo ainda entra")
    c.no_errors_in(["a"])
    c.no_secrets_in_logs()


def sc_nobackendsecret(c):
    c.start_api()
    cid = c.prepare_account("Sem")
    wrong = secrets.token_urlsafe(48)
    c.secret_values.append(wrong)
    srv, sf = c.start_server("a", secret=wrong, max_seconds=30)
    sid = c.wait_session(sf, srv, timeout=12)
    c.check(sid is None and not os.path.exists(sf), "servidor com segredo errado NAO obtem session_id nem grava --session-id-file")
    time.sleep(2)
    log = c.server_log("a")
    c.check(("401" in log) and ("registrar" in log or "register" in log), "servidor registra falha clara (401 ao registrar sessao)")
    c.check(wrong not in log and c.internal_secret not in log, "log do servidor nao contem nenhum segredo")
    sess = c.open_sessions()
    c.check(sess == [], f"backend nao lista sessao alguma ({sess})")
    bot, out = c.start_bot("a", "walk_square", "Sem", 5)
    r = c.finish_bot(bot, out, 60)
    c.check(r.get("_exit") == 4 and r.get("flow_error") == "no_session" and r.get("connected") is not True, f"bot falha claro: nenhuma sessao (exit={r.get('_exit')}, flow_error={r.get('flow_error')!r})")
    c.no_secrets_in_logs()


def sc_crash(c):
    c.start_api()
    cid = c.prepare_account("Fenix")
    srv1, sf1 = c.start_server("a", max_seconds=150)
    sid1 = c.wait_session(sf1, srv1)
    c.check(sid1 is not None and cid is not None, "API, conta, personagem e sessao 1 prontos")
    if not sid1:
        return
    # o bot continua conectado (grace longo) depois de matar, para o kill -9 pegar a sessao no meio
    a, outa = c.start_bot("a", "kill_enemy", "Fenix", 70, session_id=sid1, extra=["--kill-grace", "60"])
    ch = c.poll_character(cid, lambda x: x.get("xp", 0) > 0, timeout=70)
    xp0, rev0, lvl0 = (int(ch["xp"]), int(ch["revision"]), int(ch["level"])) if ch else (0, 0, 0)
    c.check(xp0 > 0 and rev0 > 0, f"recompensa persistida antes do crash (xp={xp0}, revision={rev0})")
    kill_tree(srv1)  # kill -9: nenhum checkpoint final, nenhum release/close
    c.check(srv1.poll() is not None, "servidor 1 encerrado com SIGKILL")
    ra = c.finish_bot(a, outa, 40)
    c.check(ra.get("connected") is True, "bot A estava conectado quando o servidor morreu")
    after = c.character(cid)
    c.check(bool(after) and int(after["xp"]) >= xp0 and int(after["revision"]) >= rev0, f"estado persistido preservado apos o crash (xp={after and after['xp']})")
    # o lock do servidor morto expira em ~HB_TIMEOUT s (SESSION_HEARTBEAT_TIMEOUT_SECONDS=5 no backend)
    time.sleep(HB_TIMEOUT + 2.5)
    srv2, sf2 = c.start_server("b", max_seconds=100)
    sid2 = c.wait_session(sf2, srv2)
    c.check(sid2 is not None and sid2 != sid1, f"novo servidor registrou NOVA sessao ({sid2 and sid2[:8]} != {sid1[:8]})")
    if not sid2:
        return
    sess = c.open_sessions() or []
    c.check(all(s["id"] != sid1 for s in sess), "sessao morta nao e mais listada em GET /v1/sessions")
    b, outb = c.start_bot("b", "kill_enemy", "Fenix", 45, session_id=sid2)
    rb = c.finish_bot(b, outb, 110)
    c.check(rb.get("connected") is True and rb.get("ticket_used_ok") is True and rb.get("session_id") == sid2, f"bot reconectou com NOVO ticket na nova sessao (rejected={rb.get('rejected')}, flow_error={rb.get('flow_error')!r})")
    ch2 = c.poll_character(cid, lambda x: int(x.get("revision", 0)) > rev0 and int(x.get("xp", 0)) > xp0, timeout=15)
    c.check(bool(ch2) and int(ch2["xp"]) >= xp0, f"XP preservado/acumulado apos reconexao (antes={xp0}, depois={ch2 and ch2['xp']})")
    c.check(bool(ch2) and int(ch2["revision"]) > rev0, f"revision avancou na nova sessao ({rev0} -> {ch2 and ch2['revision']})")
    log2 = c.server_log("b")
    c.check("falhou" not in log2 and "conflito de revision" not in log2, "novo servidor carregou o estado sem falha/conflito de checkpoint")
    c.no_errors_in(["a", "b"])
    c.no_secrets_in_logs()


SCENARIOS = {"happy": sc_happy, "replay": sc_replay, "double": sc_double, "crash": sc_crash,
             "badticket": sc_badticket, "nobackendsecret": sc_nobackendsecret}


def _on_term(signum, frame):
    cleanup()
    sys.exit(130)


def main():
    signal.signal(signal.SIGTERM, _on_term)
    if not IS_WIN:
        signal.signal(signal.SIGHUP, _on_term)
    ap = argparse.ArgumentParser()
    ap.add_argument("scenario", choices=list(SCENARIOS) + ["all"])
    ap.add_argument("--godot", default=default_godot())
    ap.add_argument("--port", type=int, default=24800)
    ap.add_argument("--persist-db", action="store_true", help="PGlite em .tools/scratch/e4_*/pglite em vez de memoria")
    a = ap.parse_args()
    global PERSIST_DB
    PERSIST_DB = a.persist_db
    os.makedirs(SCR, exist_ok=True)
    names = list(SCENARIOS) if a.scenario == "all" else [a.scenario]
    allf = []
    try:
        for i, n in enumerate(names):
            print(f"== {n}", flush=True)
            c = Ctx(n, a.godot, a.port + i * 2)
            t0 = time.time()
            try:
                SCENARIOS[n](c)
            finally:
                cleanup()
                _children.clear()
                try:
                    shutil.rmtree(os.path.join(c.dir, "pglite"))
                except OSError:
                    pass
            print(f"  ({time.time() - t0:.0f} s; logs em {os.path.relpath(c.dir, ROOT)})")
            allf += [f"{n}: {m}" for m in c.fails]
    finally:
        cleanup()
    print("RESULTADO:", "OK" if not allf else f"{len(allf)} falha(s)")
    for f in allf:
        print("  -", f)
    sys.exit(1 if allf else 0)


if __name__ == "__main__":
    main()
