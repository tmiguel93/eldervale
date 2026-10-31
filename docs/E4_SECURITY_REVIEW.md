# E4 — Revisão de segurança e integridade (gate)

Revisor independente, olhar adversarial, código lido de verdade. Padrão: AGENTS.md §6–7 e TECHNICAL_ARCHITECTURE.md §7–§9, §12.
Evidências executáveis: `backend/test/security_review.test.ts` (17 testes) e `tests/e4/test_security_server.gd` (16 checks).
Testes marcados `[ACHADO]` passam enquanto o problema existe; devem ser invertidos ao corrigir.

## Resumo executivo
**Nenhum achado CRÍTICO ou ALTO demonstrável.** As defesas centrais se sustentaram sob ataque: JWT (alg/aud/iss/exp, chaves separadas), refresh com detecção de reuso sob concorrência, todas as rotas `/internal/*` atrás de `requireInternal` (varredura estática + 9 rotas × 6 credenciais), IDOR sempre 404, mass assignment recusado, ticket de uso único, lock único por personagem, limite de party = 4, idempotência de recompensa, SQL 100% parametrizado, segredo interno só por ambiente e nunca em logs, HTTPS exigido (exceto loopback), servidor autoritativo (cliente envia só input).
Os riscos reais são **MÉDIOS** e giram em torno de: (1) rate limit por instância/IP/e-mail, (2) um único segredo interno compartilhado sem *fencing* por sessão, (3) servidor Godot abre em modo dev se faltar `ELDERVALE_BACKEND_URL`, (4) esgotamento de slots ENet sem limite por IP. Devem ser tratados antes de expor à internet (seção "Riscos residuais").
Contagem: CRÍTICO 0 · ALTO 0 · MÉDIO 7 · BAIXO 8 · INFO 6. Nenhum arquivo de produção foi alterado.

