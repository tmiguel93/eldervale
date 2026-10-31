# E3 — Cliente e bots (agente C)

## Arquivos
`scenes/client/client_boot.tscn` + `scripts/client/`: `client_main` (conexao ENet, NetRpc, loop), `client_session` (maquina de estados/hello/reject/eventos/ping, sem rede), `snapshot_interpolator`, `prediction`, `local_input`, `client_world` (apresentacao), `client_hud`, `bot_script`, `bot_result`. Testes: `tests/e3/test_client_*.gd`.

## Como rodar
Cliente (com display): `godot --path . res://scenes/client/client_boot.tscn -- --host 127.0.0.1 --port 24680 --name Fulano` (WASD, mouse1 ataque, Q/E skills, Espaco esquiva; HUD de rede no canto).
Bot headless: `godot --headless --path . res://scenes/client/client_boot.tscn -- --host 127.0.0.1 --port 24680 --bot walk_square --bot-seconds 10 --out .tools/scratch/bot1.json`.
Bots: `idle`, `walk_square`, `attack_loop`, `cheat_speed`, `invalid_flood`, `bad_version`. Extras de latencia: `--sim-latency-ms/--sim-jitter-ms/--sim-loss-pct` (NetSim).
Saida: 0 ok; 1 erro de escrita do JSON; 2 bot desconhecido; 3 nao conectou em 10 s. JSON: connected, welcome, rejected, disconnected, snapshots_received, last_server_tick, max_snapshot_gap_ms, positions (amostra 0,5 s, posicao autoritativa), entities_seen, events_by_kind, rtt_avg_ms, inputs_sent, errors. `bad_version` encerra 0,5 s apos o reject.

## Arquitetura
- Cliente so envia input (`c_input` a 30 Hz, seq crescente a partir de 1, `client_tick` crescente) e `c_ping` a 2 Hz. Nao simula combate, IA, dano nem loot; numero de dano, flash e morte vem de `s_event` (reusa `DamageNumber` e `DeathEffect` do E2).
- `ClientSession.on_snapshot` valida cada entidade com `Protocol.validate_entity_dict`, descarta tick repetido/velho e eventos com id ja visto.
- Interpolador: atraso 100 ms (configuravel), relogio do servidor = `tick*1000/tick_rate`, offset estimado pela chegada (cai rapido, sobe devagar); extrapolacao limitada a 150 ms; entidade ausente do snapshot mais novo some quando o tempo de render o alcanca.
- Predicao: so o proprio movimento plano (`PlayerMotion.world_direction * 6 m/s * dt`). Reconciliacao: remove inputs com `seq <= last_input_seq`, replay dos pendentes sobre a posicao do servidor; erro < 5 cm ignorado, ate 2 m corrigido suavemente (taxa 10/s), acima disso teleporta. Y sempre do servidor.
- Convencao de yaw (ASSUMIDA, confirmar com o servidor): `move` = entrada local (x direita, y frente) e `yaw` = yaw da camera isometrica (45 deg), de modo que o servidor aplique `PlayerMotion.world_direction(move, yaw)`; normalizado a [-PI, PI]. O cliente nao usa o yaw do avatar no envio.

## Limites
- Render nunca verificado visualmente (so headless); mundo e malhas placeholder, sem arena do servidor, sem OcclusionFader.
- Predicao sem colisao/gravidade/degraus e sem replay fisico; dodge/skills com deslocamento nao previstos (corrigidos pela reconciliacao). Velocidade 6 m/s duplicada no cliente (`Prediction.BASE_SPEED`).
- `--bot-seconds` nao e conhecido pelo NetConfig (lido em `client_main`; o aviso do parser e suprimido).
- Sem reconexao. Conexao a porta sem servidor leva ~10 s ate o timeout no modo bot.
