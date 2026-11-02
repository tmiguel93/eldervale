# E8.3 — VFX de combate e classe dos aliados

Só apresentação, só cliente (exceto o sufixo de classe no `type` dos jogadores, aditivo). Nenhuma mudança em física, dano, cooldowns ou autoridade do servidor. Decisão: `docs/DECISIONS.md` (DEC-0038). Protocolo: `shared/contracts/network_protocol.md` (Extensão E8.3).

## Arquitetura

| Arquivo | Papel |
|---|---|
| `data/vfx/_layer_schema.json` | Esquema das camadas (tipos, campos, faixas, sprites, blends). Lido pelo Godot e pelo Node (um arquivo só). |
| `data/vfx/effects_player.json`, `effects_world.json`, `effects_enemy.json` | 43 efeitos, 156 camadas. Camadas: `arc`, `ring`, `rune`, `pillar`, `orb`, `streak`, `burst` (partículas), `light`, `shake`. |
| `data/vfx/bindings.json` | habilidade -> `cast/muzzle/projectile/impact/end`; ataque de inimigo por tipo (`melee/aoe/projectile/charge/summon`) + `overrides` por id (ex.: `arrow`); eventos; drops por raridade; cores de telégrafo; `tier_scale` (normal 1, mini_boss 1.4, boss 1.9). |
| `scripts/vfx/vfx_catalog.gd` | Lê e valida os dados. Não carrega textura nem shader. |
| `scripts/vfx/vfx_player.gd` | `play(id, pos, yaw, opts)`; pool por efeito (<= 6), fila de atraso (<= 48), limite de ativos com eviction por prioridade, luzes limitadas, projéteis cosméticos. Nenhuma alocação por frame depois do aquecimento. |
| `scripts/vfx/vfx_instance.gd`, `vfx_meshes.gd`, `vfx_assets.gd`, `*.gdshader` | Efeito montado a partir das camadas; malhas e materiais em cache; shaders `blend_premul_alpha` com uniform `cover` (legíveis sobre chão claro). Partículas = `CPUParticles3D`. |
| `scripts/vfx/vfx_telegraph.gd` | Telégrafo de inimigo por tipo e cor (melee: caixa; aoe: disco; projétil: faixa; charge; summon), com progresso por frame. |
| `scripts/vfx/client_vfx.gd` | Ganchos: transições de estado do snapshot (ataque, esquiva, morte), `windup`/golpe de inimigos, cura (salto de HP), aura de chefe, eventos de dano/morte/spawn/drop/zona/respawn, level up e talento (`s_talents`), portal. |
| `scripts/vfx/vfx_settings.gd` | Acessibilidade: `reduce_motion`, `camera_shake`, `hit_stop`. |
| `scripts/ui/damage_number.gd` | Números por estilo: acerto, crítico, dano recebido, cura; pop e deriva lateral. |
| `scripts/camera/iso_camera.gd`, `scripts/visual/model_rig.gd` | `shake()` leve (offset de câmera) e `hit_stop()` cosmético (animação do alvo a ~4% por instantes). |

Headless/bot/teste: `VfxPlayer.enabled()` é `ModelRig.models_enabled()`; `ClientWorld.vfx` fica `null` e `VfxAssets.load_count` fica 0.

## Qualidade (`QualitySettings`)

| Preset | `vfx_density` | `vfx_max_active` | `vfx_max_lights` |
|---|---|---|---|
| Baixo | 0.4 | 10 | 0 |
| Médio (padrão) | 0.75 | 20 | 2 |
| Alto | 1.0 | 32 | 4 |

Trocar o preset descarta o pool (a densidade é fixada na montagem); efeitos ativos terminam normalmente.

## Conforto e acessibilidade

- Tremor de câmera leve e hit-stop ligados por padrão; `--reduce-motion 1` (ou `[accessibility] reduce_motion` em `user://settings.cfg`) desliga tremor, hit-stop e brilhos fortes de uma vez. `--reduce-motion 0` força o contrário e não grava o arquivo.
- Hit-stop não usa `Engine.time_scale`: só a animação do alvo, então nada de simulação ou rede é afetado.

