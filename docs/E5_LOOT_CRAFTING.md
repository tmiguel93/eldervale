# E5.4 — Loot individual e crafting

Estado: implementado, opt-in no loot (`ServerSettings.individual_loot`), crafting sempre disponível onde houver estação.
Decisão registrada como DEC-0008 (proposta). Contrato de rede: `shared/contracts/network_protocol.md` (extensão E5.4).

## 1. Loot individual

### Regras (servidor autoritativo)
- Cada inimigo acumula, por jogador, o dano causado (`ServerWorld._contrib`). Na morte, `LootManager.eligible_ids` decide quem rola:
  - inimigo `normal`: dano >= `loot_min_share` (5%) da vida máxima, **mais** o matador (último golpe) sempre;
  - `mini_boss`/`boss`: qualquer dano > 0 **garante** a rolagem, mais o matador.
- Além disso o jogador precisa estar **vivo e na mesma zona** do inimigo no instante da morte. Quem não participou (ou saiu da zona / morreu) não recebe loot nem XP.
- Cada elegível rola a tabela de loot do inimigo **com seu próprio RNG**: semente `hash("base:inimigo:jogador")` (`LootManager.seed_for`). `rng_factory` (Callable) é injetável nos testes; `base_seed` vem de `ServerSettings.loot_seed` ou é aleatória e **privada** (não é o `session_seed` enviado no welcome, para o cliente não prever drops).
- O resultado vira **pickups com dono** (`LootManager.LootPickup`): TTL `pickup_ttl_sec` (90 s), no máximo `max_pickups_per_player` (24; o mais antigo é descartado), coleta por proximidade (`pickup_radius` 1,8 m) e só pelo dono e na zona do drop. O dono que sai da sessão perde os pickups.
- **Visibilidade**: o snapshot de cada peer inclui só os pickups dele (`KIND_PICKUP`); `EVENT_DROP` (com `id`) e `EVENT_PICKUP` vão só ao dono.
- **Coleta idempotente**: ao coletar, a memória recebe o item (tudo-ou-nada via `room_for`) e o servidor enfileira a recompensa `loot:<sessão>:<id_do_drop>:<personagem>` (xp 0, 1 item) na fila serializada do personagem. O backend valida o formato, a sessão (`X-Session-Id`) e o personagem da URL, e grava em `reward_claims`; replay da mesma chave devolve o resultado sem aplicar de novo. O pickup é removido do servidor na coleta, então coletar duas vezes não existe; reenvio por rede reutiliza a mesma chave.
- **Inventário cheio**: o pickup **permanece** (marcado `blocked_full`, contado uma vez em `stats`), nada é enviado ao backend e nada se perde; é coletado assim que houver espaço ou expira pelo TTL. Pilhas parciais: se não couber a quantidade inteira, nada é coletado.

### XP por participante (verificação)
Antes (E2–E5.2) o XP ia **só ao matador**. No modo individual todo participante elegível recebe o XP do inimigo, com chave `kill:<sessão>:<inimigo>:<personagem>` (idempotente, uma por participante). O matador segue contando para quests (crédito de abate de quest continua só do matador).

### Anti-farm
- Adds invocados (`root_sprout` etc.) são marcados (`_add_ids`) e **não dão loot nem XP** no modo individual.
- Limite de 24 pickups por jogador e TTL curto impedem acumular objetos; o dano mínimo de 5% evita "cutucar" para ganhar loot em inimigos comuns.
- Observação: no conteúdo atual do E5.2 os `root_sprout` mortos ainda têm xp/tabela próprios; no modo legado (individual desligado) continuam valendo como antes. Não alterei dados de balanceamento.

### Configuração (`ServerSettings` / CLI)
`individual_loot` (`--individual-loot 0|1`; ligado automaticamente com `--world` diferente da arena), `loot_seed`, `loot_min_share`, `pickup_ttl_sec`, `pickup_radius`, `max_pickups_per_player`, `xp_for_participants`.

## 2. Crafting

### Dados
- Estação: `data/areas/world/greenwood_world.json`, zona `zone_hub`: `station_greenwood_workbench` em (6, 0, -4), raio 3,5 m (prop "Workbench"). `ZoneDef.stations` (até 4/zona) validado em `WorldDef`.
- Receitas: `data/recipes/*.json` (schema `shared/content_schemas/recipe.schema.json`, catálogo gerado `recipes.json` por `node tools/gen_recipes_catalog.mjs [--check]`). Só os 7 itens existentes:

| Receita | Ingredientes | Resultado |
|---|---|---|
| rcp_potion_minor | 3 scrap_material | potion_minor |
| rcp_sword_basic | 5 scrap_material | sword_basic |
| rcp_armor_leather | 6 scrap_material | armor_leather |
| rcp_armor_heavy | 1 armor_leather + 8 scrap_material | armor_heavy |
| rcp_amulet_vigor | 2 potion_minor + 10 scrap_material | amulet_vigor |

