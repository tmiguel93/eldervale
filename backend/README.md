# Eldervale backend (M1: fundacao)

Node 22 + TypeScript (DEC-0005). API Web-standard (`Request` -> `Response`), PostgreSQL (PGlite em dev/teste).

## Uso
```bash
cd backend
export npm_config_cache=../.tools/npm-cache   # cache dentro do projeto
npm ci                                        # no Windows: reinstalar (node_modules nao e portavel entre SOs)
npm run typecheck
npm test                                      # PGlite em memoria
npm run migrate                               # DATABASE_URL se definido; senao PGlite em backend/.data/pglite
npm run dev                                   # http://127.0.0.1:8787/v1/health (PORT para mudar)
```
Variaveis: ver `.env.example`. Em `NODE_ENV=production`, `DATABASE_URL`, `AUTH_SECRET`, `GAME_SESSION_INTERNAL_SECRET`
(>=32 chars, distintos) sao obrigatorios. Fora de producao segredos ausentes sao gerados em memoria (tokens invalidam ao reiniciar).

## Estrutura
- `src/config.ts` config validada. `src/app.ts` composition root (`buildApp`). `src/routes.ts` registra os modulos.
- `src/http/` app/router/erros/logger/rate-limit/auth. `src/persistence/` Db, pg, pglite, migrate.
- `src/{auth,characters,parties,sessions}/routes.ts` stubs `registerXRoutes(router, deps)`; `src/auth/verifier.ts` stub do verificador (M2).
- `migrations/` SQL numerado + `README.md` (rollback). `api/[[...path]].ts` adaptador Vercel. `test/` vitest.

## Interface para M2-M4
- `RouteDeps = { config, db, log, now, requireAuth(h), requireInternal(h), clientIp(req) }`.
- Handler: `(ctx) => Response`, `ctx = { req, url, params, requestId, log, auth?, json<T>() }`; erros: `throw new ApiError(status, code, msg)` / `Errors.*`.
- `Db`: `query<T>(sql, params)`, `exec(sql)`, `tx(fn)`, `close()`. Parametros posicionais. bigint volta como string.
- Rate limit: `new RateLimiter({ capacity, refillPerSecond }).take(key)` (estado por processo).
- Detalhes importantes do esquema estao nos comentarios de `migrations/0001_initial_schema.sql` (limite de 4 por party e transacional).

## NAO testado
- Adaptador Vercel (`api/`, `vercel.json`): nao executado na Vercel; sem deploy.
- Driver `pg` contra um PostgreSQL real (testes usam so PGlite; `createPgDb` so passou por typecheck).
- Windows (desenvolvido/validado em Linux). Rate limiter nao e global entre instancias serverless.
- PGlite persistente reabre removendo `postmaster.pid`; em sistemas de arquivos que proibem exclusao a reabertura falha.
