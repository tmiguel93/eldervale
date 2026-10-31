# E4 - Party, sessoes, join tickets, locks e reconexao (M4)

Codigo: `backend/src/parties/`, `backend/src/sessions/`. Testes: `backend/test/{parties,sessions}.test.ts` (+ `m4_harness.ts`).

## Fluxo ponta a ponta
1. **Login** (M2) -> Bearer de acesso. 2. **Party** (opcional): `POST /v1/parties` -> convites -> `join`.
3. Servidor Godot sobe e **registra** a sessao: `POST /internal/sessions` -> `session_id`; passa a enviar **heartbeat**.
4. Cliente: `POST /v1/sessions/:id/join-ticket {character_id}` -> `{ticket, expires_at, session{endpoint,...}}` (ticket vale `JOIN_TICKET_TTL_SECONDS`, 60 s).
5. Cliente conecta por ENet e envia o ticket (campo a definir no `c_hello`, ver pendencias) ao servidor.
6. Servidor: `POST /internal/tickets/redeem {ticket, session_id}` -> `{character_id, account_id, session_id, reconnected}`; lock adquirido. Carrega o personagem e joga.
7. Queda do peer: servidor chama `POST /internal/characters/:id/disconnect {session_id}` (personagem fica em estado seguro; lock mantido por `RECONNECT_WINDOW_SECONDS`, 90 s).
8. **Reconexao**: o cliente pede NOVO ticket (`join-ticket`, mesma sessao) e o servidor resgata de novo; `reconnected=true` e `reconnect_until` e limpo. O ticket antigo e de uso unico e nao serve.
9. Logout/checkpoint final: `POST /internal/characters/:id/release {session_id}`. Encerrando o servidor: `POST /internal/sessions/:id/close` (libera todos os locks).

## Contrato HTTP interno (Authorization: Bearer GAME_SESSION_INTERNAL_SECRET; sem segredo => 401)
| Rota | Corpo | Resposta / erros |
|---|---|---|
| `POST /internal/sessions` | `{region [a-z0-9-]{2,32}, capacity 1..64, protocol_version, endpoint "host:porta"}` | 201 `{session_id, status, heartbeat_timeout_seconds, reconnect_window_seconds}`; 400 `unsupported_protocol` |
| `POST /internal/sessions/:id/heartbeat` | - | 200 `{locks_refreshed}`; grava `game_sessions.heartbeat_at` (revive sessao que passou do timeout, se nao foi fechada); 404; 409 `session_closed` |
| `POST /internal/sessions/:id/close` | - | 200 (idempotente) `{locks_released}`; 404 |
| `POST /internal/tickets/redeem` | `{ticket, session_id}` | 200 `{character_id, account_id, session_id, reconnected}`; 401 (expirado/adulterado/outra sessao/sem registro, indistinguiveis); 409 `ticket_already_used`, `character_locked`, `character_already_connected`, `session_full`, `session_unavailable` |
| `POST /internal/characters/:id/disconnect` | `{session_id}` | 200 `{reconnect_until}` (idempotente, nao estende); 404 sem lock ativo; 409 `lock_held_by_other_session` |
| `POST /internal/characters/:id/release` | `{session_id}` | 200 `{released: bool}` (so libera lock da propria sessao) |

Publico (Bearer de usuario; recurso alheio => 404): `GET /v1/sessions?region=` (abertas, vivas e com vaga; max 50; `{sessions:[{id, region, capacity, free_slots, protocol_version, endpoint}]}`; protocolo nao suportado e sem endpoint ficam fora; vaga = capacity - locks ativos, inclusive em janela de reconexao; rate limit 20 de rajada, 1/s por conta), `POST /v1/parties`, `GET /v1/parties/:id`, `POST /v1/parties/:id/{invites,join,leave,kick}`, `POST /v1/sessions/:id/join-ticket`.
Se o resgate falha por 409 (lock/cheia), o ticket NAO e consumido (a transacao reverte) e pode ser tentado de novo ate expirar.

## Regras e decisoes
- **Party**: limite 4 transacional (`SELECT ... FOR UPDATE` na linha da party + contagem). Uma conta tem no maximo UM personagem por party (`account_already_in_party`). Convite expira em `PARTY_INVITE_TTL_SECONDS` (300 s); um pendente por (party, alvo); convite expirado e marcado `expired` ao convidar de novo. Convite de outra party/alvo = 404. `leave` do lider: lideranca vai ao membro mais antigo (`joined_at`, desempate por `character_id`); sem membros a party e dissolvida (`disbanded_at`, convites pendentes `revoked`). Kick: so lider, nao pode expulsar a si (usar `leave`). Respostas nao expoem `account_id`.
- **Ticket**: JWT HS256 (jose), claims `jti, sub=character_id, sid=session_id, iss=eldervale-backend, aud=eldervale-game-session, iat, exp`. Chave = `HMAC-SHA256(GAME_SESSION_INTERNAL_SECRET, "eldervale/join-ticket/v1")`. Banco guarda so `sha256(jti)`. Uso unico via `UPDATE ... WHERE used_at IS NULL AND expires_at > now` na mesma transacao que trava a linha da sessao.
- **Sessao viva** = nao fechada, status open/starting/full e `game_sessions.heartbeat_at` dentro do timeout (migracao `0002_game_sessions_heartbeat.sql`; registro e cada heartbeat gravam a coluna). Sessao morta nao emite tickets, nao resgata, nao entra na lista e seus locks contam como expirados, mesmo sem `close`.
- **Lock ativo** = heartbeat do lock recente (< `SESSION_HEARTBEAT_TIMEOUT_SECONDS`, 30 s) E (`reconnect_until` nulo ou futuro) E sessao nao encerrada. Avaliado "lazy" em cada emissao/resgate/disconnect; nao ha job de limpeza. Lock vencido e tomado por UPDATE no resgate. A janela de reconexao so vale enquanto o servidor segue enviando heartbeat.
- **Capacidade**: locks ativos (inclui quem esta em janela de reconexao) < `capacity`; checada na emissao (conselho) e no resgate (definitiva).
- **Party x sessao**: se algum companheiro tem lock ativo em alguma sessao e nenhum esta na sessao pedida => 409 `party_in_other_session`.
- Rate limit por conta: tickets 10 de rajada, 0,5/s; convites 30, 0,5/s (em memoria por instancia). Nenhum ticket/jti e logado; erros sem stack.
- Env opcionais (lidos so por M4, sem tocar `config.ts`): `SESSION_HEARTBEAT_TIMEOUT_SECONDS`, `PARTY_INVITE_TTL_SECONDS`.

## NAO verificado / limites
- Testes rodam so em PGlite (conexao unica): a concorrencia de `FOR UPDATE`/resgate esta provada logicamente, mas NAO contra PostgreSQL real com conexoes paralelas.
- Servidor Godot/cliente nao integrados: `c_hello` em `network_protocol.md` nao tem campo de ticket; precisa de revisao do contrato (E3) antes de usar.
- Expulsar/sair da party nao derruba a sessao do personagem. Selecao/matchmaking de sessao (qual `session_id` pedir) fica fora deste modulo.
- Rate limiter nao e global entre instancias serverless.
