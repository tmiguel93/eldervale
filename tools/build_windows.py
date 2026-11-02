#!/usr/bin/env python3
"""Build Windows reproduzivel do Eldervale (E7.1): cliente e servidor dedicado, tudo DENTRO da pasta do projeto.

Uso (no Windows, na raiz do projeto):
  py tools\\build_windows.py --godot D:\\Projetos\\Godot\\Godot_v4.7.2-stable_win64_console.exe
  py tools\\build_windows.py --check            # so valida o ambiente (Godot, templates, presets); nao exporta
  py tools\\build_windows.py --target client    # client | server | all (padrao: all)
Opcoes: --out DIR (padrao build/windows), --debug (templates de debug), --templates-tpz ARQUIVO (padrao
.tools/downloads/Godot_v4.7.2-stable_export_templates.tpz), --skip-import, --no-zip.

O que faz, nesta ordem:
  1. confere a versao exata do Godot (4.7.2.stable) e os presets de export_presets.cfg;
  2. grava `build_info.json` (versao do jogo, id do build = commit curto [+ -dirty], data = data do COMMIT, nao a do relogio,
     para o resultado ser reprodutivel) -- o jogo o le (BuildInfo) e mostra na tela de login / `--version` / hello do protocolo;
  3. instala os export templates 4.7.2 (extraidos do .tpz oficial, SHA-512 conferido) em .tools/appdata (Windows) ou
     .tools/xdg/data (Linux): o Godot e iniciado com APPDATA/XDG_DATA_HOME apontando para la, entao NADA e escrito no C:\\;
  4. importacao limpa (`--import`) e exportacao headless de cada preset;
  5. gera SHA256SUMS.txt, MANIFEST.json (tamanhos, hashes, versao, commit) e um .zip por alvo com metadados fixos;
  6. remove o build_info.json temporario (nao e versionado).
Saida 0 = tudo certo. Nada aqui assina codigo, faz upload, publica ou usa rede (o .tpz tem de estar no disco)."""
import argparse, hashlib, json, os, platform, re, shutil, subprocess, sys, time, zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GODOT_VERSION = "4.7.2.stable"
# SHA-512 do Godot_v4.7.2-stable_export_templates.tpz, copiado de SHA512-SUMS.txt do release oficial 4.7.2-stable.
TEMPLATES_SHA512 = "ca4d71c4d7b81dfc15d1a98baa07534aa95b03fdda78a0075b06672e1648d2e5f40980c9adc28d23e1b92e732ee7bf3461997aa804af74ec2fcd7a93ccb84079"
TPZ_DEFAULT = os.path.join(ROOT, ".tools", "downloads", "Godot_v4.7.2-stable_export_templates.tpz")
TARGETS = {
    "client": {"preset": "Windows Client", "dir": "client", "exe": "Eldervale.exe"},
    "server": {"preset": "Windows Server", "dir": "server", "exe": "EldervaleServer.exe"},
}
IS_WIN = os.name == "nt"
TEMPLATE_FILES = ["version.txt"] + [f"windows_{m}_x86_64{c}.exe" for m in ("debug", "release") for c in ("", "_console")]


def log(msg):
    print(msg, flush=True)


