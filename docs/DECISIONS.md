# Registro de decisões

Formato por decisão: ID, data, contexto, opções consideradas, escolha, consequências, responsável/aprovação.

---

## DEC-0001 — Versão da engine Godot 4.7.2-stable
- **Data:** 2026-10-31
- **Status:** VERSÃO VERIFICADA (2026-10-31); export templates pendentes
- **Verificado:** `Godot_v4.7.2-stable_win64_console.exe --version` retornou `4.7.2.stable.official.ed1daf0bf` (informado pelo proprietário).
- **Contexto:** Os binários `Godot_v4.7.2-stable_win64.exe` e `Godot_v4.7.2-stable_win64_console.exe` estão na raiz do projeto. A versão foi inferida apenas do nome dos arquivos. O binário não executa no ambiente Linux usado pelo agente, portanto `--version` não foi rodado.
- **Opções consideradas:**
  1. Fixar 4.7.2-stable com base no nome do binário, pendente de confirmação.
  2. Adiar a fixação até verificar a versão por execução.
- **Escolha:** Registrar 4.7.2-stable como versão-alvo provisória (opção 1), sujeita a confirmação.
- **Consequências:** README e documentação citam 4.7.2-stable como não verificada. Export templates não registrados nem verificados. Se a verificação divergir, atualizar README e este registro.
- **Verificação necessária:** no Windows, executar `Godot_v4.7.2-stable_win64_console.exe --version` e registrar a saída aqui, junto com a versão dos export templates.
- **Responsável/aprovação:** Proprietário do projeto; aprovação pendente.

---

## DEC-0002 — GitHub/Vercel: conexão manual pelo proprietário
- **Data:** 2026-10-31
- **Status:** PROPOSTA
- **Contexto:** O roadmap (seção 8) define que a etapa E0 inclui documentação e Git local, e que a conexão de contas GitHub/Vercel é ação manual do proprietário. A Vercel serve frontend/site/painel e funções HTTP; não hospeda o servidor Godot ENet/UDP.
- **Opções consideradas:**
  1. Agentes configuram GitHub/Vercel (exige credenciais e autorização específica).
  2. Proprietário conecta manualmente as contas; agentes só documentam.
- **Escolha:** Opção 2.
- **Consequências:** Nenhum projeto Vercel, deploy, push ou token é criado/registrado por agentes na E0. O servidor Godot e o PostgreSQL ficam em infraestrutura separada.
- **Responsável/aprovação:** Proprietário do projeto; aprovação pendente.

---

## DEC-0003 — Câmera top-down: ortográfica inclinada como padrão (E1)
- **Data:** 2026-10-31
- **Status:** PROPOSTA — aguarda aprovação visual do proprietário (gate do E1)
- **Contexto:** O E1 exige comparar câmera ortográfica inclinada e perspectiva de baixa distorção e aprovar câmera, escala e unidade de mundo antes de produzir assets.
- **Opções consideradas:**
  1. Ortográfica, yaw 45°, pitch 50°, tamanho 14.
  2. Perspectiva de baixa distorção, FOV 28.
- **Escolha provisória:** Opção 1 como padrão; F3 alterna para a opção 2 na arena de teste.
- **Consequências:** Unidade de mundo 1 = 1 m, personagem ~1,8 m. A comparação NÃO foi observada visualmente pelos agentes (execução headless); a escolha final depende de o proprietário testar no editor.
- **Responsável/aprovação:** Proprietário do projeto; aprovação pendente.

---

## DEC-0004 — Multiplayer: servidor autoritativo por input, protocolo v1 (E3)
- **Data:** 2026-10-31
- **Status:** PROPOSTA — aguarda revisão humana do protocolo (roadmap/AGENTS)
- **Contexto:** E3 exige dois clientes na mesma sessão com validação server-side.
- **Opções consideradas:** (1) cliente envia posição e servidor valida; (2) cliente envia só input e o servidor simula.
- **Escolha provisória:** opção 2 (`shared/contracts/network_protocol.md`), ENet, tick 30 Hz, snapshots 15 Hz.
- **Consequências:** o cliente nunca decide posição/dano; predição local simples com reconciliação. Valores de tick/snapshot ainda não medidos em CPU/banda.
- **Responsável/aprovação:** Proprietário do projeto; aprovação pendente.

---

