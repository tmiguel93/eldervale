# E6.5 - Balanceamento, metricas e exploits (Greenwood, classes, talentos, itens)

Status: E6.5 entregue; numeros abaixo sao MEDIDOS pelo simulador headless (`tools/balance/`), nao estimados. Os criterios-alvo sao propostas do projeto
(DEC-0026 em `docs/DECISIONS.md`) e dependem de playtest humano para virarem decisao de design (ver "Limites do modelo").

## 1. O que foi entregue

| Entrega | Onde |
|---|---|
| Simulador de balanceamento deterministico (sem rede, semente fixa) | `tools/balance/balance_core.gd` (`BalanceSim`), CLI `tools/balance/balance_sim.gd` |
| Faixas-alvo e parametros do modelo (DADOS, nao codigo) | `data/balance/balance_config.json` |
| Resultados medidos antes/depois (JSON completo) | `docs/balance/e6_before.json`, `docs/balance/e6_after.json` |
| Renderizador das tabelas deste documento | `tools/balance/balance_report.py` |
| Ajustes de balanceamento (somente em `data/`) | secao 4 |
| Telemetria essencial do servidor | `scripts/server/server_metrics.gd` + ganchos; secao 7 |
| Testes de exploits/anti-duplicacao | `backend/test/exploits.test.ts`, `tests/e6_balance/test_exploits.gd`; secao 8 |
| Testes do simulador, dados congelados e telemetria | `tests/e6_balance/` |
| Gate do E6 | `docs/E6_GATE.md` |

Como reproduzir (raiz do projeto, Godot 4.7.2 headless; a medicao completa leva ~1 min):

```
# medicao completa -> JSON (+ linhas OK/FALHA por criterio no stdout)
$G --headless --path . --script res://tools/balance/balance_sim.gd -- --label=after --out=docs/balance/e6_after.json
# medicao rapida (usada nos testes) e reavaliacao de um JSON ja medido com a configuracao atual
$G --headless --path . --script res://tools/balance/balance_sim.gd -- --quick --out=/tmp/quick.json
$G --headless --path . --script res://tools/balance/balance_sim.gd -- --evaluate=docs/balance/e6_after.json --out=docs/balance/e6_after.json
# tabelas deste documento
python3 tools/balance/balance_report.py docs/balance/e6_before.json docs/balance/e6_after.json
```

O "antes" foi medido sobre os dados do `HEAD` (originais) e o "depois" sobre os dados ajustados, ambos com o MESMO codigo do simulador e a MESMA configuracao
(semente `20261102`).

## 2. Modelo do simulador (e o que ele NAO e)

Cada personagem e montado com as mesmas funcoes do servidor (`StatCalculator`, `SkillMods`, `TalentState`, `Equipment`, `ItemRoller`, `DamageCalculator`,
`LootManager`) e luta em passos de 0,05 s contra um alvo parado. Premissas (todas em `balance_config.json > sim`):

- Rotacao gulosa: usa a habilidade pronta com maior dano esperado por tempo de conjuracao; esquiva a cada 5 s (ativa mods de sinergia com a esquiva).
- Distancia de engajamento 6 m; projeteis extras acertam 50% (100% no chefe, que e grande); perfurar acerta alvos secundarios com 50%.
- Bando = 3 `melee_grunt` com vida x10 (evita quantizacao de TTK em AoE); chance de acerto dos inimigos = 50%.
- Fases do chefe: media; sem movimento, IA, adds, pocoes, revive ou erros do jogador.
- Indice de poder = raiz(DPS x segundos de sobrevivencia contra o chefe) - resume ofensiva e defesa numa so grandeza.
- Loot: Monte Carlo com o `LootManager` real (3000 abates por tipo) + calculo analitico dos mesmos pesos.

O simulador mede balanceamento RELATIVO (classe contra classe, build contra build, antes contra depois). Ele nao substitui jogar: nao mede
sensacao, leitura de telegrafos, mobilidade, kiting, trabalho em equipe nem a dificuldade real do chefe. Veja a secao 9.

## 3. Criterios-alvo (e como foram definidos)

| Criterio (chave em `criteria`) | Faixa | Motivo |
|---|---|---|
| `class_dps_parity_pct` | +-25% da mediana (DPS contra chefe e bando, nivel 5, sem talentos) | classes diferentes por estilo, nao por poder |
| `build_spread_max_ratio` / `build_power_spread_max_ratio` | melhor/pior build <= 2,0 (DPS) e <= 1,35 (indice de poder), niveis 10 e 20 | nenhuma build obrigatoria, nem inutil |
| `tier_*` | escada de raridade monotonica (>= -3% de ruido), Lendario/Comum entre 1,2 e 2,2 (poder), Raro/Comum <= 1,6 | raridade importa mas nao decide tudo |
| `unique_max_dps_gain_pct` | nenhum unico acima de +30% de DPS (vida 30% incluida) | unicos mudam jogo, nao dominam |
| `talent_max_gain_per_point_vs_median` | no mais forte <= 4x a mediana por ponto | sem talento "obrigatorio" |
| `boss_ttk_1p_window_s` / `_4p_` | 40-120 s (1 jogador), 25-120 s (4); 4p/1p entre 0,6 e 1,4 | chefe e luta, nao tapete |
| `boss_duel_ratio_window` | dano sofrido/vida entre 0,4 e 1,2 | chefe ameaca, mas e vencivel sozinho |
| `grunt_ttk_max_s`, `duel_ratio_max_normal` | grunt <= 8 s; duelo normal <= 0,5 | trash nao e esponja |
| `xp_ratio_*` | 1->2 <= 3,0x; depois <= 2,0x; arco do Greenwood termina no nivel 6-9 | sem salto absurdo |
| `loot_normal_*` | Raro+ <= 2%/abate; Epico+ <= 0,5%/abate em comum | raro e raro |
| `loot_boss_*`, `loot_mini_boss_*` | Lendario+ a cada 3-20 abates do chefe; Epico+ a cada 1-6; Mitico >= 50 | alcancavel, nao garantido |
| `unique_kills_window` | 8-100 abates da melhor fonte por unico | alcancavel em algumas sessoes |