Godot (`RecipeCatalog`) e backend (`backend/src/crafting/catalog.ts`) leem os mesmos JSON; itens equipados não contam como ingrediente.

### Fluxo (Godot)
`c_craft_cmd(req_id, recipe_id)` → `ServerSession.on_craft_cmd` (welcome, rate limit 2/s burst 4, validação do protocolo) → `CraftingService.cmd_craft`: jogador vivo/sem transição → `req_id` repetido → receita existe → sem craft em andamento (`busy`) → estação certa e ao alcance (`no_station` = zona sem a estação/arena; `too_far`) → ingredientes (`insufficient_ingredients`) → espaço após consumir (`inventory_full`). Só então aplica.

### Consistência memória × banco
- Modo dev (sem backend): aplica e responde na hora.
- Com backend: aplica na **memória** (otimista), bloqueia o autosave desse personagem (`snapshot_character` devolve `{}`) e enfileira `POST /internal/characters/:id/craft` com chave `craft:<sessão>:<n>:<personagem>` na mesma fila serializada dos checkpoints/recompensas. Retries de rede reutilizam a chave.
  - Sucesso (ou replay) → `CRAFT_OK`.
  - Recusa definitiva (4xx exceto 429) → desfaz na memória (`undo_on`) ou, se não for possível, recarrega o personagem do banco; `CRAFT_ERROR` com o código.
  - Resultado desconhecido (rede/5xx esgotados) → recarrega do banco (a verdade); a chave garante que um reenvio posterior não duplica.

### Backend
`POST /internal/characters/:id/craft` `{idempotency_key, recipe_id}` + `X-Session-Id` (fencing por `assertSessionHoldsLock`). Em uma transação: `SELECT FOR UPDATE` do personagem → busca em `reward_claims` (replay devolve `replayed:true`; a mesma chave com outra receita = 409 `idempotency_key_reuse`) → remove ingredientes do **inventário** (maior slot primeiro, tudo-ou-nada) → adiciona resultados (tudo-ou-nada) → grava claim e revision. Erros: 400 `invalid_idempotency_key`/`invalid_recipe`/`unknown_recipe`, 409 `insufficient_ingredients`/`inventory_full`, fencing de sessão. Falha não consome a chave. As chaves `craft:` e `loot:` são reservadas: `/rewards` rejeita `craft:` e exige que `loot:` bata com sessão/personagem, xp 0 e um único item. **Sem migração 0004** (reuso de `reward_claims`).

## 3. Testes
- Godot: `tests/e5_loot/test_loot_individual.gd` (104 checks: seed/elegibilidade puras, validadores, 1–4 jogadores, não participante/morto/outra zona, mini-chefe garantido, visibilidade por dono em snapshot e eventos, coleta idempotente, inventário cheio/TTL/pilha parcial, limites, adds, `rng_factory`, modo legado, zonas) e `test_craft_server.gd` (68 checks: catálogo, sucesso, estação distante/zona/arena, ingredientes, inventário cheio, `busy`/autosave, recusa 409 com rollback, falha de rede com reload, replay, flood/rate limit, desconexão em voo, modo dev, 3 jogadores). Helpers: `tests/e5_loot/loot_helpers.gd`; fake backend estendido (`/craft`, validação de `loot:`).
- Vitest: `backend/test/crafting.test.ts` (21): catálogo, `removeItems`, sucesso, 2 ingredientes, replay, reuso de chave, concorrência, insuficiente (chave não queimada), equipado não conta, inventário cheio, slot liberado, receita desconhecida, chaves inválidas, fencing, 401, chaves `loot:`/`craft:` em `/rewards`.
- Suíte completa: Godot 2047 ok (1875 + 172); backend 13 arquivos ok (215 testes nos dois lotes), `tsc --noEmit` limpo.

## 4. Riscos / não verificado
- Desconexão com craft em voo que depois **falha** no backend: o checkpoint final foi capturado com o estado otimista e pode persistir um craft que o banco recusou (a fila serializa craft → checkpoint, mas o estado do checkpoint já foi capturado). Janela pequena; mitigação futura: capturar o checkpoint final só depois do craft concluir.
- Itens fabricados não contam para objetivos `collect` de quests; o crédito de abate de quest segue só do matador.
- Pickups somem se o dono desconecta (sem persistência de pickups).
- Concorrência do craft testada apenas em PGlite (não em PostgreSQL real).
- Não há UI de inventário/crafting no cliente: só a API de sessão (`ClientSession.craft`, sinal `craft_finished`) e o avatar do pickup/marcador da estação.
- Balanceamento de receitas e tabelas não foi alterado/ajustado; os custos são provisórios.
