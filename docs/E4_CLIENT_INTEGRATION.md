# E4 - Cliente, bots e harness E2E (M5b)

## Fluxo do cliente
Com `--backend-url URL` (cliente real): `ClientMain` mostra `scenes/client/login.tscn` (`LoginScreen`: e-mail, senha, Entrar/Registrar, lista de personagens, criar personagem, Jogar) -> `BackendFlow.choose_session` (`GET /v1/sessions`: compativel com `Protocol.VERSION` e com vaga, ou o `--session-id`) -> `POST /v1/sessions/:id/join-ticket` -> ENet ao `endpoint` -> `c_hello(version, build, name, ticket)` (hello v2). Ticket e de uso unico: ao cair/ser recusado a tela volta com a mensagem e um novo ticket e pedido em "Jogar". Sem `--backend-url`: conexao direta `--host/--port` com ticket vazio (modo dev; so funciona com servidor sem backend).

Codigo: `scripts/client/backend_api.gd` (HTTP assincrono; tokens so em memoria; renova no 401 uma vez; HTTPS exigido fora de localhost/127.0.0.1/::1; transporte injetavel), `backend_flow.gd` (login/registro, personagem, sessao, ticket), `client_args.gd` (argumentos), `login_screen.gd`, `client_main.gd`, `bot_script.gd`, `bot_result.gd`.

## Bots
`godot --headless --path . res://scenes/client/client_boot.tscn -- --backend-url http://127.0.0.1:8787 --email E --character NOME --bot kill_enemy --bot-seconds 40 --out saida.json` (senha em `ELDERVALE_PASSWORD`, preferivel a `--password`; `--session-id ID`, `--kill-grace S` opcionais). O bot faz login (registra se preciso), cria o personagem se nao existe, escolhe a sessao, pede o ticket e conecta. Roteiros novos: `kill_enemy` (anda ate o inimigo vivo mais proximo do snapshot e ataca; encerra `--kill-grace` s apos a morte, padrao 2 s), `replay_ticket` (2 conexoes sequenciais com o MESMO ticket; `attempts[]` no JSON), `bad_ticket` (ticket adulterado). Saida: 0 ok, 1 erro ao gravar JSON, 2 bot desconhecido, 3 sem conexao, 4 falha no fluxo de backend/argumentos.
JSON novo: `login_ok, character_id, session_id, ticket_used_ok, flow_error, attempts, kills, events_total, character_final{level,xp,revision,inventory_qty}, xp, level` (GET final do personagem ~2 s apos sair; `xp=-1` se nao houve).

## Harness
`python3 tools/e4_integration.py <happy|replay|double|crash|badticket|nobackendsecret|all> [--godot CAMINHO|env GODOT] [--port N] [--persist-db]`. Requer python3 (stdlib), Node >= 22, `npm ci` em `backend/` e o Godot 4.7.2 (Windows: passe `--godot` com o `..._win64_console.exe`). Sobe `tools/e4_api_server.mts` (mesmo app do dev-server; PGlite **em memoria** por padrao), o servidor Godot (`--backend-url`, `--session-id-file`, segredo por `ELDERVALE_INTERNAL_SECRET`) e bots; segredos aleatorios por execucao, so por ambiente; derruba apenas os processos que iniciou. Logs em `.tools/scratch/e4_<cenario>_<ts>/` (confirma-se que nenhum segredo/JWT aparece neles). Cada cenario leva 25-60 s; `all` soma tudo (~4 min) - rode um por vez se seu shell limita o tempo.
- `crash`: `SIGKILL` no servidor com o bot conectado, sem checkpoint final; usa `SESSION_HEARTBEAT_TIMEOUT_SECONDS=5` (minimo aceito pelo backend; 3 e rejeitado) para o lock morto expirar; sobe novo servidor (novo `session_id`) e o bot reconecta com novo ticket.

## Limites / nao verificado
- Render, tela de login e HUD nao foram vistos (headless): so instanciacao e logica (`tests/e4/`).
- PGlite em memoria no harness (o disco do ambiente levou ~50 s so para criar o diretorio persistente; `--persist-db` existe mas so foi medido, nao usado nos cenarios). Concorrencia Postgres real, TLS/HTTPS e rede fora de loopback nao testados.
- `double` foi recusado ja na emissao do ticket (`character_already_connected`), nao no `s_reject` do servidor.
- `crash` prova que o estado persistido (recompensa) sobrevive e e carregado sem conflito; o autosave em si (30 s) nao foi exercitado.
- PENDENCIA M4: `backend/src/sessions/service.ts` ainda aceita so o protocolo 1; o harness acrescenta o 2 em memoria em `e4_api_server.mts`. Corrija a constante (e o teste `protocol_version: 2` em `sessions.test.ts`).
- Servidor (M5a): `disconnect_peer` num peer que ja saiu gera `ERROR: Condition "!_is_active() || !peers.has(p_peer)"` (visto quando o cliente fecha logo apos o `s_reject`; o bot agora espera 0,5 s).
- Refresh concorrente de chamadas autenticadas simultaneas nao e serializado em `BackendApi` (usar em serie).