Honestidade sobre a definicao: as faixas de loot, TTK de chefe e unicos foram fixadas ANTES da medicao final, mas a medicao dos dados originais mostrou o que
falhava (secao 5) e algumas formulas dos criterios foram refinadas depois de ver resultados ruidosos, sempre registradas aqui: (a) a razao de XP do
nivel 1->2 e tratada a parte do resto da curva (2,83x e a unica "subida" grande, vinda da formula `100*L^1.5`); (b) o bando usa vida x10 em vez de
grunt unico (um TTK de 1 s quantiza para 0,05 s e inflava ganhos de AoE para 380%); (c) a comparacao entre builds ignora a build `none` (zero pontos nao e
uma build) e adiciona o indice de poder (so DPS punia builds defensivas); (d) builds sao avaliadas nos niveis 10 e 20 (no nivel 5 so ha 4 pontos); (e) a
escada de equipamento usa o indice de poder, 20 amostras e tolerancia -3%. Nenhuma faixa de balanceamento foi afrouxada para passar um criterio que falhava.


## 4. Ajustes de balanceamento (todos em dados)

Nenhum ajuste foi feito em codigo de jogo. Originais preservados em `.tools/scratch/e6_5_original_data/` (e no `HEAD`).

| Dado | Antes -> Depois | Motivo (criterio que falhava) |
|---|---|---|
| `data/enemies/blight_treant.tres` `max_health` (+ `greenwood_generator.gd`, `docs/E5_ENEMIES.md`) | 1200 -> 1800 | C6: TTK do chefe 32,0 s (guerreiro) e 30,2 s (mago), abaixo de 40 s |
| `data/skills/arrow_rain.tres` `damage_multiplier` | 1,7 -> 2,0 | `piercing_arrow` dominava `arrow_rain` (habilidade nunca escolhida); agora e usada 6,9x/min |
| `data/items/unique_emberfang.tres` `attack_power` | 9 -> 5 | C4: +70% de DPS com vida 30% |
| `data/items/_uniques.json` emberfang `damage_pct` | 0,25 -> 0,20 (descricao "+20%") | C4 |
| `data/items/_uniques.json` twin_quiver `damage_scale` | 0,5 -> 0,3 (descricao "30% do dano") | C4 (+52% apos o ajuste do emberfang) |
| `data/items/_uniques.json` chances de queda dos unicos | emberfang chefe 0,30->0,12 / alfa 0,20->0,06; gravitas chefe 0,25->0,10 / alfa 0,10->0,04; featherknot alfa 0,20->0,06 / bruto 0,01 (igual); twin_quiver chefe 0,25->0,10; frostbrand chefe 0,25->0,10 / alfa 0,10->0,04 | C9a: unicos em 3,3-5,0 abates (janela 8-100) |
| `data/items/_rarity.json` `tier_weight_mult` do chefe | epic 6->3, legendary 15->3, mythic 30->1 | C8c/d/e: Lendario+ a cada 1,7 abates, Mitico a cada 9,5 |
| `data/loot/loot_ranged_caster.tres` | amulet_vigor 6->2, sword_rare 1,5->0,5, armor_heavy 3->1 | C8a/b: Raro+ 4,2%/abate e Epico+ 1,2%/abate em inimigo comum |
| `data/loot/loot_bark_brute.tres` | armor_heavy 6->3, sword_basic 6->3 | C8a/b (margem) |
| `data/loot/loot_grove_shaman.tres` | amulet_vigor 8->5 | C8a/b (margem) |
| Espelhos: `scripts/data/content_generator.gd`, `greenwood_generator.gd`, `shared/content_schemas/items.json` (regenerado por `tools/gen_items_catalog.mjs`) | acompanham os dados | coerencia do gerador/validador |
| `tests/e6_items/test_item_equip.gd` | assert do emberfang 1,25 -> 1,20 | o teste codifica o valor do dado ajustado; justificativa neste documento |

### Compatibilidade com saves

- NENHUM `base_stats` ou `growth_per_level` de classe foi alterado; stats finais de um personagem existente sao recalculados no login a partir deles, dos
  talentos, do equipamento e do nivel - portanto continuam identicos. Guarda: `tests/e6_balance/test_balance_data.gd` congela esses valores e o espelho
  `shared/content_schemas/classes.json`.
- Vida do chefe, multiplicador de habilidade, tabelas de loot e parametros de unicos NAO sao persistidos por personagem. Instancias de item ja salvas
  guardam `uid`, raridade, ilvl e affixes (nao o numero do unico): o unico emberfang ja possuido passa a valer os novos numeros do `.tres`/`_uniques.json`
  (mais fracos). Nao ha migracao de banco. Jogadores que ja tinham o item perdem poder ofensivo do unico: aceito como ajuste de balanceamento pre-lancamento
  (nao ha saves de producao); registrado como risco no gate.
- XP, niveis e curva NAO mudaram.

## 5. Resultados medidos (antes x depois)

Todas as tabelas abaixo sao geradas por `tools/balance/balance_report.py` a partir dos JSONs.

### R1. Criterios: antes x depois

Antes: 67 criterios, 9 falhas. Depois: 67 criterios, 0 falhas.

