# E6.3 — Raridades, affixes e itens únicos

Servidor autoritativo: o cliente nunca rola nada nem informa valores; só PEDE equipar/desequipar (`c_equip_cmd`). O servidor de jogo rola a instância (RNG com semente), o **backend** revalida contra o catálogo e persiste. Decisões: DEC-0017 a DEC-0020 (propostas, aguardam revisão).

## Dados (tudo em `data/items/`, nada hardcoded)
- `_rarity.json` — 6 raridades (`common, uncommon="Mágico", rare, epic, legendary, mythic`) com **orçamento** (soma dos custos de tier dos affixes), faixa de affixes, limites de prefixo/sufixo, peso-base de drop e cor; `tier_weight_mult` ajusta os pesos por tipo de inimigo (`normal`, `mini_boss`, `boss`); `ilvl_max=50`, `max_affixes=6`.

  | Raridade | Orçamento | Affixes | Prefixos/Sufixos máx. | Peso base |
  |---|---|---|---|---|
  | Comum | 0 | 0 | 0/0 | 6000 |
  | Mágico | 4 | 1–2 | 1/1 | 2600 |
  | Raro | 9 | 3–4 | 2/2 | 1000 |
  | Épico | 14 | 4–5 | 3/3 | 300 |
  | Lendário | 20 | 5–6 | 3/3 | 90 |
  | Mítico | 24 | 6 | 3/3 | 10 |
- `_affixes.json` — 13 affixes (7 prefixos, 6 sufixos), id estável, `slots` permitidos (`weapon|armor|trinket`), `group` (um por grupo na mesma peça), efeito e 3 tiers (`T3` fraco e de entrada, `T2` a partir de ilvl 12, `T1` a partir de ilvl 28) com `min/max`, `cost`, `weight`, `ilvl_min`. Efeito `stat` soma ao `StatBlock` (vida, ataque, defesa, resistência, recurso, regeneração, velocidade) ou `skill_mod` com `skill:"*"` (dano, custo, área das habilidades), no **mesmo formato dos talentos** (`SkillMods`).
- `_uniques.json` — 5 itens únicos de TESTE (placeholder), cada um com `ItemData` em `data/items/unique_*.tres` (stats fixos), descrição legível, `effects[]` (mesmo formato `skill_mod` dos talentos) e `obtain` (nível mínimo + chance independente por tabela de loot). Nenhum é obrigatório para uma build; não rolam affixes.

  | Único | Slot | Efeito |
  |---|---|---|
  | Presa de Brasa | arma | +25% de dano das habilidades com vida < 40% |
  | Couraça da Gravitas | armadura | +20% de área das habilidades, −0,3 velocidade |
  | Nó de Pluma | amuleto | −20% custo, −10% recarga, −10 vida máxima |
  | Aljava Gêmea | amuleto | +1 projétil (50% do dano) |
  | Marca Gélida | arma | converte o dano para gelo, +10% dano |
- `node tools/gen_items_catalog.mjs [--check]` valida os três JSON (orçamento ≥ custos, faixas, grupos, slots, tabelas de loot, itens) e gera `shared/content_schemas/items.json` (campos novos `rarities`, `affixes`, `uniques`, `ilvl_max`, `max_affixes`; `schema_version` continua 1; itens únicos marcados `unique: true`).

## Instância de item
`{uid:"<16 hex>", rarity, ilvl:1..50, affixes:[{id, tier, value}]}` (≤ 512 bytes de JSON) guardada AO LADO da base (`item_id` continua a base, `qty` 1). Item sem instância = Comum (saves antigos). Itens únicos nunca têm instância.
- **Rolagem** (`ItemRoller`, só servidor): `uid = sha256("<base_seed>|<sessão>:<inimigo>:<jogador>:<n>")[:16]`; raridade por peso × multiplicador do tipo de inimigo; affixes sorteados respeitando slot, grupo, limites de prefixo/sufixo, `ilvl_min` do tier e o **orçamento** (reserva 1 por affix restante; até 16 tentativas). Mesma seed → mesma instância (testado). `ilvl` = nível do participante (limitado a 50).
- **Validação** (`ItemRules.validate_instance` no jogo e `parseInstance` no backend, mesmas regras): forma, raridade ≠ comum, ilvl, número de affixes da raridade, affix conhecido/permitido no slot, grupo único, tier existente e liberado pelo ilvl, valor finito dentro da faixa do tier, prefixos/sufixos, orçamento, tamanho.

