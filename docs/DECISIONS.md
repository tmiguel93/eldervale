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

---

## DEC-0010 — Classes como JSON validado em `data/classes`, catálogo derivado para o backend; habilidades seguem em `.tres` (E6.1)
- **Data:** 2026-11-01
- **Status:** PROPOSTA — aguarda revisão humana (modelo de conteúdo; contrato com o backend)
- **Contexto:** o GDD pede 3 classes (Guerreiro, Mago, Patrulheiro) com 3 especializações cada, "uma classe e uma especialização por classe" no vertical slice, e a arquitetura exige conteúdo data-driven com IDs estáveis e referências validadas (AGENTS §8). O backend precisa conhecer as classes para validar `class_id` e criar o personagem com os stats base certos.
- **Opções consideradas:** (a) `Resource` `.tres` por classe; (b) JSON por classe lido por Godot e pelo backend (como quests, DEC-0006); (c) tabela de classes no banco.
- **Escolha provisória:** (b). `data/classes/<id>.json` (fonte de verdade; `class_id`, recurso stamina/mana, `base_stats`, `growth_per_level`, 4 slots → ids de habilidade, especializações `{id, display_name, tags, planned}`), lido por `ClassDef`/`ClassCatalog`, com `tools/gen_classes_catalog.mjs` gerando `shared/content_schemas/classes.json` (`--check` em testes) e validando referências (habilidade existe em `data/skills`, tipo certo por slot, ataque básico sem custo, habilidade exclusiva por classe, especializações únicas, ao menos uma especialização inicial). As habilidades continuam `SkillData` `.tres` (ganharam campos de projétil e `tags`). Uma especialização inicial por classe (`berserker`, `elementalist`, `hunter`) e as outras 6 `planned: true`, **sem mecânica nem seleção** nesta etapa.
- **Consequências:** adicionar classe/habilidade = dados + regenerar catálogo, sem migração. Dois leitores do mesmo JSON (GDScript e TypeScript) mantidos em paridade por teste. Especialização ainda não é escolhida nem persistida (E6.x: árvore de talentos). `move_speed` por classe existe como stat, mas o `Player` ainda não o consome (movimento segue fixo).
- **Responsável/aprovação:** Proprietário do projeto; aprovação pendente.

---

## DEC-0011 — Classe imutável por personagem em `characters.class_id`; migração 0004 (default + CHECK); stats base na criação (E6.1)
- **Data:** 2026-11-01
- **Status:** PROPOSTA — aguarda revisão humana (schema persistente, regra de economia/progressão)
- **Contexto:** `characters.class_id text NOT NULL` já existia desde a 0001 e a API só aceitava `warrior`. Era preciso aceitar as 3 classes sem quebrar saves (AGENTS §2.12) e sem mexer no formato do estado (`schema_version` 1).
- **Opções consideradas:** (a) nova coluna/tabela de classe; (b) reaproveitar a coluna existente com migração de endurecimento; (c) guardar a classe dentro do `state` do checkpoint.
- **Escolha provisória:** (b). Migração `0004_character_class_default.sql` (aditiva, idempotente): normaliza para `warrior` só ids malformados, `DEFAULT 'warrior'`, `CHECK` de formato de id; a validação contra o catálogo é da aplicação (novas classes não exigem migração). A classe é escolhida **só** na criação (`POST /v1/characters`, validada contra `classes.json`) e nunca muda; fica **fora** do checkpoint (o backend já rejeita campo desconhecido no estado) e chega ao servidor Godot em `GET /internal/characters/:id`. Personagem novo nasce com `characters.stats` = `base_stats` da classe (guerreiro = os stats históricos, então saves existentes não mudam); o crescimento por nível vem da classe no servidor (`PlayerLoadout.apply_class`). Plano de rollback em `backend/migrations/README.md`.
- **Consequências:** não há troca de classe/respec de classe (decisão de produto pendente). Rebalancear `base_stats` de uma classe não altera personagens já criados (valem os stats gravados); o crescimento por nível, sim, vale para todos. `class_id` desconhecido vindo do backend faz o servidor Godot recusar a entrada (`REJECT_NOT_AUTHENTICATED`) em vez de improvisar.
- **Responsável/aprovação:** Proprietário do projeto; aprovação pendente.

---

