# E2 - Dados, inventario, equipamento, loot e XP

Logica pura (RefCounted/Resource), sem dependencia de cena. Todo o conteudo em `data/` e PLACEHOLDER de teste.

## Modelos (`scripts/data/`)
- `ItemData`: id, display_name, slot (NONE/WEAPON/ARMOR/TRINKET), stackable, max_stack, rarity (COMMON..LEGENDARY), `stat_modifiers: StatBlock`, placeholder.
- `EnemyData`: id, display_name, `stats: StatBlock`, xp_reward, `loot_table`, behavior (`&"melee"`/`&"ranged"`), aggro_range, attack_range, attack_cooldown, attack_damage_multiplier, projectile_speed (ranged exige > 0).
- `LootTable` + `LootEntry` (item_id, weight, min_qty, max_qty) + `LootDrop` (resultado). `roll(rng)`: `rolls` sorteios ponderados; `nothing_weight` e o peso de "nada"; drops do mesmo item sao somados. Determinístico: depende so do estado do `RandomNumberGenerator` recebido.
- `ContentRegistry`: `load_all()` le `data/items`, `data/loot`, `data/enemies`; `validate() -> Array[String]` (0 = ok).
- `StatUtil`: `zero()` (StatBlock tem defaults de personagem, entao modificadores partem de zero), `scaled()`, `equals()`.

## Logica
- `Inventory` (`scripts/inventory/`): capacidade em pilhas; `add` devolve o que nao coube; `remove` e tudo-ou-nada; sinal `changed`; sem pilhas vazias.
- `Equipment`: um item por slot; `equip` devolve o anterior ao inventario, `unequip` devolve ao inventario; falhas sao atomicas (`last_error`); sinal `equipment_changed(slot)`.
- `StatCalculator.compute(base, equipment, progress)` = base + bonus de nivel + equipados via `StatBlock.combine` (nao muta entradas).
- `CharacterProgress` (`scripts/progression/`): XP para L -> L+1 = `round(100 * L^1.5)`; MAX_LEVEL 50; `add_xp` ignora <= 0, limita cada concessao a 1e9 e satura o total no nivel maximo; `leveled_up(new_level, levels_gained)` 1x por chamada; bonus por nivel em `bonus_per_level`.

## IDs
StringName snake_case estavel (`sword_rare`, `melee_grunt`, `loot_melee_grunt`); nunca derivados do display_name. O nome do arquivo `.tres` = id (convencao). Mudar um id quebra saves/referencias.

## Adicionar conteudo
1. Edite `scripts/data/content_generator.gd` e rode (apos `--import`): `$G --headless --path . --script res://scripts/data/content_generator.gd` (regenera TODOS os .tres de `data/`, sobrescrevendo edicoes manuais), ou crie o `.tres` direto no editor.
2. Rode a suite: `tests/e2/test_data_content.gd` falha se houver referencia quebrada, id duplicado etc. (teste espera 7 itens/2 inimigos/2 tabelas; atualize ao crescer).

## Limites conhecidos
- Sem persistencia/serializacao de inventario, equipamento ou progresso (nao ha schema de save ainda).
- Um unico item por slot (sem aneis duplos); equipar remove 1 unidade.
- Loot so por peso (sem chance independente por entrada, sem condicoes/niveis).
- Resistencia somada e limitada a 0.75 pelo StatBlock; bonus de nivel nao usa curva por dados.
- Registry nao tem hot-reload; IDs duplicados entre arquivos sao detectados, nao resolvidos.
- Lógica e autoridade local: nao ha validacao de rede/servidor (E3).