| Criterio | Antes (dados originais) | Depois (dados ajustados) |
|---|---|---|
| `C4_unique_no_domination` | FALHA: maior ganho de dps de um unico = 70.0% em warrior/none/unique_emberfang/dps_gain_pct_hp30 (limite 30%) | OK: maior ganho de dps de um unico = 28.4% em ranger/none/unique_emberfang/dps_gain_pct_hp30 (limite 30%) |
| `C6_boss_ttk_warrior` | FALHA: 1 jogador 32.0 s (janela 40-120); 4 jogadores 26.0 s (janela 25-120) | OK: 1 jogador 48.3 s (janela 40-120); 4 jogadores 39.1 s (janela 25-120) |
| `C6_boss_ttk_mage` | FALHA: 1 jogador 30.2 s (janela 40-120); 4 jogadores 24.7 s (janela 25-120) | OK: 1 jogador 46.1 s (janela 40-120); 4 jogadores 37.4 s (janela 25-120) |
| `C8a_normal_rare_plus` | FALHA: Raro+ por abate de inimigo comum: max 0.0417 (ranged_caster), limite 0.020 | OK: Raro+ por abate de inimigo comum: max 0.0166 (bark_brute), limite 0.020 |
| `C8b_normal_epic_plus` | FALHA: Epico+ por abate de inimigo comum: max 0.01192 (ranged_caster), limite 0.0050 | OK: Epico+ por abate de inimigo comum: max 0.00475 (bark_brute), limite 0.0050 |
| `C8c_boss_legendary_reachable` | FALHA: abates do chefe por Lendario+ = 1.7 (janela 3-20) | OK: abates do chefe por Lendario+ = 6.3 (janela 3-20) |
| `C8d_boss_epic_reachable` | FALHA: abates do chefe por Epico+ = 0.8 (janela 1-6) | OK: abates do chefe por Epico+ = 1.5 (janela 1-6) |
| `C8e_boss_mythic_rare` | FALHA: abates do chefe por Mitico = 9.5 (minimo 50) | OK: abates do chefe por Mitico = 177.3 (minimo 50) |
| `C9a_unique_obtain` | FALHA: abates da melhor fonte por unico {"unique_emberfang":3.3,"unique_featherknot":5.0,"unique_frostbrand":4.0,"unique_gravitas_plate":4.0,"unique_twin_quiver":4.0} (janela 8-100); fora: ["unique_emberfang", "unique_gravitas_plate", "unique_featherknot", "unique_twin_quiver", "unique_frostbrand"] | OK: abates da melhor fonte por unico {"unique_emberfang":8.3,"unique_featherknot":16.7,"unique_frostbrand":10.0,"unique_gravitas_plate":10.0,"unique_twin_quiver":10.0} (janela 8-100); fora: [] |

Criterios que falham depois: nenhum.

### R2. Paridade de DPS entre classes (nivel 5, sem talentos, equipamento Comum)

| Classe | DPS chefe antes | DPS chefe depois | DPS bando antes | DPS bando depois | TTK chefe 1p antes (s) | TTK chefe 1p depois (s) | TTK chefe 4p antes (s) | TTK chefe 4p depois (s) |
|---|---|---|---|---|---|---|---|---|
| warrior | 37.4 | 37.3 | 50.7 | 50.7 | 32.0 | 48.3 | 26.0 | 39.1 |
| mage | 39.7 | 39.0 | 52.5 | 52.5 | 30.2 | 46.1 | 24.7 | 37.4 |
| ranger | 28.9 | 29.6 | 47.6 | 48.7 | 41.5 | 60.8 | 33.6 | 49.1 |

Desvio do DPS de chefe (depois) em relacao a mediana: warrior +0.0%, mage +4.6%, ranger -20.5%.

### R3. Sobrevivencia e duelo (nivel 5, Comum, sem talentos)

| Classe | Vida | Ataque | Defesa | Sobrevive ao chefe (s) | Razao de duelo vs chefe | TTK grunt (s) | TTK bando (s) |
|---|---|---|---|---|---|---|---|
| warrior | 175 | 19.0 | 4.0 | 64.7 | 0.75 | 1.30 | 35.5 |
| mage | 143 | 23.6 | 3.4 | 53.9 | 0.86 | 1.50 | 34.2 |
| ranger | 159 | 20.8 | 3.6 | 57.4 | 1.06 | 1.80 | 37.0 |

### R4. Builds de talento, nivel 10 (equipamento Comum, 1 jogador)

| Classe | Build | Pontos | DPS chefe | DPS bando | TTK chefe (s) | Sobrevive (s) | Indice de poder |
|---|---|---|---|---|---|---|---|
| warrior | berserker_burst | 9/9 | 78.8 | 98.6 | 22.9 | 90.1 | 84.2 |
| warrior | berserker_mobile | 9/9 | 67.0 | 81.8 | 26.9 | 90.1 | 77.7 |
| warrior | berserker_sturdy | 9/9 | 63.4 | 78.4 | 28.4 | 127.1 | 89.8 |
| warrior | generic_tank | 9/9 | 51.8 | 65.3 | 34.8 | 127.1 | 81.1 |
| warrior | none | 0/9 | 51.8 | 65.1 | 34.8 | 90.1 | 68.3 |
| mage | elementalist_bolt | 9/9 | 74.4 | 88.5 | 24.2 | 69.1 | 71.7 |
| mage | elementalist_combo | 9/9 | 58.4 | 73.6 | 30.9 | 69.1 | 63.5 |
| mage | elementalist_fire | 9/9 | 90.2 | 98.4 | 19.9 | 69.1 | 79.0 |
| mage | generic_sustain | 9/9 | 56.1 | 72.1 | 32.1 | 78.4 | 66.3 |
| mage | none | 0/9 | 55.6 | 72.1 | 32.4 | 69.1 | 62.0 |
| ranger | generic_skirmisher | 9/9 | 41.2 | 65.6 | 43.6 | 85.2 | 59.3 |
| ranger | hunter_ambush | 9/9 | 45.5 | 71.3 | 39.6 | 76.1 | 58.8 |
| ranger | hunter_deadeye | 9/9 | 66.5 | 91.8 | 27.1 | 76.1 | 71.2 |
| ranger | hunter_rain | 9/9 | 44.0 | 69.5 | 40.9 | 76.1 | 57.9 |
| ranger | none | 0/9 | 41.2 | 65.6 | 43.6 | 76.1 | 56.0 |

