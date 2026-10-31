# E5.2 - Inimigos, mini-chefe e chefe de Greenwood

Conteudo e arte sao PLACEHOLDER (formas/cores simples, nomes "[PLACEHOLDER]"). Tudo e data-driven (`data/enemies/*.tres`); a IA roda so no servidor (`ServerWorld`), o cliente apenas apresenta (snapshots + eventos do protocolo v2).

## Ids para o agente de quests (exatos)
Inimigos comuns: `melee_grunt`, `ranged_caster`, `forest_stalker`, `bow_scout`, `bark_brute`, `grove_shaman`, `burrow_lurker`, `root_sprout`.
Mini-chefe: `thorn_alpha`. Chefe: `blight_treant`. (`EnemyCatalog.GREENWOOD_REGULAR`, `MINI_BOSS_ID`, `BOSS_ID`, `all_ids()`.)
- O id do inimigo e o nome de `data/enemies/<id>.tres`, `scenes/enemy/<id>.tscn` e `loot_<id>` (`data/loot/`). O tipo viaja no snapshot (`type`) e em `enemy_spawn`.
- O sinal `ServerWorld.enemy_killed(enemy_id, killer_id, xp, items)` traz o id de ENTIDADE; o id de tipo e `ServerWorld.get_enemy_node(enemy_id).data.id` (valido durante o sinal; o corpo some 0,7 s depois).
- `root_sprout` e add invocado (xp 8): decida se conta para quests de caca. Adds **dispensados** (invocador morreu / encontro reiniciou) NAO emitem `defeated` nem `enemy_killed`.
- Para criar inimigo no servidor: `ServerWorld.spawn_enemy(EnemyCatalog.scene_path(&"bark_brute"), Vector3)`. Nada em `scripts/arena` / `TestArena.ENEMY_SPAWNS` foi alterado (a arena de teste continua com 3 grunts + 2 casters).

## Tabela de inimigos
Stats: vida / ataque (poder) / defesa / velocidade (m/s). Dano bruto de um golpe = poder x multiplicador do ataque x multiplicadores de fase e de dificuldade (depois a defesa do alvo). Todo ataque tem telegrafo (`windup`) com o inimigo PARADO e indicador de chao (`EnemyTelegraph`) que escurece ate o golpe; o corpo tambem incha 25% durante o windup.

| id | Papel | HP / ATQ / DEF / VEL | Aggro | Ataques (telegrafo) | XP | Loot (`loot_<id>`) |
|---|---|---|---|---|---|---|
| `melee_grunt` (E2) | melee basico | 60 / 8 / 1 / 3,5 | 10 | golpe frontal: windup 0,45 s, pausa 1,4 s, alcance 1,8 (caixa) | 40 | scrap 1-3, potion, sword_basic, armor_leather (40% nada) |
| `ranged_caster` (E2) | ranged magico | 40 / 10 / 0 / 3,0 | 14 | orbe 12 m/s x1,2: windup 0,45 s, pausa 2,2 s; recua se alvo < 4,5 m | 60 | potion 1-2, amulet_vigor, sword_rare, armor_heavy (2 rolls) |
| `forest_stalker` | rapido (flanqueador) | 36 / 6 / 0 / 5,6 | 11 | mordida: windup 0,30 s, pausa 1,0 s, alcance 1,7 | 45 | scrap 1-2, potion (45% nada) |
| `bow_scout` | arqueiro | 34 / 9 / 0 / 3,4 | 16 | flecha 20 m/s x1,1, alcance 3-12: windup 0,60 s (linha no chao), pausa 2,0 s; recua se alvo < 5,5 m | 55 | scrap 1-2, potion, armor_leather |
| `bark_brute` | brutamontes | 140 / 16 / 3 / 2,6 | 9 | varrida (caixa 2,2 x 2,6, x0,8): 0,60 s, pausa 1,6 s; pancada no chao (AOE raio 2,6 a 1,4 m a frente, x1,1): 0,90 s, pausa 2,4 s, recarga propria 4 s | 110 | scrap 2-4, potion 1-2, armor_heavy, sword_basic (2 rolls) |
| `grove_shaman` | invocador/suporte | 50 / 7 / 0 / 2,8 | 14 | espinho 11 m/s: 0,55 s, pausa 2,2 s; invocar brotos (anel ciano): 1,20 s, recarga 14 s, 2 `root_sprout`, max 3 vivos e 6 por encontro; recua se alvo < 4,5 m | 90 | potion 1-2, scrap 1-3, amulet_vigor (2 rolls) |
| `burrow_lurker` | emboscador | 55 / 11 / 1 / 4,2 | 6,5 (leash 16) | "enterrado" (corpo achatado) ate o alvo chegar a 6,5 m; bote (investida 6 m a 14 m/s, x1,3, alcance 2,8-6,5): 0,45 s, recarga 6 s; garra (alcance 1,8, x0,9): 0,35 s, pausa 1,2 s | 85 | scrap 1-3, potion, armor_leather, sword_rare |
| `root_sprout` | add (invocado) | 18 / 5 / 0 / 3,8 | 12 | chicote: 0,50 s, pausa 1,6 s, alcance 1,5 | 8 | 10% scrap |

