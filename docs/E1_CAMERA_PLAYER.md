# E1 — Camera e jogador (modulo B)

## Arquivos
- `scenes/player/player.tscn`, `scripts/player/player.gd` (logica), `player_motion.gd` (funcoes puras), `player_visual.gd` (apresentacao).
- `scenes/camera/iso_camera.tscn`, `scripts/camera/iso_camera.gd`.
- `scripts/occlusion/occlusion_fader.gd` (grupo `occluder`).
- Input Map: `move_forward/back/left/right` = W/S/A/D (teclas fisicas).
- Testes: `tests/run_tests.gd` + `tests/e1/`.

## Controles
WASD move relativo a yaw da camera; **F3** alterna camera ortografica / perspectiva.

## Parametros
| Item | Valor |
|---|---|
| Yaw / inclinacao da camera | 45 deg / 50 deg (exports `yaw_deg`, `pitch_deg`) |
| Ortografica | `ORTHO_SIZE` 14 m (altura visivel), distancia 30 |
| Perspectiva | FOV 28 deg, distancia 28 (area visivel no alvo ~ igual a ortografica, por calculo) |
| Follow | suavizacao exponencial, `follow_speed` 8 |
| Jogador | 6 m/s, gravidade 24, capsula 1,8 m x raio 0,4, giro `turn_speed` 14 |
| Rampa | `floor_max_angle` = 30 deg + 0,5 deg de tolerancia |
| Degrau | `step_height` 0,3 m (step-up simples + floor snap 0,45) |
| Fade | alpha minimo 0,25, 6 alpha/s, checagem a cada 0,05 s |

## Como funciona
- A camera expoe `get_yaw()`; o jogador a localiza por `camera` (export) ou grupo `game_camera`. Sem camera valida, usa yaw 0 e avisa.
- Degrau: se o passo bate numa superficie nao andavel, ha folga ate `step_height` e nao ha teto, o corpo sobe `step_height` e o floor snap o acomoda.
- Mira por mouse: ponto de extensao `Player._desired_facing_direction()` (hoje devolve a direcao de movimento).
- Fade: teste segmento (camera->jogador) x AABB global (+0,2 m) dos meshes do grupo `occluder`; usa duplicata do material por superficie e restaura o override original ao liberar. Nao exige colisores.

## Ortografica vs perspectiva
Nao houve comparacao visual: o ambiente de teste foi headless, sem render. Verificado apenas que as duas projecoes sao aplicadas ao alternar (F3) e que os parametros foram escolhidos para cobrir area similar. A decisao fica para o usuario, comparando em jogo com F3.

## Limites conhecidos
- Degrau acima de 0,3 m e escadas altas nao sao tratados; step-up testado so com 0,2 m e rampa de 25 deg.
- Fade por AABB e conservador: pode esmaecer objetos grandes/diagonais cujo AABB cruza o segmento sem oclusao real; chao fino nao deve estar no grupo `occluder`.
- Camera sem colisao nem limites de mapa; yaw fixo.
- Desempenho nao medido.
- Testes de fisica usam `await physics_frame`; passaram 3 execucoes seguidas, mas dependem do timing do motor.
