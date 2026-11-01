# E5.3 - Mundo de Greenwood (zonas, puzzle, transicao, respawn)

Visual BLOCKOUT (primitivas, sem assets externos, arte provisoria). Tudo e data-driven e **servidor autoritativo**: nenhum RPC novo, o cliente so recebe estado. Decisao registrada como proposta em `docs/DECISIONS.md` (DEC-0007). Protocolo continua **v2** (extensao aditiva, ver `shared/contracts/network_protocol.md`).

## Como ligar
- Dados: `data/areas/world/greenwood_world.json` (esquema em `shared/content_schemas/world.schema.json`). Carregado por `WorldDef` (`scripts/world/world_def.gd`, `zone_def.gd`); `WorldDef.validate()` confere referencias e jogabilidade (ver "Regras validadas").
- Servidor dedicado: `--world greenwood` (`ServerSettings.world_id`). **Padrao continua a arena de teste do E1/E3** (`--world arena` ou omitido) para nao mexer em E3/E4 e nos bots antigos; trocar o padrao e uma linha em `server_main.gd`. Se o mundo for invalido o servidor registra `push_error` e cai na arena.
- Testes: `ServerSettings.world_id = "greenwood"` (helper `H.make_rig(tree, spawn_enemies, max, auto_tick, "greenwood")`).

## Mapa (coordenadas de mundo; 1 unidade = 1 m; zonas no mesmo espaco fisico, separadas por >= 20 m)
| Zona | Centro / tamanho | Conteudo |
|---|---|---|
| `zone_hub` Vila de Greenwood (sempre carregada) | (0,0,0) 60x60 | 3 NPCs (Orla (10,-8), Brannoch (21,3), Ilmar (-12,10)), casas, poco, arvores; **sem inimigos**. Portal leste (27,0) -> selvagem |
| `zone_wild` Mata Selvagem | (200,0,0) 100x80 | Trilha central (z ~ 0) entre os portais (153,0) (volta ao hub) e (247,0) (ruinas). 17 inimigos: 6 `melee_grunt`, 2 `ranged_caster`, 2 `forest_stalker`, 2 `bow_scout`, 1 `bark_brute`, 1 `grove_shaman`, 2 `burrow_lurker`, mini-chefe `thorn_alpha` (toca em (236,-31)). Todos a >= 20 m da trilha (fora do aggro) para que a travessia seja segura |
| `zone_ruins` Ruinas | (400,0,0) 90x60 | Antecamara (x 355..395): 2 `ranged_caster` + 2 `forest_stalker`, **placas A (380,-14) e B (380,14)**, portao em x=395 (abertura de 6 m). Salao (x 396..445): 2 `ranged_caster` nos flancos, gatilho do chefe (centro (415,0), raio 9), `blight_treant` nasce em (432,0). Portal de volta (358,0) |
Areas de quest (`data/areas/greenwood.json`, posicoes reais): `area_ruins_gate` (388,0,0) r6 (antes do portao) e `area_ruins_hall` (408,0,0) r8 (depois do portao => o puzzle precede o objetivo do salao).

Geometria: `WorldBuilder` (`scripts/world/world_builder.gd`) monta piso, muralha (grupo `occluder`), props (caixa/cilindro/arvore), portais, placas e portao. Servidor: so colisao (`with_visuals=false`); cliente: malhas placeholder + marcadores de NPC/portal (`Label3D`). Occluders sao `StaticBody3D` com `MeshInstance3D` filho, compativeis com o `OcclusionFader` do E1 (testado com pilar das ruinas); chao e trilhas (decalques sem colisao) nao entram no grupo. O cliente liga o `OcclusionFader` ao avatar local (`client_main.gd`).