## DEC-0012 — Habilidades permitidas decididas no servidor por slot fixo + `s_class` aditivo só para o dono (E6.1)
- **Data:** 2026-11-01
- **Status:** PROPOSTA — aguarda revisão humana (contrato de rede e limite de 4 habilidades)
- **Contexto:** o cliente nunca pode decidir habilidades permitidas (AGENTS §2.8, §6). O protocolo v2 tem 4 bits de ação (ataque, skill_1, skill_2, esquiva).
- **Opções consideradas:** (a) mais bits de ação (até 6 habilidades) já agora; (b) manter 4 bits e deixar o servidor resolver cada bit pela classe; (c) o cliente envia `skill_id`.
- **Escolha provisória:** (b). O servidor aplica a classe no join (`PlayerCombat.apply_class`: troca os 4 slots e restringe `try_use` aos ids da classe; recusa `not_allowed` sem custo/cooldown); o cliente continua enviando só bits. Novo RPC aditivo `s_class({class_id})` (reliable, só o dono) alimenta o HUD (`SkillBar`); `VERSION` continua 2 e a máscara de ações (15) não muda — bit desconhecido continua rejeitado. Sem backend (bots/dev) vale `ServerSettings.default_class_id` (`--default-class`, só servidor); o guerreiro mantém os stats da cena (E1–E5 intactos).
- **Consequências:** 4 habilidades por classe nesta etapa (faixa 4–6 do roadmap, no piso); passar disso exige bits novos (aditivos). O RPC novo vale a mesma ressalva de `s_inventory`: servidor e cliente atualizados juntos. O cliente remoto não escolhe nem vê classe de outros jogadores (só a própria).
- **Responsável/aprovação:** Proprietário do projeto; aprovação pendente.

---

## DEC-0013 — Projétil de habilidade como `SkillProjectile` varrido, só no servidor; áreas à distância por `hitbox_offset` (E6.1)
- **Data:** 2026-11-01
- **Status:** PROPOSTA — aguarda revisão humana (combate/rede/apresentação)
- **Contexto:** Mago e Patrulheiro precisam de projéteis e áreas; o servidor roda a física a 30 Hz e o `Hitbox` do E2 é uma área presa ao jogador.
- **Opções consideradas:** (a) reaproveitar `Hitbox` movendo-o; (b) estender o `Projectile` inimigo; (c) novo `SkillProjectile` (Area3D sem polling de overlap) com consulta de forma por sub-passo.
- **Escolha provisória:** (c). `SkillData` ganhou `projectile_speed/range/pierce` e `tags` (projétil = ataque com esfera, `hitbox_size.x` = raio); `PlayerCombat` o cria na fase ACTIVE com dano = ataque × multiplicador calculado no servidor. O movimento é varrido em sub-passos de no máximo o raio (`intersect_shape` na camada `ENEMY_HURT`), então não atravessa alvos a 30 Hz; um `StaticBody` do mundo (raio) o consome; cada alvo leva um golpe por projétil (dedupe por `hit_id`, como o `Hitbox`); `pierce` = alvos adicionais. Áreas (`frost_nova`, `arrow_rain`) são esferas com `hitbox_offset` (a distância). Esquivas/mobilidade (`blink`, `roll`) usam o `DODGE` existente (deslocamento + i-frames).
- **Consequências:** o cliente **não** renderiza projéteis (não são entidades de snapshot): vê só o efeito (vida, números de dano) — apresentação de projétil/áreas fica para quando houver arte/eventos cosméticos. Limite de velocidade 40 m/s e alcance 40 m na validação. Acertos além de `pierce` no mesmo sub-passo são ignorados (ordem de sobreposição). Balanceamento dos números é provisório (sem medição de DPS/uso).
- **Responsável/aprovação:** Proprietário do projeto; aprovação pendente.

---

## DEC-0014 — Árvore de talentos como JSON validado por classe, catálogo derivado para o backend; modificadores de habilidade como dado (E6.2)
- **Data:** 2026-11-01
- **Status:** PROPOSTA — aguarda revisão humana (modelo de dados e balanceamento)
- **Contexto:** a especialização e a árvore precisam produzir builds com resultados diferentes sem tocar nos `.tres` compartilhados das habilidades e sem o cliente decidir nada.
- **Opções consideradas:** (a) talentos em código; (b) mutar o `SkillData` carregado; (c) JSON por classe em `data/talents` + curva em `_progression.json`, agregado por jogador e resolvido em tempo de uso sobre uma cópia.
- **Escolha provisória:** (c). 15 nós por classe (genéricos da classe + nós da especialização inicial; tiers `small`/`notable`, 1 `mastery` por árvore), grafo acíclico com `requires` e `min_points_spent`, `cost` e `max_rank`. Efeitos: `stat` (por rank) ou `skill_mod` (`damage`, `extra_projectiles`, `area`, `duration`, `cost`, `convert`, `condition`, `synergy`). `SkillMods.collect` agrega ao mudar a build; `SkillMods.resolve` roda no `try_use` e devolve uma cópia (`duplicate`) — o recurso compartilhado nunca muda. Bônus de dano somam-se entre si e multiplicam o multiplicador base; custo/cooldown têm piso de 25%, área 25%–300%, extras no máximo 6. `tools/gen_talents_catalog.mjs` valida tudo e gera `shared/content_schemas/talents.json` (`--check`) para o backend; testes comparam Godot x catálogo.
- **Consequências:** `damage_type` (conversão elemental) é gravado no golpe/projétil mas ainda não há resistências por inimigo — o efeito atual da conversão é o bônus de dano. Números são provisórios (sem medição de DPS). Novas classes exigem um arquivo em `data/talents` (o gerador falha se faltar).
- **Responsável/aprovação:** Proprietário do projeto; aprovação pendente.

