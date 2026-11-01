# E5 — Gate de fechamento (E5.6)

Estado: validação **automatizada** concluída; **playtest humano pendente** (ver seção 6). Legenda: **OK** = coberto por teste/execução citada; **parcial** = coberto só em parte (limite explicado); **não verificado** = não exercitado.

Tudo abaixo vem de execuções reais nesta VM (Linux, 2 núcleos, Godot 4.7.2 headless, backend Node com PGlite em memória). Nada foi inferido.

## 1. O que o E5.6 acrescentou
- **Inventário sincronizado** (mensagem aditiva `s_inventory`, protocolo `VERSION` 2 intacto). Contrato em `shared/contracts/network_protocol.md` (seção E5.6). Servidor: `ServerSession.sync_inventories/send_inventory`, payload em `CharacterCodec.inventory_payload`, validador `Protocol.validate_inventory_update`. Cliente: `ClientSession.on_inventory_update` → `ClientUi` → `ClientInventory.apply_full` (o aviso de "estimativa" some).
- **Reentrega idempotente de recompensas** (`BackendSync`): se o backend não responde (timeout/5xx/429, depois das 3 tentativas do `BackendClient`), a recompensa fica na frente da fila do personagem e é reenviada a cada 3 s (até 20 vezes) **com a mesma chave idempotente**. Antes, uma recompensa perdida numa queda do backend ficava só em memória e era perdida de vez. Log: `[sync] recompensa <chave> sem resposta do backend (...); reentrega n/20`.
- **Correção de erro de motor no servidor** (`NetRpc._deliver`): vários clientes saindo ao mesmo tempo geravam `ERROR: Unable to send packet on channel 0, max channels: 0` (envio a peer que o ENet já fechara, mas cujo sinal de desconexão ainda não fora processado). Agora o envio é descartado se o peer ENet não está `STATE_CONNECTED`.
- **Bot de aventura** (`scripts/client/adventure_bot.gd`, bots `adv_*` em `bot_script.gd`) e **harness** `tools/e5_adventure_integration.py` (backend real + servidor `--world greenwood` + bots autenticados).
- **Knobs só de teste** (`ServerSettings`/`server_main.gd`; só valem com a variável de ambiente `ELDERVALE_TEST_MODE=1`, o servidor imprime `MODO DE TESTE`): `--test-hp-mult` (vida dos inimigos), `--test-speed-mult` (velocidade dos jogadores) e `--measure-snapshots` (imprime `[server] snapshots: {json}`). Existem porque a cadeia completa (4 jogadores + chefe) não cabe em 180 s por chamada com a vida/velocidade de produção. **Nunca usar em produção**; o balanceamento real não é validado por esses cenários.

## 2. Critérios de aceite do roadmap (E5)
| Critério | Status | Evidência |
|---|---|---|
| Grupo conclui uma pequena sequência de aventura | **OK** (headless) | `party`: 4 jogadores autenticados, aceitam `gw_ruin_guardian`, hub→selvagem→ruínas, puzzle, chefe, loot (123 s). `adventure`: 1 jogador, 3 quests (`gw_welcome`, `gw_scrap_for_orla`, `gw_clear_clearing`) com diálogo, abate, loot, crafting e entrega (66 s). `ruins`: cadeia completa até `gw_ruins_expedition` com mini-chefe, puzzle, chefe, volta ao hub e entrega (108 s). Percepção de "pequena aventura" jogável: **não verificado** (playtest). |
| Quests persistem por personagem | **OK** | Em todos os cenários: `GET` do personagem no backend real após a sessão (`active`/`completed`/progresso). `party`: cada um dos 4 personagens tem a quest no **próprio** registro; só o matador tem `kill_guardian=1`. `server_crash`: estado após o crash = último checkpoint. |
| Loot individual correto | **OK** | `party`: cada jogador recebe os **próprios** pickups; os itens que o cliente viu coletar batem com o que o backend persistiu; quem não causou dano mínimo não recebe XP nem loot do chefe (consistência verificada). Unit: `tests/e5_loot` (104 + 68 checks). |
| Boss funciona com 1–4 jogadores | **OK** (lógica/integração); **parcial** (sensação) | 1 jogador: `ruins`. 4 jogadores: `party` (todos veem o chefe ativo e derrotado; XP de participação para todos os que causaram dano). 2 e 3 jogadores: só testes unitários (`test_e5_server_boss`, escala 1–4). Vida do chefe reduzida (x0,15) e jogadores mais rápidos (x1,7) nos cenários de integração: a duração/dificuldade real da luta **não** foi exercitada. |
| Dificuldade escala de forma controlada | **parcial** | Testes unitários da escala por jogadores da zona (`tests/e5/test_e5_scaling_threat.gd`, `test_e5_server_boss.gd`). Equilíbrio real: **não verificado** (playtest). |
| Nenhuma recompensa duas vezes por replay | **OK** | `adventure`/`server_crash`/`outage`: reentrega da mesma quest recusada (`already_completed`), XP idêntico antes/depois. `outage`: recompensa reentregue com a mesma chave, aplicada **exatamente uma vez** (xp=60; itens x1). Reuso de chave com corpo diferente → 400/409 e XP intacto. Backend: `quests.test.ts`, `crafting.test.ts`, `security_review.test.ts`. Cenários e4 `replay` e `double` OK. |
| Região concluível sem softlock conhecido | **OK** (sem softlock encontrado) | Cadeia completa incluindo puzzle (portão permanece aberto), morte/respawn (o bot do `party` morreu em execuções e continuou), reconexão. Ausência de softlock em uso real: **não verificado** (só execuções com bots). |