## Achados
| # | Sev. | Status | Achado | Local |
|---|---|---|---|---|
| M1 | MÉDIO | aberto | **Lockout dirigido**: o balde `loginEmail` (10 + 10/min) é consumido por tentativas de QUALQUER origem; 10 tentativas ruins bloqueiam o login legítimo (senha correta, outro IP) → 429. Atacante sustenta com ~10 req/min. Teste: "lockout dirigido". Correção: chavear por (e-mail, IP) + balde global por e-mail mais frouxo, ou só contar falhas; backoff por conta. | auth/routes.ts:82 |
| M2 | MÉDIO | aberto | **Sem `TRUST_PROXY` todos dividem o balde "unknown"** (padrão = false): 100 logins/instância e 30 registros (0,1/s) para o mundo inteiro; um atacante esgota e causa DoS de login/registro. Em produção `TRUST_PROXY` precisa ser decisão explícita. Correção: `loadConfig` exigir `TRUST_PROXY` definido em production (ou ler IP do adaptador). | http/rate-limit.ts:78, config.ts:94 |
| M3 | MÉDIO | aberto | `clientIp` usa o **primeiro item de `x-forwarded-for`** quando `x-real-ip` falta; atrás de proxy que apenas anexa, o cliente forja o IP e foge de todos os limites por IP (registro em massa, brute force limitado só pelo e-mail). Correção: ler somente `x-real-ip`/cabeçalho do provedor, ou o ÚLTIMO item confiável. | rate-limit.ts:79 |
| M4 | MÉDIO | aberto | **Sem fencing**: `checkpoint`/`rewards`/`GET` internos não recebem nem verificam `session_id`/lock; um servidor zumbi (partição >30 s, lock tomado por outra sessão) ou qualquer portador do segredo grava no personagem. Perde progresso da sessão legítima (409 de revision); não duplica. Correção: enviar `session_id` e exigir lock ativo da sessão (`character_locks`) nessas rotas. | characters/routes.ts:60-76 |
| M5 | MÉDIO | aberto | **Segredo interno único e confiança total no servidor de jogo**: qualquer servidor pode resgatar tickets/fechar/heartbeat de QUALQUER sessão e conceder até 1 000 000 XP por request e +100 000 XP / +500 itens por checkpoint sem limite de taxa; `stats` aceitam salto (attack_power 10→100000, teste "stats nao tem teto relativo"). Aceitável com 1 servidor confiável; inaceitável com servidores de terceiros. Correção: segredo/credencial por servidor (ligada ao `session_id`), orçamento por janela de tempo, teto relativo de stats (derivar do nível/equipamento no backend). | characters/model.ts:71, limits.ts |
| M6 | MÉDIO | aberto | **Servidor Godot abre em modo dev se a URL do backend faltar** (typo/ambiente vazio): só um `print`; sem ticket, sem persistência. Testes `[ACHADO] segredo presente + URL ausente`. Correção: `--require-backend`/`ELDERVALE_REQUIRE_BACKEND=1` (padrão ligado quando `ELDERVALE_INTERNAL_SECRET` existe) → `quit(2)`. | server_main.gd:96-99, server_backend_config.gd:251 |
| M7 | MÉDIO | aberto | **Slots ENet sem limite por IP**: `create_server(port, max_players + 4)`; 8 conexões ociosas (5 s de `hello_timeout`, reabertas em loop) bloqueiam todos. Nenhum uso de endereço remoto no código. Correção: limite por IP via `get_peer(id).get_remote_address()`, backoff, firewall/anti-DDoS na frente. | server_main.gd:63, server_session.gd:292 |
| B1 | BAIXO | aberto | Lock vencido (sessão morta sem `close`) **impede apagar o personagem** (409 para sempre; `deleteCharacter` ignora vivacidade do lock). Teste "lock vencido". Correção: usar a mesma noção de lock ativo (`activeLock`). | characters/service.ts:149 |
| B2 | BAIXO | aberto | Personagem apagado **permanece em `party_members`** (ocupa vaga, aparece no view). Teste "personagem apagado continua". Correção: remover da party no soft delete. | characters/service.ts:149, parties |
| B3 | BAIXO | aberto | Corrida delete × redeem: redeem não trava a linha do personagem; pode criar lock para personagem recém-apagado (checkpoint depois falha 404). Correção: `FOR SHARE` em `characters` no redeem. | sessions/service.ts:245 |
| B4 | BAIXO | aberto | `/internal/*` roteado publicamente na Vercel (`vercel.json`) e **sem limite/auditoria de falha** de segredo. Segredo ≥32 chars torna força bruta inviável, mas não há log/alerta. Correção: log `warn` + rate limit por IP em `requireInternal`; restringir por rede/WAF. | http/auth.ts:31 |
| B5 | BAIXO | aberto | Rate limiters em memória por instância (serverless): limites efetivos multiplicam por nº de instâncias; evicção de `maxKeys` (10 000) por inundação de e-mails distintos pode zerar o balde da vítima (exige IP forjado, ver M3). | http/rate-limit.ts |
| B6 | BAIXO | aberto | `join_tickets`, `refresh_tokens`, `reward_claims` e convites nunca são limpos (crescimento ilimitado). | migrations |
| B7 | BAIXO | aberto | Cliente aceita `--password` por CLI (visível em `ps`); preferir `ELDERVALE_PASSWORD`/prompt. `HTTPRequest` do cliente mantém redirecionamentos padrão (definir `max_redirects = 0` como no servidor). | client_args.gd, backend_api.gd:159 |
| B8 | BAIXO | aberto | Ping sem limite que gere kick (excesso é descartado em silêncio) e RPC com aridade errada gera log de erro do Godot por chamada (spam de log). | server_session.gd:525 |
| I1 | INFO | — | Senha: 10–128, sem lista de senhas vazadas, sem verificação de e-mail, sem recuperação de conta; access token vale até expirar (15 min) após logout. | auth/validate.ts |
| I2 | INFO | — | scrypt N=2^15,r=8,p=1 (~32 MiB); teto de verificação logN≤17 (hash do banco não força custo arbitrário); conta inexistente usa hash descartável (tempo igualado; o 1º miss paga hash extra uma vez). Pool de threads libuv (4) é o gargalo sob flood; limitado por M2/M3. | auth/password.ts |
| I3 | INFO | — | Reuso estrito de refresh: retry de rede do cliente após rotação bem-sucedida derruba a cadeia (por desenho; documentado no cliente). | auth/service.ts:84 |
| I4 | INFO | — | Ticket: chave HMAC derivada do segredo interno com rótulo `eldervale/join-ticket/v1`, `aud`/`iss` próprios, `jti` só em hash, 1 uso atômico, TTL 60 s; forjar exigiria também a linha em `join_tickets`. Domínio adequado. | sessions/ticket.ts |
| I5 | INFO | — | Fora de production, `NODE_ENV` ausente = development (segredos efêmeros/curtos aceitos, PGlite). Falha fechada (segredo aleatório) mas confirme `NODE_ENV=production` no host. | config.ts:48 |
| I6 | INFO | — | Nomes aceitam qualquer letra Unicode (homóglifos/personificação possível); no jogo o nome exibido é validado ASCII. | characters/model.ts:161 |

