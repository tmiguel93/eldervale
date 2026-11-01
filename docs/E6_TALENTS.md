# E6.2 — Especialização, árvore de talentos e modificadores de habilidade

Servidor autoritativo: o cliente só PEDE (`c_talent_cmd`); o servidor valida, o **backend** (PostgreSQL/PGlite) é a verdade e persiste, e os efeitos são calculados no servidor. Decisões: DEC-0014 a DEC-0016 (propostas).

## Dados
- `data/talents/<class_id>.json` (warrior, mage, ranger): `{schema_version, class_id, nodes[]}`; nó = `id, name, description, tier (small|notable|mastery), spec ("" = genérico da classe), requires[], min_points_spent, min_level, cost, max_rank, effects[]`. 15 nós por classe (7 genéricos + 8 da especialização inicial: Berserker, Elementalista, Caçador), 1 mestria por árvore (exige nós profundos e pontos gastos). A árvore inteira custa mais que os 49 pontos do nível 50, então há escolhas.
- Efeitos: `{"type":"stat","stat","amount"}` (por rank; entra em `StatCalculator.compute` como `talent_bonus`) ou `{"type":"skill_mod","skill","mod",...}` com `mod` = `damage` (`damage_pct`), `extra_projectiles` (`count, spread_deg, damage_scale`), `area` (`radius_pct`), `duration` (`i_frames_add`, só esquivas), `cost` (`cost_pct`, `cooldown_pct`), `convert` (`to` elemento, `damage_pct`), `condition` (`when` = self_hp_below/self_hp_above/resource_above + `threshold` + `damage_pct`), `synergy` (`after_skill`, `window`, `damage_pct`). Parâmetros valem POR RANK.
- `data/talents/_progression.json`: `points` (`first_point_level=2`, `points_per_level=1`, `max_points=60`: pontos(n) = clamp((n-2+1)·1, 0, 60)) e `respec` (`cost_items`=[scrap_material x3], `require_safe_zone=true`). Tudo configurável por dado.
- `node tools/gen_talents_catalog.mjs [--check]` valida (estrutura, efeitos, grafo acíclico, spec/tier, 1 mestria, skills da classe, itens) e gera `shared/content_schemas/talents.json` para o backend. `tools/gen_classes_catalog.mjs` passou a expor quais skills são de projétil.

## Regras (iguais em `scripts/talents/talent_state.gd` e `backend/src/talents/rules.ts`)
Ordem de checagem da alocação: nó existe (`unknown_node`) → especialização (`spec_not_chosen`/`wrong_spec`) → `max_rank` → `level_too_low` → `requires`/`min_points_spent` (`prerequisite`) → pontos (`no_points`). Escolher especialização: `unknown_spec`/`spec_already_chosen`. Respec: `nothing_to_reset`, zona segura (`not_safe_zone`, só no servidor de jogo), itens (`insufficient_items`). Troca de classe zera os talentos (a classe é imutável por personagem no backend).

## Modificadores em combate
`SkillMods.collect` (ao entrar/mudar build) e `SkillMods.resolve` (a cada uso, em `PlayerCombat.try_use`) trabalham sobre uma CÓPIA do `SkillData`; o `.tres` compartilhado nunca muda. Dano: bônus aditivos que multiplicam o multiplicador base (limites −90%…+900%); custo/cooldown piso 25%; área 25%–300%; projéteis extras ≤ 6 em leque (o central com dano cheio, extras com `damage_scale`); conversão grava `damage_type` no golpe/projétil.

## Backend
- Migração `0005_character_talents` (ver `backend/migrations/README.md`: aditiva, idempotente, rollback documentado).
- `POST /internal/characters/:id/talents` — corpo `{idempotency_key: "talent:<sessão>:<n>:<personagem>", op: allocate|respec|choose_spec, arg?, expected_revision?}`; exige `X-Session-Id` (fencing) e segredo interno; transação com `FOR UPDATE`; idempotência via `reward_claims` (replay = `replayed:true` sem mudar nada; mesma chave com outro conteúdo = 409 `idempotency_key_reuse`); recusas de regra = 409 com o código da regra e nada gravado; `revision_conflict` quando `expected_revision` diverge. `GET /v1/characters/:id` e a visão interna incluem `talents`. O prefixo `talent:` é reservado (recusado em `/rewards`).
- O checkpoint não grava nem apaga `talents` (campo extra no `state` é rejeitado).

## Servidor de jogo e cliente
`TalentService` (comando → validação local idêntica → fila serializada `BackendSync.enqueue_talent` → só então muda a memória; erro definitivo devolve o custo e avisa o dono; erro de rede recarrega o personagem do banco). Estado enviado ao dono no join, após cada comando, ao subir de nível e após recarga. Painel `TalentPanel` (tecla **K**; `scripts/ui/client`, nunca instanciado em servidor/bot): Cima/Baixo navegam, Enter aloca, **S** escolhe a especialização, **R** reseta (dois toques para confirmar). O cliente só exibe o que o servidor mandou.

## Testes
`tests/e6_talents/` (275 asserts): dados, regras puras, modificadores em combate (cada tipo + builds com resultados medidos diferentes + recurso compartilhado intacto), autoridade (backend falso: válido/ inválido, replay, rate limit, respec, nível, reconexão, falha do backend, modo dev) e UI. `backend/test/talents.test.ts` (13): catálogo, migração, alocação válida/inválida, concorrência, idempotência, respec, checkpoint. Integração: `python3 tools/e6_talents_integration.py talents` (bot aloca, backend persiste, reconexão traz a build e a vida máxima com bônus).

## Limites conhecidos
- `damage_type` ainda não tem resistências por inimigo: conversão hoje = marcação + bônus de dano.
- Custo do respec em item (não há moeda); números de balanceamento provisórios.
- Nível em memória acima do banco pode render `no_points` do backend (o banco vence).
- O cliente não mostra os números efetivos das habilidades (só stats pelo fluxo normal).