### Itens de tarefa do roadmap (E5)
Hub, selvagem, ruínas, puzzle, 10 tipos de inimigos, mini-chefe e chefe, NPCs/diálogo, 5 quests, recompensas server-side, loot individual, crafting, mapa/minimapa, UI mínima (inventário/party/quests), sessão com 4 jogadores, troca de região e falha de conexão: **implementados e exercitados por testes headless** (E5.1–E5.5 e este módulo). O aspecto visual é blockout (sem arte final) e **não foi visto em cliente gráfico**.

## 3. Cenários de falha (todos com backend real e servidor Godot real)
| Cenário | Resultado | Evidência |
|---|---|---|
| Queda do cliente no meio da transição de zona + reconexão com o mesmo personagem | **OK** | `zone_drop` (92 s): o cliente A cai ao iniciar a transição; o personagem reconecta com **novo ticket** dentro da janela de reconexão; volta ao hub (posição não persiste); inventário sincronizado de novo; uma **terceira** conexão simultânea do mesmo personagem é recusada (`character_already_connected`); sem `ERROR` no servidor. |
| Queda (SIGKILL) do servidor Godot | **OK** | `server_crash` (96 s): o estado após o crash = **último checkpoint** (aceite imediato e recompensa persistidos; progresso posterior ao último checkpoint é perdido por desenho, ver riscos); novo servidor registra **nova** sessão; reconexão com novo ticket; nova entrega da mesma quest recusada; sem recompensa duplicada. |
| Backend indisponível durante uma recompensa | **OK** | `outage` (154 s): backend congelado (SIGSTOP no grupo de processos) por 32 s enquanto o bot entrega a quest; o servidor mantém o jogo, loga `reentrega 1/20`, o backend volta e a recompensa é aplicada **uma vez**; o cliente continua conectado e com inventário sincronizado. |
| Ticket reaproveitado/adulterado, duplo login, replay | **OK** | Cenários e4 reexecutados: `happy`, `replay`, `double`, `crash`, `badticket`. (`badticket` falhou **uma vez** quando a VM estava sob carga — o login do bot estourou o timeout de 15 s com `network_error` — e passou nas execuções seguintes; ver risco de flakiness.) |
| Segredos em logs | **OK** | Todos os cenários varrem logs e JSONs procurando senha, tokens, segredos internos e tickets (nenhum encontrado); segredos são aleatórios por execução e passados só por ambiente. |
| `ERROR` nos logs do servidor | **OK** | Todos os cenários checam; o único achado real (envio a peer já fechado) foi corrigido (seção 1). |

## 4. Snapshots e MTU (medido)
`--measure-snapshots` mede o tamanho aproximado da codificação Variant dos 3 argumentos de `s_snapshot` (sem cabeçalhos de RPC/ENet) a cada envio. MTU de payload considerado: 1392 B.

| Situação | Máx. entidades | Máx. bytes | Amostras acima do MTU |
|---|---|---|---|
| `party` (4 jogadores, luta de chefe) | 21 | **4912** | 2091 de 3600 (~58%) |
| `ruins` (1 jogador, antecâmara/salão/chefe) | 18 | **4456** | 806 de 1000 (~81%) |

Conclusão: **os snapshots dessas zonas excedem o MTU com frequência**, mesmo com 1 jogador (cada entidade ocupa ~230–250 B porque é um `Dictionary` com chaves string). O ENet fragmenta pacotes `unreliable` maiores que o MTU e **a perda de qualquer fragmento descarta o snapshot inteiro**. Em localhost não há perda (nenhum cenário falhou), mas na Internet o efeito seria maior perda efetiva de snapshots (a interpolação do cliente tolera lacunas curtas; não medido).

**Correção simples não aplicada**: omitir `phase`/`atk` padrão economiza só ~20 B por inimigo (insuficiente) e o `BossBar` usa a presença de `phase`. Reduzir o AOI não ajuda na arena do chefe. A solução real é estrutural e mexe no contrato: **codificação compacta de entidade** (arrays posicionais/quantização) ou **snapshot particionado** (várias mensagens por tick com mescla no cliente). Fica como **risco alto #1** para decisão antes do E6. O código de medição continua no repositório (`--measure-snapshots`) para validar a correção.

