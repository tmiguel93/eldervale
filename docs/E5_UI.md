# E5.5 - UI mínima do cliente

Interface do cliente feita só com `Control` em código (sem cenas novas, sem assets externos, tema único em `UiStyle`). **Sem lógica de jogo**: só reflete o que o servidor envia a `ClientSession` e envia comandos pelas APIs que já existiam (`dialogue_open/choose/close`, `quest_accept/abandon/turn_in`, `craft`). Servidor, backend, combate e protocolo **não foram alterados** (VERSION continua 2).

## Teclas
Definidas em `project.godot` (`[input]`): `interact` = **F**, `quest_log_toggle` = **J**, `map_toggle` = **M**; `inventory_toggle` (**I**) já existia. O pedido sugeria E para interagir, mas E é `skill_2`, então a interação ficou em F (teste `test_ui_panels` garante que nenhuma tecla das ações se repete).

| Tecla | Efeito |
|---|---|
| F | perto de NPC: `ClientSession.dialogue_open(npc)`; perto da bancada: abre o crafting; com diálogo terminal aberto fecha; com crafting aberto fecha |
| J / I / M | alterna diário de quests / inventário / mapa grande |
| Cima, Baixo, Enter | navegação e confirmação do painel aberto (lista de quests, receitas, escolhas, cursor do inventário com as 4 setas) |
| 1-9 | escolhe a opção do diálogo |
| Del / Backspace | no diário: abandonar (2 toques em até 3 s) |
| Esc | fecha o painel aberto; no diálogo em curso envia `dialogue_close` |

Os paineis modais são **exclusivos** (abrir um fecha o outro). Enquanto algum estiver aberto `ClientUi.blocks_game_actions()` é verdadeiro e o `ClientMain` envia `actions = 0` (clique em botão não vira ataque); o movimento continua. Botões não pegam foco do teclado (evita Espaço = esquiva + clique no botão focado).

## Arquitetura (`scripts/ui/client/`)
| Arquivo | Papel |
|---|---|
| `client_ui.gd` (`ClientUi`, CanvasLayer 10) | cola: `bind(session)`, `on_event(kind,data)`, `update_frame(delta, camera_yaw)`, `handle_input(ev)`; liga sinais da sessão aos painéis e os pedidos dos painéis à sessão |
| `ui_panel.gd` | base dos modais (título, status, dica, `handle_key`) |
| `dialogue_panel.gd` | fala, nome do NPC, escolhas (índice do servidor), nó terminal |
| `quest_panel.gd` | diário: prontas > ativas > disponíveis > concluídas; objetivos com progresso, recompensa, aceitar/entregar/abandonar |
| `inventory_panel.gd` + `client_inventory.gd` | grade de 25 slots + 3 slots de equipamento (sincronizada com o servidor desde o E5.6) |
| `craft_panel.gd` | receitas da estação (`data/recipes`), ingredientes, resultado, botão Fabricar, resultado de `craft_finished` |
| `party_panel.gd` | jogadores do snapshot com barra de vida |
| `boss_bar.gd` | barra do chefe/mini-chefe vivo (tier `boss`/`mini_boss` do `EnemyData`) com fase |
| `map_view.gd`, `map_panel.gd` | minimapa quadrado (janela de 36 m, girada pela câmera: cima = frente da câmera) e mapa grande (zona inteira, norte = -Z) |
| `toast_stack.gd`, `screen_fade.gd` | avisos empilhados (máx. 5, repetidos só renovam o tempo) e fade preto de zona/overlay de morte |
| `interact_target.gd` | NPC/estação mais próximo (mesmos dados do servidor, só para o prompt) |
| `ui_text.gd`, `ui_style.gd` | textos pt-BR sem acento (padrão do projeto), nomes de itens/NPCs/zonas, tradução de códigos de erro; cores/tema |

### Integração com `ClientMain`
Mudanças mínimas em `scripts/client/client_main.gd`: (1) `_build_presentation` cria o `ClientUi` (só no caminho **não-bot**); (2) `_new_session` chama `_ui.bind(ss)` (login cria sessão nova); (3) eventos drenados vão também para `_ui.on_event`; (4) `_ui.update_frame` por frame; (5) `world.notice` (chefe, respawn, entrou/saiu) vira toast, com o texto do HUD como fallback; (6) ações de combate zeradas com painel aberto; (7) `local_name` para o grupo. `ClientHud` continua igual (texto de rede + zona). Bots/headless nunca criam a UI (teste `_test_bot_safety` confere que `ClientUi.new()` só existe em `_build_presentation` e que o fluxo de bot não chama a apresentação).

