# E8.1 - Modelos 3D animados no cliente

Escopo: so o CLIENTE. O servidor continua headless, sem carregar assets; protocolo e gameplay nao mudaram (nenhum campo novo de rede). Sem asset, em modo headless/bot/teste ou com `ClientWorld.use_models = false`, o cliente cai nas primitivas de sempre (capsula/caixa).

## 1. Peças
| Arquivo | Papel |
|---|---|
| `scripts/visual/visual_spec.gd` (`VisualSpec`) | Dados de apresentacao (schema abaixo), parse/validacao. Sem carregar nada: o servidor pode ler. |
| `scripts/visual/asset_aliases.gd` (`AssetAliases`) | Resolve alias/id do `assets/ASSET_MANIFEST.json` (chaves `aliases` e `assets`) ou `res://...` para o caminho do `.glb`. Le o manifest uma vez; so o cliente chama. |
| `scripts/visual/clip_table.gd` (`ClipTable`) | Estado visual -> clip, remocao de prefixo, fallback, velocidade do clip, estado do snapshot -> estado visual. |
| `scripts/visual/model_rig.gd` (`ModelRig`) | Instancia o GLB (cache de `PackedScene` por caminho), mede o AABB, normaliza a escala, esconde acessorios, tinge, toca clips com blend, gira suave. |
| `ClientWorld` | Cria um `ModelRig` por avatar (jogador, inimigo, pickup) e o alimenta com o `state` do snapshot e com eventos cosmeticos. |
| `WorldBuilder._add_npc_marker` | NPCs com `visual_scene` viram modelo em idle olhando para a camera; sem asset, a capsula amarela de antes. |

## 2. Schema `visual_*`
Mesmos nomes em tres lugares: `.tres` do inimigo (`EnemyData`, campos exportados), `data/classes/<id>.json` e `data/npcs/<id>.json` (chaves planas). Todos opcionais; sem `visual_scene` o resto e ignorado (e, no JSON, acusado como erro se aparecer sozinho).

| Campo | Tipo | Padrao | Descricao |
|---|---|---|---|
| `visual_scene` | texto | `""` (primitivas) | Alias do manifest (`class.warrior`, `enemy.minion`, `prop.chest`), id de asset (`model.kaykit_adventurers.knight`) ou `res://assets/third_party/...glb\|gltf`. Sem `..`. |
| `visual_height` | numero (m) | 1.8 | Altura ALVO do corpo, 0.1..12. O cliente mede o AABB do modelo e escala para esta altura (os pacotes nao compartilham escala: KayKit ~2.2 u, Quaternius com escalas internas x100). |
| `visual_tint` | `Color` no `.tres`; `[r,g,b]` no JSON (0..4) | sem tintura (alpha 0) | Multiplica o albedo de todas as malhas (materiais duplicados e compartilhados em cache por cor). |
| `visual_yaw_offset` | graus | 0 | Giro extra sobre a orientacao padrao (`ModelRig.BASE_YAW_DEG = 180`: os GLB olham para +Z; o jogo usa -Z como frente). Os modelos atuais nao precisam. |
| `visual_clips` | `{estado: clip}` | `{}` | Troca o clip de um estado. Nome sem prefixo (`Walking_A`, `Spider_Attack`); com prefixo (`AnimalArmature\|Idle`) tambem vale. Maiusculas nao importam. |
| `visual_equip` | lista de nomes de mesh | `[]` | Acessorios (chapeu, arma, escudo, capa) que ficam VISIVEIS entre as malhas penduradas em `BoneAttachment3D`. Os pacotes KayKit trazem TODAS as armas/chapeus visiveis ao mesmo tempo, entao personagens precisam desta lista. Vazia = nao esconde nada. |
| `visual_placeholder` | bool | false | Visual provisorio (asset reaproveitado). Bruto e chefe: true. |

A altura medida considera so malhas visiveis e SKINNED (corpo) mais malhas estaticas fora de `BoneAttachment3D`; chapeus e armas nao entram. O pe do modelo e colocado em y = 0.

### Validacao
- Godot: `VisualSpec.from_dict` / `validate()` (formato da referencia, faixas, estados validos); `ClassDef.parse` e `NpcDirectory.add_dict` rejeitam visual invalido; testes em `tests/e8_models/`.
- Node: `tools/visual_check.mjs`, chamado por `tools/validate_content.mjs` para inimigos, classes e NPCs: alias/id existe no manifest, arquivo existe em `assets/`, faixas, estados e (lendo o JSON embutido do `.glb`) se cada clip e cada acessorio citado EXISTE no modelo. `tools/gen_classes_catalog.mjs` aceita as chaves `visual_*` mas `shared/content_schemas/classes.json` nao as inclui (o backend nao precisa de arte).

