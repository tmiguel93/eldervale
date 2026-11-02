# E8.2 — Cenário nórdico 3D e iluminação semi-realista

Só apresentação, só cliente. Nenhuma mudança em servidor, protocolo, colisão ou física. Decisão: `docs/DECISIONS.md` (DEC-0037).

## Peças

| Arquivo | Papel |
|---|---|
| `scripts/scenery/scenery_theme.gd` (`SceneryTheme`) | Dados por zona: humor (céu, sol, ambiente, névoa, glow), regiões (salão do chefe), chão/trilhas, "skins" de props existentes, perímetro, espalhamento, tochas/fogueiras/lampiões, covil, portais. Lista os pacotes usados. |
| `scripts/scenery/scenery_plan.gd` (`SceneryPlan`) | Gera a lista de colocações. Determinístico: seed = FNV-1a de `zona|sal`. Respeita exclusões (colisores, NPCs, estações, trilhas) e a regra de câmera. |
| `scripts/scenery/scenery_builder.gd` (`SceneryBuilder`) | `decorate(zone_root, zone, quality, npcs)`: estiliza chão e trilhas (shaders), esconde as paredes primitivas quando o tema manda, veste props/portais com GLB e instancia a decoração em `MultiMeshInstance3D` por (asset, célula de 40 m, sombra). |
| `scripts/scenery/scenery_env.gd` (`SceneryEnv`) | `WorldEnvironment` (céu procedural, ambiente, tonemap filmic, névoa, glow, ajustes; SSAO/névoa volumétrica só no Forward+) + `DirectionalLight3D` (sombras ortogonais) + mistura de humor por região + poda e tremulação de luzes. |
| `scripts/scenery/*.gdshader`, `ground_common.gdshaderinc` | Chão procedural (ladrilho/grama/patches), trilhas com borda suave e decais, chama em billboard aditivo. |
| `scripts/settings/quality_settings.gd` | Presets Baixo/Médio/Alto, `--quality`, `ConfigFile`, capacidades do renderer. |
| `scripts/client/client_world.gd` / `client_main.gd` | Liga tudo só quando `SceneryBuilder.enabled()` (= `ModelRig.models_enabled()`); F9 alterna a qualidade e grava. |
| `tools/scenery_stats.gd`, `tools/probe_assets.gd`, `tools/shots/run_lab.sh` + `scenery_lab.gd` | Orçamento estático por zona/preset; inspeção de GLB; bancada visual sem servidor. |

## Garantias

- **Headless/bot/teste:** `enabled()` é falso, nada é carregado (`ModelRig.load_count == 0`, `SceneryBuilder.extract_count == 0`), as primitivas do `WorldBuilder` continuam (fallback intacto). Servidor continua com `with_visuals=false`.
- **Física inalterada:** a decoração não tem colisão (somente visual). Colisores, camadas, máscaras e posições da zona decorada são idênticos aos da zona do servidor (teste compara a assinatura). O nó `Mesh` do `PuzzleGate` é mantido (o portão continua abrindo/fechando).
- **Oclusão (bug das ruínas):** o interior só recebe cobertura baixa (chão). Objetos altos ficam em anel externo e passam pelo filtro `casts_view_shadow_on` (nada alto fica entre a câmera e área jogável). Na zona das ruínas as paredes primitivas do lado da câmera (S/E) viram barreiras baixas; as do lado oposto (N/W) são altas porque ficam atrás do jogador. As peças vestidas continuam no grupo `occluder` (o `OcclusionFader` segue funcionando).
- **Determinismo:** mesma zona, mesma lista, em qualquer plataforma (FNV-1a, não `String.hash()`). Densidade por `rank` por item: Baixo ⊂ Médio ⊂ Alto.

## Humor por zona

- **Vila (Greenwood):** crepúsculo dourado, sol quente e baixo, névoa quente leve.
- **Floresta selvagem:** verde-azulado, névoa mais presente, sol frio e filtrado.
- **Ruínas:** antecâmara azul fria e escura com tochas quentes (energia 3, alcance 11 m); salão do chefe roxo-avermelhado, mais dramático. A mistura é suave (`BLEND_RATE`) quando o jogador cruza a região.

## Presets de qualidade

| Chave | Baixo | Médio (padrão) | Alto |
|---|---|---|---|
| Sombras / atlas | desligadas / 1024 | ligadas / 2048 | ligadas / 4096 |
| Distância das sombras | 50 m | 55 m | 60 m |
| SSAO | não | não | sim (só Forward+) |
| Névoa volumétrica | não | não | sim (só Forward+) |
| SSIL | não | não | não (custo alto, ganho baixo no iso) |
| Glow | não | sim | sim |
| MSAA / escala 3D | off / 0,75 | 2x / 1,0 | 4x / 1,0 |
| Densidade de decoração | 0,35 | 0,70 | 1,00 |
| Distância de desenho de props | 60 m | 90 m | 130 m |
| Luzes ativas (mais próximas) | 4 | 8 | 14 |

Ordem de resolução: `--quality low|medium|high` (não grava) > `user://settings.cfg` (`[graphics] quality`) > Médio. F9 em jogo alterna e grava. Aliases em pt-BR (`baixo`, `medio`, `alto`). Não há item de menu (não havia tela de opções simples).

