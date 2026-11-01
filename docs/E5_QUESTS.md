# E5.1 — Quests e diálogo

Módulo data-driven de quests e diálogo, servidor autoritativo. Sem UI: o cliente expõe sinais/API. Decisão registrada como proposta em `docs/DECISIONS.md` (DEC-0006).

## Princípios
- O progresso **só** avança por eventos do servidor (`kill`, item coletado, área, fala). Não existe RPC que conceda progresso ou recompensa; o cliente só envia comandos (aceitar/abandonar/entregar, abrir/escolher/fechar diálogo).
- Estados: `unavailable`, `available`, `active`, `ready` (derivado: todos os objetivos completos; não persistido), `completed`.
- Máximo de 10 quests ativas (`QuestTracker.MAX_ACTIVE`; backend `CHARACTER_MAX_ACTIVE_QUESTS`, 1..50). Abandonar zera o progresso. Recompensa única por quest.
- Conclusão e pagamento são atômicos no backend (mesma transação). Chave idempotente `quest:<quest_id>:<character_id>`.

## Formato dos dados
Esquemas: `shared/content_schemas/{quest,dialogue,npc,area}.schema.json`. Catálogo derivado: `shared/content_schemas/quests.json` (gerado por `node tools/gen_quests_catalog.mjs`; `--check` roda também no vitest). O gerador valida estrutura e referências cruzadas (itens, inimigos, NPCs, áreas, pré-requisitos, ciclos).
- `data/quests/<id>.json`: `type` (story, hunt, gather, exploration, dungeon, ...), `giver_npc`, `turn_in_npc`, `prerequisites{quests,min_level}`, `objectives[{id,type,target,required}]` com tipos `kill` (id de inimigo), `collect` (id de item), `reach_area` (id de área), `talk` (id de NPC), `rewards{xp,items[{item_id,qty}]}`, `abandonable`, textos com `*_key` para localização. Arquivos que começam com `_` são ignorados (`_pending_refs.json`).
- `data/dialogues/<id>.json`: `entries[{if?,node}]` escolhe o nó inicial (primeira condição verdadeira; a última é o fallback), `nodes{id:{speaker,text,text_key,on_enter?,choices?}}`. Nó sem `choices` é terminal. Condições: `{quest,state}`, `{min_level}`, `all`/`any`/`not` (profundidade máx. 4). Efeitos: `accept_quest`, `turn_in_quest` (exigem o NPC certo e proximidade; erro `wrong_npc`/`too_far`).
- `data/npcs/<id>.json` e `data/areas/<região>.json`: posições e raios usados pelo servidor para validar distância e entrada em área. Posições de Greenwood são as reais do mundo E5.3 (ver `docs/E5_WORLD.md`).

## Código (Godot)
- `scripts/quests/`: `QuestDef`, `QuestState`, `QuestCatalog`, `QuestTracker` (regras puras, sinais `quest_accepted`, `objective_progressed`, `quest_ready`, `quest_completed`, `quest_abandoned`), `QuestService` (cola do servidor), `NpcDirectory`, `AreaSet`/`AreaWatcher`, `ClientQuestLog` (espelho somente leitura para a UI).
- `scripts/dialogue/`: `DialogueCondition`, `DialogueDef`, `DialogueCatalog`, `DialogueRunner` (puros e testáveis).
- Rede: `Protocol` (`QUEST_*`, `DIALOGUE_*`, `validate_quest_cmd`, `validate_dialogue_cmd`), `NetRpc` (4 RPCs), contrato em `shared/contracts/network_protocol.md` (extensão E5.1, `VERSION` continua 2).
- Servidor: `ServerSession` cria o `QuestService`, anexa/desanexa por peer, rate limit (`quest_rate_per_sec=5`, `quest_burst=10`), abuso conta como inválido. `ServerWorld.player_killed_enemy(killer_id, enemy_id, enemy_type)` alimenta `kill`; ganhos de item (`persist_drops`) alimentam `collect`; `tick()` verifica áreas a cada 5 ticks.
- Cliente: `ClientSession.quest_log`, `dialogue_view`, `quest_accept/abandon/turn_in`, `dialogue_open/choose/close`, sinais `dialogue_changed`, `dialogue_error`.
- Persistência: `CharacterCodec` (`quests` em validate/apply/capture; restauração leniente: ids desconhecidos descartados, progresso limitado a `[0, required]`).

