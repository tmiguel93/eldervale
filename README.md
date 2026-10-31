# Eldervale — Pacote de implementação

Este pacote contém os quatro documentos-base para iniciar o desenvolvimento.

## Arquivos
- `GDD_MASTER.md` — visão, gameplay, conteúdo e escopo.
- `AGENTS.md` — regras permanentes para Claude Code e Codex.
- `TECHNICAL_ARCHITECTURE.md` — cliente, servidor, rede, backend e persistência.
- `IMPLEMENTATION_ROADMAP.md` — fases, tarefas e critérios de aceite.

## Como começar
1. Crie um repositório Git vazio.
2. Copie estes arquivos para a raiz.
3. Abra Claude Code ou Codex na raiz.
4. Envie o prompt de início E0 que está no final de `IMPLEMENTATION_ROADMAP.md`.
5. Não autorize E1 até revisar os critérios de aceite de E0.

## Requisitos
- Godot `4.7.2-stable` win64 (`Godot_v4.7.2-stable_win64.exe` e `Godot_v4.7.2-stable_win64_console.exe`, na raiz do repositório local).
  - Versão **inferida do nome do binário**, ainda **não verificada por execução** (ver DEC-0001 em `docs/DECISIONS.md`).
  - Export templates: ainda não registrados nem verificados.
- Git (configuração local; conexão com GitHub é manual, ver abaixo).

## Estrutura do repositório
- `GDD_MASTER.md`, `AGENTS.md`, `CLAUDE.md`, `TECHNICAL_ARCHITECTURE.md`, `IMPLEMENTATION_ROADMAP.md`, `VERCEL_CLAUDE_GITHUB_ADDENDUM.md` — documentos-base.
- `docs/` — documentação do projeto:
  - `docs/CONVENTIONS.md` — convenções de branch, commit e código.
  - `docs/DECISIONS.md` — registro de decisões.
  - `docs/ASSET_CREDITS.md` — créditos e licenças de assets.
- `Godot_v4.7.2-stable_win64*.exe` — binários da engine (a tratar no `.gitignore`).

## Comandos (a partir da raiz, no Windows)
Abrir o editor:
```
Godot_v4.7.2-stable_win64.exe --path . --editor
```
Importar o projeto em modo headless:
```
Godot_v4.7.2-stable_win64_console.exe --headless --path . --import
```
Executar o projeto e encerrar após 2 frames:
```
Godot_v4.7.2-stable_win64_console.exe --headless --path . --quit-after 2
```
Confirmar a versão da engine:
```
Godot_v4.7.2-stable_win64_console.exe --version
```
Estes comandos dependem do `project.godot` (etapa E0, módulo M2) e ainda não foram executados/validados.

## Documentação adicional
- Convenções: [`docs/CONVENTIONS.md`](docs/CONVENTIONS.md)
- Decisões: [`docs/DECISIONS.md`](docs/DECISIONS.md)
- Créditos de assets: [`docs/ASSET_CREDITS.md`](docs/ASSET_CREDITS.md)

## GitHub e Vercel (ações manuais do proprietário)
A conexão com GitHub e Vercel é feita manualmente pelo proprietário; agentes não criam projeto Vercel, deploy ou push sem autorização. O servidor Godot multiplayer (ENet/UDP) **não** vai na Vercel.

## Observação
O nome Eldervale é provisório. A arquitetura e os prazos são propostas iniciais e devem ser validados por protótipos. Não há código de jogo implementado neste pacote.

## Claude Code, GitHub e Vercel
- `CLAUDE.md` contém instruções curtas específicas para Claude Code.
- `VERCEL_CLAUDE_GITHUB_ADDENDUM.md` contém links oficiais, passos de conexão e limites de uso da Vercel.
- A Vercel será usada para o frontend/site/painel web. O servidor multiplayer Godot/ENet e o PostgreSQL ficam fora da Vercel.
