# E6.4 — Quests, exploração/segredos e validador de conteúdo

Estado: implementado e validado (ver "Testes"). Decisões em `docs/DECISIONS.md` (DEC-0021 a DEC-0025, propostas pendentes de aprovação). Protocolo em `shared/contracts/network_protocol.md` ("Extensão E6.4").

## 1. Arco de quests (12 quests)
Todas em `data/quests/`, nas zonas existentes (hub, wild, ruínas). Recompensa sempre do servidor via `reward_claims` com chave `quest:<quest_id>:<personagem>` (única por personagem).

| Quest | Tipo | Pré-requisitos (quests / nível) | Objetivos | Recompensa |
|---|---|---|---|---|
| `gw_welcome` | story | - / 1 | falar com Brannoch | 60 xp, 2x poção |
| `gw_scrap_for_orla` | gather | welcome / 1 | coletar 6 sucata | 120 xp, 3x poção |
| `gw_clear_clearing` | hunt | welcome / 1 | matar 5 `melee_grunt` | 150 xp, 3x sucata |
| `gw_wild_survey` | exploration | welcome / 1 | descobrir `poi_wild_fallen_oak` e `poi_wild_old_milestone` | 180 xp, 2x poção |
| `gw_bench_lessons` | side | scrap / 1 | craftar 2x poção menor (bancada) | 140 xp, 4x sucata |
| `gw_whispers` | story | wild_survey / 1 | falar com Lysa e Ilmar | 160 xp, poção x2, sucata x2 |
| `gw_shaman_roots` | hunt | whispers / 2 | matar 1 `grove_shaman` e 2 `burrow_lurker` | 260 xp, `armor_leather` |
| `gw_thorn_hunt` | hunt | clear_clearing / 3 | matar 2 `bow_scout` e `thorn_alpha` | 320 xp, **`sword_rare`** (raro E6.3), poção x2 |
| `gw_ruins_expedition` | exploration | clear_clearing / 2 | chegar a `area_ruins_gate` e `area_ruins_hall` | 200 xp, poção x2 |
| `gw_ruin_guardian` | dungeon | ruins_expedition / 3 | matar 3 `ranged_caster` e o `blight_treant` | 500 xp, `amulet_vigor`, poção x3 |
| `gw_ruin_secrets` | hidden | ruins_expedition / 2 | descobrir 3 segredos das ruínas | 280 xp, `armor_heavy` |
| `gw_rootsong` | main | guardian + shaman_roots + thorn_hunt / 4 | falar com Ilmar, coletar 4 sucata | 700 xp, **`unique_featherknot`** (único E6.3), poção x3 |

Cadeia: `welcome` abre três ramos (limpeza -> caça/expedição -> ruínas; sobrevivência -> sussurros -> raízes; sucata -> bancada). `rootsong` fecha o arco e exige os três ramos. Tipos de objetivo usados: `kill`, `collect`, `reach_area`, `talk`, `craft`, `discover`.

NPCs novos (`data/npcs/`, com diálogos em `data/dialogues/`): `npc_smith_dorran` e `npc_mapper_pell` (hub), `npc_warden_lysa` (wild). Os diálogos de Orla, Brannoch e Ilmar ganharam ofertas/entregas das novas quests. `data/areas/world/greenwood_world.json` lista os NPCs por zona.

### Objetivos novos
- `craft`: alvo = item produzido na bancada; `CraftingService` emite o sinal `crafted` e `QuestService.on_crafted` soma a quantidade (só quests ativas; sem retroatividade).
- `discover`: alvo = `poi_id`; `required` = 1. Se o ponto já foi descoberto ao aceitar a quest, conta na hora (descoberta é única por personagem).

## 2. Exploração e segredos
Dados: `data/exploration/greenwood_exploration.json` (9 pontos). Catálogo gerado para o backend: `shared/content_schemas/exploration.json` (`node tools/gen_quests_catalog.mjs` regenera; o validador falha se estiver desatualizado).

