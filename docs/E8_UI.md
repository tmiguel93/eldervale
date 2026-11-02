# E8.4 — UI nórdica e efeitos de interface

Escopo: aparência e feedback da UI do cliente. **Nada de gameplay, protocolo ou servidor mudou** (DEC-0039). Evidências: `docs/img/e8_4_ui_*.png`
(`e8_4_ui_hud_boss`, `e8_4_ui_panels_a`, `e8_4_ui_panels_b`, `e8_4_ui_login_menu`, `e8_4_ui_antes_depois`), geradas por `tools/shots/` em Compatibility/GL por
software (`xvfb-run` + `LIBGL_ALWAYS_SOFTWARE=1`); não representam GPU real.

## Tema (`scripts/ui/theme/`)
| Arquivo | Papel |
|---|---|
| `norse_theme.gd` (`NorseTheme`) | paleta (madeira escura, ferro, ouro velho, azul-gelo, vermelho-sangue, pergaminho), cores/variações por raridade, contraste WCAG, `build()` do `Theme` único (botão normal/hover/pressed/focus/disabled, painéis, tooltip, barras de rolagem, separadores, campos de texto, slider, checkbox) |
| `ui_art.gd` (`UiArt`) | molduras 9-patch **procedurais** (pixel a pixel: chanfro, banda de ferro, fio de ouro, rebites, ruído, ornamentos), em cache: painel, HUD, chefe, botão, slot por raridade (com brilho), tooltip, aviso, minimapa |
| `norse_fonts.gd` (`NorseFonts`) | Cinzel Decorative Bold (título), Cinzel variável (títulos), IM Fell Double Pica (corpo), Noto Sans Runic (runas); cadeia de fallback para a fonte padrão; `missing_glyphs()` confere os acentos do português |
| `ui_icons.gd` (`UiIcons`) | ver abaixo |
| `stat_bar.gd` (`StatBar`) | barra com gradiente, faixa de vidro, marcas, "fantasma" do dano recente e brilho que varre; tipos HEALTH/MANA/STAMINA/XP/BOSS/ALLY |
| `rune_divider.gd`, `rune_spinner.gd`, `ui_tooltip.gd` | separador rúnico, runa girando (carregamento/login), tooltip tematizado |

`UiStyle` (já usado por todos os painéis) passou a delegar ao tema: `UiStyle.theme()`, `label()`, `heading()`, `bar()`. Os painéis usam variações de tipo
(`ModalPanel`, `HudPanel`, `PanelTitle`, `HeadingLabel`, `TitleLabel`, `DimLabel`, `RuneLabel`, `CloseButton`, `Slot<Raridade>`, `SlotSelected`).

## Ícones (`data/ui/icons.json`)
Mapeia ids de jogo → `autor/nome` de `assets/third_party/game_icons/<autor>/<nome>.svg` (game-icons.net, **CC BY 3.0**): habilidades, itens (inclusive únicos), tipos de
item (fallback), slots de equipamento, atributos, classes, recursos, tiers de chefe, ícones de interface e tiers de talento. Os SVG são glifos brancos sobre fundo
preto opaco: `UiIcons.texture()` converte a luminância em alfa (96 px, mipmaps) e o ícone é tingido por `modulate` (cor da raridade). Em headless devolve a textura crua.
Sem ícone => `UiIcons.make()` devolve um `Label` com a inicial (fallback de texto); item desconhecido usa o ícone do tipo. Validação: `UiIcons.validate()`, `tools/icons_check.mjs`
(chamado por `node tools/validate_content.mjs`: formato, arquivo existente, cobertura de todas as habilidades/itens/classes/tipos/slots/atributos/recursos e aviso de atribuição para cada pacote CC BY).
Para mapear um ícone novo: editar o JSON e rodar `python3 tools/gen_export_filter.py` (o teste `test_e84_export` falha se a lista de exclusão do cliente ficar velha).

Molduras de raridade (comum, incomum, raro, épico, lendário, mítico): moldura + cor do ícone + brilho (`RARITY_GLOW`); lendário/mítico têm brilho pulsante e reflexo (só com movimento).

## Efeitos (`scripts/ui/fx/ui_fx.gd`)
`appear/vanish` (fade + escala/subida dos painéis; o painel é re-centralizado por `UiPanel.recenter()`), `pulse`, `shake` (tremor leve da HUD ao tomar dano), `slide_in` (avisos),
`fade_to`. Hotbar: pulso quando a recarga termina. Barra do chefe: quadro dramático, pulso + tremor na troca de fase. Runa girando na transição de zona (`ScreenFade`) e no login.
**Headless/bot/testes:** tudo instantâneo e determinístico (`UiFx.available()`), salvo `UiFx.force_enabled` nos testes. **`--reduce-motion` / opção:** sem escala, subida, tremor,
pulso nem brilho em laço; só fades curtos (55%).

