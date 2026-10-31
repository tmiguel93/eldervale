# E4 - Personagens, inventario, checkpoint e recompensas (backend)

Codigo: `backend/src/characters/` (`catalog`, `limits`, `progression`, `model` puro, `service` transacional, `routes`).
Testes: `backend/test/characters.test.ts`. Catalogo: `shared/content_schemas/items.json`.

## Modelo
- Tabelas da migracao 0001 (nenhuma migracao nova): `characters` (level, xp TOTAL, stats jsonb, schema_version, revision),
  `character_inventory` (slot, item_id, qty; slot vazio = sem linha), `character_equipment` (weapon/armor/trinket), `reward_claims`.
- Estado (`CharacterState`): `schema_version=1, level, xp, stats, inventory[{slot,item_id,qty}], equipment{weapon?,armor?,trinket?}`.
  `stats` sao os stats BASE (100/50/5/10/0/0/5, como `StatBlock`); bonus de nivel/equipamento continuam calculados pelo jogo.
- Curva: `round(100*L^1.5)`, nivel max 50, XP satura em `MAX_TOTAL_XP` (identica a `character_progress.gd`; testada: 100, 283, 520, 800).
- Itens nao tem identidade de instancia: um item equipado e outro igual no inventario sao legitimos; a conservacao e por contagem por `item_id`.
- Kit inicial (dados): `sword_basic` (weapon) e `armor_leather` (armor) equipados, inventario vazio.
- `revision` comeca em 0 e sobe em cada checkpoint, recompensa aplicada e soft delete.

## Catalogo de itens
`shared/content_schemas/items.json` e DERIVADO de `data/items/*.tres` por `node tools/gen_items_catalog.mjs`
(`--check` so verifica). **Regenere sempre que um item em data/items mudar.** O teste `items.json esta em dia` roda o `--check`
(pulado se `data/items` nao existir). `catalog.ts` valida o JSON na subida (ids, slot, stackable, max_stack) e a API rejeita ids fora dele.

## Endpoints
Publicos (`requireAuth`; personagem de outra conta ou inexistente = 404 identico; id malformado = 400):
- `GET /v1/characters` (resumo) · `GET /v1/characters/:id` (completo) · `POST /v1/characters {name, class_id}` -> 201.
- `DELETE /v1/characters/:id` -> 204 (soft delete; 409 `character_in_session` se existe linha em `character_locks`).
- Nome: NFC, trim, 2-24 caracteres, letras/numeros/espaco simples/`'`/`-`/`_`, comeca com letra ou numero; unico case-insensitive
  entre nao apagados (409 `name_taken`). `class_id` so `warrior` (400 `invalid_class`). Limite por conta (409 `character_limit`), exato sob concorrencia (trava a linha da conta).

Internos (`requireInternal`, Bearer `GAME_SESSION_INTERNAL_SECRET`; sem/errado = 401):
- `GET /internal/characters/:id` -> estado completo + `revision` + `account_id`.
- `POST /internal/characters/:id/checkpoint {expected_revision, state}` -> 200 com o novo estado.
- `POST /internal/characters/:id/rewards {idempotency_key, xp?, items?}` -> 200 `{replayed, result, character}`.
  - E5.1: aceita `quest_id` (chave `quest:<quest_id>:<character_id>`, xp/itens iguais ao catalogo; conclui a quest na mesma transacao). O checkpoint aceita `state.quests` opcional (`completed` e somente-servidor). Ver `docs/E5_QUESTS.md`.

## Checkpoint
Tudo em uma transacao com `SELECT ... FOR UPDATE` do personagem. Ordem: revision (409 `revision_conflict`, nada alterado) -> sanidade (422) -> grava.
Validacao do estado (422 `invalid_state`): campos exatos, `schema_version`, level 1..50 e **coerente com o xp** pela curva, xp inteiro <= maximo,
stats numericos nos intervalos, itens no catalogo, qty 1..max_stack, slot 0..capacidade-1 sem repeticao, no maximo `capacidade` entradas,
equipamento so em weapon/armor/trinket com item do slot correspondente.
Escolha de sanidade (o servidor de sessao e a autoridade, entao o estado e aceito, mas com tetos configuraveis): xp nunca diminui; ganho de xp por checkpoint <= `checkpointMaxXpGain`;
ganho de qualquer item_id (inventario+equipado) por checkpoint <= `checkpointMaxItemGain`. Perdas de itens sao livres (consumo/queda). Rejeicoes sao registradas via `log.warn("checkpoint_rejected", {character_id, reason})`
(somente log; nao ha tabela de auditoria).

## Recompensas
Transacao unica com lock da linha do personagem. Chave repetida (mesmo conteudo) devolve o resultado ORIGINAL com `replayed:true`, sem reaplicar; chave igual com conteudo diferente = 409 `idempotency_key_reuse`.
Aplica xp (level-ups pela curva, satura no 50) e itens (completa pilhas por ordem de slot, depois menor slot livre). Sem espaco = 409 `inventory_full`, nada aplicado e a chave NAO e consumida (o rollback desfaz tambem o claim).
Itens repetidos na mesma request sao somados. `payload` do claim = `{request, result}`. A recompensa sobe a `revision`: o servidor de sessao deve adotar a revision devolvida antes do proximo checkpoint.

## Limites (padrao; `CharacterLimits`, env opcional `CHARACTER_*`)
personagens/conta 5 · capacidade do inventario 24 · xp por request 1.000.000 · itens por request 20 · qty por linha 1..999 · chave 8..128 `[A-Za-z0-9._:-]` ·
ganho de xp por checkpoint 100.000 · ganho por item por checkpoint 500. Corpo maximo: `MAX_BODY_BYTES` do M1.

## NAO verificado / riscos
- Concorrencia testada so em PGlite (conexao unica serializa transacoes); o comportamento sob PostgreSQL real com varias conexoes
  (FOR UPDATE, PK de `reward_claims`) esta desenhado para funcionar mas NAO foi executado.
- O checkpoint/recompensa NAO exigem que o chamador detenha o lock de sessao do personagem (isso e do M4); um lock orfao bloqueia o DELETE ate ser liberado.
- `items.json` e lido do disco (`import.meta.url`); no deploy Vercel o arquivo precisa ser incluido no bundle (nao testado).
- `/v1` foi testado com verificador injetado em `createApp`, nao com o JWT real do M2.
- Nomes: sem filtro de palavroes/confundiveis (homoglifos). Sem rate limit proprio nos endpoints.
- Sem endpoint para equipar/desequipar no backend (so via checkpoint do servidor de sessao); sem moeda.
