# E2 - Inimigos, IA, feedback, drop/XP e loop jogavel local

Autoridade local (E2): nada e validado por servidor (E3). Conteudo e arte sao PLACEHOLDER.

## Arquitetura
| Peca | Arquivo | Papel |
|---|---|---|
| `EnemyAI` | `scripts/enemy/enemy_ai.gd` | Maquina de estados pura (RefCounted): IDLE, CHASE, ATTACK, RETURN, DEAD. Tabela de transicoes no cabecalho. |
| `Enemy` | `scripts/enemy/enemy.gd`, `scenes/enemy/enemy.tscn` | CharacterBody3D: Health (stats do `EnemyData`, copia), Hurtbox (camada 3), Hitbox (camada 5, mascara player_hurt), movimento por steering + `move_and_slide` (sem navmesh). |
| Variantes | `scenes/enemy/melee_grunt.tscn`, `ranged_caster.tscn` | Cenas herdadas que so apontam `data` para o `.tres`. |
| `EnemyVisual` | `scripts/enemy/enemy_visual.gd` | Malha placeholder por tipo (grunt = caixa vermelha, caster = cone roxo + orbe), etiqueta com nome, pulso no windup. |
| `Projectile` | `scripts/enemy/projectile.gd` | Area3D camada 5; dano unico; `lifetime`; mundo detectado por raycast. |
| `Pickup` | `scripts/pickups/pickup.gd`, `scenes/pickups/pickup.tscn` | Area3D (mascara player_hurt) com coleta por polling; entrega no `PlayerLoadout`. |
| `PlayerLoadout` | `scripts/player/player_loadout.gd` (no "Loadout" do Player) | Inventory + Equipment + CharacterProgress; recalcula stats com `StatCalculator` e aplica em `HealthComponent.stats` e no `ResourcePool`. |
| Feedback | `scripts/ui/hit_flash.gd`, `damage_numbers.gd`, `damage_number.gd`, `death_effect.gd` | Apresentacao, ligada a sinais (`damaged`). A logica nao depende deles. |
| HUD | `scripts/ui/playtest_hud.gd` | CanvasLayer que so le estado e chama `PlayerLoadout.equip_from_index/unequip_slot`. |
| Arena | `scripts/arena/test_arena.gd` | Spawns, kit inicial, HUD, reinicio por R, respawn opcional. |

Fluxo de morte do inimigo (uma vez, flag `defeat_count`): para a IA, desliga colisoes, rola o `LootTable` com `RandomNumberGenerator` (`loot_seed >= 0` = deterministico), cria pickups (adicionados via `call_deferred`, aparecem no frame seguinte), concede `xp_reward` ao `PlayerLoadout` da fonte do golpe final, emite `defeated(enemy, xp, drops)`, some apos 0,7 s.

IA: aggro_range -> CHASE; `attack_range` + cooldown -> ATTACK (windup 0,45 s parado = telegrafo, release unico, depois cooldown); `leash_range` = 2 x aggro_range da origem (inimigo ou alvo alem disso, ou alvo morto) -> RETURN (ignora o alvo ate chegar; ao chegar cura e volta a IDLE). Anti-softlock: windup e return_timeout (10 s, depois teleporta para a origem). Ranged para em 90% do alcance e recua se o alvo chega a < 50% do alcance.

### Politica de vida/recurso ao recalcular stats
Ao equipar, desequipar ou subir de nivel, vida e recurso mantem a PROPORCAO (`atual/max_antigo * max_novo`). Evita ganhar vida trocando item e nao deixa vida acima do novo maximo. Jogador morto continua morto (vida 0). O dano do golpe e `health.stats.attack_power * multiplicador`, entao equipar arma muda o dano real.

## Controles de playtest
WASD move, LMB ataque, Q golpe pesado, E redemoinho, Espaco esquiva (E2 combate); F2 qualidade, F3 camera. Novos: **I** abre/fecha inventario; com ele aberto **1-9** equipa a pilha numerada, **X** desequipa arma, **C** armadura, **V** amuleto; **R** reinicia a cena apos a morte. Acoes no Input Map: `inventory_toggle`, `inventory_slot_1..9`, `unequip_weapon/armor/trinket`, `restart`. Kit inicial na arena: `sword_basic`, `armor_leather`. Spawns: 3 grunts + 2 casters a >= 18 m do jogador. Respawn: `TestArena.respawn_enabled` (padrao false), `respawn_delay` 8 s.

## Como adicionar
- Inimigo: crie o `EnemyData` (em `scripts/data/content_generator.gd` ou `.tres`), uma cena herdada de `enemy.tscn` com `data` apontando para ele, e inclua em `ENEMY_SPAWNS` da arena. Comportamentos suportados: `melee`, `ranged`. A aparencia por comportamento esta em `EnemyVisual.apply`.
- Item: ver `docs/E2_DATA.md`; pickups funcionam para qualquer `item_id` do registry.

## Testes (`tests/e2/`)
`test_enemy_ai` (puro, deterministico), `test_enemy_death`, `test_enemy_projectile`, `test_enemy_behavior`, `test_loop_pickup`, `test_loop_loadout`, `test_loop_full`, `test_loop_feedback`; helpers em `loop_helpers.gd`.
**Dependem de timing** (frames reais de fisica a 60 Hz, com folga): `test_enemy_projectile`, `test_enemy_behavior` (trecho melee), `test_loop_pickup` (sobreposicao), `test_loop_loadout` (golpes reais), `test_loop_full`. Os demais trechos sao deterministicos (step manual).

## Limites conhecidos / armadilhas
- Com Jolt, `Area3D` nao detecta `StaticBody3D`: o projetil usa raycast contra o mundo. Pickups/hitboxes dependem so de area x area.
- Godot 4.7.2 derruba o processo (signal 11) ao passar uma instancia ja liberada como argumento de funcao; nos testes use `is_instance_valid` inline / sinais.
- Inimigos nao desviam de obstaculos (steering direto): podem ficar encostados em paredes enquanto o alvo esta dentro do leash; so o RETURN tem destravamento (teleporte). Inimigos nao tem stagger nem barra de vida.
- Sem navmesh, sem pooling (projeteis/pickups/numeros sao instanciados e liberados).
- Projetil com `hit_from_inside` no raycast; inimigo colado na parede pode atirar atraves dela se o ponto de saida estiver alem dela.
- Pickups sao coletados so se a Hurtbox do jogador os sobrepoe; sem imã/atracao. Itens consumiveis (pocao) apenas empilham; nao ha uso.
- `move_speed` do StatBlock do jogador ainda nao alimenta o `Player`.

## NAO verificado
Render real (cores, escala, legibilidade dos Label3D, pulso de telegrafo), input real (teclado/mouse, Input Map so testado por `InputEventAction` sintetico no HUD), HUD em tela, desempenho/numero de inimigos, balanceamento/duracao dos encontros, playtest de 30 min do gate E2, reinicio por `reload_current_scene` com cena real aberta por usuario. **Audio: nao existe** (feedback sonoro e placeholder ausente; apenas feedback visual).
