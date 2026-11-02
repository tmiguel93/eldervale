# E8.0 - Aquisicao de assets gratuitos (tema nordico)

Data: 2026-11-02. Escopo: encontrar e importar assets 3D/UI/VFX/audio gratuitos e de licenca livre usando apenas o que a VM alcanca (`github.com`, `api.github.com`, `raw.githubusercontent.com`, `codeload.github.com`). Nada foi integrado a cenas ainda (isso e o E8.1).

Regra de licenca aplicada: aceitar CC0, MIT, Apache-2.0, OFL, CC-BY (com credito); rejeitar NC, ND, sem licenca, desconhecida, "free for personal use". Creditos formais: `docs/ASSET_CREDITS.md`. Lista de arquivos: `assets/ASSET_MANIFEST.json`. Verificacao: `python3 -I tools/verify_assets.py` e `godot --headless --path . -s tools/verify_assets.gd`.

## 1. O que foi adquirido (numeros reais)
Total: 1597 arquivos catalogados no manifest (612 modelos, 230 audios, 740 icones, 10 fontes, 5 sprites de VFX); `assets/` ocupa ~91 MB incluindo os 1713 `.import` (79,4 MB sem eles); maior arquivo 4,9 MB. Pacotes brutos ficaram em `.tools/downloads/` (ignorado pelo Git).

| Pacote (pasta em assets/third_party) | Licenca | Conteudo usado | Papel no jogo |
|---|---|---|---|
| kaykit_adventurers | CC0 | Barbarian, Knight, Mage, Rogue, Rogue_Hooded (glb, rig unico, 76 animacoes cada) | Classes Guerreiro/Mago/Patrulheiro |
| kaykit_skeletons | CC0 | Skeleton_Warrior/Rogue/Mage/Minion (glb, 95 animacoes cada, inclui Spawn/Awaken/Death_C/Taunt) | Inimigos esqueleto, brutos (escala), chefe (escala) |
| kaykit_dungeon_remastered | CC0 | 101 pecas: paredes, pilares, colunas, escadas, piso, tochas, barris, caixas, entulho, banners, mesas | Ruinas de pedra, interiores, props |
| kaykit_halloween_bits | CC0 | 50 pecas (gltf+bin): tumulos, cripta, santuario, arco, cercas, lanternas, ossos, arvores mortas, caminhos | Ruinas/cemiterio, "arvores corrompidas" estaticas |
| kaykit_medieval_hexagon | CC0 | natureza (rochas, arvores, colinas), props (barraca, estandartes, rack de armas, escada), construcoes neutras e vermelhas (casas, taverna, torre, ponte, muralhas) | Vila, pontes, muralhas |
| quaternius_animals | CC0 (declarada upstream) | Wolf, Fox, Stag, Husky (12-13 animacoes: Idle, Walk, Gallop, Attack, HitReact, Death) | Criatura-lobo e bestas |
| quaternius_easy_enemies | CC0 | Spider, Rat, Snake(+angry), Frog, Wasp (3-6 animacoes) | Bestas pequenas |
| quaternius_nature | CC0 | 58: pinheiros (normais e com neve), bétulas com neve, arvores mortas (com neve), arbustos (neve), rochas (neve/musgo), tocos, toras, grama | Floresta nevada |
| quaternius_medieval_village | CC0 | 44: casas, estalagem, ferreiro, moinho, serraria, poco, fogueira (acesa), carroca, cercas, barraca de mercado | Vila |
| quaternius_medieval_buildings | CC0 | 30 modulares: torres, muralhas, portao, tunel, ponte | Fortificacoes |
| quaternius_rpg_items | CC0 | 86 itens: armas, armaduras, pocoes, cristais, baus (fechado/aberto), chaves, aneis, livros, moedas | Itens/loot, baus |
| quaternius_survival | CC0 | tocha, tocha acesa, fogueira (+fogo), barraca, tora | Acampamentos |
| quaternius_rts | CC0 | 47: muralhas e torres First Age, casas rusticas, pinheiros, rochas, montanhas, mina | Cenario, silhuetas distantes |
| quaternius_modular_dungeon | CC0 | 41 modulos | Masmorras |
| kenney_mini_arena | CC0 | 18 modelos (coluna, estatua, banner, muros, soldado animado) | Prototipo/arena |
| kenney_starter_kits | CC0 (assets) | 5 sprites de particula (particle, smoke, burst, hit, blob_shadow); 14 SFX/ambiente | Texturas de VFX basicas, sombras |
| oculus_audio_pack | CC BY 4.0 (credito obrigatorio) | 230 OGG: passos (neve, terra, madeira, pedra), combate (espada, machado, socos), magia, swooshes, vozes de ogro/troll/gigante/criatura, vozes humanas, ossos, latido, UI (magico/metal/madeira), stingers orquestrais, ambientes de floresta/noite, vento | SFX e ambientacao |
| google_fonts | OFL-1.1 | Cinzel, Cinzel Decorative, Almendra, Uncial Antiqua, MedievalSharp, IM Fell Double Pica, Metamorphous, Noto Sans Runic (glifos de runas) | UI/titulos |
| game_icons | CC BY 3.0 (credito obrigatorio) | 740 SVG (Lorc, Delapouite): armas, runas, magias, pocoes, habilidades | Icones de habilidade/item |