| POI | Zona | Tipo | Regra | Recompensa |
|---|---|---|---|---|
| `poi_hub_hollow_stump` | hub | segredo | - | 25 xp, 2x sucata, poção |
| `poi_wild_fallen_oak` | wild | marco | - | 40 xp |
| `poi_wild_old_milestone` | wild | marco | - | 40 xp, poção |
| `poi_wild_hunter_cache` | wild | baú | quest `gw_welcome` | 30 xp, 2x poção, 3x sucata |
| `poi_wild_thorn_relic` | wild | segredo | nível >= 3 | 100 xp, `amulet_vigor` |
| `poi_ruins_scribe_niche` | ruínas | marco | - | 60 xp |
| `poi_ruins_pillar_cache` | ruínas | baú | - | 50 xp, 2x poção, 2x sucata |
| `poi_ruins_altar_inscription` | ruínas | marco | - | 80 xp |
| `poi_ruins_hidden_vault` | ruínas | segredo | nível >= 2 | 150 xp, 3x poção, 4x sucata |

Regras (todas no servidor):
- Descoberta automática por proximidade: `QuestService.tick()` varre os pontos da zona do jogador usando `position_of` (posição autoritativa). Não existe comando de cliente para descobrir; o cliente só recebe `QUEST_DISCOVERED`.
- Cilindro `center/radius/height`, nível mínimo e quests exigidas conferidos antes de qualquer efeito.
- Sem exploit de repetição: o ponto entra em `quests.discovered` na MESMA transação da recompensa; a chave `explore:<poi_id>:<personagem>` é idempotente (replay devolve o resultado, outra descoberta do mesmo ponto = 409 `poi_already_discovered`). Reentrar no raio, reconectar ou trocar de zona não repete.
- Inventário cheio: nada é aplicado, o ponto continua não descoberto, `QUEST_ERROR(inventory_full)` é avisado uma vez e a descoberta ocorre quando houver espaço.
- O backend recusa xp/itens diferentes do catálogo (`poi_reward_mismatch`), POI desconhecido, nível baixo (`poi_level_too_low`) e pré-requisito faltando (`poi_prereq_missing`).
- Persistência por personagem em `characters.quests.discovered` (jsonb existente). O checkpoint do servidor nunca cria nem remove `discovered`. **Sem migração 0007** (ver `backend/migrations/README.md`).
- Snapshot: sem mudança; nenhum byte por entidade a mais.

## 3. Validador de conteúdo
```
node tools/validate_content.mjs [--root <pasta>] [--json] [--no-generated]
```
Códigos de saída: `0` sem erros, `1` conteúdo inválido, `2` erro de uso/execução. Sem dependências (só Node). Verifica: JSON legível; ids únicos, no padrão e iguais ao nome do arquivo; referências cruzadas (classes, talentos, itens, receitas, inimigos, loot, NPCs, diálogos, quests, áreas/zonas/portais, POIs); ciclos de pré-requisitos; alcançabilidade de cada quest (ponto fixo: pré-requisitos, nível, NPC numa zona alcançável por portais, oferta/entrega em diálogo, fontes de cada objetivo); faixas numéricas; catálogos gerados (`shared/content_schemas/*.json`) em dia (desligável com `--no-generated`). Teste: `backend/test/content_validation.test.ts` (conteúdo real passa; ~50 corrupções, cada uma deve falhar com a mensagem esperada).

## 4. Reprodutibilidade e testes
- Godot `tests/e6_quests/`: `test_e6_content.gd` (dados, grafo, referências), `test_e6_arc.gd` (arco completo na ordem, recompensas únicas por personagem, descoberta/anti-repetição, inventário cheio, reconexão).
- Backend (vitest por arquivo): `exploration.test.ts`, `quests.test.ts`, `content_validation.test.ts`.
- Integração real: `python3 tools/e6_quests_integration.py quests` (servidor Godot + backend + bots; cobre >= 2 quests novas e >= 2 atividades de exploração, replay/forja/reconexão).

## 5. Limites conhecidos
- Pontos de exploração ainda sem marcador visual/UI dedicada (o log mostra o toast de descoberta).
- Sem retroatividade de `craft` e `collect` fora da quest ativa.
- Textos em PT-BR via `title_key`; sem localização adicional.