## Servidor: `WorldDirector` (`scripts/world/world_director.gd`)
Pertence ao `ServerWorld` (`world.director`; null na arena). Cada tick de fisica: temporizadores por jogador (respawn, transicao, trava de portal) e, por zona carregada, puzzle, encontro e descarga.
- **Zonas carregadas sob demanda**: hub no inicio; selvagem/ruinas ao primeiro portal (inimigos dos dados, puzzle fechado, chefe armado). **Zona sem jogadores por `unload_grace` (12 s)** e descarregada: inimigos (e adds) removidos sem evento, puzzle e portao reiniciados, chefe rearmado; reentrar recarrega tudo novo (inclusive inimigos ja mortos). Cenas de inimigos sao pre-carregadas (sem engasgo ao carregar).
- **Portais e transicao** (`begin_transition`): pisar num portal (raio dos dados, jogador vivo, sem `portal_lock`) -> carrega o destino ANTES -> jogador fica parado e sem acoes por `transition_time` (0,6 s) -> teleporte ao spawn de chegada (indice rotativo, 4 pontos distintos) -> `portal_lock` 1,5 s. Eventos: `zone(phase=0)` ao iniciar, `zone(phase=1)` + catch-up (enemy_spawn da zona, puzzle, chefe) ao chegar, so para o jogador. Ameaca nos inimigos da zona antiga e limpa; a escala de dificuldade e recalculada.
- **Falhas**: destino inexistente/carga falha -> transicao recusada, jogador livre e `portal_lock` (nada de softlock); **morrer durante a transicao** cancela e reaparece na zona de ORIGEM; **desconectar durante a transicao** apenas remove o slot (o destino sem ninguem e descarregado depois da graca; `incoming_count` impede descarga enquanto alguem esta a caminho).
- **Respawn/morte**: apos `respawn_delay` (3 s) o jogador morto e reanimado (`ServerWorld.revive_player`: vida cheia, maquina de estados revivida) e teleportado ao **checkpoint da zona** (spawn `checkpoint` dos dados), mesma zona; ameaca limpa; evento `respawn`. Morto desconectando = slot removido sem erro. Nao ha protecao de spawn.
- **Encontro do chefe** (`encounter`): `ARMED -> ACTIVE` quando um jogador VIVO entra no gatilho (o `blight_treant` e criado nesse instante, com a escala de dificuldade dos jogadores da zona); `ACTIVE -> DEFEATED` no abate (recompensa normal do E5.2, uma vez; reentrar nao recria); **wipe** (nenhum jogador vivo na zona, inclusive todos mortos ou fugindo pelo portal) -> chefe e adds removidos e encontro `ARMED` de novo (eventos `boss`). Descarregar/recarregar a zona rearma.
- **Interesse**: snapshots por peer = so a zona do jogador + raio `ServerSettings.aoi_radius` (50 m) para inimigos (jogadores da zona sempre). Eventos de dano/morte/fase/drop/spawn/puzzle/chefe/respawn so vao aos jogadores da zona (`ServerWorld.event_targets`); `player_joined/left` seguem globais. Sem isso um snapshot do selvagem passava de 4 KB; com zona+raio fica em ~1 KB (um snapshot de luta de chefe ainda pode passar do MTU de 1392 B, aviso do ENet - ver limites).
- **Dificuldade**: a escala usa os jogadores da ZONA do inimigo (arena: todos), mais os que estao a caminho.
- **Inimigos por zona**: `ServerWorld` guarda `entity -> zone`; alvo/ameaca so entre jogadores da mesma zona; "zona ativa/inativa" (parar IA, reiniciar chefe quando todos morrem) e por zona (na arena, tudo na zona "" = comportamento antigo).

## Puzzle cooperativo: placas de pressao (`PuzzleState`, logica pura)
- 2 placas (raio 1,8 m, +-2 m de altura). Cada placa fica **acesa enquanto pisada + `latch_time` (10 s) depois**. O portao abre quando **todas** estao acesas ao mesmo tempo: em grupo, dois jogadores ficam nas placas; **sozinho**, corre de A a B (28 m ~ 4,7 s) dentro da janela.
- **Reset**: por timeout (a janela expira e as placas apagam sozinhas) e por reentrada (zona descarregada). **Depois de aberto o portao permanece aberto** ate a descarga da zona (nunca fecha com gente dentro; jogador que morre no salao reaparece na antecamara e o portao continua aberto) => sem softlock.
- Autoridade: so posicoes de jogadores VIVOS da zona, calculadas no servidor; nenhum comando de cliente toca no puzzle. Portao = `StaticBody3D` que perde a colisao quando abre.
- Replicacao: evento `puzzle` `{zone, puzzle, plates:[bool], open, state}` so quando algo muda + catch-up a quem chega. O cliente acende as placas e abre o portao visualmente (`ClientWorld`).