## 3. Estados e clips
Estados visuais: `idle`, `move`, `attack`, `skill`, `dodge`, `hit`, `death`, `spawn`.

| Estado | Vem de | Candidatos padrao (primeiro que existir) | Fallback se nenhum existir |
|---|---|---|---|
| idle | jogador IDLE; inimigo IDLE | `Idle`, `Idle_A`, `Unarmed_Idle` | primeiro clip que nao e pose (T-Pose, `*_Pose`) |
| move | jogador MOVE (ou predicao local); inimigo CHASE/RETURN | `Walking_A`, `Walk`, `Running_A`, `Gallop`, `Walking_B` | idle |
| attack | jogador ATTACK; inimigo ATTACK corpo a corpo | `1H_Melee_Attack_Chop`, `Attack`, `2H_Melee_Attack_Chop`, `Unarmed_Melee_Attack_Punch_A` | skill |
| skill | inimigo ATTACK em area/projetil/carga/invocacao (`EnemyAttack.kind != MELEE`, via `atk` do snapshot) | `Spellcast_Shoot`, `Spellcast_Raise`, `2H_Melee_Attack_Spin` | attack |
| dodge | jogador DODGE | `Dodge_Forward`, `Roll` | move |
| hit | `EVENT_DAMAGE` no alvo; jogador HIT | `Hit_A`, `Idle_HitReact_Left`, `Hit_B` | nenhum |
| death | `EVENT_DEATH`; jogador/inimigo DEAD | `Death_A`, `Death` | nenhum |
| spawn | `EVENT_ENEMY_SPAWN` | `Spawn_Ground`, `Skeletons_Awaken_Standing`, `Spawn_Air` | nenhum |

Clip faltando nunca e erro: segue a cadeia e, no fim, so idle/move usam "o primeiro disponivel"; os demais ficam sem clip (nada acontece). Um override de `visual_clips` que nao existe no modelo cai no padrao (o validador Node acusa o erro em tempo de conteudo).

### Comportamento
- Idle/move em loop; ataque, esquiva, hit e spawn tocam uma vez e voltam ao idle; morte segura o ultimo quadro (o corpo some quando o servidor o tira do snapshot). Blend de 0.15 s entre clips.
- One-shots sao acelerados/desacelerados para caber na duracao (`ClipTable.TARGET_SECONDS`; inimigos usam `windup + 0.3 s` do ataque). Um one-shot recente (60% da duracao) nao e cortado por idle/move: o pedido fica pendente. Prioridade: morte > spawn > esquiva > ataque/habilidade > hit; eventos cosmeticos (dano) nao interrompem algo de prioridade maior; o `state` do servidor sempre vence.
- Jogador local: anda/para pela predicao (`_prev_local`), nao pelo snapshot atrasado.
- Giro: o avatar mantem o yaw autoritativo; o `ModelRig` so aplica uma defasagem visual suave (`TURN_SPEED = 14`). Posicao nunca e alterada.
- Dano: flash por `material_overlay` branco; numeros de dano sobem com a altura do modelo (`meta height`).
- Pickups: pocao (`Potion1_Filled`) para ids que comecam com `potion`, bau (`prop.chest`) para o resto; rotulo mantido.
- Nao ha barra de vida/nome sobre a cabeca no `ClientWorld` (a UI mostra vida em paineis); os rotulos de NPC/pickup acompanham a altura do modelo.

## 4. Mapeamento atual
| Entidade | Modelo (alias) | Altura | Tintura | Observacao |
|---|---|---|---|---|
| Guerreiro | Barbarian (`class.warrior`) | 1.9 | - | machado 2H + chapeu |
| Mago | Mage (`class.mage`) | 1.85 | - | cajado + chapeu |
| Patrulheiro | Rogue_Hooded (`class.ranger`) | 1.85 | - | besta + capa |
| Aliados remotos | Knight (`class.warrior_alt`) | 1.9 | - | classe vem do `type` do snapshot (`player:<classe>`, E8.3); Cavaleiro e o fallback |
| melee_grunt | Skeleton_Minion (`enemy.minion`) | 1.7 | - | |
| ranged_caster | Skeleton_Mage (`enemy.skeleton_conjurer`) | 1.8 | - | |
| bow_scout | Skeleton_Rogue (`enemy.skeleton_archer`) | 1.8 | verde claro | |
| forest_stalker | Fox (`enemy.beast_fox`) | 1.1 | quente | |
| bark_brute | Skeleton_Warrior (`enemy.brute`) | 2.7 | marrom | PLACEHOLDER |
| grove_shaman | Skeleton_Mage (`enemy.skeleton_conjurer`) | 2.1 | verde | |
| root_sprout | Spider (`enemy.spider`) | 0.7 | lima | |
| burrow_lurker | Spider (`enemy.spider`) | 1.2 | roxo | |
| thorn_alpha (mini-chefe) | Wolf (`enemy.wolf`) | 2.0 | ferrugem | |
| blight_treant (CHEFE) | Skeleton_Warrior (`enemy.boss`) | 4.6 | verde | PLACEHOLDER |
| NPCs (6) | Mage / Rogue_Hooded / Rogue / Barbarian / Knight | 1.75..1.95 | tons diferentes | idle parado, olhando para a camera |