## Feedback (toasts, fade, morte)
- `pickup` coletado: `+ 3x Sucata` (loot); `craft_finished`: fabricado/erro traduzido.
- Quests (sinais do `ClientQuestLog`): aceita, progresso `(v/r)`, pronta, concluída (XP + itens), abandonada, erro (`too_far`, `wrong_npc`, `inventory_full`, ...).
- Zona: `zone(phase 0)` do jogador local escurece em 0,25 s; `zone(phase 1)` clareia em 0,4 s e avisa o nome. Trava de segurança: preto por mais de 3 s sem chegada clareia sozinho; `respawn` também clareia (morrer durante a transição cancela o fade).
- Morte: evento `death` do jogador local mostra overlay "Voce morreu. Reaparecendo..." e toast; `respawn` (ou hp > 0 no snapshot) remove.
- Barra do chefe: aparece quando há inimigo de tier chefe vivo no snapshot (inclui o interesse de 50 m do servidor); mostra nome, vida e fase (`phase` replicado).
- Vida do jogador local: barra no canto inferior esquerdo.

## Lacunas conhecidas (importante)
1. **RESOLVIDA no E5.6**: o servidor envia o inventário/equipamento completo por `s_inventory` (welcome + após mudanças; ver `shared/contracts/network_protocol.md`). `ClientUi` aplica `ClientInventory.apply_full`; o aviso de estimativa só aparece até a primeira sincronização ("aguardando o inventário do servidor"). Continuam sem existir comandos de equipar/usar/vender item (fora do escopo do protocolo v2).
2. O crafting não sabe se o jogador tem os ingredientes: o botão sempre fica ativo e o servidor responde `insufficient_ingredients` (mostrado em texto).
3. Grupo: o snapshot só traz jogadores da **mesma zona**; quem está em outra zona não aparece. Nomes vêm de `player_joined` (que o servidor só envia para jogadores já presentes no join/depois); sem nome, aparece "Jogador <id>".
4. Diálogo terminal: o servidor não manda `DIALOGUE_END` ao fim de um nó terminal; o painel fecha localmente (Enter/F/clique) sem enviar `close`. Fechar no meio de uma conversa envia `dialogue_close`.
5. O minimapa usa o yaw da câmera (`IsoCamera.get_yaw()`), a mesma base do movimento; a orientação é testada por cálculo (frente da câmera -> cima) mas **não vista** num cliente gráfico.
6. `interact` usa o raio dos dados (NPC `interact_radius`, estação `radius`); o servidor é quem valida (`too_far`).
7. Textos de itens/quests/NPCs vêm dos dados atuais (`name`/`title`, ainda sem tradução por `*_key`); os `[PLACEHOLDER]` dos nomes são omitidos na tela.

## Testes (`tests/e5_ui/`, headless, sem GPU)
- `test_ui_panels.gd`: ações de input e colisão de teclas, textos/erros, `ClientInventory`, diálogo (navegação, índices do servidor, terminal, malformados, limites), diário (agrupamento, estados vazios, aceitar/entregar/abandonar com confirmação e cooldown), inventário (grade, cursor, aviso de lacuna, completo), crafting (estado vazio, pedido, erro/sucesso, timeout), grupo, chefe, toasts, fade (inclui trava), alvo de interação, mapa (projeção, filtro por janela, mapa grande).
- `test_ui_client.gd`: `ClientUi` + `ClientSession` falsa com comandos capturados: teclas J/I/M/F/Esc, fluxo de diálogo completo, fluxo de quests por sinais, crafting até `craft_finished`, eventos (loot, zona/fade, morte/respawn, nomes), quadro de HUD (vida, grupo, chefe, minimapa), religação de sessão, segurança do modo bot e passadas de frames com render dummy.

## Verificação visual humana necessária (cliente gráfico)
Layout em 1280x720 e 1920x1080 (sobreposição entre HUD de texto, grupo, minimapa, barra do chefe e toasts), legibilidade do tema/fonte padrão, orientação do minimapa com a câmera isométrica, fade da troca de zona (0,6 s de transição no servidor), foco/mouse nos botões, tamanho dos paineis em janelas pequenas e a sensação das teclas F/J/I/M.