## Mini-chefe `thorn_alpha` (Alfa Espinhoso, tier `mini_boss`)
HP 420 / ATQ 14 / DEF 4 / VEL 3,2; aggro 14, leash 30; XP 400; loot `loot_thorn_alpha` (3 rolls; potion 1-3, scrap 3-6, amulet_vigor, armor_heavy, sword_rare).
| Fase | Entra em | Mudancas | Ataques |
|---|---|---|---|
| 1 `alpha_p1` | 100% | - | `swipe` (caixa 2,6 x 3,0): 0,6 s; `slam` (AOE raio 3,2 centrado nele, x1,2): 1,0 s, recarga 5 s |
| 2 `alpha_p2` | <= 50% | transicao 0,8 s (parado + invulneravel); velocidade x1,25; dano x1,2; pausas x0,8; invoca 2 `forest_stalker` | + `gore` (investida 8 m a 15 m/s, x1,4, alcance 5-12): 0,8 s, recarga 7 s |

## Chefe `blight_treant` (Anciao Corrompido, tier `boss`)
HP 1200 / ATQ 18 / DEF 6 / VEL 2,4; aggro 20, leash 45; escala visual 2,2 (hurtbox maior); XP 1200; loot `loot_blight_treant` (4 rolls, sem "nada"; potion 2-4, scrap 4-8, amulet_vigor, armor_heavy, sword_rare).
| Fase | Entra em | Mudancas | Ataques |
|---|---|---|---|
| 1 `treant_p1` | 100% | - | `sweep` (caixa 3,6 x 4,0): 0,8 s, pausa 1,8 s; `stomp` (AOE raio 4,5 em volta dele, x1,2): 1,1 s, pausa 2,2 s, recarga 6 s |
| 2 `treant_p2` | <= 66% | transicao 1,0 s; invoca 3 `root_sprout` | + `seed_volley` (5 sementes em leque de 50 graus, x0,7, alcance 4-16): 0,9 s, recarga 6 s; `call_sprouts` (2 brotos, max 4 vivos / 8 no total): 1,3 s, recarga 18 s |
| 3 `treant_p3` | <= 33% | transicao 1,0 s; velocidade x1,2; dano x1,25; pausas x0,75; invoca 2 `forest_stalker` | sweep, stomp, `seed_volley` (7 sementes, 70 graus) + `trample` (investida 10 m a 13 m/s, x1,5, alcance 6-14): 1,0 s, recarga 9 s (sem `call_sprouts`) |

Regras comuns de fase: so avancam (vida subindo nao volta); um golpe que cruza dois limiares entra nas duas, em ordem; golpe letal nao dispara fase; durante a transicao o chefe fica parado e invulneravel (o windup em andamento e cancelado); o dano durante a transicao e ignorado (nao ha como pular fase). Reset do encontro (leash estourado ou todos os jogadores mortos): vida cheia, fase 1, ameaca limpa, adds dispensados, volta a origem (mini-chefe/chefe so; comuns mantem o comportamento do E2).

## Dados (como estao modelados)
- `EnemyAttack` (`scripts/data/enemy_attack.gd`): `kind` MELEE | AOE | PROJECTILE | CHARGE | SUMMON, `windup` (> 0 obrigatorio), `cooldown` (pausa global apos o golpe), `own_cooldown`, `damage_multiplier`, faixa `min_range..max_range` em que pode ser iniciado, `weight` (sorteio), geometria (`width`, `radius`, `aoe_offset`, `projectile_count/spread_degrees/projectile_speed`, `charge_distance/charge_speed`) e invocacao (`summon_id/summon_count/summon_max_alive/summon_max_total`). `validate()` lista erros.
- `EnemyPhase` (`enemy_phase.gd`): `health_threshold` (fase 0 = 1,0; estritamente decrescente), `attacks`, `speed_mult`, `damage_mult`, `cooldown_mult`, `transition_time` (0..3 s), `summon_id/summon_count` ao entrar.
- `EnemyData` ganhou (padroes neutros; E2 intacto): `tier` (normal|mini_boss|boss), `role`, `windup`, `leash_range`, `attacks`, `phases`, `ambush`, `dismiss_adds_on_death`, `visual_shape/color/scale`. Sem `attacks`/`phases` vale o ataque unico legado (behavior melee/ranged). Chefe exige `phases`; `attacks` e `phases` sao exclusivos.
- `ContentRegistry.validate()` agora tambem confere tier, windup, leash, fases (ordem), ataques, `summon_id` existente, auto-invocacao e a escala de dificuldade.
- Regerar os .tres de Greenwood: `$G --headless --path . --script res://scripts/data/greenwood_generator.gd` (apos `--import`; so toca nos 8 inimigos novos, seus loots e `data/difficulty/`; nao reescreve os itens nem os 2 inimigos do E2). Os valores vivem no gerador; edicao manual dos .tres tambem vale.
- Itens: nenhum novo (7 existentes). Loot usa so `scrap_material`, `potion_minor`, `sword_basic`, `sword_rare`, `armor_leather`, `armor_heavy`, `amulet_vigor`.