## Fluxo
1. **Loot**: no modo individual (mundo/`--individual-loot 1`) `LootManager.roll_for` expande equipamentos da tabela em instâncias e adiciona os únicos elegíveis (nível mínimo + chance da tabela de origem). O evento de drop leva só `rarity`; o snapshot compacto não muda.
2. **Coleta**: o servidor põe a instância no inventário e envia `POST /rewards` com chave `loot:<sessão>:<n>:<personagem>` e `inst` no item (replay pela chave não duplica; o mesmo `uid` com outra chave → `409 duplicate_instance`).
3. **Equipar** (`c_equip_cmd`): `EquipService` (vivo, fora de transição, req_id novo, sem craft/talento em voo → `busy`, índice/base conferem, instância válida, espaço para o item anterior). Equipamento é atômico; `PlayerLoadout` recalcula stats (clamp sanitário `StatCalculator.CAPS`) e mods de habilidade (`PlayerCombat.mods_for`: curinga `*`, nunca na esquiva). Em seguida enfileira checkpoint coalescido.
4. **Persistência**: migração `0006_item_instances` (colunas `inst jsonb` em `character_inventory` e `character_equipment`, CHECK de objeto, índices únicos parciais por `(character_id, inst->>'uid')`). O **checkpoint nunca cria nem altera** uma instância: só move (uid já existente e conteúdo igual, `unknown_instance`/`instance_modified`). Crafting ignora itens com affixes (`count_plain`/`remove` só enxergam simples; backend idem).
5. **Concorrência**: tudo sob `SELECT … FOR UPDATE` do personagem + `revision`; equipar × craft × checkpoint × recompensa simultâneos nunca duplicam nem perdem a instância (teste de concorrência no backend).

## Protocolo e cliente
Ver `shared/contracts/network_protocol.md` (Extensão E6.3): `c_equip_cmd`, `s_equip`, `inst`/`equipment_inst` em `s_inventory`, `rarity` no drop, `inst` no pickup ao dono. `VERSION` continua 2.
Cliente (`scripts/ui/client`): botões e rótulos na cor da raridade, nome composto (`Brutal Espada Básica da Fúria`), tooltip com raridade/ilvl e uma linha por affix, linha `Equipado:` para comparar, Enter equipa o slot do cursor e `1/2/3` desequipa arma/armadura/amuleto. Itens únicos mostram a descrição autorada.

## Testes
- Godot `tests/e6_items/` (253 asserts): dados (+ batem com `items.json`), roller (orçamento, faixas, determinismo, distribuição de raridade em 20 000 rolagens, gating de slot/ilvl, payloads inválidos, valores finitos), equip (stats exatos, cada único, clamps NaN/negativo/overflow, regras de inventário), servidor com backend falso (loot rolado → coleta → recompensa idempotente, único só no nível e tabela certos, comandos de equipar, abuso, checkpoint, reconexão, saves antigos e adulterados), protocolo e UI.
- Backend `backend/test/items.test.ts` (16): catálogo, `parseInstance`, migração 0006 (aditiva, idempotente, constraints), recompensas com instância (replay, concorrência, rejeições), checkpoint (mover vs forjar), crafting × instâncias e concorrência equipar × craft × checkpoint × recompensa.
- Integração real: `python3 tools/e6_items_integration.py items` (bot abate, recebe item rolado, equipa, vida máxima muda pela soma dos affixes calculada a partir do catálogo, persistência idêntica, tentativas forjadas recusadas, reconexão).

## Limites conhecidos
- Só existem os 3 slots atuais (arma, armadura, amuleto); só os stats do `StatBlock` (sem crítico, velocidade de ataque nem dano elemental por affix — dependem de sistemas futuros).
- Rolagem só no modo de loot individual (o modo legado da arena/E3 continua com itens simples).
- `ilvl` = nível do personagem; sem escala por zona.
- Números de orçamento/pesos/faixas e os 5 únicos são placeholders de balanceamento.
- O gancho `--loot-test-force <raridade>` (só com `ELDERVALE_TEST_MODE=1`) existe para a integração ser determinística; é ignorado em produção.
- Itens com affixes não entram em receitas (nem como ingrediente); um futuro "reforjar" fica para outra etapa.
