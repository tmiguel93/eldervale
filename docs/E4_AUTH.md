# E4 - Autenticacao (M2)

Codigo: `backend/src/auth/` (`password.ts`, `validate.ts`, `tokens.ts`, `service.ts`, `routes.ts`, `verifier.ts`). Testes: `backend/test/auth.test.ts`.

## Fluxo
1. `POST /v1/auth/register {email, password}` -> sempre `202 {"status":"accepted"}` (sem tokens).
2. `POST /v1/auth/login {email, password}` -> `200 {access_token, token_type:"Bearer", expires_in, refresh_token, refresh_expires_in}`.
3. Chamadas autenticadas: `Authorization: Bearer <access_token>` (`GET /v1/account`).
4. `POST /v1/auth/refresh {refresh_token}` -> novos access + refresh; o refresh apresentado e revogado e ligado ao novo (`replaced_by`).
5. `POST /v1/auth/logout {refresh_token}` -> `204`; revoga o token e os sucessores. Idempotente, nao revela se o token existia.
Todas as respostas de auth levam `Cache-Control: no-store`.

## Decisoes
- **Anti-enumeracao no registro:** e-mail novo ou ja existente respondem igual (202) e o hash scrypt e calculado nos dois casos (tempo similar). Sem verificacao de e-mail, nao ha como o cliente saber se a conta ja existia (o dono real descobre ao logar). Alternativa 409 rejeitada: permite listar e-mails cadastrados. Custo: UX pior (quem erra a senha de uma conta existente so descobre no login).
- **Login:** conta inexistente verifica contra um hash descartavel; conta inexistente, senha errada e conta `disabled` dao o mesmo `401 invalid_credentials`.
- **E-mail:** `trim().toLowerCase()` antes do INSERT/consulta; so ASCII (sem IDN), validacao por varredura linear (sem regex), local <=64, total <=254.
- **Senha:** 10..128 caracteres (pontos de codigo), diferente do e-mail, sem regras de composicao. No login so se valida tipo/tamanho (<=1024).

## Hash de senha
`scrypt$1$<log2N>$<r>$<p>$<salt b64url>$<hash b64url>` - v1: N=2^15, r=8, p=1, salt 16 B aleatorio por usuario, chave 32 B (~32 MiB de RAM por hash). Verificacao com `timingSafeEqual`; parametros lidos do hash (teto N<=2^17, r<=16, p<=4 para um registro adulterado nao forcar custo). Apos login valido, hash com parametros abaixo do alvo e regravado (`passwordNeedsRehash`). Nova versao de algoritmo = novo prefixo de versao.

## Tokens
- **Access:** JWT HS256 (`jose`) com `AUTH_SECRET`; claims `sub, iat, exp, jti, iss="eldervale-api", aud="eldervale-access"`. TTL `ACCESS_TOKEN_TTL_SECONDS` (900 s). Verificador aceita so HS256 e exige iss/aud/exp; consulta `accounts.disabled` a cada requisicao (revogacao imediata). Outros JWT que usem o mesmo segredo (join ticket) devem usar `aud` diferente.
- **Refresh:** 32 bytes aleatorios (base64url, 43 chars), guardado so como SHA-256 hex em `refresh_tokens`. TTL `REFRESH_TOKEN_TTL_SECONDS` (30 d), renovado (deslizante) a cada rotacao.
- **Reuso:** token com `revoked_at` ou `replaced_by` reapresentado -> revoga o token e todos os sucessores (cadeia via `replaced_by`, CTE recursiva) e responde 401. Outras sessoes (outros logins) da mesma conta nao sao afetadas. Sem migracao nova (nao ha coluna de familia).
- Refresh de conta `disabled` -> cadeia revogada + 401.

## Rate limiting (token bucket em memoria, `http/rate-limit.ts`)
| Chave | Rajada | Reposicao |
|---|---|---|
| login por IP | 100 | 2/s |
| login por e-mail | 10 | 1 a cada 6 s |
| registro por IP | 30 | 1 a cada 10 s |
| registro por e-mail | 3 | 1 por minuto |
| refresh/logout por IP | 60 | 1/s |
Excedido -> `429` + `Retry-After`. Configuravel via `createAuthRoutes(router, deps, limits)`; `registerAuthRoutes` usa os padroes. Chave de e-mail e um digest SHA-256 truncado. Lockout progressivo NAO implementado.

## Logs
Somente eventos (`auth_login_ok`, `auth_login_failed{reason}`, `auth_refresh_reuse_detected`...) e `account_id`. Nunca senha, hash, token ou e-mail (o logger ainda redige por chave/padrao).

## NAO verificado / riscos conhecidos
- Rate limit e em memoria por instancia: em Vercel (varias instancias, cold starts) so reduz abuso; limite global exige store compartilhado. Sem `TRUST_PROXY=true` todo cliente compartilha o IP "unknown" (limite de IP vira global).
- O bucket por e-mail permite a um atacante bloquear temporariamente o login de uma vitima (10 tentativas rapidas). Trade-off aceito; sem CAPTCHA/lockout por dispositivo.
- Timing: registro/login igualam custo de scrypt, mas nao foi medido estatisticamente; a consulta ao banco difere entre os caminhos.
- Duas requisicoes simultaneas com o mesmo refresh: a segunda e tratada como reuso e revoga a cadeia (estrito; um cliente com retry agressivo perde a sessao). Concorrencia real so testada em PGlite (conexao unica); `FOR UPDATE` nao foi exercitado em Postgres real.
- Rotacao de `AUTH_SECRET` invalida todos os access tokens (sem suporte a multiplas chaves / `kid`).
- Sem verificacao de e-mail, reset de senha, MFA, listagem/revogacao geral de sessoes, nem limpeza de `refresh_tokens` expirados (job futuro).
- scrypt ~32 MiB/hash: dimensionar memoria das Functions; nao testado em Vercel. Argon2id (citado na arquitetura) exigiria dependencia nova.
- Senhas nao sao normalizadas em Unicode (NFC/NFKC).
