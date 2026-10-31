# Protocolo de rede — Eldervale (E3)

**PROTOCOL_VERSION = 1** · Estado: rascunho do E3, **pendente de revisão humana** (AGENTS/roadmap).
Transporte: `ENetMultiplayerPeer` (UDP), servidor = peer 1, porta padrão 24680, até 4 clientes (config). Godot RPC de alto nível.
Autoridade: o servidor decide movimento, combate, IA, dano, morte, XP e drops. O cliente envia **apenas input**; nunca posição, dano, cooldown, alvo ou recompensa.
Fora do E3: autenticação/credenciais (E4 adiciona ticket de sessão), persistência, quests. Nunca enviar senha por RPC.

## RPCs
| Nome | Dir | Modo | Payload | Frequência máx. | Validação no receptor |
|---|---|---|---|---|---|
| `c_hello` | C→S | reliable | `version:int, build:String, name:String` | 1/s, uma aceitação por conexão | versão == PROTOCOL_VERSION; build ≤ 32 chars; name 1..24 chars `[A-Za-z0-9 _-]` |
| `s_welcome` | S→C | reliable | `player_id:int, tick_rate:int, session_seed:int` | 1 por conexão | cliente ignora se não pediu hello |
| `s_reject` | S→C | reliable | `code:int, message:String` | 1 | após enviar, servidor desconecta o peer |
| `c_input` | C→S | unreliable_ordered | `seq:int, move:Vector2, yaw:float, actions:int, client_tick:int` | ≤ 60/s | só após welcome; `seq` > último aceito (senão descarta); `move` finito, `length() ≤ 1.001` (clamp); `yaw` finito em [-π, π] (normaliza); `actions` ⊂ máscara válida |
| `s_snapshot` | S→C | unreliable_ordered | `server_tick:int, last_input_seq:int, entities:Array[Dictionary]` | tick_rate/2..tick_rate por s | cliente descarta `server_tick` ≤ último |
| `s_event` | S→C | reliable | `event_id:int, kind:int, data:Dictionary` | por evento | `event_id` crescente; cliente ignora ids já vistos |
| `c_ping` / `s_pong` | C→S / S→C | unreliable | `client_time_ms:int` | ≤ 2/s | eco do valor para RTT |

`actions` (bitmask): `1=attack, 2=skill_1, 4=skill_2, 8=dodge`. Bits desconhecidos → input rejeitado.
Entidade no snapshot: `{id:int, kind:int (1=player, 2=enemy), pos:Vector3, yaw:float, hp:float, max_hp:float, state:int, type:String}`.
Eventos (`kind`): 1 player_joined, 2 player_left, 3 damage `{source_id, target_id, amount, crit}`, 4 death `{id}`, 5 enemy_spawn, 6 drop `{pos, item_id, qty}` (informativo no E3).
Códigos de rejeição: 1 versão incompatível, 2 payload inválido, 3 servidor cheio, 4 rate limit, 5 não autenticado/ordem inválida.

## Regras
- Toda mensagem passa por validação de tipo, tamanho e intervalo; inválida → descartar + contador; reincidência (limite configurável) → `s_reject(4)` e desconectar.
- Rate limit por peer (token bucket). Peer sem hello válido em N s é desconectado.
- Servidor nunca confia em IDs do cliente; referências são sempre resolvidas dentro da sessão.
- Eventos cosméticos (flash, número de dano) são derivados de `s_event`, nunca decididos pelo cliente.
- Cliente: interpolação das entidades remotas com buffer de ~100 ms; predição local só do próprio movimento com reconciliação por `last_input_seq`.
- Tick rate inicial 30 Hz de simulação, snapshots a 15–30 Hz; **valores a medir** (CPU/banda) antes de fixar.
- Simulação de latência/perda é feita na camada de aplicação (`NetSim`); não substitui teste em rede real.

## Configuração (fora do código)
Argumentos após `--`: `--port N --max-players N --tick-rate N --snapshot-rate N --sim-latency-ms N --sim-jitter-ms N --sim-loss-pct N`; cliente: `--host H --name X --bot <script> --out <arquivo.json>`. Variáveis de ambiente `ELDERVALE_*` equivalentes. Sem segredos em argumentos.

