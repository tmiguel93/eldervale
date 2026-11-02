# Creditos de assets

Todo asset externo deve ser listado aqui com origem, autor, licenca e alteracoes (AGENTS.md, secao 8).
Arte de placeholder deve ser claramente identificada.

**Inventario anterior (E7.1, 2026-11-02, antes do E8.0):** varredura da arvore versionada (excluindo `.tools/`, `build/`, `node_modules/`, `.git/`) por imagens (png/jpg/svg/webp/ico), audio (ogg/wav/mp3), fontes (ttf/otf/woff) e modelos (glb): **nenhum arquivo encontrado**. O jogo usa apenas formas/cores geradas por codigo e a fonte padrao do Godot (parte do motor). `project.godot` nao define icone nem fonte customizada.

**E8.0 (2026-11-02):** pacotes externos adquiridos do GitHub e copiados (sem alteracao, salvo indicado) para `assets/third_party/<pacote>/`, cada um com a licenca ao lado. Lista completa de arquivos: `assets/ASSET_MANIFEST.json` (gerado por `tools/build_asset_manifest.py`). Pesquisa e rejeicoes: `docs/E8_ASSETS.md`.

**E8.2 (2026-11-02):** nenhum asset novo e nenhum arquivo alterado. Passam a ser USADOS no cenário do cliente os pacotes já creditados abaixo: Quaternius Nature, Medieval Village e Survival, KayKit Dungeon Remastered e Halloween Bits (e o cliente deixa de excluí-los do `.pck`). Chão, trilhas e chamas são shaders procedurais próprios. Detalhes: `docs/E8_SCENERY.md`.

**E8.1 (2026-11-02):** nenhum asset novo. Passam a ser USADOS no jogo (cliente): KayKit Adventurers (Barbarian, Knight, Mage, Rogue, Rogue_Hooded: classes e NPCs), KayKit Skeletons (4: inimigos, bruto e chefe PLACEHOLDER), Quaternius animais (Wolf, Fox), Easy Enemies (Spider) e RPG items (Chest_Closed, Potion1_Filled: pickups). Tinturas e escala sao aplicadas em runtime; os arquivos nao foram alterados. Detalhes: `docs/E8_MODELS.md`.