### Animacoes por rig (contagem real, medida com GLTFDocument no Godot 4.7.2)
KayKit Adventurers: 76 por personagem (Idle, Walking_A/B/C, Running_A/B, 1H/2H_Melee_Attack_*, 1H_Ranged_Shoot, Spellcast_*, Hit_A/B, Death_A/B, Block*, Dodge_*, Jump_*, Interact, Cheer...). KayKit Skeletons: 95 (as mesmas + Idle_Combat, Spawn_Ground/Air, Skeletons_Awaken_*, Death_C_Skeletons(_Resurrect), Taunt, Spellcast_Summon, Running_C, Walking_D_Skeletons). Quaternius animais: 12-13 (Wolf: Attack, Death, Eating, Gallop, Gallop_Jump, Idle, Idle_2, Idle_2_HeadLow, Idle_HitReact_Left/Right, Jump_ToIdle, Walk). Easy enemies: 3-6. Knight (Quaternius): 12. Soldado Kenney: 32. Soma de animacoes em todos os modelos: 879.
Os rigs KayKit passam no conjunto minimo idle/walk/run/attack/hit/death. Quaternius easy enemies e Knight nao tem "hit"; Wasp/Snake tem poucas animacoes (so servem como bestas simples).

## 2. Pesquisa: o que existe e o que foi rejeitado
| Candidato | Resultado | Motivo |
|---|---|---|
| KayKit-Game-Assets (Adventurers, Skeletons, Dungeon Remastered, Medieval Hexagon, Halloween Bits) | ACEITO | LICENSE.txt em cada pacote declara CC0. A API do GitHub mostra "NOASSERTION" porque o arquivo e texto livre, nao SPDX |
| KayKit Character Animations / Forest / Prototype / outros | Nao encontrado/nao usado | O org tem so 10 repositorios; "Character Animations" nao esta la (os glb dos personagens ja trazem 76-95 clips). City Builder, Furniture, Restaurant, Space Base: fora do tema |
| KenneyNL (org) | PARCIAL | So Starter Kits (MIT codigo + assets CC0 declarado no README) e um Mini Arena CC0; os packs grandes (Nature Kit, RPG Audio, Particle Pack) NAO estao no GitHub |
| trebeljahr/quaternius-showcase (espelho) | ACEITO | LICENSES.md lista licenca e URL de origem por pacote (todos CC0). O MIT do repo cobre so o codigo do site. Foi a unica forma de obter Quaternius via GitHub. Risco: licenca de terceiros por declaracao do espelho; as paginas upstream do Quaternius declaram CC0 |
| gdquest-demos/godot-4-VFX-assets, godot-visual-effects, godot-shaders | REJEITADO (texturas/modelos) | Arte sob CC BY-NC-SA 4.0 (NC). Somente codigo/shaders seriam MIT; nao incluidos para nao misturar |
| gdquest-demos/godot-4-3D-Characters, godot-3d-mannequin | NAO AVALIADO | Licenca "NOASSERTION"; nao verificada, nao baixado |
| game-icons/icons | ACEITO (CC BY 3.0) | Credito obrigatorio. Apenas pastas lorc e delapouite |
| facebookincubator/Meta-open-sound | PARCIAL | Instrumentos (CC0) fora de escopo; Oculus Audio Pack 01 (CC BY 4.0) usado. Previews OGG (qualidade reduzida); WAV originais estao em Releases (nao baixados) |
| google/fonts (ofl/) | ACEITO (OFL-1.1) | Fontes escolhidas por estetica antiga/runica. Noto Sans Runic cobre glifos reais de runas (Futhark) |
| beep2bleep/FreeAssetsByKenneyNLandQuaternius, nginetechnologies/pack-zoo-character, tshrjn/openFIFA, etc. | REJEITADO | Sem licenca no repositorio (license None) / procedencia incerta |
| Malcolmnixon/Quaternius-* (Sci-fi, Spaceships) | Fora do tema | CC0 mas ficção cientifica |
| sfxmint/*, mshark1/audio-mcp-assets, GhazaGG/... | Nao usado | Poucos sons, licenca ambigua ou tema inadequado |
| Variantes "pine_orange/yellow" do Halloween Bits, abobora, hex tiles/rios/costa, dinossauros e demais packs Quaternius | Nao copiados | Cor/tema inadequado ou tamanho (manter repositorio enxuto) |

## 3. Lacunas (nao existe de graca no GitHub, ou nao foi alcancavel)
Nao verificado a partir da VM (sites bloqueados): confirmar licenca na pagina antes de baixar.
- **Goblin/orc/bruto/troll animados, arqueiro e conjurador nao-esqueleto, chefe grande**: nada adequado encontrado. Opcoes manuais: Quaternius "Ultimate Monsters" / pacotes de monstros animados (https://quaternius.com/packs.html, CC0), KayKit "Skeletons"/"Adventurers" extras e Character Animations (https://kaylousberg.itch.io, CC0), Kenney "Animated Characters" (https://kenney.nl/assets, CC0). Ate la: esqueletos com escala/tintura como bruto e chefe.
- **Arvore corrompida animada**: nao ha; usar `CommonTree_Dead_Snow_*` (Quaternius) com shader de balanco/emissao nas raizes.
- **Portais/runas 3D, pedras runicas (runestones), longships, casas vikings (longhouse)**: nao ha. Sugestoes: Kenney "Nature Kit" e "Castle Kit" (https://kenney.nl/assets, CC0), Quaternius "Stylized Nature MegaKit" e "Medieval Village MegaKit" (https://quaternius.com/packs.html), itch.io "Viking" (conferir licenca de cada um).
- **Texturas de VFX nordicas (chama, faisca, raio, aura, runas)**: so 5 sprites basicos. Opcao manual: Kenney "Particle Pack" (https://kenney.nl/assets/particle-pack, CC0); alternativa: shaders procedurais.
- **Musica**: so stingers e ambientes. Opcoes manuais: OpenGameArt (cada faixa tem licenca propria, filtrar CC0/CC-BY, https://opengameart.org), Kevin MacLeod (incompetech, CC-BY), Kenney "Music Jingles" (CC0).
- **Texturas PBR (neve, pedra, madeira, gelo)**: ambientCG (https://ambientcg.com, CC0) e Poly Haven (https://polyhaven.com, CC0) - nao alcancaveis daqui.
- **Fonte de UI de leitura longa**: IM Fell Double Pica ja serve; Noto Sans Runic so tem runas.
- **Escala**: os modelos nao compartilham escala (KayKit ~2 m de altura de personagem, Quaternius animais vem com escalas internas distintas). O E8.1 deve normalizar por altura medida em runtime; o AABB do `verify_assets.gd` e apenas indicativo para meshes skinned.

## 4. Mapeamento proposto para o E8.1 (id de jogo -> asset)
Os mesmos ids estao em `ASSET_MANIFEST.json` > `aliases` (44 entradas). Nomes de clips: KayKit usa nomes sem prefixo (`Idle`, `Walking_A`, `Running_A`, `Hit_A`, `Death_A`); Quaternius usa `AnimalArmature|Idle` etc. (remover prefixo no mapeamento).

| Funcao no jogo | Asset | Clips sugeridos |
|---|---|---|
| Guerreiro (barbaro) | kaykit_adventurers/Barbarian.glb (alt.: Knight.glb) | Idle, Walking_A, Running_A, 2H_Melee_Attack_Chop/Slice/Spin, Block, Hit_A, Death_A |
| Mago | kaykit_adventurers/Mage.glb | Idle, Walking_A, Running_A, Spellcast_Shoot/Raise/Long, Hit_A, Death_A |
| Patrulheiro | kaykit_adventurers/Rogue_Hooded.glb (alt.: Rogue.glb) | Idle, Walking_A, Running_A, 1H_Ranged_Shoot/Aiming, Dodge_*, Hit_A, Death_A |
| Esqueleto guerreiro | kaykit_skeletons/Skeleton_Warrior.glb | Idle_Combat, Walking_D_Skeletons, Running_C, 1H_Melee_Attack_*, Skeletons_Awaken_*, Death_C_Skeletons |
| Esqueleto arqueiro | Skeleton_Rogue.glb | 1H_Ranged_Shoot |
| Conjurador | Skeleton_Mage.glb | Spellcast_Summon/Shoot |
| Capanga (goblin provisorio) | Skeleton_Minion.glb | Spawn_Ground, Walking_*, 1H_Melee_Attack_Stab |
| Bruto | Skeleton_Warrior.glb escala ~1.3 + tintura, anim 2H_* | 2H_Melee_Attack_Spin |
| Chefe grande (PLACEHOLDER) | Skeleton_Warrior.glb escala ~2.2 com shader de brilho; spawn Spawn_Air/Taunt_Longer | Taunt, 2H_Melee_Attack_Spinning, Death_B |
| Criatura-lobo | quaternius_animals/Wolf.glb | Idle, Walk, Gallop, Attack, Idle_HitReact_Left, Death |
| Bestas secundarias | Fox, Stag, Husky, Spider, Rat | idem |
| Arvore corrompida | quaternius_nature/CommonTree_Dead_Snow_1..3 (+shader) | (sem animacao) |
| Floresta nevada | PineTree_Snow_1..5, BirchTree_Snow_*, Bush_Snow_*, Rock_Snow_*, TreeStump_Snow, WoodLog_Snow | |
| Casas de vila | quaternius_medieval_village/House_1..4, Inn, Blacksmith, Mill, Stable, Well, Bonfire_Lit | |
| Muralhas/pedras | kaykit_dungeon_remastered/wall*, pillar*, column, stairs*, rubble_*; quaternius_medieval_buildings/Wall*, Tower*, Bridge | |
| Ruinas/runas | kaykit_halloween_bits/arch*, pillar, shrine, plaque, gravemarker_*, crypt; Wall_broken/wall_cracked do Dungeon | |
| Pontes | kaykit_medieval_hexagon/buildings_neutral/building_bridge_A/B; quaternius_medieval_buildings/Bridge | |
| Fogueiras/tochas | medieval_village/Bonfire_Lit, survival/Bonfire_Fire + WoodenTorch_Fire, dungeon/torch_lit, torch_mounted | |
| Baus/loot | quaternius_rpg_items/Chest_Closed/Open, Coin*, Potion*_Filled, Key*, Crystal* | |
| VFX | kenney_starter_kits/vfx/particle.png, smoke.png, burst.png, hit.png (CPUParticles/GPUParticles3D com mistura aditiva) | |
| UI | Cinzel Decorative Bold (titulo), Cinzel (cabecalhos), IM Fell Double Pica (corpo), Noto Sans Runic (runas); icones game_icons | |
| SFX | oculus: FEETHmn_ShoeSnow*/Dirt*/Wood*, WEAPSwrd_*, FGHTImpt_*, MAGSpel_*, CREAHmn_Ogre/Troll/Giant_* (inimigos/chefe), VOXMale_* (jogador), GOREBone_*, ANMLDog_DogBark (lobo), UIClick_Wood/Metal/Magical_*, MUSCStngr_Victory/Loss/LevelUpOrchestral, AMBForst_* / WINDVege_LightWind* | |

## 5. Passos de verificacao e resultados
Ver o bloco "Validacao" do relatorio de entrega e `docs/ASSET_CREDITS.md`. Reproduzir: `python3 -I tools/build_asset_manifest.py && python3 -I tools/verify_assets.py`; no Godot: `--import` (rodar ate concluir; ~25 min em disco montado na primeira vez, ~1 min depois) e `-s tools/verify_assets.gd`.

## 6. Riscos
- `export_presets.cfg` usa `export_filter="all_resources"`: todo recurso importado entra no `.pck` do cliente e do servidor, inclusive `assets/` nao referenciado (~80 MB). Decidir no E8.1 (excluir `assets/*` do preset do servidor e usar "selected scenes" no cliente); nao alterado aqui.
- Previews OGG do Oculus (qualidade reduzida); WAV originais so em Releases.
- Licenca Quaternius depende da declaracao do espelho + pagina upstream; nenhum arquivo de licenca por pacote existe no espelho (criamos `LICENSE.txt` explicativo em cada pasta).
- CC BY: creditos precisam aparecer no jogo (icones game-icons e Oculus).