## Revisado (leitura de código + teste)
- **A Auth**: scrypt, JWT, refresh/rotação/reuso (8 rotações concorrentes ⇒ ≤1 sucesso, cadeia revogada), rate limits, validação de e-mail (sem regex), logger com redação, mensagens de erro, política de senha.
- **B Autorização**: characters, parties, sessions (404 vs 403, mass assignment, `requireInternal` em 9/9 rotas, comparação `timingSafeEqual`, separação AUTH_SECRET × segredo interno × chave de ticket).
- **C Integridade**: recompensas (10 requests simultâneos, mesma chave ⇒ 1 aplicação; payload diferente ⇒ 409), checkpoint com `revision` + `FOR UPDATE`, ticket de uso único (6 resgates ⇒ 1), duas sessões × um personagem ⇒ 1 lock, party ≤4 sob concorrência, SQL parametrizado, migrações (checksum + advisory lock).
- **D Godot/rede**: `net_rpc.gd`, `protocol.gd` (fuzz: tipos, NaN/inf, 200 KB, controle, BBCode), `server_session.gd` (ações antes de autenticar ⇒ reject; pendente limitado; release tardio), `backend_client/sync`, `server_backend_config` (segredo só por env), `ServerLog.scrub`.
- **E Cliente**: tokens só em memória, HTTPS exigido, validação de URL (12 bypasses), `validate_entity_dict`.
- **F Operacional**: `.gitignore` (`.env*`, `*.pem/key`, `.tools/`), varredura de segredos em `git ls-files` (só `.env.example` vazio e fixtures de teste), `npm audit` (0 vulnerabilidades, prod e dev), versões fixas, licenças em `docs/DEPENDENCIES.md`, headers (nosniff, HSTS, CSP none, no-store), sem CORS.

## NÃO revisado / não verificado
Deploy real na Vercel e PostgreSQL gerenciado (TLS `sslmode`, pool, isolamento real vs PGlite, que serializa transações); exploração de corrupção de memória no ENet/Godot e tamanho máximo de pacote antes da decodificação de `Variant`; DDoS volumétrico UDP; `client_main.gd`/HUD/interpolação além da validação de entidades; conteúdo `.tres`; backups/restauração; reprodução de corridas com Postgres de verdade (testes de concorrência rodam em PGlite). `python3 tools/e4_integration.py`: rodados `badticket` e `nobackendsecret` (OK); `happy|replay|double|crash` não reexecutados nesta revisão.

## Riscos residuais antes de expor à internet
1. M2/M3/M1 (rate limit): definir `TRUST_PROXY` explicitamente, ler IP só de cabeçalho do provedor, mudar chave do balde de login; considerar store compartilhado (serverless).
2. M4/M5: fencing por sessão + orçamento/teto relativo no backend; um segredo por servidor.
3. M6: `--require-backend` obrigatório em produção.
4. M7: limite por IP/firewall para a porta UDP.
5. `/internal/*` restrito por rede ou WAF, com alerta de 401.
6. Rotina de limpeza de tabelas efêmeras e backups testados.

## Checklist de produção
- [ ] `NODE_ENV=production`; `DATABASE_URL` com TLS (`sslmode=require`+); `AUTH_SECRET` ≠ `GAME_SESSION_INTERNAL_SECRET`, ambos ≥32 aleatórios, só no cofre do provedor.
- [ ] `TRUST_PROXY=true` somente atrás da Vercel/proxy que sobrescreve `x-real-ip`; backend não acessível direto.
- [ ] Migrações via `npm run migrate` como etapa separada; backup antes.
- [ ] Servidor Godot: `ELDERVALE_BACKEND_URL` https, `ELDERVALE_INTERNAL_SECRET` por ambiente, nunca CLI; confirmar log "ticket OBRIGATORIO" no boot.
- [ ] Firewall: UDP só da porta do jogo; `/internal/*` por allowlist.
- [ ] Rotação de segredos documentada (trocar o rótulo do ticket invalida tickets).
- [ ] `npm audit` e testes (`npm test`, `run_tests.gd`, harness e2e) verdes no CI antes de cada deploy.