| Asset | Origem (URL/fonte) | Autor | Licenca | Alteracoes | Local no repo |
|-------|--------------------|-------|---------|------------|---------------|
| Fonte padrao e icone do motor embutidos nos executaveis | Godot Engine 4.7.2 (templates de exportacao) | Godot Engine contributors | MIT (ver licencas de terceiros do Godot) | nenhuma | (motor) |
| KayKit Adventurers Character Pack 1.0 (Barbarian, Knight, Mage, Rogue, Rogue_Hooded) | https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0 (autor: kaylousberg.com) | Kay Lousberg | CC0-1.0 | Somente `Characters/gltf/*.glb` copiados; nenhuma modificacao | assets/third_party/kaykit_adventurers/ |
| KayKit Skeletons Character Pack 1.0 (4 esqueletos) | https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Skeletons-1.0 | Kay Lousberg | CC0-1.0 | Somente `Characters/gltf/*.glb`; nenhuma | assets/third_party/kaykit_skeletons/ |
| KayKit Dungeon Remastered 1.0 (101 pecas selecionadas) | https://github.com/KayKit-Game-Assets/KayKit-Dungeon-Remastered-1.0 | Kay Lousberg | CC0-1.0 | Subconjunto; arquivos renomeados de `*.gltf.glb` para `*.glb`; conteudo intacto | assets/third_party/kaykit_dungeon_remastered/ |
| KayKit Halloween Bits 1.0 (50 pecas: tumulos, cripta, arvores mortas, cercas, lanternas) | https://github.com/KayKit-Game-Assets/KayKit-Halloween-Bits-1.0 | Kay Lousberg | CC0-1.0 | Subconjunto (gltf+bin+textura); nenhuma | assets/third_party/kaykit_halloween_bits/ |
| KayKit Medieval Hexagon Pack 1.0 (decoracao natureza/props, construcoes neutras e vermelhas) | https://github.com/KayKit-Game-Assets/KayKit-Medieval-Hexagon-Pack-1.0 | Kay Lousberg | CC0-1.0 | Subconjunto (gltf+bin+textura); nenhuma | assets/third_party/kaykit_medieval_hexagon/ |
| Quaternius Ultimate Animated Animal Pack (Wolf, Fox, Stag, Husky) | pagina: https://quaternius.com/packs/ultimateanimatedanimals.html ; arquivos obtidos do espelho https://github.com/trebeljahr/quaternius-showcase | Quaternius | CC0-1.0 (declarada upstream; ver LICENSE.txt local) | Subconjunto; nenhuma | assets/third_party/quaternius_animals/ |
| Quaternius Easy Enemy Pack (6) | https://quaternius.com/packs/easyenemy.html (espelho trebeljahr/quaternius-showcase) | Quaternius | CC0-1.0 | nenhuma | assets/third_party/quaternius_easy_enemies/ |
| Quaternius Animated Knight Pack (1) | https://quaternius.com/packs/knightcharacter.html (espelho) | Quaternius | CC0-1.0 | Somente KnightCharacter.glb | assets/third_party/quaternius_knight/ |
| Quaternius Ultimate Nature Pack (58: pinheiros/bétulas com neve, arvores mortas, rochas, arbustos, tocos) | https://quaternius.com/packs/ultimatenature.html (espelho) | Quaternius | CC0-1.0 | Subconjunto; nenhuma | assets/third_party/quaternius_nature/ |
| Quaternius Medieval Village Pack (44) | https://quaternius.com/packs/medievalvillage.html (espelho) | Quaternius | CC0-1.0 | nenhuma | assets/third_party/quaternius_medieval_village/ |
| Quaternius Modular Medieval Building Pack (30) | https://quaternius.com/packs/modularmedievalbuildings.html (espelho) | Quaternius | CC0-1.0 | nenhuma | assets/third_party/quaternius_medieval_buildings/ |
| Quaternius Ultimate RPG Pack (86 itens) | https://quaternius.com/packs/ultimaterpg.html (espelho) | Quaternius | CC0-1.0 | Subconjunto; nenhuma | assets/third_party/quaternius_rpg_items/ |
| Quaternius Survival Pack (11: tochas, fogueira, barraca) | https://quaternius.com/packs/survival.html (espelho) | Quaternius | CC0-1.0 | Subconjunto; nenhuma | assets/third_party/quaternius_survival/ |
| Quaternius Ultimate Fantasy RTS (47: muralhas, torres, casas First Age, pinheiros, rochas) | https://quaternius.com/packs/ultimatefantasyrts.html (espelho) | Quaternius | CC0-1.0 | Subconjunto; nenhuma | assets/third_party/quaternius_rts/ |
| Quaternius Modular Dungeon Pack (41) | https://quaternius.com/packs/medievaldungeon.html (espelho) | Quaternius | CC0-1.0 | nenhuma | assets/third_party/quaternius_modular_dungeon/ |
| Kenney Mini Arena 1.0 (18 modelos, via Starter-Kit-Basic-Scene) | https://github.com/KenneyNL/Starter-Kit-Basic-Scene (sample/Mini Arena) | Kenney (credito adicional: Tony Schaer) | CC0-1.0 | Subconjunto; nenhuma | assets/third_party/kenney_mini_arena/ |
| Kenney Starter Kits: 5 sprites de particula (E8.3: particle, smoke, burst, hit usados nos VFX de combate; blob_shadow nas sombras) + 14 SFX/ambiente (ainda fora do build do cliente) | https://github.com/KenneyNL/Starter-Kit-3D-Platformer, -FPS, -City-Builder, -Racing | Kenney | CC0-1.0 (assets); MIT (codigo dos kits, nao incluido) | Subconjunto; nenhuma | assets/third_party/kenney_starter_kits/ |
| Oculus Audio Pack 01 (subconjunto, 230 .ogg: passos, combate, magia, criaturas, UI, stingers, ambientes) | https://github.com/facebookincubator/Meta-open-sound (corpora/oculus-audio-pack); original: https://developers.meta.com/vr/downloads/package/oculus-audio-pack-1/ | Oculus VR, LLC | CC-BY-4.0 (**exige credito**: ver `ATTRIBUTION.txt` na pasta) | Subconjunto de previews OGG ja transcodificados pelo mantenedor do repositorio; nenhuma alteracao nossa | assets/third_party/oculus_audio_pack/ |
| Fontes Google Fonts: Cinzel, Cinzel Decorative, Almendra, Uncial Antiqua, MedievalSharp, IM Fell Double Pica, Metamorphous, Noto Sans Runic | https://github.com/google/fonts (diretorio ofl/) | Autores por fonte (ver OFL.txt de cada pasta): The Cinzel Project Authors; Ana Sanfelippo; Brian J. Bonislawsky; wmk69; Igino Marini; Sorkin Type Co; Noto Project Authors | OFL-1.1 | `Cinzel[wght].ttf` renomeado para `Cinzel-Variable.ttf`; nenhuma outra | assets/third_party/google_fonts/ |
| game-icons.net (740 icones SVG das pastas lorc e delapouite) | https://github.com/game-icons/icons (site: https://game-icons.net) | Lorc, Delapouite | CC-BY-3.0 (**exige credito**: "Icons made by Lorc / Delapouite from game-icons.net, CC BY 3.0"; ver `ATTRIBUTION.txt`) | Subconjunto por palavra-chave; nenhuma | assets/third_party/game_icons/ |