Stag, Husky, Rat, Snake, Frog e Wasp estao importados mas sem uso (a lacuna de monstros do E8.0 continua: ver `docs/E8_ASSETS.md` secao 3).

## 5. Como adicionar um modelo novo
1. Importe o `.glb` em `assets/third_party/<pacote>/`, registre a licenca em `docs/ASSET_CREDITS.md` e rode `python3 -I tools/build_asset_manifest.py` (opcional: crie um alias em `aliases`).
2. Descubra clips e acessorios: `godot --headless --path . --script res://tools/shots/model_gallery.gd -- --matrix enemy:<id>` (ou abra o GLB no editor). Os nomes de clip aparecem sem prefixo.
3. Preencha `visual_scene`, `visual_height` e, se precisar, `visual_clips`/`visual_equip`/`visual_tint` no `.tres` do inimigo ou no JSON da classe/NPC.
4. `node tools/validate_content.mjs` (acusa alias, arquivo, clip e acessorio inexistentes) e `--only=tests/e8_models/`.
5. Confira o resultado: `tools/shots/run_gallery.sh idle,move,attack,hit,death,spawn x enemy:<id>` gera uma matriz estado x modelo em `.tools/scratch/shots/`.
6. Se o pacote era excluido do cliente em `export_presets.cfg`, tire-o da lista (secao 6).

## 6. Build
- Servidor: `exclude_filter` inclui `assets/*`. Nenhum script do servidor carrega arte (todo acesso a `assets/` e por `load()` dinamico no cliente, nunca `preload`). Medido: `EldervaleServer.pck` 1,011,096 B, 0 ocorrencias de `assets/third_party` no `.pck`.
- Cliente: `include_filter` leva `assets/ASSET_MANIFEST.json` (aliases) e `exclude_filter` tira os pacotes ainda nao usados (dungeon, halloween, hexagon, village, buildings, rts, modular dungeon, nature, survival, knight, mini arena, starter kits, audio Oculus, icones, fontes; Stag/Husky; Frog/Rat/Snake/Wasp). Medido: `Eldervale.pck` 18,240,988 B. Fica dentro: KayKit Adventurers e Skeletons, Wolf, Fox, Spider, os 86 itens RPG (bau e pocao). O E8.2+ deve remover da lista os pacotes que passar a usar.

## 7. Ferramentas de screenshot (dev)
- `tools/shots/run_gallery.sh [estados] [enemy,class,npc] [matriz]`: monta os visuais lado a lado (sem servidor) e salva em `.tools/scratch/shots/`. Ex.: `tools/shots/run_gallery.sh idle,move,attack,hit,death,spawn x enemy:bark_brute,class:warrior`.
- `TOUR_CLASS=warrior|mage|ranger tools/shots/run_tour.sh hub|wild|ruins|chars|wild_close|alpha`: tour real (servidor `--default-class`); prints prefixados com a classe. `chars` = parado, andando, ataque, habilidades, esquiva e NPCs de perto.

## 8. Limitacoes conhecidas
- RESOLVIDO no E8.3 (DEC-0038): o snapshot traz `type = "player:<classe>"` e o cliente usa o modelo da classe do aliado; servidor antigo ou `--party-class 0` (type `player`) cai no Cavaleiro neutro.
- Esqueletos KayKit vem sem armas no GLB; os ataques corpo a corpo sao desarmados. Chefe e bruto sao o mesmo modelo do esqueleto guerreiro (PLACEHOLDER).
- A camera isometrica e alta: chapeus e capuzes dominam a silhueta de cima. Nas ruinas a camera aproximada entra nas muralhas primitivas (E5.3) e o jogador some; o tour `ruins` ja tinha jogador oculto atras de muralhas antes do E8.1.
- `Husky`, `Stag` etc. sem uso. Sombra/iluminacao/pos-processamento sao do E8.2; VFX do E8.3.
- Executar o cliente exportado no Windows nao foi verificado (VM Linux).
