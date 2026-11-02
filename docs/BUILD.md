# Build do Windows (E7.1)

Build reproduzivel do cliente e do servidor dedicado, **feito a partir do Linux (VM) ou do Windows**, tudo dentro da pasta do projeto (`.tools/`, `build/`); nada e instalado fora dela.

## Pre-requisitos
- Godot **4.7.2.stable** (`.tools/godot-linux/...` na VM; no Windows use o `Godot_v4.7.2-stable_win64.exe` e passe `--godot`).
- Templates de exportacao 4.7.2 (`Godot_v4.7.2-stable_export_templates.tpz`) em `.tools/downloads/`. O script confere o SHA-512 do `.tpz` (`TEMPLATES_SHA512` em `tools/build_windows.py`, extraido do `SHA512-SUMS.txt` oficial) e extrai para `.tools/xdg/data/godot/export_templates/4.7.2.stable/` (variaveis `APPDATA`/`XDG_DATA_HOME` isoladas; nada em `C:\`).
- Python 3.

## Uso
```
python tools/build_windows.py --check                  # so valida ambiente (versao, templates, presets)
python tools/build_windows.py                           # client + server (release), zips, MANIFEST, SHA256SUMS
python tools/build_windows.py --target server --skip-import
python tools/build_windows.py --target client --no-zip --debug
```
Saida em `build/windows/` (ignorada pelo Git): `client/Eldervale.exe + .pck`, `server/EldervaleServer.exe + .console.exe + .pck`, `Eldervale-<alvo>-<versao>+<id>-win64.zip`, `MANIFEST.json`, `SHA256SUMS.txt`, `logs/`.
Execucoes por alvo (`--target`) preservam o outro alvo no `MANIFEST.json` desde que o build id e o modo sejam iguais. Uma chamada com `all` leva ~3 min nesta VM; se o seu ambiente limita o tempo por comando, rode um alvo por vez.

## Presets (`export_presets.cfg`)
| Preset | Feature | Cena principal | Saida |
|---|---|---|---|
| Windows Client | `eldervale_client` | `run/main_scene.eldervale_client` | `build/windows/client/Eldervale.exe` |
| Windows Server | `eldervale_server` | `run/main_scene.eldervale_server` | `build/windows/server/EldervaleServer.exe` (com wrapper de console) |
Ambos: `embed_pck=false`, inclusao de `build_info.json`, `data/*`, `shared/*`; exclusao de `tests`, `tools`, `docs`, `backend`, `build`, `.tools`, `.git`, `*.md`, `*.py` etc.

## Versao e build id
- Versao do jogo: `BuildInfo.GAME_VERSION` (`scripts/boot/build_info.gd`), atualmente `0.7.0-alpha.1`.
- Build id: hash curto do commit (`-dirty` se a arvore tem mudancas) e data do commit; escritos em `build_info.json` antes do export e descartados depois (`/build_info.json` esta no `.gitignore`).
- Visivel: titulo da tela de login (`BuildInfo.display()`), `--version` do cliente e do servidor, linha de log de inicializacao do servidor, `hello` do cliente.
- Zips deterministicos (metadados fixos, ordem fixa).

## Resultado da validacao (VM Linux, 2026-11-02)
| Item | Resultado |
|---|---|
| Versao do Godot e SHA-512 do `.tpz` | OK (versao 4.7.2.stable.official.ed1daf0bf; hash conferido) |
| Importacao limpa (`--import`) | OK |
| Export headless dos dois presets | OK; sem `ERROR` nos logs de export |
| Tamanhos | `Eldervale.exe` / `EldervaleServer.exe` 109 268 480 B (mesmo template Windows release); `.pck` cliente 980 200 B; zips ~37 MB (cliente) e ~38 MB (servidor) |
| Hashes | `build/windows/SHA256SUMS.txt` e `MANIFEST.json` |
| Reprodutibilidade | dois builds consecutivos do mesmo commit deram PCK identico; um build anterior diferiu e a causa nao foi investigada. **Parcial.** |
| `.pck` do servidor executa no Godot Linux headless (`godot --headless --main-pack EldervaleServer.pck -- --version`) | OK: imprime `Eldervale server v0.7.0-alpha.1 (feddce3-dirty) protocol 2 godot 4.7.2-stable` (valida cena principal por feature, scripts e `build_info.json` embutidos; nao valida o `.exe`) |
| **Executar o `.exe` no Windows** | **NAO VERIFICADO**: a VM e Linux, sem Windows nem Wine. O dono deve abrir o cliente e o servidor (`EldervaleServer.console.exe --version`). |
| Assinatura de codigo | **nao assinado** (precisa de certificado do dono); o Windows SmartScreen vai avisar. |
| Icone/metadados do `.exe` | nao configurados (sem arte). |

## Rodar o servidor dedicado
Sempre com variaveis de ambiente para segredos (nunca por CLI):
```
set ELDERVALE_BACKEND_URL=https://...        (https obrigatorio fora de dev)
set ELDERVALE_INTERNAL_SECRET=...            (cofre; igual a GAME_SESSION_INTERNAL_SECRET do backend)
EldervaleServer.console.exe --port 24565 --log-format json --log-level info --health-file health.json --max-conns-per-ip 6
```
Em modo dev local: `--dev-mode 1` (ver `docs/E4_GODOT_SERVER.md`).