### R4. Builds de talento, nivel 20 (equipamento Comum, 1 jogador)

| Classe | Build | Pontos | DPS chefe | DPS bando | TTK chefe (s) | Sobrevive (s) | Indice de poder |
|---|---|---|---|---|---|---|---|
| warrior | berserker_burst | 19/19 | 131.9 | 145.8 | 13.7 | 155.7 | 143.3 |
| warrior | berserker_mobile | 19/19 | 102.6 | 110.1 | 17.6 | 155.7 | 126.4 |
| warrior | berserker_sturdy | 18/19 | 102.6 | 117.7 | 17.6 | 222.5 | 151.1 |
| warrior | generic_tank | 16/19 | 90.5 | 105.6 | 19.9 | 222.5 | 141.9 |
| warrior | none | 0/19 | 77.6 | 91.4 | 23.2 | 155.7 | 109.9 |
| mage | elementalist_bolt | 19/19 | 119.2 | 136.4 | 15.1 | 114.9 | 117.0 |
| mage | elementalist_combo | 19/19 | 148.8 | 142.9 | 12.1 | 102.4 | 123.4 |
| mage | elementalist_fire | 19/19 | 148.8 | 137.4 | 12.1 | 102.4 | 123.4 |
| mage | generic_sustain | 18/19 | 97.8 | 114.7 | 18.4 | 112.3 | 104.8 |
| mage | none | 0/19 | 88.0 | 103.8 | 20.4 | 102.4 | 94.9 |
| ranger | generic_skirmisher | 18/19 | 107.5 | 125.9 | 16.8 | 129.4 | 117.9 |
| ranger | hunter_ambush | 19/19 | 136.9 | 141.7 | 13.2 | 119.4 | 127.8 |
| ranger | hunter_deadeye | 19/19 | 134.8 | 136.9 | 13.3 | 119.4 | 126.9 |
| ranger | hunter_rain | 18/19 | 89.5 | 136.9 | 20.1 | 119.4 | 103.4 |
| ranger | none | 0/19 | 64.4 | 89.5 | 27.9 | 119.4 | 87.7 |

### R5. Escada de equipamento (nivel 5, build `none`, DPS contra o chefe / indice de poder)

| Classe | common | uncommon | rare | epic | legendary | mythic | fixed_best |
|---|---|---|---|---|---|---|---|
| warrior | 37.3 / 49.1 | 40.1 / 53.0 | 43.8 / 57.6 | 45.4 / 60.3 | 46.0 / 62.3 | 47.6 / 64.9 | 56.2 / 75.3 |
| mage | 39.0 / 45.8 | 41.8 / 49.7 | 45.2 / 54.2 | 46.0 / 55.9 | 48.2 / 57.6 | 48.8 / 60.5 | 53.3 / 67.0 |
| ranger | 29.6 / 41.2 | 32.9 / 44.9 | 34.5 / 48.4 | 35.6 / 50.6 | 36.3 / 52.3 | 36.7 / 54.0 | 43.4 / 62.2 |

### R6. Unicos: ganho sobre o mesmo personagem sem o unico (depois do ajuste)

| Classe | Build | Unico | DPS% (vida 100%) | DPS% (vida 30%) | DPS% bando | Sobrevive% chefe | dVida | dDefesa |
|---|---|---|---|---|---|---|---|---|
| mage | elementalist_fire | emberfang | 0.0 | 24.2 | 0.0 | 0.0 | 0 | 0.0 |
| mage | elementalist_fire | featherknot | 8.7 | 8.7 | 10.0 | -25.1 | -30 | 0.0 |
| mage | elementalist_fire | frostbrand | 16.3 | 16.3 | 11.5 | 0.0 | 0 | 0.0 |
| mage | elementalist_fire | gravitas_plate | 0.0 | 0.0 | 0.0 | 19.2 | -15 | 3.0 |
| mage | elementalist_fire | twin_quiver | 27.0 | 27.0 | 14.8 | -18.5 | -20 | 0.0 |
| mage | none | emberfang | 0.0 | 24.7 | 0.0 | 0.0 | 0 | 0.0 |
| mage | none | featherknot | 8.5 | 8.5 | 9.3 | -25.1 | -30 | 0.0 |
| mage | none | frostbrand | 19.3 | 19.3 | 17.1 | 0.0 | 0 | 0.0 |
| mage | none | gravitas_plate | 0.0 | 0.0 | 0.0 | 19.2 | -15 | 3.0 |
| mage | none | twin_quiver | 25.2 | 25.2 | 23.6 | -18.5 | -20 | 0.0 |
| ranger | hunter_deadeye | emberfang | 0.0 | 24.9 | 0.0 | 0.0 | 0 | 0.0 |
| ranger | hunter_deadeye | featherknot | 0.9 | 0.9 | -1.0 | -22.9 | -30 | 0.0 |
| ranger | hunter_deadeye | frostbrand | 17.9 | 17.9 | 12.7 | 0.0 | 0 | 0.0 |
| ranger | hunter_deadeye | gravitas_plate | 0.0 | 0.0 | 0.0 | 20.3 | -15 | 3.0 |
| ranger | hunter_deadeye | twin_quiver | 19.3 | 19.3 | 11.8 | -16.9 | -20 | 0.0 |
| ranger | none | emberfang | 0.0 | 28.4 | 0.0 | 0.0 | 0 | 0.0 |
| ranger | none | featherknot | 0.6 | 0.6 | 2.5 | -22.9 | -30 | 0.0 |
| ranger | none | frostbrand | 21.5 | 21.5 | 14.9 | 0.0 | 0 | 0.0 |
| ranger | none | gravitas_plate | 0.0 | 0.0 | 0.0 | 20.3 | -15 | 3.0 |
| ranger | none | twin_quiver | 22.4 | 22.4 | 22.8 | -16.9 | -20 | 0.0 |
| warrior | berserker_burst | emberfang | 0.0 | 23.6 | 0.0 | 0.0 | 0 | 0.0 |
| warrior | berserker_burst | featherknot | 0.6 | 0.6 | 4.8 | -21.3 | -30 | 0.0 |
| warrior | berserker_burst | frostbrand | 17.8 | 17.8 | 16.0 | 0.0 | 0 | 0.0 |
| warrior | berserker_burst | gravitas_plate | 0.0 | 0.0 | 0.0 | 22.1 | -15 | 3.0 |
| warrior | berserker_burst | twin_quiver | 9.9 | 9.9 | 10.0 | -15.9 | -20 | 0.0 |
| warrior | none | emberfang | 0.0 | 26.9 | 0.0 | 0.0 | 0 | 0.0 |
| warrior | none | featherknot | 1.4 | 1.4 | 2.0 | -21.3 | -30 | 0.0 |
| warrior | none | frostbrand | 22.7 | 22.7 | 17.9 | 0.0 | 0 | 0.0 |
| warrior | none | gravitas_plate | 0.0 | 0.0 | 0.0 | 22.1 | -15 | 3.0 |
| warrior | none | twin_quiver | 14.6 | 14.6 | 11.3 | -15.9 | -20 | 0.0 |