## Escala de dificuldade (`data/difficulty/greenwood_coop.tres`, `DifficultyScaling`)
`vida = min(teto, 1 + bonus x (n-1))`, `dano = min(teto, 1 + bonus x (n-1))`, n = jogadores conectados (1..4). Funcao pura: `health_mult(n, tier)` / `damage_mult(n, tier)`; tetos absolutos no codigo (vida 6x, dano 2x) valem mesmo com dados absurdos; a validacao os rejeita.
| Jogadores | 1 | 2 | 3 | 4 |
|---|---|---|---|---|
| Vida comum | 1,00 | 1,50 | 2,00 | 2,50 |
| Vida chefe / mini-chefe | 1,00 | 1,75 | 2,50 | 3,25 |
| Dano | 1,00 | 1,10 | 1,20 | 1,30 |
Teto dos dados: vida 3,5x, dano 1,35x. `ServerWorld.refresh_difficulty()` roda ao entrar/sair jogador e ao criar inimigo; `Enemy.set_difficulty` preserva a PROPORCAO de vida (sair nao cura, entrar nao mata). Adds invocados nascem com a escala atual.

## Alvo / agro (servidor)
`ThreatTable` (dano causado por jogador, decai 10%/s) + `TargetSelector.pick`: maior ameaca entre os vivos a ate `leash_range` do inimigo, com histerese (so troca se a ameaca nova > atual x 1,25); sem ameaca valida, o jogador vivo mais proximo (empate: menor id). Jogador morto sai da lista no mesmo tick (sem RETURN indevido); jogador que sai tem a ameaca removida; sem jogadores vivos os inimigos param (como no E3) e chefes reiniciam.

## Replicacao (protocolo v2, aditivo)
Ver `shared/contracts/network_protocol.md`: campos opcionais `phase` e `atk` na entidade-inimigo do snapshot e evento `7 enemy_phase {id, phase}`. Adds invocados geram `enemy_spawn` normal. `ClientWorld` usa `EnemyCatalog.data_for(type)` para cor/escala e desenha o indicador de chao quando `state == ATTACK` e `atk != ""`. `SnapshotInterpolator._view` repassa `phase`/`atk`.

## Arquivos
Dados: `scripts/data/{enemy_attack,enemy_phase,difficulty_scaling,greenwood_generator}.gd`, `data/enemies|loot|difficulty/`, `scenes/enemy/<id>.tscn`. Logica: `scripts/enemy/{enemy,enemy_ai,enemy_visual}.gd` (alterados), `enemy_phase_controller`, `threat_table`, `target_selector`, `enemy_catalog`, `enemy_telegraph` (novos). Servidor/rede/cliente: `server_world.gd`, `protocol.gd`, `snapshot_interpolator.gd`, `client_world.gd`.

## Testes (`tests/e5/`, incluidos em `tests/e2/test_data_content.gd` os novos totais)
- `test_e5_data`: carregam/validam 10 inimigos, cenas, loots, fases; dados sinteticos quebrados sao rejeitados. Deterministico.
- `test_e5_scaling_threat`: escala 1-4 jogadores e tetos, controle de fase, ameaca, selecao de alvo, validacao de `phase`/`atk`. Deterministico.
- `test_e5_ai`: selecao de ataque (alcance/recarga/peso/semente/variedade/bloqueio), telegrafo, trava, ritmo do chefe, simulacao de TODOS os tipos (40 s). Deterministico.
- `test_e5_enemy_combat`: geometria real dos golpes (AOE/caixa/leque/investida/invocacao), limites de adds, transicoes de fase, morte/XP/loot/adds dispensados, telegrafo visual, todos os 10 tipos engajando. DEPENDE DE TIMING (frames de fisica; asserts com folga).
- `test_e5_server_boss`: servidor com 1-4 jogadores (escala, snapshot/evento de fase, ameaca, luta de 6 s com 1 e 4 jogadores, morte/loot do chefe, reset em wipe). DEPENDE DE TIMING.

## Limites conhecidos / nao verificado
- Balanceamento (vida/dano/duracao da luta), legibilidade visual dos indicadores e do corpo "enterrado", sensacao do ritmo no teclado: NAO verificados em playtest (so testes headless). Sem audio.
- Investida: o corpo do jogador bloqueia o inimigo (colisao camada 1); o bote pode parar encostando no alvo. Sem navmesh: inimigos nao contornam obstaculos.
- Emboscador nao fica invisivel nem intocavel: so achatado em IDLE/RETURN.
- Loot do chefe vai para o jogador do golpe final (comportamento do E3/E4); loot individual por participante e tarefa a parte do E5.
- Cliente de rede: indicador de chao vem de `atk` com ~66 ms de latencia de snapshot; o desenho nao e lag-compensado.
- `scripts/arena/test_arena.gd` e `TestArena.ENEMY_SPAWNS` nao foram tocados: encontros de Greenwood (posicoes, gatilho da arena do chefe) dependem do agente de mundo.