Data de aquisicao de todos os pacotes acima: 2026-11-02.

## Creditos obrigatorios na tela de creditos do jogo (CC BY)
- "Icons made by Lorc (http://lorcblog.blogspot.com) and Delapouite (https://delapouite.com) from https://game-icons.net, licensed under CC BY 3.0".
- "Oculus Audio Pack 01" by Oculus VR, LLC (https://developers.meta.com/vr/downloads/package/oculus-audio-pack-1/), licensed under CC BY 4.0. Files renamed to the UCS naming convention; OGG previews transcoded from the original WAVs.
- Recomendado (nao obrigatorio, CC0): Kay Lousberg (KayKit), Quaternius, Kenney.

## Placeholders restantes (E8.0)
- **Todo o jogo continua usando formas/cores geradas por codigo** ate o E8.1 integrar os assets; nada em `assets/` esta referenciado por cena ainda.
- Sem asset adquirido (lacuna): goblin/orc/bruto/troll animados, chefe grande dedicado, arvore corrompida animada, conjurador nao-esqueleto, portal/runas 3D, texturas de VFX nordicas (chama, faisca, raio, runa), musica longa (so ha stingers e ambientes), texturas PBR (neve/pedra). Ver `docs/E8_ASSETS.md` secao Lacunas. Enquanto isso, usar escala/tintura dos esqueletos como chefe e shaders procedurais para VFX; marcar como `PLACEHOLDER` no nome da cena/recurso.
- Rejeitado por licenca: ver `docs/E8_ASSETS.md` (ex.: texturas/modelos de `gdquest-demos/godot-4-VFX-assets`, CC BY-NC-SA 4.0).
- Dono: incluir o texto das licencas (OFL, CC BY) e os avisos do Godot na distribuicao.

Observacoes: o executavel exportado embute o motor Godot; a distribuicao deve incluir os avisos de licenca do Godot (Projeto > Licencas) **[o dono deve incluir o texto na distribuicao]**. Dependencias de codigo do backend: `docs/DEPENDENCIES.md`.