## Backend
- Migração `0003_character_quests.sql`: `characters.quests jsonb NOT NULL DEFAULT '{}'` (rollback em `backend/migrations/README.md`).
- `backend/src/quests/{catalog,state}.ts`: catálogo (cruza com itens), validação do estado, `mergeCheckpointQuests`, `completeQuest`.
- Checkpoint: `state.quests` opcional (ausente = mantém o do banco); validado (ids/objetivos conhecidos, progresso inteiro `0..required`, limite de ativas, sem conclusão+ativa). `completed` é **somente-servidor**: o checkpoint não conclui nem desfaz. Exige `X-Session-Id` como antes. `revision` e concorrência otimista inalteradas.
- Recompensa: `POST /internal/characters/:id/rewards` aceita `quest_id`; exige `idempotency_key = quest:<quest_id>:<character_id>` e xp/itens **idênticos ao catálogo**. Erros: `unknown_quest` (400), `quest_reward_mismatch` (400), `invalid_idempotency_key` (400), `quest_already_completed` (409), `inventory_full` (409, nada aplicado, chave não consumida), `idempotency_key_reuse` (409). Replay devolve o resultado original (`replayed:true`) sem reaplicar. Vistas pública/interna expõem `quests`.

## Quests de Greenwood (5)
| id | tipo | objetivos | pré-requisitos | recompensa |
|---|---|---|---|---|
| `gw_welcome` | story | falar com `npc_hunter_brannoch` | — | 60 xp, `potion_minor` x2 |
| `gw_clear_clearing` | hunt | matar `melee_grunt` x5 | gw_welcome | 150 xp, `scrap_material` x3 |
| `gw_scrap_for_orla` | gather | coletar `scrap_material` x6 | gw_welcome | 120 xp, `potion_minor` x3 |
| `gw_ruins_expedition` | exploration | chegar a `area_ruins_gate` e `area_ruins_hall` | gw_clear_clearing, nível 2 | 200 xp, `potion_minor` x2 |
| `gw_ruin_guardian` | dungeon | matar `ranged_caster` x3 e `blight_treant` x1 | gw_ruins_expedition, nível 3 | 500 xp, `amulet_vigor` x1, `potion_minor` x3 |

## Ids referenciados / novos
- Inimigos existentes: `melee_grunt`, `ranged_caster`. `ruin_guardian` foi resolvido no E5.3: `gw_ruin_guardian` mata `blight_treant` (chefe existente); `data/quests/_pending_refs.json` está sem pendências.
- Itens existentes (nenhum novo): `potion_minor`, `scrap_material`, `amulet_vigor`.
- NPCs novos (posições reais no hub): `npc_elder_orla`, `npc_hunter_brannoch`, `npc_scholar_ilmar`. Áreas novas (nas ruínas): `area_ruins_gate`, `area_ruins_hall`. Diálogos: `dlg_elder_orla`, `dlg_hunter_brannoch`, `dlg_scholar_ilmar`.

## Testes
- Godot: `tests/e5_quests/` (conteúdo, tracker, diálogo, protocolo/rede/cliente, servidor com backend falso). O runner aceita `-- --only=<trecho do caminho>` para rodar em partes (ex.: `--only=tests/e5_quests`).
- Backend: `backend/test/quests.test.ts` (catálogo, validação, persistência/monotonia, recompensa, replay, concorrência, fencing). `migrate.test.ts` atualizado para 3 migrações.

## Limitações conhecidas
- Crédito de abate só para quem deu o golpe final; `collect` só conta ganhos após aceitar a quest e apenas com `persist_drops` ligado.
- O aceite persiste por checkpoint imediato; o progresso por abate persiste pelo autosave (30 s) — um crash perde até esse intervalo.
- Pré-requisitos e nível não são revalidados no backend.
- Se a entrega falhar por `inventory_full` no backend, memória e banco divergem até a próxima carga: a quest volta a "pronta" e o jogador repete a entrega.
- Posições de NPC/áreas são as reais do E5.3; o export deve incluir `res://data/**/*.json` (filtro de export).