Antes do ajuste (mesma tabela, so os maiores ganhos de DPS a vida 30%):

| Classe | Build | Unico | DPS% (100%) | DPS% (30%) | DPS% bando |
|---|---|---|---|---|---|
| warrior | none | emberfang | 30.8 | 70.0 | 22.2 |
| ranger | none | emberfang | 26.7 | 68.0 | 21.3 |
| mage | none | emberfang | 22.3 | 65.0 | 18.9 |
| ranger | hunter_deadeye | emberfang | 17.0 | 54.9 | 11.3 |
| warrior | berserker_burst | emberfang | 20.1 | 53.0 | 21.1 |
| mage | elementalist_fire | emberfang | 17.3 | 50.8 | 11.5 |

### R7. Talentos: ganho isolado por ponto (nivel 20, DPS contra o chefe), depois do ajuste

| Classe | Nos | Com efeito de DPS | Sem efeito de DPS (utilidade) | Mediana %/ponto | Maior %/ponto (no) | Maior / mediana |
|---|---|---|---|---|---|---|
| warrior | 15 | 7 | 8 | 4.15 | b_frenzy (6.94) | 1.7 |
| mage | 15 | 6 | 9 | 3.92 | e_twin_fireball (7.46) | 1.9 |
| ranger | 15 | 9 | 6 | 4.92 | r_deep_quiver (13.18) | 2.7 |

### R8. Curva de XP e fontes

| Nivel | XP p/ proximo | XP acumulado | Razao vs nivel anterior |
|---|---|---|---|
| 1 | 100 | 100 | 0.00 |
| 2 | 283 | 383 | 2.83 |
| 3 | 520 | 903 | 1.84 |
| 4 | 800 | 1703 | 1.54 |
| 5 | 1118 | 2821 | 1.40 |
| 6 | 1470 | 4291 | 1.31 |
| 7 | 1852 | 6143 | 1.26 |
| 8 | 2263 | 8406 | 1.22 |
| 9 | 2700 | 11106 | 1.19 |
| 10 | 3162 | 14268 | 1.17 |
| 15 | 5809 | 37807 | 1.11 |
| 20 | 8944 | 76079 | 1.08 |
| 30 | 16432 | 205461 | 1.05 |
| 40 | 25298 | 417495 | 1.04 |
| 49 | 34300 | 689513 | 1.03 |

| Fonte | XP total | Participacao |
|---|---|---|
| Abates (um de cada, chefe incl.) | 2860 | 44% |
| Quests (12) | 3070 | 47% |
| Exploracao (9 pontos) | 575 | 9% |
| Total | 6505 | 100% |

Nivel final: tudo = 8; so abates = 6; so quests = 6.

### R9. Drops por raridade (Monte Carlo com o LootManager real, 3000 abates por tipo, semente fixa; analitico entre parenteses)

Depois do ajuste:

| Inimigo | Tier | Equip./abate | Raro/abate | Epico/abate | Lendario/abate | Mitico/abate | Unico/abate (analitico) |
|---|---|---|---|---|---|---|---|
| bark_brute | normal | 0.116 | 0.0137 (0.0119) | 0.0023 (0.0036) | 0.0010 (0.0011) | 0.0000 (0.0001) | 0.010 |
| blight_treant | boss | 2.090 | 1.1373 (1.1281) | 0.5107 (0.5076) | 0.1587 (0.1523) | 0.0060 (0.0056) | 0.420 |
| bow_scout | normal | 0.047 | 0.0050 (0.0043) | 0.0017 (0.0013) | 0.0000 (0.0004) | 0.0003 (0.0000) | 0.000 |
| burrow_lurker | normal | 0.094 | 0.0123 (0.0086) | 0.0030 (0.0026) | 0.0007 (0.0008) | 0.0003 (0.0001) | 0.000 |
| forest_stalker | normal | 0.000 | 0.0000 (0.0000) | 0.0000 (0.0000) | 0.0000 (0.0000) | 0.0000 (0.0000) | 0.000 |
| grove_shaman | normal | 0.106 | 0.0087 (0.0111) | 0.0033 (0.0033) | 0.0010 (0.0010) | 0.0003 (0.0001) | 0.000 |
| melee_grunt | normal | 0.097 | 0.0137 (0.0091) | 0.0030 (0.0027) | 0.0007 (0.0008) | 0.0003 (0.0001) | 0.000 |
| ranged_caster | normal | 0.102 | 0.0097 (0.0110) | 0.0020 (0.0033) | 0.0007 (0.0010) | 0.0000 (0.0001) | 0.000 |
| root_sprout | normal | 0.000 | 0.0000 (0.0000) | 0.0000 (0.0000) | 0.0000 (0.0000) | 0.0000 (0.0000) | 0.000 |
| thorn_alpha | mini_boss | 1.094 | 0.2937 (0.3047) | 0.1880 (0.1828) | 0.0880 (0.0823) | 0.0137 (0.0091) | 0.200 |