## DEC-0005 — Backend em Node.js/TypeScript; API deployável como Vercel Functions; PostgreSQL externo (E4)
- **Data:** 2026-10-31
- **Status:** APROVADA pelo proprietário (linguagem); hospedagem do banco pendente
- **Contexto:** A arquitetura previa Go como decisão provisória e exige registrar a escolha antes de implementar autenticação. O addendum Vercel permite API HTTP em Functions, mas mantém PostgreSQL em serviço externo e o servidor Godot (ENet/UDP) fora da Vercel.
- **Opções consideradas:** Go; Node/TypeScript; Python/FastAPI.
- **Escolha:** Node.js 22 + TypeScript (proprietário escolheu). API em handlers Web-standard (`Request` → `Response`), adaptáveis a Vercel Functions e a servidor Node local.
- **Banco:** PostgreSQL. Em dev/teste: PGlite (Postgres em WASM, dentro da pasta do projeto, sem instalar nada no sistema). Produção/staging: Postgres gerenciado (ex.: Neon via Marketplace da Vercel) conectado manualmente pelo proprietário via `DATABASE_URL` (segredo, fora do repositório).
- **Consequências:** mesmas migrações SQL numeradas em todos os ambientes; `node_modules` nativo é por plataforma (rodar `npm ci` no Windows). Nenhum deploy, conta ou segredo é criado por agentes.
- **Responsável/aprovação:** Proprietário do projeto.

---

## DEC-0006 — Quests e diálogo: dados em JSON, estado em coluna jsonb, conclusão atômica com a recompensa (E5.1)
- **Data:** 2026-10-31
- **Status:** PROPOSTA — aguarda revisão humana (contrato de rede e esquema do banco)
- **Contexto:** E5.1 precisa de quests/diálogo data-driven, progresso só por eventos do servidor, recompensa idempotente e persistência por personagem.
- **Opções consideradas:** (a) quests/diálogo como `.tres` vs JSON; (b) estado em tabelas novas vs coluna jsonb em `characters`; (c) conclusão pelo checkpoint vs pela recompensa; (d) subir `Protocol.VERSION` vs extensão aditiva.
- **Escolha provisória:** (a) JSON em `data/quests|dialogues|npcs|areas` (o backend e as ferramentas leem os mesmos arquivos; catálogo derivado em `shared/content_schemas/quests.json`); (b) coluna `characters.quests jsonb` (migração 0003, aditiva): estado pequeno, sempre lido com o personagem, mesma `revision`/lock; (c) `completed` é somente-servidor: só `POST …/rewards` com `quest_id` o altera, na MESMA transação que paga xp/itens (reenvio com a mesma chave devolve o original; chave nova para quest concluída => 409 `quest_already_completed`), e o checkpoint ignora tentativas de concluir/desfazer; (d) 4 RPCs novos sem mudar a versão do protocolo.
- **Consequências:** impossível pagar duas vezes ou concluir sem pagar; o backend valida a recompensa contra o catálogo (`quest_reward_mismatch`). Pré-requisitos não são revalidados no backend (o servidor de sessão é confiável). Remover uma quest do conteúdo faz o jogo descartá-la ao carregar (a conclusão no banco é preservada). Se o inventário estiver cheio na entrega, a quest fica "pronta" no banco e o jogador repete a entrega.
- **Responsável/aprovação:** Proprietário do projeto; aprovação pendente.

---

## DEC-0007 — Mundo de Greenwood: zonas no mesmo espaço físico, modo opt-in, interesse por zona (E5.3)
- **Data:** 2026-10-31
- **Status:** PROPOSTA — aguarda revisão humana (padrão do servidor e contrato de rede)
- **Contexto:** E5.3 precisa de hub/selvagem/ruínas conectados, puzzle cooperativo, transição, respawn e chefe, sem quebrar a arena do E1/E3 nem o protocolo v2.
- **Opções consideradas:** (a) um mundo contínuo vs zonas separadas; (b) um `PhysicsServer` por zona vs um espaço com zonas afastadas; (c) tornar o mundo o padrão vs opt-in; (d) subir `Protocol.VERSION` vs eventos aditivos.
- **Escolha provisória:** (a) zonas ligadas por portais; (b) mesmo espaço físico com zonas a >= 20 m umas das outras (centros 0/200/400 m), pertencimento por jogador/inimigo; hub sempre carregado, demais sob demanda e descarregadas após 12 s vazias; (c) `--world greenwood` opt-in, padrão arena; (d) eventos 8..11 aditivos e snapshots filtrados por zona + raio de 50 m.
- **Consequências:** nenhum RPC novo; arena e testes antigos intactos; puzzle/chefe reiniciam ao descarregar (sem softlock); jogadores de outras zonas não aparecem nos snapshots. Trocar o padrão para o mundo é uma linha em `server_main.gd`.
- **Responsável/aprovação:** Proprietário do projeto; aprovação pendente.

---