---

## DEC-0015 — Talentos persistidos só pelo backend (coluna `characters.talents`, migração 0005), aplicação pessimista e custo de respec em itens (E6.2)
- **Data:** 2026-11-01
- **Status:** PROPOSTA — aguarda revisão humana (economia, persistência e janela de duplicação)
- **Contexto:** os talentos valem poder; o checkpoint do servidor de jogo não pode ser caminho para forjá-los, e não existe moeda no jogo.
- **Opções consideradas:** (a) talentos dentro do `state` do checkpoint; (b) tabela própria; (c) coluna jsonb no personagem, alterada apenas por `POST /internal/characters/:id/talents`.
- **Escolha provisória:** (c). Migração `0005_character_talents` (aditiva, idempotente, `DEFAULT '{}'` + CHECK de objeto; rollback documentado). O endpoint trava a linha (`FOR UPDATE`), exige `X-Session-Id` (fencing) e chave reservada `talent:<sessão>:<n>:<personagem>`, é idempotente via `reward_claims` (replay devolve o mesmo resultado; mesma chave com outro conteúdo = 409), valida pontos pelo NÍVEL do banco, pré-requisitos, `max_rank`, classe e especialização, aceita `expected_revision` opcional e grava com `revision + 1`. O checkpoint rejeita o campo `talents` (400/422) e nunca o apaga. O servidor de jogo aplica na memória só DEPOIS da confirmação (pessimista); recusa definitiva do banco não altera nada. **Respec:** custa `scrap_material` x3 (configurável em `_progression.json`) tirados do inventário na mesma transação e só vale em zona segura (hub `sticky`; sem mundo/arena de desenvolvimento vale sempre) — a zona é regra do servidor de sessão, o backend não conhece zona. O custo sai do inventário em memória ANTES de enfileirar (autosave não repõe) e é devolvido se o banco recusar de forma definitiva.
- **Consequências:** janela residual: se o jogo cair entre o respec confirmado e o checkpoint seguinte, o inventário persistido já reflete o custo (o backend o cobrou), então não há duplicação; a janela oposta (itens removidos em memória e backend sem resposta) recarrega o personagem do banco. Nível em memória acima do do banco pode gerar `no_points` do backend (o banco é a verdade). Sem moeda, o custo em item é provisório.
- **Responsável/aprovação:** Proprietário do projeto; aprovação pendente.

---

## DEC-0016 — Protocolo de talentos aditivo (`c_talent_cmd` / `s_talents`), um comando por vez com anti-replay por `req_id` (E6.2)
- **Data:** 2026-11-01
- **Status:** PROPOSTA — aguarda revisão humana (contrato de rede)
- **Contexto:** o cliente precisa pedir alocação/escolha/reset e ver o estado, sem decidir pontos nem stats.
- **Opções consideradas:** (a) enviar o estado desejado; (b) um comando por mensagem com `req_id`; (c) piggyback no snapshot.
- **Escolha provisória:** (b), `VERSION` continua 2. Detalhes e códigos em `shared/contracts/network_protocol.md`. Rate limit próprio (2/s, rajada 4), validação estrita, `busy` enquanto um comando está em voo, estado reenviado só ao dono quando muda (join, comando, nível, recarga).
- **Consequências:** o bônus de vida/ataque chega ao cliente pelo caminho normal (snapshot/HUD), não pelo `s_talents`. Servidor e cliente precisam ser atualizados juntos.
- **Responsável/aprovação:** Proprietário do projeto; aprovação pendente.

---