Antes do ajuste:

| Inimigo | Tier | Equip./abate | Raro/abate | Epico/abate | Lendario/abate | Mitico/abate | Unico/abate (analitico) |
|---|---|---|---|---|---|---|---|
| bark_brute | normal | 0.217 | 0.0197 (0.0224) | 0.0067 (0.0067) | 0.0013 (0.0020) | 0.0003 (0.0002) | 0.010 |
| blight_treant | boss | 2.090 | 0.7187 (0.6991) | 0.6243 (0.6292) | 0.4643 (0.4719) | 0.1087 (0.1049) | 1.050 |
| bow_scout | normal | 0.047 | 0.0050 (0.0043) | 0.0017 (0.0013) | 0.0000 (0.0004) | 0.0003 (0.0000) | 0.000 |
| burrow_lurker | normal | 0.094 | 0.0123 (0.0086) | 0.0030 (0.0026) | 0.0007 (0.0008) | 0.0003 (0.0001) | 0.000 |
| forest_stalker | normal | 0.000 | 0.0000 (0.0000) | 0.0000 (0.0000) | 0.0000 (0.0000) | 0.0000 (0.0000) | 0.000 |
| grove_shaman | normal | 0.166 | 0.0167 (0.0172) | 0.0040 (0.0052) | 0.0013 (0.0015) | 0.0003 (0.0002) | 0.000 |
| melee_grunt | normal | 0.097 | 0.0137 (0.0091) | 0.0030 (0.0027) | 0.0007 (0.0008) | 0.0003 (0.0001) | 0.000 |
| ranged_caster | normal | 0.297 | 0.0283 (0.0298) | 0.0073 (0.0089) | 0.0020 (0.0027) | 0.0003 (0.0003) | 0.000 |
| root_sprout | normal | 0.000 | 0.0000 (0.0000) | 0.0000 (0.0000) | 0.0000 (0.0000) | 0.0000 (0.0000) | 0.000 |
| thorn_alpha | mini_boss | 1.094 | 0.2937 (0.3047) | 0.1880 (0.1828) | 0.0880 (0.0823) | 0.0137 (0.0091) | 0.600 |

Abates da melhor fonte por unico (analitico):

| Unico | Antes | Depois |
|---|---|---|
| unique_emberfang | {"best_kills": 3.3, "min_level": 5, "sources": [{"chance": 0.2, "kills_per_unique": 5.0, "loot_table": "loot_thorn_alpha"}, {"chance": 0.3, "kills_per_unique": 3.3, "loot_table": "loot_blight_treant"}]} | {"best_kills": 8.3, "min_level": 5, "sources": [{"chance": 0.06, "kills_per_unique": 16.7, "loot_table": "loot_thorn_alpha"}, {"chance": 0.12, "kills_per_unique": 8.3, "loot_table": "loot_blight_treant"}]} |
| unique_featherknot | {"best_kills": 5.0, "min_level": 3, "sources": [{"chance": 0.2, "kills_per_unique": 5.0, "loot_table": "loot_thorn_alpha"}, {"chance": 0.01, "kills_per_unique": 100.0, "loot_table": "loot_bark_brute"}]} | {"best_kills": 16.7, "min_level": 3, "sources": [{"chance": 0.06, "kills_per_unique": 16.7, "loot_table": "loot_thorn_alpha"}, {"chance": 0.01, "kills_per_unique": 100.0, "loot_table": "loot_bark_brute"}]} |
| unique_frostbrand | {"best_kills": 4.0, "min_level": 5, "sources": [{"chance": 0.25, "kills_per_unique": 4.0, "loot_table": "loot_blight_treant"}, {"chance": 0.1, "kills_per_unique": 10.0, "loot_table": "loot_thorn_alpha"}]} | {"best_kills": 10.0, "min_level": 5, "sources": [{"chance": 0.1, "kills_per_unique": 10.0, "loot_table": "loot_blight_treant"}, {"chance": 0.04, "kills_per_unique": 25.0, "loot_table": "loot_thorn_alpha"}]} |
| unique_gravitas_plate | {"best_kills": 4.0, "min_level": 5, "sources": [{"chance": 0.25, "kills_per_unique": 4.0, "loot_table": "loot_blight_treant"}, {"chance": 0.1, "kills_per_unique": 10.0, "loot_table": "loot_thorn_alpha"}]} | {"best_kills": 10.0, "min_level": 5, "sources": [{"chance": 0.1, "kills_per_unique": 10.0, "loot_table": "loot_blight_treant"}, {"chance": 0.04, "kills_per_unique": 25.0, "loot_table": "loot_thorn_alpha"}]} |
| unique_twin_quiver | {"best_kills": 4.0, "min_level": 5, "sources": [{"chance": 0.25, "kills_per_unique": 4.0, "loot_table": "loot_blight_treant"}]} | {"best_kills": 10.0, "min_level": 5, "sources": [{"chance": 0.1, "kills_per_unique": 10.0, "loot_table": "loot_blight_treant"}]} |

### R10. Uso de habilidades e pontos de talento (nivel 5, sem talentos / nivel 20 builds de pico)

