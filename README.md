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
- Godot `4.7.2-stable` win64 (`Godot_v4.7.2-stable_win64.exe` e `Godot_v4.7.2-stable_win64_console.exe`, guardados FORA da pasta do projeto, por exemplo `D:\Godot\` (o gerenciador do Godot recusa importar um projeto na mesma pasta do executável)).
  - Versão **inferida do nome do binário**, ainda **não verificada por execução** (ver DEC-0001 em `docs/DECISIONS.md`).
  - Export templates: ainda não registrados nem verificados.
- Git (configuração local; conexão com GitHub é manual, ver abaixo).

## Estrutura do repositório
- `GDD_MASTER.md`, `AGENTS.md`, `CLAUDE.md`, `TECHNICAL_ARCHITECTURE.md`, `IMPLEMENTATION_ROADMAP.md`, `VERCEL_CLAUDE_GITHUB_ADDENDUM.md` — documentos-base.
- `docs/` — documentação do projeto:
  - `docs/CONVENTIONS.md` — convenções de branch, commit e código.
  - `docs/DECISIONS.md` — registro de decisões.
  - `docs/ASSET_CREDITS.md` — créditos e licenças de assets.
- Binários do Godot: mantenha fora desta pasta (`*.exe` já é ignorado pelo git).

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

## Controles
Cliente de jogo (`scenes/client/client_boot.tscn`, ver `docs/E3_CLIENT.md` e `docs/E5_UI.md`):

| Tecla | Ação |
|---|---|
| W A S D | mover |
| Mouse 1 | ataque |
| Q / E | habilidades 1 / 2 |
| Espaço | esquiva |
| **F** | interagir: falar com o NPC ou usar a bancada de crafting próxima (`interact`; E já é a habilidade 2) |
| **J** | diário de quests |
| **I** | inventário e equipamento (E6.3: Enter equipa o item do cursor; 1/2/3 desequipa arma/armadura/amuleto; a cor do nome mostra a raridade e o detalhe lista os affixes) |
| **K** | talentos: escolher especialização, gastar pontos, resetar (Cima/Baixo navegam, Enter aloca, S especialização, R reset com dois toques) |
| **M** | mapa grande da zona (o minimapa fica sempre no canto superior direito) |
| Cima / Baixo, Enter | navegar e confirmar nos painéis (diálogo também aceita 1-9) |
| Del (no diário) | abandonar a quest selecionada (pede confirmação com um segundo toque) |
| Esc | fecha o painel aberto (no diálogo, avisa o servidor) |

As **habilidades dependem da classe** do personagem (E6.1: Guerreiro, Mago ou Patrulheiro; escolhida ao criar o personagem na tela de login). As teclas acima
valem para todas as classes (Mouse 1 = ataque básico, Q/E = habilidades, Espaço = esquiva/mobilidade); a barra no canto inferior direito mostra as habilidades da classe.
Servidor de desenvolvimento sem backend: `--default-class mage|ranger|warrior` (padrão `warrior`; só no servidor). Detalhes em [`docs/E6_CLASSES.md`](docs/E6_CLASSES.md).
A **árvore de talentos** (E6.2, tecla K) dá 1 ponto por nível a partir do 2; o servidor valida tudo e o banco guarda a build. Detalhes em [`docs/E6_TALENTS.md`](docs/E6_TALENTS.md).

**Itens com raridade e affixes** (E6.3): o servidor rola os affixes ao dropar, o banco persiste a instância e itens únicos de teste têm efeito próprio. Detalhes em [`docs/E6_ITEMS.md`](docs/E6_ITEMS.md).

Com um painel aberto o cliente não envia ataque/habilidade/esquiva (clicar em botão não ataca); o movimento continua.

## Documentação adicional
- Convenções: [`docs/CONVENTIONS.md`](docs/CONVENTIONS.md)
- Decisões: [`docs/DECISIONS.md`](docs/DECISIONS.md)
- Créditos de assets: [`docs/ASSET_CREDITS.md`](docs/ASSET_CREDITS.md)

## GitHub e Vercel (ações manuais do proprietário)
A conexão com GitHub e Vercel é feita manualmente pelo proprietário; agentes não criam projeto Vercel, deploy ou push sem autorização. O servidor Godot multiplayer (ENet/UDP) **não** vai na Vercel.

## E1 — Arena de teste
- Abrir `scenes/arena/test_arena.tscn` no editor e executar (F6). Controles: WASD move, F2 alterna qualidade, F3 alterna câmera ortográfica/perspectiva.
- Testes headless: `Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/run_tests.gd`
- Detalhes: `docs/E1_ARENA.md` e `docs/E1_CAMERA_PLAYER.md`. Decisão de câmera: DEC-0003 (pendente de aprovação).

## Observação
O nome Eldervale é provisório. A arquitetura e os prazos são propostas iniciais e devem ser validados por protótipos. Não há código de jogo implementado neste pacote.

## Claude Code, GitHub e Vercel
- `CLAUDE.md` contém instruções curtas específicas para Claude Code.
- `VERCEL_CLAUDE_GITHUB_ADDENDUM.md` contém links oficiais, passos de conexão e limites de uso da Vercel.
- A Vercel será usada para o frontend/site/painel web. O servidor multiplayer Godot/ENet e o PostgreSQL ficam fora da Vercel.
