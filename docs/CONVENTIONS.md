# Convenções de Git — Eldervale

Baseado em `AGENTS.md`, seção 10.

## Branches
- `main` é protegida: sem push direto, sem force push.
- Trabalho em branches curtas a partir de `main`:
  - `feat/<assunto>` — nova funcionalidade
  - `fix/<assunto>` — correção de bug
  - `docs/<assunto>` — documentação
  - `test/<assunto>` — testes
  - `refactor/<assunto>` — refatoração dentro do escopo
  - `build/<assunto>` — build, CI, configuração
- Nomes em minúsculas, com hífens (ex.: `feat/boot-scene`).

## Commits
Prefixos: `feat:`, `fix:`, `test:`, `docs:`, `refactor:`, `build:`.
Mensagem curta, no imperativo, descrevendo o que mudou (ex.: `docs: adiciona convenções de git`).

## Regras
- Nenhum agente faz commit automaticamente; só quando o proprietário solicitar.
- Proibido sem autorização: `reset --hard`, `clean -fd`, force push, apagar branches.
- Não versionar `.godot/`, builds/exports, executáveis da engine, caches, logs, segredos (`.env*`, `*.pem`, `*.key`, `secrets/`) nem arquivos locais.
- Arquivos `*.import` da Godot são versionados.
- Manter o `.gitignore` atualizado.