## Capacidades do renderer

O projeto é "Forward Plus", mas as evidências foram geradas com `--rendering-driver opengl3` (Compatibility, o único disponível com Xvfb + GL por software). `QualitySettings.renderer_caps()` só liga SSAO/SSIL/névoa volumétrica quando o método é `forward_plus`.

| Efeito | Compatibility (verificado) | Forward+ |
|---|---|---|
| Céu procedural, ambiente, tonemap, névoa exponencial, glow, ajustes | sim | sim |
| Sombras direcionais ortogonais, OmniLights com tremulação, chamas emissivas | sim | sim |
| SSAO, névoa volumétrica | não existe | previsto, **não verificado visualmente** |

Calibração: no Compatibility `fog_density` é muito mais forte que no Forward+. 0,0004 é leve; 0,002 dá ~35% de névoa; ≥ 0,0025 satura. Os humores usam 0,0016–0,0022 (teste impede passar de 0,0025).

## Evidências visuais (Baixo à esquerda, Alto à direita; câmera isométrica real, zoom 1,0)

- `docs/img/e8_2_cmp_hub.png`, `e8_2_cmp_wild.png`, `e8_2_cmp_ante.png` (antecâmara), `e8_2_cmp_boss.png` (salão do chefe).
- Baixo: sem sombras nem glow, menos decoração, cena mais escura e chapada. Alto: sombras projetadas (árvores, jogador), glow nas chamas/portal, mais pedras/ossos/lajes. O personagem se destaca em todas.
- Provas das tours: `.tools/scratch/shots/` (`ruins_01_antecamara`, `ruins_02_combate1`, `ruins_03_salao`, `ruins_04_salao_combate1`; `scn_hub`, `scn_wild`, `scn_ruins` em `tools/shots/screenshot_tour.gd`). Nelas o jogador aparece ao lado das barreiras baixas, sem sumir.
- Reprodução: `tools/shots/run_lab.sh --quality high --shot nome,zone_ruins,432,0,1.0` ou `QUALITY=high tools/shots/run_tour.sh ruins`.

## Orçamento de performance

Medição em **GL por software** (Xvfb + llvmpipe, 1280x720, bancada `scenery_lab`). O tempo em ms é do rasterizador por CPU e **não representa uma GPU real**; vale só para comparar presets e contar chamadas.

| Cena | Baixo (draws / ms) | Médio | Alto |
|---|---|---|---|
| Vila (0,6) | 117 / 108 | 333 / 498 | 403 / 521 |
| Selva (200,4) | 66 / 65 | 215 / 326 | 259 / 350 |
| Ruínas, antecâmara | 44 / 73 | 124 / 372 | 136 / 389 |
| Ruínas, salão do chefe | 42 / 96 | 114 / 425 | 138 / 444 |

Orçamento documentado (alvo para GPU integrada, Médio): **≤ 500 draw calls e ≤ 100 mil primitivas por quadro** em qualquer ponto de zona (com NPCs/entidades); Alto até 600 draws. Estático por zona (`tools/scenery_stats.gd`): vila 202/268/312 MultiMeshes e 706/1251/1688 instâncias em Baixo/Médio/Alto; selva 339/432/474 MultiMeshes; ruínas 184/268/319. Medido (Alto, vila): 403 draws, 87 mil primitivas; dentro do orçamento. Nas tours completas (com entidades e HUD) o Médio mediu 130–490 draws (vila ≈ 410–490, o pior caso), por volta de 480–575 ms/quadro em software.

## Exportação

- Cliente (`Windows Client`): removidas da exclusão só as pastas usadas (`quaternius_nature`, `quaternius_medieval_village`, `quaternius_survival`, `kaykit_dungeon_remastered`, `kaykit_halloween_bits`). `--export-pack` verificado por listagem: 58 + 44 + 11 + 202 + 51 entradas desses pacotes; nenhum pacote excluído, nada de `tests/` ou `tools/`. `.pck` de 27,7 MB.
- Servidor (`Windows Server`): continua `assets/*`; `.pck` de 1,0 MB, nenhum `assets/` nem `third_party`.
- `.exe` não foi gerado nem executado no Windows.

## Testes (`tests/e8_scenery/`)

`test_e8s_plan` (FNV, seed, constantes da câmera = `IsoCamera`, determinismo, aninhamento, exclusões, regra de câmera), `test_e8s_assets` (todos os assets do tema existem e têm malha; presets de exportação; esquema do tema), `test_e8s_headless` (nada carrega em headless; com modelos forçados a assinatura física é idêntica; decoração sem colisão; portão), `test_e8s_quality` (chaves, padrão, `--quality`, `ConfigFile`, caps, humores, poda de luzes).

## Limitações

- Decoração sem colisão: o jogador atravessa árvores/pedras decorativas do anel externo (que ficam fora da área jogável ou em cobertura baixa).
- SSAO e névoa volumétrica (Forward+) não foram vistos em imagem.
- Sem item de menu de qualidade (só `--quality`, arquivo e F9).
- Aliados remotos continuam como Cavaleiro (E8.1).
- `OcclusionFader` ganhou verificação `is_instance_valid` (malhas liberadas na reconstrução da zona).
