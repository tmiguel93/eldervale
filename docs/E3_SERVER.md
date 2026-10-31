# E3 — Servidor dedicado headless (agente S)

Contrato de rede: `shared/contracts/network_protocol.md` (versao 1). O servidor e a autoridade: o cliente so envia input.

## Como rodar
```
godot --headless --path . res://scenes/server/server_boot.tscn -- --port 24680 --max-players 4 \
      --tick-rate 30 --snapshot-rate 15 [--sim-latency-ms N --sim-jitter-ms N --sim-loss-pct P] \
      [--max-seconds N] [--max-invalid N] [--hello-timeout S]
```
- Args apos `--` e variaveis `ELDERVALE_*` (NetConfig); args vencem o ambiente. Extras so do servidor: `--max-seconds` (0 = sem limite), `--max-invalid` (padrao 30 invalidos por janela de 10 s), `--hello-timeout` (padrao 5 s).
- Encerramento limpo: `--max-seconds`, `--quit-after` (engine) ou fechar a janela/`SceneTree.quit`. **SIGTERM nao e interceptavel em GDScript** (Godot sai com 143 sem rodar o shutdown; os clientes caem por timeout do ENet). Para parada controlada use `--max-seconds`.
- Logs: `[server] ...` em stdout (peer id, nome validado, codigos). Sem tokens, e-mails ou payloads.

## Arquitetura (`scripts/server/`)
| Arquivo | Papel |
|---|---|
| `server_main.gd` / `scenes/server/server_boot.tscn` | config, ENet (`max_players` + 4 vagas de folga para poder responder `reject(3)`), `NetRpc.install`, NetSim opcional, liga sinais do NetRpc e do multiplayer a sessao |
| `server_session.gd` | ciclo do peer (hello/welcome/reject), validacao + rate limit, snapshots, replicacao de eventos. Nao conhece ENet |
| `server_world.gd` | mundo autoritativo: `ArenaGeometry` sem malhas, inimigos E2, jogadores (`player.tscn` com `use_external_input`), eventos |
| `server_transport.gd` / `net_rpc_transport.gd` | saida (base no-op; real = NetRpc, que aplica o NetSim) |
| `server_settings.gd` | parametros (rates, limites, spawn) |
| `scripts/arena/arena_geometry.gd` | geometria compartilhada com a arena local (`TestArena` a usa com malhas) |

## Fluxo
- **Hello**: `Protocol.validate_hello` -> versao errada `reject(1)`, payload `reject(2)`, cheio `reject(3)`, hello repetido ou input antes do welcome `reject(5)`, sem hello em N s `reject(5)`. Todo reject e seguido de desconexao (apos o reject chegar). Mensagens de peer ja rejeitado sao ignoradas.
- **Input**: token bucket por peer e tipo (input 75/s, burst 120; ping 4/s; hello 1/s) -> `Protocol.validate_input` (seq crescente; seq repetido/antigo e descartado sem contar como abuso) -> guarda move/yaw e latcheia as acoes ate o proximo tick. Descartes por tipo/range/bits/rate contam em janela de 10 s; acima de `max_invalid` -> `reject(4)` + disconnect.
- **Simulacao**: tick = tick de fisica do Godot (`Engine.physics_ticks_per_second = tick_rate`). Ordem: `ServerWorld.apply_inputs` (prio -20: velocidade/cooldown/custo do servidor via `PlayerCombat.try_use`, prioridade dodge > attack > skill_1 > skill_2, e alvo de cada inimigo = jogador vivo mais proximo) -> `PlayerCombat` (-10) -> Player/Enemy (0) -> `ServerSession.step_tick` (20: contador, timeouts, snapshots a cada `tick_rate/snapshot_rate` ticks).
- **Snapshot**: por peer, mesmas entidades (jogadores + inimigos, formato do contrato) e o `last_input_seq` do peer. **Eventos** reliable com `event_id` crescente global: player_joined/left, damage, death, enemy_spawn, drop. Quem entra recebe `player_joined` dos presentes e `enemy_spawn` dos inimigos vivos.
- Dano, morte unica, XP e drops decididos no servidor; drops saem so como evento informativo (`Enemy.spawn_pickups = false`, sem inventario/persistencia).

## Testes
`tests/e3/test_server_session.gd` (handlers diretos + transporte gravador, relogio injetado) e `tests/e3/test_server_world.gd` (fisica real headless). Helper: `tests/e3/server_helpers.gd`. Sem rede real. O mundo depende de timing (frames de fisica com limites generosos).

## Limites conhecidos
- Jogador morto nao renasce (sem respawn neste marco); reconectar cria outro jogador.
- Sem interest management/deltas: snapshot completo a todos (4 jogadores, ~9 entidades). Taxas 30/15 Hz ainda nao medidas em CPU/banda.
- Inimigos sem respawn; sem persistencia/inventario/quests; sem autenticacao (E4).
- Fisica a 30 Hz difere dos 60 Hz da arena local (passo de degrau/rampa nao calibrado a 30 Hz).
- Inimigos ficam parados enquanto nao ha jogadores (nao processam, nao voltam a origem).
- Nao verificado: 2+ clientes reais, NetSim em rede real, carga, comportamento do ENet com reject seguido de disconnect sob perda.
