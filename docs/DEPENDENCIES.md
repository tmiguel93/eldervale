# Dependencias do backend (`backend/`)

Versoes EXATAS (sem `^`/`~`), travadas em `backend/package-lock.json`. Todas open-source; nenhuma com modulo nativo
(`node_modules` e portavel, mas rode `npm ci` na maquina de destino, ex.: Windows). Nenhum framework web.

| Pacote | Versao | Licenca | Tipo | Uso |
|---|---|---|---|---|
| typescript | 7.0.2 | Apache-2.0 | dev | typecheck/build |
| vitest | 5.0.5 | MIT | dev | testes |
| tsx | 4.23.15 | MIT | dev | executar TS (dev-server, migrate) |
| @types/node | 22.20.5 | MIT | dev | tipos (Node 22, DEC-0005) |
| @types/pg | 8.23.1 | MIT | dev | tipos do driver |
| pg | 8.23.1 | MIT | runtime | driver PostgreSQL (JS puro) |
| @electric-sql/pglite | 0.5.14 | Apache-2.0 (+ PostgreSQL License no core) | runtime | Postgres em WASM para dev/teste |
| jose | 6.2.14 | MIT | runtime | JWT (uso: M2) |

Licencas conferidas no `package.json` de cada pacote instalado. Dependencias transitivas nao foram auditadas
individualmente (`npm audit` no momento da instalacao: 0 vulnerabilidades). Hash de senha: `node:crypto` scrypt (M2), sem pacote extra.