## 5. Riscos conhecidos (E5.1–E5.6)
Alto
1. **Snapshot acima do MTU** na luta de chefe e nas ruínas (seção 4).
2. **Cenários de integração dependem de knobs de teste** (vida/velocidade) e de VM de 2 núcleos: o equilíbrio e a duração reais da luta/cadeia não foram exercitados.

Médio
3. **Posição não persistida**: ao entrar (ou reconectar) o jogador nasce no hub; HP/recurso/cooldowns também não persistem.
4. **Craft otimista**: o craft é aplicado na memória antes do backend; um craft em voo que o banco recusa e uma desconexão logo depois podem persistir um estado otimista (janela pequena; E5.4).
5. **Progresso por abate só persiste no autosave** (30 s; o aceite e a entrega persistem na hora): um crash do servidor perde até esse intervalo (o `server_crash` confirma que só o último checkpoint sobrevive).
6. **Perda de loot**: pickups não persistem; somem por TTL, quando o dono desconecta ou num wipe/reinício do encontro. Inventário cheio no backend na entrega de quest: memória e banco divergem até a próxima carga (E5.1).
7. **Reentrega limitada**: 20 tentativas × 3 s (cerca de 1 min além das 3 tentativas do cliente HTTP); depois disso a recompensa fica só em memória (log `falhou de forma permanente`). Um servidor que cai **durante** uma reentrega perde a recompensa pendente (o jogador pode repetir a entrega, pois a quest continua ativa no banco).
8. **Flakiness do ambiente**: com 4 clientes Godot + servidor + API na VM de 2 núcleos, o login scrypt pode estourar o timeout de 15 s do cliente (`network_error`). O harness do `party` entra com bots um a um e repete a entrada; os cenários e4 podem falhar esporadicamente por isso (reexecutar).
9. **Compatibilidade do `s_inventory`** com clientes de build anterior não verificada (atualizar servidor e cliente juntos).

Baixo
10. Concorrência do backend testada só em PGlite (não PostgreSQL real); TLS/proxy reais, SIGTERM e rede com perda não testados.
11. Itens fabricados não contam para objetivos `collect`; crédito de abate só do matador; sem comandos de equipar/usar/vender item; o crafting não sabe se há ingredientes (botão sempre ativo); diálogo terminal não manda `DIALOGUE_END`.
12. `--world greenwood` ainda não é o padrão do servidor (padrão = arena de teste).
13. O cenário `party` não inclui o passo "matar `ranged_caster`" da quest do guardião (o `ruins` cobre `ranged_caster`); o `party` verifica XP, loot, abate e persistência por personagem, não a conclusão da quest `gw_ruin_guardian`.

## 6. Depende de playtest humano
- Sensação do ritmo de combate no teclado, legibilidade de telégrafos/indicadores e do inimigo "enterrado", câmera isométrica nas ruínas, escala das zonas.
- Duração e dificuldade reais do chefe com 1–4 jogadores (sem knobs), balanceamento de XP/loot/receitas.
- UI: usabilidade do inventário (25 slots), diário, diálogo, mapa/minimapa, fade de zona, HUD de grupo; clareza do aviso "aguardando o inventário do servidor".
- Qualidade da conexão real (latência, perda) com a fragmentação dos snapshots; reconexão numa rede de verdade.
- Ausência de softlock fora do caminho previsto pelos bots (ex.: comportamentos inesperados de grupo).

## 7. Como reproduzir
```
export npm_config_cache=$PWD/.tools/npm-cache
python3 tools/e5_adventure_integration.py <adventure|ruins|party|zone_drop|server_crash|outage>   # um por vez, ~60-160 s cada
python3 tools/e4_integration.py <happy|replay|double|crash|badticket>
godot --headless --path . --script res://tests/run_tests.gd        # suíte Godot completa
cd backend && npx vitest run test/<arquivo>.test.ts                 # um arquivo por vez
```
Nota: `--only=<trecho>` filtra a suíte Godot, mas `tests/e3/test_net_rpc.gd` precisa de frames do SceneTree: com `--only=tests/e3` (primeiro teste do processo) o loopback falha por artefato do filtro; na suíte completa passa.

## 8. Resultados da execução final
- Suíte Godot completa: **2363 passaram, 0 falharam** (inclui `tests/e5_gate/test_inventory_sync.gd`, 59 checks: validador, superfície do `NetRpc`, join, coalescência, privacidade, craft/undo, recompensa de quest, payload limitado, `ClientSession`, `ClientUi`, reentrega).
- Backend (vitest, por arquivo): auth 23, characters 68, constraints 9, crafting 21, http 10, migrate 5, misc 9, parties 9, quests 20, security_review 17, sessions 24 — **215 passaram, 0 falharam** (o backend não foi alterado no E5.6).
- Integração: `adventure`, `ruins`, `party`, `zone_drop`, `server_crash`, `outage` OK; e4 `happy`, `replay`, `double`, `crash`, `badticket` OK; `tools/e5_world_integration.py 1bot` OK.