## API de código compartilhada (`scripts/net/`)
- `Protocol` (consts: `VERSION`, `DEFAULT_PORT`, `MAX_NAME_LEN`, `ACTION_*`, `REJECT_*`, `EVENT_*`, `KIND_*`; `static validate_hello(version, build, name) -> Dictionary{ok, code, message, name}`; `static validate_input(seq, move, yaw, actions, last_seq) -> Dictionary{ok, code, move, yaw}`; `static validate_entity_dict(d) -> bool`).
- `RateLimiter` (`new(rate_per_sec, burst)`, `allow(now_msec) -> bool`; um por peer e por tipo de mensagem).
- `NetSim` (`configure(latency_ms, jitter_ms, loss_pct, seed)`, `submit(callable, reliable: bool, now_msec)`, `pump(now_msec)`; reliable nunca perde, só atrasa).
- `NetConfig` (`static parse(args: PackedStringArray) -> NetConfig` com campos tipados e defaults seguros).

## NetRpc (sinais e senders)
`scripts/net/net_rpc.gd` (`class_name NetRpc extends Node`) é o ÚNICO nó com `@rpc`; servidor e cliente usam o mesmo script e o nó se chama `NetRpc`, filho da raiz (`NetRpc.install(tree)`, idempotente; `NetRpc.get_instance(tree)`). Os `@rpc` só validam remetente (c_* só no servidor; s_* só do peer 1) e tipos básicos, e emitem sinais. Sem lógica de jogo.

RPCs (parâmetros `Variant` no fio; canal 1 nos `unreliable_ordered`):
- `c_hello` any_peer/call_remote/reliable · `c_input` any_peer/call_remote/unreliable_ordered · `c_ping` any_peer/call_remote/unreliable
- `s_welcome` authority/call_remote/reliable · `s_reject` reliable · `s_snapshot` unreliable_ordered · `s_event` reliable · `s_pong` unreliable

Sinais: `hello_received(peer_id:int, version:int, build:String, player_name:String)`, `input_received(peer_id:int, seq:int, move:Vector2, yaw:float, actions:int, client_tick:int)`, `ping_received(peer_id:int, client_time_ms:int)`, `welcome_received(player_id:int, tick_rate:int, session_seed:int)`, `reject_received(code:int, message:String)`, `snapshot_received(server_tick:int, last_input_seq:int, entities:Array)`, `event_received(event_id:int, kind:int, data:Dictionary)`, `pong_received(client_time_ms:int)`.

Senders (sem `@rpc`; passam por `sim: NetSim` se definido; ignorados sem conexão): cliente `send_hello(version, build, player_name)`, `send_input(seq, move, yaw, actions, client_tick)`, `send_ping(client_time_ms)`; servidor `send_welcome(peer, player_id, tick_rate, session_seed)`, `send_reject(peer, code, message)`, `send_snapshot(peer, server_tick, last_seq, entities)`, `send_event(peer, event_id, kind, data)`, `send_pong(peer, client_time_ms)`.

Esclarecimentos: os sinais NÃO aplicam `Protocol.validate_*` (o servidor deve chamar `validate_hello/validate_input`; o cliente `validate_entity_dict` por entidade). Nomes das constantes de rejeição: `REJECT_VERSION=1, REJECT_INVALID_PAYLOAD=2, REJECT_SERVER_FULL=3, REJECT_RATE_LIMIT=4, REJECT_NOT_AUTHENTICATED=5`; eventos `EVENT_PLAYER_JOINED..EVENT_DROP` (1..6); `KIND_PLAYER=1, KIND_ENEMY=2`. `validate_input` devolve `stale=true` para `seq <= last_seq` (descartar sem contar abuso). `NetConfig.parse(args, env={})` aceita também `--k=v`; `NetConfig.from_environment()` lê `OS.get_cmdline_user_args()` + env; campo `errors`.

## Esclarecimentos de integração (E3)
- `c_input.yaw` é o **yaw da câmera** (WASD é relativo à câmera); o servidor calcula a direção com `PlayerMotion.world_direction(move, yaw)`. O facing do personagem é derivado do movimento no servidor.
- Entregas atrasadas pelo `NetSim` para um peer já desconectado são descartadas sem erro.