| Classe | Habilidade | Usos/min (luta vs chefe) | Parcela do dano |
|---|---|---|---|
| warrior | basic_attack | 115.5 | 66% |
| warrior | dodge | 12.4 | 0% |
| warrior | heavy_strike | 18.6 | 34% |
| mage | arcane_bolt | 89.7 | 67% |
| mage | blink | 11.7 | 0% |
| mage | fireball | 13.0 | 28% |
| mage | frost_nova | 3.9 | 5% |
| ranger | arrow_rain | 6.9 | 14% |
| ranger | piercing_arrow | 13.8 | 24% |
| ranger | quick_shot | 86.9 | 62% |
| ranger | roll | 11.9 | 0% |

| Nivel | Pontos de talento disponiveis |
|---|---|
| 5 | 4 |
| 10 | 9 |
| 20 | 19 |


### Leitura dos resultados

- Dos 67 criterios, 9 falhavam com os dados originais (R1) e nenhum falha depois. Todos os ajustes foram feitos em dados.
- Paridade de classes (R2): passou sem mexer em stats de classe. O arqueiro fica -20,5% abaixo da mediana no nivel 5 (dentro de +-25%, mas e o ponto mais
  proximo do limite); em nivel 20 as builds de pico das tres classes ficam entre 123 e 143 de indice de poder.
- Builds (R4): sem build obrigatoria nem inutil pelos criterios; ainda assim `berserker_burst` (guerreiro) e `elementalist_fire/combo` (mago) lideram DPS no
  nivel 20 e `hunter_rain` e a mais fraca do arqueiro (indice 103,4 contra 117,9-127,8). Recomendacao de playtest, nao falha.
- Talentos (R7): 23 dos 45 nos nao tem efeito de DPS no modelo (sao utilidade: vida, recurso, velocidade, controle) - o simulador nao valora isso; o no
  mais forte por ponto e `r_deep_quiver` (13,2%/ponto, 2,7x a mediana do arqueiro), dentro do limite de 4x.
- Unicos (R6): o maior ganho de DPS depois do ajuste e emberfang no arqueiro sem build (+28,4% com vida 30%, limite 30%); a margem e pequena. `featherknot` e
  `gravitas_plate` sao trocas defensivas/de utilidade (vida -30 ou -15; sobrevive +19 a +22%) e `featherknot` tem efeito de DPS desprezivel para classes
  que nao dependem dele (0,6-1,4% fora do mago) - o criterio `unique_min_decision_effect_pct` (3%) e satisfeito pelo efeito em sobrevivencia, nao por DPS.
- Loot (R9): o Monte Carlo (3000 abates) concorda com o calculo analitico dentro do ruido esperado para eventos raros (por exemplo Epico+ de inimigo comum
  0,2-0,3% contra 0,13-0,48% analitico).
- XP (R8): subida de 2,83x so de 1->2, depois <= 1,84x e decrescente; todo o conteudo do Greenwood (abates unicos + 12 quests + 9 pontos) soma 6505 XP =
  nivel 8. Observacao: o numero de abates usado e UM de cada tipo (a medicao e de fontes de XP, nao de tempo de jogo); o ritmo real de level-up depende de
  quanto o jogador repete abates e so playtest responde.


## 6. Skills, pontos e builds - achados

- `arrow_rain` era dominada por `piercing_arrow` (menor dano, mesmo custo/uso): corrigida (1,7 -> 2,0). Agora sai com 6,9 usos/min e 14% do dano do arqueiro (R10).
- `whirlwind`, `arrow_rain` e `frost_nova` so se justificam contra grupos (AoE): o simulador mostra o DPS de bando acima do de chefe nas builds que as potencializam.
- Os nos de recurso/vida/velocidade nao aparecem como DPS (R7): sao escolhas de sobrevivencia/utilidade, que o modelo cobre apenas pelo tempo de sobrevivencia.
- Nos de projetil extra sao os mais fortes por ponto (~10-13%/ponto contra ~4% de mediana), mas ficam dentro do limite de 4x.
- Defesa fixa do chefe (6) amplifica bonus de ataque fixo (`attack_power`) e percentuais: por isso o ajuste do emberfang foi feito em `attack_power` + `damage_pct`.

## 7. Telemetria essencial do servidor

Implementacao: `ServerMetrics` (`scripts/server/server_metrics.gd`), instanciada pela `ServerSession`. Contadores em memoria, sem servico externo e sem custo.

| Categoria | Chave | Quando conta |
|---|---|---|
| `joins` | classe | jogador entrou |
| `skill_use` | `classe.habilidade` | habilidade REALMENTE iniciada no servidor (recusas nao contam) |
| `kills` | tipo de inimigo | abate por jogador |
| `xp_from_kills` | `killer` | XP concedido por abates |
| `drops_rarity` | raridade da instancia | item com raridade COLETADO |
| `drops_unique` | id do unico | unico coletado |
| `drops_items` | item | item simples coletado (x quantidade) |
| `quests_completed` | id da quest | quest concluida |
| `pois_discovered` | id do ponto | ponto de exploracao descoberto |
| `talents` | operacao (`allocate`, `choose_spec`, `respec`) | comando APLICADO |
| `equips` | raridade ou `unequip` | equipar/desequipar |
| `crafts` | item produzido | craft concluido |

- Saida: uma linha de log estruturada `[metrics] {"uptime_s":..., "dropped_keys":0, "counters":{"categoria":{"nome":n}}}` a cada `--metrics-interval=<s>`
  (padrao 60 s; `0` desliga o periodico; maximo 86400) e uma linha final no `shutdown()`. Vai pelo `ServerLog` (stdout do servidor), que o operador ja coleta.
- Privacidade: so contagens agregadas. Nomes de chave passam por `sanitize` (`[a-z0-9_.]`, <= 64 caracteres), portanto texto livre vindo do cliente nunca vira chave.
  Nao ha id de personagem, nome de jogador, ticket, token ou segredo; `tests/e6_balance/test_telemetry.gd` confere que nenhuma linha contem essas strings.