## Quests
- Posicoes reais: NPCs no hub (`data/npcs/*.json`, `placeholder:false`), areas nas ruinas. A validacao de distancia do `QuestService` usa estas posicoes.
- **Eventos de area**: o `QuestService.tick` (a cada 5 ticks) usa a posicao autoritativa do jogador, que agora e a real do mundo => entrar em `area_ruins_gate`/`area_ruins_hall` avanca `gw_ruins_expedition` (testado ponta a ponta apos o puzzle).
- **`ruin_guardian` resolvido**: `gw_ruin_guardian` agora mata `blight_treant` (existente) e `ranged_caster` x3 (as ruinas tem 4). `data/quests/_pending_refs.json` sem pendencias; `shared/content_schemas/quests.json` regenerado (`node tools/gen_quests_catalog.mjs`); testes backend de quests passam. O gerador agora le o `id` da secao `[resource]` do `.tres` (antes lia o primeiro `id =`, que nos chefes e o de um ataque).
- `gw_scrap_for_orla` (6 sucatas) e `gw_clear_clearing` (5 `melee_grunt`) sao atendiveis so com o selvagem (6 grunts; os inimigos reaparecem ao recarregar a zona). O pre-requisito de nivel das quests de ruinas (2 e 3) nao e imposto pelo mundo: nada impede entrar nas ruinas antes.

## Regras validadas (`WorldDef.validate`, teste `test_world_data.gd`)
Portais apontam para zonas/spawns existentes; spawns dentro da zona e **fora do raio de qualquer portal** (+1 m, anti-loop); inimigos/chefe existem em `EnemyCatalog`; NPCs e areas dentro de alguma zona; zonas sem sobreposicao e >= 20 m de distancia; **toda zona tem caminho de volta ao hub e e alcancavel dele**; checkpoint existe. Definicoes quebradas sinteticas sao rejeitadas.

## Cliente (apresentacao)
`ClientSession` valida os eventos novos (`Protocol.validate_world_event`; malformados sao descartados e contados em `world_events_rejected`), guarda `zone_id`/`puzzle_state`/`boss_state` e refaz a predicao ao teleportar (zona/respawn do jogador local). `ClientWorld.show_zone` monta o visual da zona atual e esconde o chao generico; `ClientHud` mostra o nome da zona. Sem UI de mapa/minimapa (fora do escopo).

## Testes
- Godot `tests/e5_world/`: `test_world_data` (dados, validacao, rejeicoes, geometria servidor x cliente, occluders + OcclusionFader), `test_world_puzzle` (estados puros, 2 jogadores, solo/janela, morto, outra zona, portao fisico, reset por reentrada, sem softlock, eventos/catch-up), `test_world_server` (hub, spawns por zona/dados, portal+transicao, sem loop, interesse por zona e raio, descarga/recarga, desconexao e morte na transicao, destino invalido, 4 jogadores, dificuldade por zona, respawn, chefe: gatilho/wipe/vitoria/fuga, quests: area + abates ate o chefe, validadores/cliente, andar pelo input ate o portal), `test_world_bot` (roteiro do bot). Sao deterministicos: o tempo do diretor avanca por `director.tick` manual; so os testes marcados "fisica" usam frames reais.
- Integracao de processos: `python3 tools/e5_world_integration.py all` (1 e 4 bots `world_tour`: hub -> selvagem -> ruinas -> placas -> portao -> salao; checa 3 zonas em ordem, puzzle aberto, chegada ao salao, snapshots, ERROR no log). Bot novo `world_tour` (`BotScript.world_tour_step`, dirigido pelos dados do mundo). Em VM de 2 nucleos com 4 bots + servidor, o maior intervalo entre snapshots chegou a ~800 ms (contencao de CPU); o limite do script e 1000 ms para 4 bots.

## Limites conhecidos / nao verificado
- Visual so em primitivas; legibilidade em camera isometrica real, escala das zonas e sensacao de ritmo NAO foram vistas num cliente grafico (so headless).
- Balanceamento do selvagem/ruinas (densidade, aggro, recarga) nao testado em jogo; os inimigos do selvagem nao reaparecem enquanto a zona esta carregada.
- Jogadores de outras zonas nao aparecem no snapshot (sem lista de grupo no HUD); chat/party fora do escopo.
- Snapshots de luta de chefe com varios adds podem passar do MTU (1392 B) em `unreliable` (aviso do ENet, mais perda); medir antes de fixar o tick/AOI.
- Transicao e instantanea no servidor apos 0,6 s; nao ha tela de carregamento nem fade no cliente (o evento `zone(phase=0)` esta pronto para isso).
- Posicao do jogador nao e persistida: entrar sempre nasce no hub (backend inalterado).
- O padrao do servidor continua a arena; falta decidir quando `--world greenwood` vira padrao.