## DEC-0008 — Loot individual opt-in e crafting com otimismo + desfazer, sem nova migracao (E5.4)
- **Data:** 2026-10-31
- **Status:** PROPOSTA — aguarda revisão humana (economia, contrato de rede e persistência)
- **Contexto:** E5.4 exige loot por participante, visível só ao dono, coleta idempotente, e crafting server-side atômico.
- **Opções consideradas:** (a) loot individual como padrão vs opt-in; (b) semente pública (`session_seed`) vs privada; (c) craft só após resposta do backend vs otimista com desfazer; (d) nova tabela vs reuso de `reward_claims`.
- **Escolha provisória:** (a) opt-in (`individual_loot`, ligado em `--world` não-arena) para não alterar o comportamento do E2–E4; (b) semente-base privada por servidor (`loot_seed` ou aleatória), RNG por (inimigo, jogador) injetável; (c) o servidor aplica na memória, bloqueia o autosave daquele personagem e enfileira `POST /craft` na fila serializada; recusa definitiva desfaz, resultado desconhecido recarrega do banco; (d) reuso de `reward_claims` (sem migração 0004).
- **Consequências:** sem novos RPCs de coleta; XP passa a ser dado a todo participante elegível no modo individual (antes era só do matador); adds invocados não dão loot/XP no modo individual. Risco residual: desconexão com craft em voo que depois falha deixa o checkpoint final com estado otimista (ver docs/E5_LOOT_CRAFTING.md).
- **Responsável/aprovação:** Proprietário do projeto; aprovação pendente.

---

## DEC-0009 — Snapshot compacto por capacidade, particionado e mesclado no cliente; legado preservado (E5.7)
- **Data:** 2026-11-01
- **Status:** PROPOSTA — aguarda revisão humana (contrato de rede, orçamento de MTU, quantização)
- **Contexto:** o risco alto #1 do gate E5.6: `s_snapshot` legado (Dictionary com chaves string, ~240 B/entidade) chegava a 4912 B (chefe, 4 jogadores) e 4456 B (ruínas) contra um MTU de payload de 1392 B; acima disso o ENet fragmenta `unreliable` e perder um fragmento descarta o snapshot inteiro.
- **Opções consideradas:** (a) só codificação compacta; (b) só particionar o formato legado em várias mensagens; (c) as duas coisas; (d) substituir o `s_snapshot` (subir `VERSION`) vs RPC novo negociado por capacidade; (e) estado compartilhado entre mensagens (tabela de tipos enviada uma vez, deltas) vs partes autocontidas; (f) entregar snapshot parcial vs descartar tick incompleto.
- **Escolha provisória:** (c)+(d)+(e)+(f): `c_caps(caps)` reliable após o welcome; `s_snapshot_c(tick, last_seq, part, parts, blob)` unreliable_ordered para quem declara `CAP_SNAPSHOT_COMPACT`, legado para os demais (`VERSION` continua 2; kill-switch `--compact-snapshots 0`). Blob binário (posição 1 cm `s16` relativa a uma origem por parte, yaw `u16`, hp/max_hp inteiros em varint, `type`/`atk` por índice de tabela *por parte*, `phase`/`atk` só quando != padrão). Cada parte é autocontida (sem estado entre pacotes unreliable, então perda/duplicação/reordenação não corrompem nada). Particiona por orçamento de 1200 B de blob (<= 16 partes); o cliente só entrega o snapshot com todas as partes do tick (parte perdida ⇒ tick descartado, mesma semântica do legado). Interesse (AOI/zona/pickups do dono) segue por peer, aplicado antes de codificar. Só a codificação já dá ~10x (30 entidades: 7216 → 620 B); o particionamento é a garantia de teto (256 entidades = 4 partes, maior mensagem 1236 B <= 1392 B), e custou pouco por reutilizar a mesma estrutura de mensagem.
- **Consequências:** medido: `party` 4912 → 792 B/mensagem e `ruins` 4456 → 400 B, 0 mensagens acima do MTU; erro de posição <= 0,87 cm (abaixo da zona morta de 5 cm da reconciliação), yaw <= 4,8e-5 rad, hp inteiro (vivo nunca vira 0). Custos: dois formatos para manter (o legado só sai quando todos os clientes migrarem — decisão futura); `NetRpc` ganhou 2 RPCs, então servidor e cliente precisam ser atualizados juntos (mesma limitação do `s_inventory`); quantização de hp/posição vale também para a UI de grupo e o BossBar (proporção); mais CPU no servidor para codificar por peer (não medida isoladamente; o harness `party` não apresentou atraso). Não validado em rede real com perda.
- **Responsável/aprovação:** Proprietário do projeto; aprovação pendente.