- Memoria limitada: no maximo 512 chaves distintas; excedentes incrementam `dropped_keys` (chaves existentes continuam somando).
- Contagem de drops: mede o que o jogador recebeu (coleta), nao o que foi rolado - e o que importa para a economia.
- Nao ha endpoint novo: o servidor Godot de sessao nao expoe HTTP; o backend protegido existente nao recebe essas metricas (decisao DEC-0028).
- Para ler: `grep '^\[metrics\]' <log>`; o ultimo snapshot do processo e a linha final do desligamento.

## 8. Exploits e anti-duplicacao: cobertura

Cada teste TENTA o exploit e confirma que ele falha. `backend/test/exploits.test.ts` roda no backend REAL (PGlite, 20 testes); `tests/e6_balance/test_exploits.gd`
roda no servidor Godot contra o backend falso, que espelha as regras do real (14 verificacoes).

| Exploit | Backend real (`exploits.test.ts`) | Servidor Godot (`test_exploits.gd`) |
|---|---|---|
| Replay de recompensa (mesma chave) | N replays -> `replayed:true`, XP/itens/revisao inalterados | recompensa de quest reenviada 3x -> XP uma vez |
| Mesma chave, corpo adulterado | XP maior -> 400 `quest_reward_mismatch`; loot com conteudo diferente -> 409 `idempotency_key_reuse` | - |
| Chave nova para a mesma quest / chave de outro personagem | recusadas, XP inalterado | outra chave -> recusada pelo backend, XP inalterado |
| Replays paralelos | 8 em paralelo -> exatamente 1 aplicacao | - |
| Fencing (sessao sem o lock) | recompensa recusada (>= 400) | - |
| Uid duplicado sob outra chave / em paralelo | 409 `duplicate_instance`; 6 paralelos -> 1 vence | coleta repetida e replay da chave de loot (x2): inventario do backend inalterado |
| Checkpoint forjado (instancia inexistente), duplicado (2 copias) ou com affixes alterados | 422 / >= 400; nada muda | - |
| Instancia em item base diferente | recusada | - |
| Equipar + craftar + checkpoint + recompensa simultaneos (3 rodadas) | cada uid existe no maximo uma vez; a original nunca some | equipar com craft em voo -> `busy`; com talento em voo -> `busy` |
| Equipar a instancia e deixar copia no inventario | checkpoint recusado | - |
| Replay de `talent_cmd` | mesma chave -> `replayed:true`; outra operacao com a mesma chave -> 409 `idempotency_key_reuse` | req_id repetido/antigo (12 rodadas) nao aplica; gasto <= pontos do nivel |
| Alocacao paralela alem dos pontos | 10 paralelas, 2 pontos -> no maximo 2 aplicadas; `no_points` em loop | gasto no backend = gasto em memoria <= pontos |
| Chave de talento de outra sessao/personagem | recusada | - |
| Respec repetido com a mesma chave | custo cobrado uma vez | - |
| Descoberta repetida | mesma chave 6x paralelo -> 1; chave forjada recusada; sem claim -> 409 `poi_already_discovered` | entrar/sair 4x do ponto -> 1 pagamento; replay + chave forjada: XP inalterado |
| Checkpoint apagando `discovered` | campo somente-servidor continua intacto | - |

Nenhum exploit funcionou: todas as tentativas foram recusadas ou neutralizadas pelo backend. Duas correcoes de TESTE (nao de comportamento) foram necessarias na
primeira execucao: no backend, o corpo adulterado de quest recebe 400 `quest_reward_mismatch` (validacao contra o catalogo, antes da checagem de chave) e nao
409 como o teste previa - igualmente seguro, nada aplicado; no Godot, os cenarios de `busy` usavam a opcao `hold` errada do rig de teste (o jogador nem entrava).

Lacunas conhecidas (nao cobertas por teste automatizado): (1) o mesmo uid em dois personagens distintos aceita ate a segunda entrega se a origem
(servidor de sessao) a emitir - a unicidade global depende de que so o servidor de sessao autenticado emita instancias, nao de uma constraint no banco
(o teste registra o contrato atual); (2) concorrencia real entre processos do backend (PGlite e monoprocesso); (3) duplicacao por desconexao no meio de um
checkpoint sob latencia real; (4) corrida entre dois servidores de sessao para o mesmo personagem (coberta pelo fencing do M4, nao repetida aqui).

## 9. Limites do modelo e o que depende de playtest humano

- DPS sustentado contra alvo parado: nao mede movimento, esquiva real, telegrafos do chefe, posicionamento, kiting nem adds.
- Chefe: fases em media; o balanceamento real de dificuldade (leitura de ataques, janelas de dano) precisa de jogadores.
- Talentos de utilidade (controle, velocidade, recurso, cura) sao subvalorizados pelo modelo.
- Ritmo de level-up depende de quantas vezes o jogador repete abates; o modelo conta uma ocorrencia de cada fonte.
- Loot: taxas medidas por abate; a sensacao de "raro" depende da frequencia de abates por hora e da economia (venda/craft), ainda nao implementadas.
- Faixas-alvo sao propostas (DEC-0026); o dono do produto pode muda-las em `data/balance/balance_config.json` sem tocar em codigo e reexecutar.


## E7.1 — Telemetria adicional
A linha `[metrics]` e o snapshot de `ServerMetrics` ganharam: categorias `rejects`, `reconnects`, `disconnects`; `gauges` (`players_online`, `peers`, `pending`, `tick`); `timings` com p50/p95/máx de `tick_ms`, `tick_dt_ms` e `snapshot_bytes` (600 amostras). Consumidores do formato antigo continuam válidos (campos novos são aditivos). Sem PII.