## HUD
Party (canto superior esquerdo, abaixo do texto de debug), **barra do chefe** (topo central), minimapa com moldura rúnica e "N" (topo direito), **hotbar** (4 `SkillSlot`: ícone, tecla,
custo, recarga radial), vida + nível (`NV n`), prompt de interação, avisos, atalhos em "chips" e banner de zona. Layout por âncoras; `UiSettings.apply_scale()` usa `canvas_items`/`expand`
com base 1280x720 (+ fator 85/100/115/130%), então vale de 1280x720 a 1920x1080+ (ignorado em headless). Painéis são medidos pelo teste para caber em 1280x720.

### Barra do chefe (correção)
Antes: aparecia sempre que havia um chefe vivo no snapshot. Agora (`BossBar`/`ClientUi.update_frame`): só com sessão PLAYING, posição local conhecida, snapshot recente (`SNAPSHOT_STALE_MS`),
chefe vivo **na mesma zona** (`ZoneDef.contains(pos, 1.5)`) e a ≤ `SHOW_RANGE` (40 m); depois de visível só some além de `HIDE_RANGE` (46 m, histerese). A troca de zona a zera na hora.

### Recarga da hotbar = estimativa
O protocolo não envia recargas. O cliente inicia a recarga na borda de subida do bit da tecla (`ClientUi.note_local_actions`) com o `cooldown` do `SkillData`. É só visual; o servidor decide.

## Créditos e opções
`F1` (ou Menu > Créditos): `CreditsModel` lê `assets/ASSET_MANIFEST.json` + `data/ui/credits.json` e lista **todos** os pacotes por licença (CC BY 3.0 e 4.0 com o texto de atribuição, CC0, OFL, MIT);
o teste confere que nenhum pacote do manifesto fica de fora. `O` (ou Menu > Opções): qualidade Baixa/Média/Alta (`QualitySettings`), escala da interface, reduzir movimento (`VfxSettings`) e volume
(`UiSettings`), gravados em `user://settings.cfg` (seções graphics/accessibility/audio/interface). `Esc` sem painel abre o Menu (antes não era consumido; teste do e5_ui ajustado).

## Exportação
`export_presets.cfg`: o cliente deixou de excluir `game_icons/*` e `google_fonts/*` por inteiro e passou a excluir **arquivo a arquivo** o que não é usado (696 arquivos; gerado por
`tools/gen_export_filter.py`, `--check` confere). O servidor continua com `assets/*` excluído. Conferido com `--export-pack "Windows Client"`: o `.pck` (30 MB) contém os 50 ícones usados e as 4 fontes, e nenhum ícone/fonte não usado.

## Testes
`tests/e8_ui/` (287 checagens): tema/variações/contraste/fontes/molduras, ícones (existem, cobertura, fallback), painéis (abrem/fecham com e sem animação, cabem e ficam centrados em 1280x720),
barra do chefe (alcance, histerese, outra zona, sem posição, sem snapshot, fora de PLAYING, troca de zona), hotbar, reduce-motion, créditos (todos os pacotes), opções persistidas, exportação.
`backend/test/content_validation.test.ts` ganhou o caso de ícones/créditos. Ajuste justificado em teste existente: `tests/e5_ui/test_ui_client.gd` ("Esc sem painel não é consumido" → "Esc sem painel abre o Menu").

## Ferramentas
`tools/shots/run_ui.sh [cenas] [prefixo]` (bancada `ui_lab.gd`, sem servidor: hud, inventory, talents, quests, dialogue, map, options, credits, menu, boss, craft, toasts, login);
`tools/shots/run_tour.sh ui_hub|ui_alpha` (cliente real, injeta `InputEventAction`/teclas); `python3 tools/shots/ui_collage.py` (colagens em `docs/img`).

## Limitações
- Sem barras de mana/stamina/XP e sem XP no HUD: o protocolo não as envia (as classes existem, não ligadas).
- Visto só em Compatibility/GL por software; fontes e brilho em GPU real/HiDPI não verificados; escala (`apply_scale`) não exercitada em janela real.
- IM Fell a 17 px é fina; se houver queixa de leitura, trocar `NorseFonts.PATHS["body"]` (e regenerar o filtro de exportação).
- O tour `ui_hub` interage primeiro com a bancada (posição de `_goto`); o diálogo do NPC foi capturado na bancada `ui_lab`.