def sha256_of(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def default_godot():
    if os.environ.get("GODOT"):
        return os.environ["GODOT"]
    for c in (r"D:\Projetos\Godot\Godot_v4.7.2-stable_win64_console.exe",
              os.path.join(ROOT, ".tools", "godot-win", "Godot_v4.7.2-stable_win64_console.exe"),
              os.path.join(ROOT, ".tools", "godot-linux", "Godot_v4.7.2-stable_linux.x86_64")):
        if os.path.exists(c):
            return c
    return "godot"


def godot_env():
    """Isola dados/config/templates do Godot dentro do projeto (nada fora da pasta do projeto)."""
    env = dict(os.environ)
    if IS_WIN:
        d = os.path.join(ROOT, ".tools", "appdata")
        os.makedirs(d, exist_ok=True)
        env["APPDATA"] = d
        env["LOCALAPPDATA"] = d
    else:
        for k, sub in (("XDG_DATA_HOME", "data"), ("XDG_CONFIG_HOME", "config"), ("XDG_CACHE_HOME", "cache")):
            d = os.path.join(ROOT, ".tools", "xdg", sub)
            os.makedirs(d, exist_ok=True)
            env[k] = d
    return env


def templates_dir():
    base = os.path.join(ROOT, ".tools", "appdata", "Godot") if IS_WIN else os.path.join(ROOT, ".tools", "xdg", "data", "godot")
    return os.path.join(base, "export_templates", GODOT_VERSION)


def run(argv, log_path, env, timeout=900):
    with open(log_path, "w", encoding="utf-8", errors="replace") as lf:
        p = subprocess.run(argv, cwd=ROOT, env=env, stdout=lf, stderr=subprocess.STDOUT, timeout=timeout)
    return p.returncode


def log_has_errors(path):
    text = open(path, encoding="utf-8", errors="replace").read()
    bad = [l for l in text.splitlines() if re.search(r"SCRIPT ERROR|Parse Error|Failed to load script|ERROR: .*(export|pck|template)", l, re.I)]
    return bad


def git(*args):
    try:
        return subprocess.run(["git", *args], cwd=ROOT, capture_output=True, text=True, timeout=30).stdout.strip()
    except Exception:
        return ""


def game_version():
    src = open(os.path.join(ROOT, "scripts", "boot", "build_info.gd"), encoding="utf-8").read()
    m = re.search(r'const GAME_VERSION: String = "([^"]+)"', src)
    if not m:
        sys.exit("GAME_VERSION nao encontrada em scripts/boot/build_info.gd")
    return m.group(1)


def read_presets():
    txt = open(os.path.join(ROOT, "export_presets.cfg"), encoding="utf-8").read()
    names = re.findall(r'^name="([^"]+)"', txt, re.M)
    plats = re.findall(r'^platform="([^"]+)"', txt, re.M)
    return names, plats


def check_godot(godot):
    try:
        out = subprocess.run([godot, "--version"], capture_output=True, text=True, timeout=60).stdout.strip()
    except Exception as e:
        sys.exit(f"nao consegui executar o Godot ({godot}): {e}")
    if not out.startswith(GODOT_VERSION):
        sys.exit(f"versao do Godot incompativel: '{out}' (esperado {GODOT_VERSION}; AGENTS.md fixa a engine)")
    return out


def ensure_templates(tpz, force_debug):
    d = templates_dir()
    need = [t for t in TEMPLATE_FILES if not os.path.exists(os.path.join(d, t))]
    if not need:
        log(f"  templates ja instalados em {os.path.relpath(d, ROOT)}")
        return
    if not os.path.exists(tpz):
        sys.exit("export templates ausentes e o .tpz nao foi encontrado em " + tpz + "\n"
                 "  Baixe https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz (1,2 GB)\n"
                 "  para .tools/downloads/ (ou use --templates-tpz) e rode de novo. Veja docs/BUILD.md.")
    log("  conferindo SHA-512 do .tpz (1,2 GB, ~10 s)...")
    h = hashlib.sha512()
    with open(tpz, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 22), b""):
            h.update(chunk)
    if h.hexdigest() != TEMPLATES_SHA512:
        sys.exit("SHA-512 do .tpz NAO confere com o release oficial 4.7.2-stable; recuse o arquivo e baixe de novo.")
    os.makedirs(d, exist_ok=True)
    with zipfile.ZipFile(tpz) as z:
        for t in TEMPLATE_FILES:
            with z.open("templates/" + t) as src, open(os.path.join(d, t), "wb") as dst:
                shutil.copyfileobj(src, dst)
    log(f"  templates Windows x86_64 extraidos para {os.path.relpath(d, ROOT)}")


