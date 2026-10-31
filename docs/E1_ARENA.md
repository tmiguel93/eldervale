# E1 — Arena de teste (modulo A)

Cena: `res://scenes/arena/test_arena.tscn` (script `scripts/arena/test_arena.gd`). Unidade: 1 unidade = 1 m.
Geometria placeholder (caixas com material simples) e criada em codigo no `_ready`.

## Dimensoes
- Piso 60x60 m, topo em y=0 (StaticBody3D). Muralha externa 4 m de altura.
- Area aberta central: x,z em [-10, 10], com caixas baixas e 4 pilares de 6 m.
- Corredor estreito ao norte: largura livre 2,5 m, comprimento 14 m (z -12 a -26, x=0).
- Rampa a leste (x~14, z=8): 20 graus (limite 30), 8 m de comprimento, 4 m de largura, plataforma no topo (~2,74 m).
- Escada a oeste (x=-16, z a partir de 4): 10 degraus de 0,2 m x 0,4 m de profundidade, 3 m de largura, plataforma no topo (2,0 m).
- Spawn do jogador: (0, 0, 0).

## Grupos
- `occluder`: StaticBody3D da muralha, do corredor e dos pilares (MeshInstance3D filho chamado `Mesh`). O fade e responsabilidade do modulo B.

## Integracao (por caminho, carregados em runtime)
- `res://scenes/player/player.tscn`, `res://scenes/camera/iso_camera.tscn` (usa `set_target(Node3D)`).
- Se algum faltar: `push_error` e a arena continua sem ele.

## Qualidade
`scripts/settings/quality_settings.gd` (`QualitySettings`, estatico, sem autoload). F2 alterna Baixo/Medio/Alto; o preset aparece no HUD (padrao: Alto).
Aplica: sombras on/off + resolucao do atlas direcional, SSAO, glow, MSAA e escala 3D.

## Limites conhecidos
- Nenhuma medicao de desempenho foi feita; hardware-alvo nao medido. Presets sao valores iniciais nao calibrados.
- A resolucao do atlas de sombra e global (RenderingServer), nao por viewport.
- Geometria so em codigo: nao editavel visualmente no editor.
- Sem navmesh.