## DEC-0017 — Instância de item (raridade + affixes) guardada ao lado da base, em `inst jsonb`, migração 0006 (E6.3)
- **Data:** 2026-11-01
- **Status:** PROPOSTA — aguarda revisão humana (modelo de dados e economia)
- **Contexto:** raridades e affixes precisam de identidade por item (`uid`), persistência compatível com saves antigos e nenhum caminho para o cliente ou o checkpoint forjarem poder.
- **Opções consideradas:** (a) tabela própria de instâncias com FK; (b) trocar `item_id` por um id composto; (c) coluna `inst jsonb` NULLable em `character_inventory` e `character_equipment`, com a base ainda em `item_id`.
- **Escolha provisória:** (c). Migração `0006_item_instances` aditiva e idempotente (`IF NOT EXISTS`, CHECK só se ausente, índices únicos parciais por `(character_id, inst->>'uid')`, sem backfill: `NULL` = item simples/Comum). As regras (orçamento, faixas, slots) vivem em `shared/content_schemas/items.json` e são aplicadas pelo backend (`parseInstance`, espelho de `ItemRules.validate_instance`); o banco garante só a forma e a unicidade. Instâncias só nascem em `POST /rewards` com chave `loot:`; o checkpoint apenas as move (`unknown_instance`/`instance_modified`). Rollback documentado em `backend/migrations/README.md` (destrutivo para os affixes: exige backup).
- **Consequências:** cada instância ocupa 1 slot (não empilha); itens com affixes ficam fora de receitas. A unicidade entre inventário e equipamento é checada na transação (não por índice). Se o jogo cair entre o loot coletado e o próximo checkpoint, a recompensa já persistida garante a posse (sem duplicar, pela chave).
- **Responsável/aprovação:** Proprietário do projeto; aprovação pendente.

---

## DEC-0018 — Itens únicos como itens simples (`ItemData`) com efeitos autorados em dado, reaproveitando `SkillMods` e `StatBlock` (E6.3)
- **Data:** 2026-11-01
- **Status:** PROPOSTA — aguarda revisão humana (balanceamento e design dos únicos)
- **Contexto:** os únicos precisam de efeito legível, condição de obtenção e drop em dados, sem sistema paralelo e sem serem obrigatórios.
- **Opções consideradas:** (a) scripts por item; (b) únicos como instâncias com affixes fixos; (c) `ItemData` + `_uniques.json` com `effects[]` no formato `skill_mod` dos talentos e `obtain` (nível mínimo + chance por tabela de loot).
- **Escolha provisória:** (c). Efeito curinga `skill:"*"` mesclado em `PlayerCombat.mods_for` (exceto esquiva), stats fixos no `.tres`. Os 5 únicos são placeholders de teste (3 slots, efeitos de dano condicional, área, custo, projétil, conversão).
- **Consequências:** únicos não rolam affixes e não aceitam instância (validação os recusa). Números provisórios; `damage_type` ainda sem resistências por inimigo (conversão = marcação + dano).
- **Responsável/aprovação:** Proprietário do projeto; aprovação pendente.

---

## DEC-0019 — Equipar pela rede: `c_equip_cmd`/`s_equip` aditivos, `inst`/`equipment_inst` só ao dono, snapshot compacto intacto (E6.3)
- **Data:** 2026-11-01
- **Status:** PROPOSTA — aguarda revisão humana (contrato de rede)
- **Contexto:** o cliente precisa pedir equipar/desequipar e ver os affixes sem decidir nada e sem aumentar o custo por entidade do snapshot.
- **Opções consideradas:** (a) estender o snapshot; (b) enviar a instância em todo evento; (c) comando por índice + base esperada, instância completa só em `s_inventory`/`EVENT_PICKUP` ao dono.
- **Escolha provisória:** (c), `VERSION` continua 2. `c_equip_cmd(req_id, op, index, item_id)` com rate limit (4/s, rajada 8), anti-replay por `req_id`, `busy` com craft/talento em voo, recusas de regra de jogo viram `s_equip(EQUIP_ERROR, code)` sem punir o peer; payload inválido conta como abuso. Limite de 512 bytes por instância (cabe no MTU de `s_inventory` com folga).
- **Consequências:** servidor e cliente devem ser atualizados juntos (mesma ressalva dos RPCs anteriores). O índice é o da pilha no servidor; a base esperada protege contra corrida de inventário.
- **Responsável/aprovação:** Proprietário do projeto; aprovação pendente.

---

## DEC-0020 — Gancho de teste `--loot-test-force <raridade>` (só com `ELDERVALE_TEST_MODE=1`) para integração determinística (E6.3)
- **Data:** 2026-11-01
- **Status:** PROPOSTA — aguarda revisão humana (superfície de teste no servidor)
- **Contexto:** a integração real precisa de um item rolado a cada abate, mas a raridade é probabilística.
- **Opções consideradas:** (a) abater até sair sorte; (b) semente fixa de loot; (c) forçar a raridade e garantir um equipamento por rolagem, mantendo affixes/valores rolados pelo servidor normalmente.
- **Escolha provisória:** (c), no mesmo padrão dos `--test-*` existentes: sem `ELDERVALE_TEST_MODE=1` o argumento é ignorado com aviso e nunca vale em produção. Não toca a validação (a instância forçada é validada como qualquer outra).
- **Consequências:** a integração valida a rolagem real (orçamento/faixas), mas não a distribuição de raridade (coberta pelo teste unitário).
- **Responsável/aprovação:** Proprietário do projeto; aprovação pendente.

