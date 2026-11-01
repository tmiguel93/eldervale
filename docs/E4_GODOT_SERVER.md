# E4 - Servidor Godot <-> backend (lado servidor, M5a) + protocolo v2

Codigo: `scripts/server/{backend_client,backend_transport,http_backend_transport,backend_sync,character_codec,server_backend_config,server_log}.gd`
(+ alteracoes em `server_session`, `server_world`, `server_main`, `server_settings`). Testes: `tests/e4/test_backend_client.gd`, `test_server_backend.gd`
(+ `fake_backend.gd`, `backend_helpers.gd`). Contrato HTTP: `docs/E4_SESSIONS.md`, `docs/E4_CHARACTERS.md`. Contrato de rede: `shared/contracts/network_protocol.md` (v2).

## Protocolo v2
`c_hello(version, build, name, ticket)`; `Protocol.VERSION = 2`; `Protocol.validate_hello(version, build, name, ticket)` (ticket <= 1024, `[A-Za-z0-9._-]`, vazio valido);
`NetRpc.send_hello(version, build, name, ticket)`; sinal `hello_received(peer_id, version, build, name, ticket)`; `ServerSession.on_hello(peer_id, version, build, name, ticket)`.
Cliente (M5b): obter o ticket em `POST /v1/sessions/:id/join-ticket` e enviar no hello; `reject(5)` = nao autenticado (sem detalhes).

## Configuracao (argumentos apos `--`, ou ambiente)
| Argumento | Ambiente | Padrao |
|---|---|---|
| `--backend-url U` | `ELDERVALE_BACKEND_URL` | vazio = ERRO, a menos que `--dev-mode 1` / `ELDERVALE_DEV_MODE=1` (MODO DEV explícito: sem ticket, nada persiste) |
| (nao existe argumento) | `ELDERVALE_INTERNAL_SECRET` | OBRIGATORIO com backend; so por ambiente; nunca logado |
| `--public-endpoint host:porta` | `ELDERVALE_PUBLIC_ENDPOINT` | `127.0.0.1:<port>` |
| `--region R` (`[a-z0-9-]{2,32}`) | `ELDERVALE_REGION` | `local` |
| `--session-id-file P` | `ELDERVALE_SESSION_ID_FILE` | vazio (grava o session_id apos registrar) |
| `--heartbeat-interval S` | `ELDERVALE_HEARTBEAT_INTERVAL` | 10 (reduzido a 1/3 do `heartbeat_timeout_seconds` devolvido) |
| `--autosave-interval S` | `ELDERVALE_AUTOSAVE_INTERVAL` | 30 |
| `--redeem-timeout S` | `ELDERVALE_REDEEM_TIMEOUT` | 8 (resgate + carga do personagem) |
| `--max-pending N` | `ELDERVALE_MAX_PENDING` | 8 |
| `--shutdown-timeout S` | `ELDERVALE_SHUTDOWN_TIMEOUT` | 8 |
Capacidade registrada = `--max-players`. HTTPS obrigatorio, exceto `localhost`/`127.0.0.1`/`[::1]`. Config invalida com backend => sai com codigo 2.

## Fluxo
1. Boot: `POST /internal/sessions` (region, capacity, protocol_version=2, endpoint). Falha => tenta de novo com backoff (5/10/20/30 s); ate registrar, todo hello leva `reject(5)`. Heartbeat periodico; 404/`session_closed` => re-registra (nova sessao).
2. Hello: valida; sem ticket (com backend) => `reject(5)`; peer fica PENDENTE (sem jogador, sem simulacao; input => `reject(5)`), limite `max-pending` (`reject(3)`), prazo `redeem-timeout` (`reject(5)`).
3. `POST /internal/tickets/redeem` (SEM retry: uso unico) -> `GET /internal/characters/:id` -> valida o estado (itens no registry, faixas) -> jogador criado de nivel/xp/stats/inventario/equipamento (`CharacterCodec`; sem kit inicial; capacidade do inventario do backend) -> `s_welcome`.
   Qualquer falha (401, 409, timeout, estado invalido) => `reject(5)` generico; se o lock foi adquirido, `release`. Mesmo personagem em 2 peers locais: o segundo e recusado.
4. Persistencia: por personagem, fila SERIALIZADA (load, checkpoint, reward, disconnect, release; uma por vez, em ordem) e `revision` guardada (adotada de cada resposta). Autosave a cada `autosave-interval`: checkpoint completo com `expected_revision` (coalescido: no maximo 1 pendente).
   409 `revision_conflict` => recarrega (GET), adota a revision e REAPLICA o estado do backend ao jogador vivo (o backend vence), loga, nao derruba ninguem.
5. Desconexao: checkpoint final e `POST .../disconnect` (lock mantido pela janela de reconexao do backend). Encerramento limpo (`--max-seconds`/close request): checkpoint + `release` de todos, depois `POST /internal/sessions/:id/close`, com prazo `shutdown-timeout` (estourou: abandona e cancela o transporte).
6. Recompensas: o servidor decide XP/drops (E2). Quem deu o golpe final (rastreado em `ServerWorld`) recebe XP (no Enemy) e os drops entram no Inventory dele (so o que couber); `POST .../rewards` com `idempotency_key = kill:<session_id>:<enemy_id>:<character_id>`;
   erro de rede/5xx/429 => retry com a MESMA chave/corpo (ate 3 tentativas, backoff 0,25/0,5 s); falha permanente (ex. 409 `inventory_full`) e logada e o estado em memoria fica (o proximo checkpoint reconcilia).
   Em modo dev os drops continuam so informativos (E3).

## Limites / decisoes
- Retry so em idempotentes (GET, checkpoint, rewards, disconnect, release, close, heartbeat); nunca em redeem nem register.
- Tecnicamente um checkpoint cujo resultado se perdeu e repetido com a mesma revision e vira 409 -> recarga idempotente (estado identico).
- Recompensa vai so para o matador (golpe final); sem divisao de XP/loot na party.
- HP/recurso atual, posicao e cooldowns NAO sao persistidos (o backend nao tem esses campos); o jogador entra com vida cheia.
- Nome exibido = nome do personagem no backend (se passar em `Protocol.validate_name`), senao o nome do hello.
- O segredo entra so no cabecalho Authorization; `ServerLog` mascara segredos registrados; tickets nunca sao formatados em log/erro.

## NAO verificado
- Nenhum teste e2e com o backend real nem com cliente real conectado por ENet (e do M5b). So testes com backend FALSO e um smoke manual do `HttpBackendTransport` contra `npm run dev` (register/heartbeat/close/401/porta fechada).
- BLOQUEIO para o e2e: `backend/src/sessions/service.ts` ainda aceita `SUPPORTED_PROTOCOL_VERSIONS = [1]`; o registro com `protocol_version=2` volta 400 `unsupported_protocol` (observado). O backend precisa aceitar 2 (escopo do M4).
- TLS real (HTTPS/CA) e proxies nao testados; encerramento por SIGTERM nao verificado (so `--max-seconds`); concorrencia real de varios jogadores e perda de rede em meio a operacoes nao testadas fora do fake.
- Estado de HP/recurso/posicao nao persiste; desempenho do autosave com 4 jogadores nao medido.

## E5.6 — Notas
- Recompensas (`reward`) que falham por rede/5xx/429 sao **reentregues** com a mesma chave idempotente (a cada 3 s, ate 20 vezes) na frente da fila do personagem; ver `docs/E5_GATE.md`.
- Knobs so de teste (exigem `ELDERVALE_TEST_MODE=1`): `--test-hp-mult`, `--test-speed-mult`, `--measure-snapshots`. Nao usar em producao.