def write_build_info(version):
    sha = git("rev-parse", "--short=7", "HEAD") or "nogit"
    dirty = bool(git("status", "--porcelain", "--untracked-files=no"))
    build_id = sha + ("-dirty" if dirty else "")
    built_at = git("show", "-s", "--format=%cI", "HEAD") or "1970-01-01T00:00:00Z"  # data do commit: reprodutivel
    info = {"version": version, "build_id": build_id, "built_at": built_at}
    path = os.path.join(ROOT, "build_info.json")
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(info, f, indent=1, sort_keys=True)
        f.write("\n")
    return info, path


def discard(path):
    """Remove o arquivo temporario; se o SO bloquear a remocao (VM do agente), move para .tools/scratch."""
    try:
        os.remove(path)
    except OSError:
        dst_dir = os.path.join(ROOT, ".tools", "scratch")
        os.makedirs(dst_dir, exist_ok=True)
        os.replace(path, os.path.join(dst_dir, f"build_info.{int(time.time())}.json"))


def clean_dir(path):
    """Esvazia a pasta de saida (sobras de uma exportacao interrompida, ex.: 'Eldervale.exe-xxxxxx'). Se o SO bloquear a
    remocao (VM do agente), move para .tools/scratch/old_build em vez de apagar."""
    if not os.path.isdir(path):
        return
    for name in os.listdir(path):
        full = os.path.join(path, name)
        if os.path.isdir(full):
            continue
        try:
            os.remove(full)
        except OSError:
            dst = os.path.join(ROOT, ".tools", "scratch", "old_build")
            os.makedirs(dst, exist_ok=True)
            os.replace(full, os.path.join(dst, f"{int(time.time())}_{name}"))


def zip_dir(src_dir, zip_path, top):
    """Zip deterministico: ordem alfabetica, data fixa (1980-01-01), permissoes fixas."""
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for dp, dn, fn in os.walk(src_dir):
            dn.sort()
            for name in sorted(fn):
                full = os.path.join(dp, name)
                arc = os.path.join(top, os.path.relpath(full, src_dir)).replace("\\", "/")
                zi = zipfile.ZipInfo(arc, (1980, 1, 1, 0, 0, 0))
                zi.compress_type = zipfile.ZIP_DEFLATED
                zi.external_attr = 0o644 << 16
                with open(full, "rb") as f:
                    z.writestr(zi, f.read())