## O que o cliente sabe (e não sabe)

- Não há projéteis no snapshot: o projétil é cosmético, reto, com velocidade/alcance de `SkillData`/`EnemyAttack`, e some em `EVENT_DAMAGE` da mesma origem. Pode divergir do projétil real em colisões com obstáculos.
- Habilidade do jogador local: inferida da borda de subida dos bits de ação que o cliente enviou. Aliados remotos: só o ataque básico da classe (o snapshot não diz qual habilidade usaram). Sugestão de passo futuro: campo opcional `skill`/`atk` por jogador no snapshot (aditivo).
- Golpe de inimigo: tocado `windup` depois que `state = ATTACK` e `atk` chegam; o telégrafo usa o mesmo `atk`.
- Classe dos aliados: `type = "player:<classe>"` (kill-switch `--party-class 0`); fallback para o Cavaleiro.

## Validação e testes

- `node tools/validate_content.mjs` (inclui `tools/vfx_check.mjs`: esquema, referências, sprites, habilidades existentes e cobertura de habilidades e tipos de ataque).
- `tests/e8_vfx/` (Godot): `test_e83_catalog.gd` (catálogo, referências, mapeamento completo das 3 classes e de todos os ataques de inimigos), `test_e83_player.gd` (headless sem carga, pool, limite/eviction, fila, qualidade, acessibilidade), `test_e83_class_protocol.gd` (helpers, validação, codec, MTU, servidor com kill-switch, cliente escolhendo o modelo).
- Execução: `godot --headless --path . --script res://tests/run_tests.gd -- --only=tests/e8_vfx/`.

## Bancada e evidências

- `tools/shots/run_vfx.sh --zone zone_wild --at 200,0 --zoom 0.45 --shot "nome,p:warrior:attack,0.12;0.2;0.3;0.45"` (aspas em volta por causa do `;`). Modos: `p:<classe>:<attack|skill_1|skill_2|dodge>`, `e:<inimigo>:<ataque>`, `ev:<levelup|heal|death|spawn|drop|crit|boss|portal|hurt>`. Saída em `.tools/scratch/shots/<nome>_f<i>.png`; colagem: `python3 tools/shots/vfx_collage.py saida.png nome1 nome2 ...`.
- Requer xvfb e o Godot Linux em `.tools/godot-linux`; render Compatibility com GL por software. A animação dos modelos roda em tempo real escalado, então a sincronia com os efeitos é aproximada.
- Evidências versionadas: `docs/img/e8_3_vfx_warrior_mage.png` (guerreiro: giro e esquiva; mago: projétil arcano e bola de fogo), `docs/img/e8_3_vfx_mage_ranger.png` (nova de gelo; arqueiro: ataque, chuva de flechas, rolamento), `docs/img/e8_3_vfx_enemy_levelup_heal.png` (telégrafo/golpe do Bruto e da flecha do batedor, level up, cura).

## Limitações

- Visto só em Compatibility com GL por software; custo em GPU real e em Forward+ não foi medido.
- Ataque básico e chuva de flechas do patrulheiro ficaram discretos; avaliar com jogadores.
- O flash branco de acerto dos inimigos é o do E8.1 (cobre o modelo inteiro).
- Morte, drop lendário e aura de chefe estão em `docs/img/e8_3_vfx_death_drop_boss_spawn.png` (vistos); a runa de spawn aparece no primeiro quadro do telégrafo do Bruto. A aura de chefe ficou grande no enquadramento aproximado da bancada (zoom 0.45) e deve ser revista na câmera de jogo. O efeito de portal passou pelo pipeline (sem erro, `missing = 0`) mas NÃO foi visto em captura.

## Créditos

Sprites de partícula: Kenney (CC0) em `assets/third_party/kenney_starter_kits/vfx/` (`particle`, `smoke`, `burst`, `hit`). O brilho (`glow`) é gradiente procedural. Nenhum asset GDQuest/CC BY-NC. Ver `docs/ASSET_CREDITS.md`.