def main():
    ap = argparse.ArgumentParser(description="Build Windows reproduzivel (E7.1)")
    ap.add_argument("--godot", default=default_godot())
    ap.add_argument("--target", choices=["client", "server", "all"], default="all")
    ap.add_argument("--out", default=os.path.join("build", "windows"))
    ap.add_argument("--debug", action="store_true", help="exporta com templates de debug (padrao: release)")
    ap.add_argument("--templates-tpz", default=TPZ_DEFAULT)
    ap.add_argument("--skip-import", action="store_true")
    ap.add_argument("--no-zip", action="store_true")
    ap.add_argument("--check", action="store_true", help="so valida o ambiente")
    a = ap.parse_args()

    out_root = a.out if os.path.isabs(a.out) else os.path.join(ROOT, a.out)
    try:
        rel = os.path.relpath(out_root, ROOT)
    except ValueError:
        rel = ".."
    if rel.startswith(".."):
        sys.exit("--out tem de ficar dentro da pasta do projeto (nada fora dela)")
    names, plats = read_presets()
    targets = list(TARGETS) if a.target == "all" else [a.target]
    for t in targets:
        if TARGETS[t]["preset"] not in names:
            sys.exit(f"preset '{TARGETS[t]['preset']}' ausente em export_presets.cfg")
    if any(p != "Windows Desktop" for p in plats):
        sys.exit("export_presets.cfg tem preset de outra plataforma; este script so exporta Windows Desktop")
    log("== Eldervale: build Windows")
    gv = check_godot(a.godot)
    log(f"  Godot: {gv}")
    version = game_version()
    log(f"  versao do jogo: {version}")
    ensure_templates(a.templates_tpz, a.debug)
    if a.check:
        log("  --check: ambiente OK (nada exportado)")
        return 0

    env = godot_env()
    logs = os.path.join(out_root, "logs")
    os.makedirs(logs, exist_ok=True)
    info, info_path = write_build_info(version)
    log(f"  build_info: {info}")
    results = []
    failed = False
    try:
        if not a.skip_import:
            log("  importacao limpa (--import)...")
            rc = run([a.godot, "--headless", "--path", ROOT, "--import"], os.path.join(logs, "import.log"), env)
            bad = log_has_errors(os.path.join(logs, "import.log"))
            if rc != 0 or bad:
                log(f"  FALHA na importacao (codigo {rc}): {bad[:3]}")
                return 1
        flag = "--export-debug" if a.debug else "--export-release"
        for t in targets:
            spec = TARGETS[t]
            tdir = os.path.join(out_root, spec["dir"])
            os.makedirs(tdir, exist_ok=True)
            clean_dir(tdir)
            exe = os.path.join(tdir, spec["exe"])
            log(f"  exportando '{spec['preset']}' -> {os.path.relpath(exe, ROOT)}")
            lp = os.path.join(logs, f"export_{t}.log")
            rc = run([a.godot, "--headless", "--path", ROOT, flag, spec["preset"], exe], lp, env)
            bad = log_has_errors(lp)
            files = sorted(os.listdir(tdir))
            pck = os.path.splitext(spec["exe"])[0] + ".pck"
            if rc != 0 or not os.path.exists(exe) or not os.path.exists(os.path.join(tdir, pck)) or bad:
                log(f"  FALHA ao exportar {t} (codigo {rc}); veja {os.path.relpath(lp, ROOT)} {bad[:3]}")
                failed = True
                continue
            entry = {"target": t, "preset": spec["preset"], "files": {f: {"bytes": os.path.getsize(os.path.join(tdir, f)), "sha256": sha256_of(os.path.join(tdir, f))} for f in files}}
            results.append(entry)
            for f, d in entry["files"].items():
                log(f"    {f}: {d['bytes']:,} bytes  sha256={d['sha256'][:16]}...")
            if not a.no_zip:
                zname = f"Eldervale-{t}-{version}+{info['build_id']}-win64.zip"
                zip_dir(tdir, os.path.join(out_root, zname), f"Eldervale-{t}")
                entry["zip"] = {"name": zname, "bytes": os.path.getsize(os.path.join(out_root, zname)), "sha256": sha256_of(os.path.join(out_root, zname))}
                log(f"    {zname}: {entry['zip']['bytes']:,} bytes")
    finally:
        discard(info_path)
    # Execucoes por alvo (--target) preservam os alvos ja gerados com o MESMO build id/modo.
    mpath = os.path.join(out_root, "MANIFEST.json")
    if os.path.exists(mpath):
        try:
            prev = json.load(open(mpath, encoding="utf-8"))
            if prev.get("build", {}).get("build_id") == info["build_id"] and prev.get("mode") == ("debug" if a.debug else "release"):
                done = {r["target"] for r in results}
                results = [r for r in prev.get("targets", []) if r["target"] not in done] + results
                results.sort(key=lambda r: r["target"])
        except (OSError, ValueError, KeyError):
            pass
    manifest = {"game_version": version, "build": info, "godot": gv, "mode": "debug" if a.debug else "release",
                "host": platform.system(), "signed": False, "targets": results}
    with open(os.path.join(out_root, "MANIFEST.json"), "w", encoding="utf-8", newline="\n") as f:
        json.dump(manifest, f, indent=1, sort_keys=True)
        f.write("\n")
    with open(os.path.join(out_root, "SHA256SUMS.txt"), "w", encoding="utf-8", newline="\n") as f:
        for r in results:
            for name, d in sorted(r["files"].items()):
                f.write(f"{d['sha256']}  {r['target']}/{name}\n")
            if "zip" in r:
                f.write(f"{r['zip']['sha256']}  {r['zip']['name']}\n")
    log(f"  MANIFEST.json e SHA256SUMS.txt em {os.path.relpath(out_root, ROOT)}")
    log("RESULTADO: " + ("FALHOU" if failed or not results else "OK (artefatos nao assinados; veja docs/BUILD.md)"))
    return 1 if failed or not results else 0


if __name__ == "__main__":
    sys.exit(main())
