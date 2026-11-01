# Protocolo de rede — Eldervale (E3)

**PROTOCOL_VERSION = 2** · Estado: rascunho do E3 + ticket do E4 (M5a), **pendente de revisão humana** (AGENTS/roadmap).
**v2 (E4):** `c_hello` ganhou o campo `ticket` (ticket de sessão emitido pelo backend em `POST /v1/sessions/:id/join-ticket`). Servidor v2 rejeita `version != 2` com `reject(1)`. Sem ticket o servidor só aceita em modo dev (sem `--backend-url`); com backend o ticket é OBRIGATÓRIO.
Transporte: `ENetMultiplayerPeer` (UDP), servidor = peer 1, porta padrão 24680, até 4 clientes (config). Godot RPC de alto nível.
Autoridade: o servidor decide movimento, combate, IA, dano, morte, XP e drops. O cliente envia **apenas input**; nunca posição, dano, cooldown, alvo ou recompensa.
Autenticação: o cliente só envia o **ticket de sessão** (uso único, 60 s) no `c_hello`; o servidor o resgata no backend (`docs/E4_GODOT_SERVER.md`). Persistência é decidida só pelo servidor. Nunca enviar senha por RPC; o ticket nunca é logado.

## RPCs
| Nome | Dir | Modo | Payload | Frequência máx. | Validação no receptor |
|---|---|---|---|---|---|
| `c_hello` | C→S | reliable | `version:int, build:String, name:String, ticket:String` | 1/s, uma aceitação por conexão | versão == PROTOCOL_VERSION (2); build ≤ 32 chars; name 1..24 chars `[A-Za-z0-9 _-]`; ticket ≤ 1024 chars `[A-Za-z0-9._-]` (vazio passa no validador; o servidor decide se exige) |
| `s_welcome` | S→C | reliable | `player_id:int, tick_rate:int, session_seed:int` | 1 por conexão | cliente ignora se não pediu hello |
| `s_reject` | S→C | reliable | `code:int, message:String` | 1 | após enviar, servidor desconecta o peer |
| `c_input` | C→S | unreliable_ordered | `seq:int, move:Vector2, yaw:float, actions:int, client_tick:int` | ≤ 60/s | só após welcome; `seq` > último aceito (senão descarta); `move` finito, `length() ≤ 1.001` (clamp); `yaw` finito em [-π, π] (normaliza); `actions` ⊂ máscara válida |
| `s_snapshot` | S→C | unreliable_ordered | `server_tick:int, last_input_seq:int, entities:Array[Dictionary]` | tick_rate/2..tick_rate por s | cliente descarta `server_tick` ≤ último |
| `s_event` | S→C | reliable | `event_id:int, kind:int, data:Dictionary` | por evento | `event_id` crescente; cliente ignora ids já vistos |
| `c_ping` / `s_pong` | C→S / S→C | unreliable | `client_time_ms:int` | ≤ 2/s | eco do valor para RTT |

`actions` (bitmask): `1=attack, 2=skill_1, 4=skill_2, 8=dodge`. Bits desconhecidos → input rejeitado.
Entidade no snapshot: `{id:int, kind:int (1=player, 2=enemy), pos:Vector3, yaw:float, hp:float, max_hp:float, state:int, type:String}`.
**E5.2 (aditivo, `VERSION` continua 2):** inimigos (`kind=2`) publicam também os campos OPCIONAIS `phase:int` (0..15; fase atual do chefe/mini-chefe, 0 nos demais) e `atk:String` (≤ 32 chars; id do ataque em telegrafo enquanto `state == 2` (ATTACK), `""` caso contrário — o cliente desenha o indicador de chão a partir do `EnemyAttack` do `type`). `Protocol.validate_entity_dict` aceita a ausência dos dois (clientes/servidores antigos) e rejeita tipo/faixa inválidos quando presentes; `state` de inimigo = `EnemyAI.State` (0 IDLE, 1 CHASE, 2 ATTACK, 3 RETURN, 4 DEAD). Clientes antigos ignoram os campos novos.
Eventos (`kind`): 1 player_joined, 2 player_left, 3 damage `{source_id, target_id, amount, crit}`, 4 death `{id}`, 5 enemy_spawn `{id, type, pos}` (também para adds invocados), 6 drop `{pos, item_id, qty}` (informativo no E3), **7 enemy_phase `{id, phase}`** (E5.2; chefe entrou na fase `phase` ≥ 1, enviado uma vez por fase; clientes que não conhecem o `kind` o ignoram). Adds dispensados (invocador morreu/encontro reiniciou) não geram `death`: somem do snapshot.
Códigos de rejeição: 1 versão incompatível, 2 payload inválido (inclui ticket malformado), 3 servidor cheio/ocupado (inclui limite de resgates pendentes), 4 rate limit, 5 não autenticado/ordem inválida (ticket ausente/inválido/expirado/já usado, personagem já conectado, falha ao carregar o personagem, backend indisponível; os detalhes NÃO são enviados ao cliente).
Em modo com backend o `s_welcome` só sai depois do resgate + carga do personagem (pode levar alguns segundos; o servidor desiste após `--redeem-timeout`, padrão 8 s, com `reject(5)`).

## Regras
- Toda mensagem passa por validação de tipo, tamanho e intervalo; inválida → descartar + contador; reincidência (limite configurável) → `s_reject(4)` e desconectar.
- Rate limit por peer (token bucket). Peer sem hello válido em N s é desconectado.
- Servidor nunca confia em IDs do cliente; referências são sempre resolvidas dentro da sessão.
- Eventos cosméticos (flash, número de dano) são derivados de `s_event`, nunca decididos pelo cliente.
- Cliente: interpolação das entidades remotas com buffer de ~100 ms; predição local só do próprio movimento com reconciliação por `last_input_seq`.
- Tick rate inicial 30 Hz de simulação, snapshots a 15–30 Hz; **valores a medir** (CPU/banda) antes de fixar.
- Simulação de latência/perda é feita na camada de aplicação (`NetSim`); não substitui teste em rede real.

## Configuração (fora do código)
Argumentos após `--` (servidor com backend: ver `docs/E4_GODOT_SERVER.md`): `--port N --max-players N --tick-rate N --snapshot-rate N --sim-latency-ms N --sim-jitter-ms N --sim-loss-pct N`; cliente: `--host H --name X --bot <script> --out <arquivo.json>` (o M5b define como o cliente recebe o ticket). Variáveis de ambiente `ELDERVALE_*` equivalentes. Sem segredos em argumentos.

## API de código compartilhada (`scripts/net/`)
- `Protocol` (consts: `VERSION`, `DEFAULT_PORT`, `MAX_NAME_LEN`, `ACTION_*`, `REJECT_*`, `EVENT_*`, `KIND_*`; `static validate_hello(version, build, name, ticket) -> Dictionary{ok, code, message, name, ticket}`; `static validate_ticket(ticket) -> bool`; `static validate_input(seq, move, yaw, actions, last_seq) -> Dictionary{ok, code, move, yaw}`; `static validate_entity_dict(d) -> bool`).
- `RateLimiter` (`new(rate_per_sec, burst)`, `allow(now_msec) -> bool`; um por peer e por tipo de mensagem).
- `NetSim` (`configure(latency_ms, jitter_ms, loss_pct, seed)`, `submit(callable, reliable: bool, now_msec)`, `pump(now_msec)`; reliable nunca perde, só atrasa).
- `NetConfig` (`static parse(args: PackedStringArray) -> NetConfig` com campos tipados e defaults seguros).

## NetRpc (sinais e senders)
`scripts/net/net_rpc.gd` (`class_name NetRpc extends Node`) é o ÚNICO nó com `@rpc`; servidor e cliente usam o mesmo script e o nó se chama `NetRpc`, filho da raiz (`NetRpc.install(tree)`, idempotente; `NetRpc.get_instance(tree)`). Os `@rpc` só validam remetente (c_* só no servidor; s_* só do peer 1) e tipos básicos, e emitem sinais. Sem lógica de jogo.

RPCs (parâmetros `Variant` no fio; canal 1 nos `unreliable_ordered`):
- `c_hello` any_peer/call_remote/reliable · `c_input` any_peer/call_remote/unreliable_ordered · `c_ping` any_peer/call_remote/unreliable
- `s_welcome` authority/call_remote/reliable · `s_reject` reliable · `s_snapshot` unreliable_ordered · `s_event` reliable · `s_pong` unreliable

Sinais: `hello_received(peer_id:int, version:int, build:String, player_name:String, ticket:String)`, `input_received(peer_id:int, seq:int, move:Vector2, yaw:float, actions:int, client_tick:int)`, `ping_received(peer_id:int, client_time_ms:int)`, `welcome_received(player_id:int, tick_rate:int, session_seed:int)`, `reject_received(code:int, message:String)`, `snapshot_received(server_tick:int, last_input_seq:int, entities:Array)`, `event_received(event_id:int, kind:int, data:Dictionary)`, `pong_received(client_time_ms:int)`.

Senders (sem `@rpc`; passam por `sim: NetSim` se definido; ignorados sem conexão): cliente `send_hello(version, build, player_name, ticket)`, `send_input(seq, move, yaw, actions, client_tick)`, `send_ping(client_time_ms)`; servidor `send_welcome(peer, player_id, tick_rate, session_seed)`, `send_reject(peer, code, message)`, `send_snapshot(peer, server_tick, last_seq, entities)`, `send_event(peer, event_id, kind, data)`, `send_pong(peer, client_time_ms)`.

Esclarecimentos: os sinais NÃO aplicam `Protocol.validate_*` (o servidor deve chamar `validate_hello/validate_input`; o cliente `validate_entity_dict` por entidade). Nomes das constantes de rejeição: `REJECT_VERSION=1, REJECT_INVALID_PAYLOAD=2, REJECT_SERVER_FULL=3, REJECT_RATE_LIMIT=4, REJECT_NOT_AUTHENTICATED=5`; eventos `EVENT_PLAYER_JOINED..EVENT_DROP` (1..6); `KIND_PLAYER=1, KIND_ENEMY=2`. `validate_input` devolve `stale=true` para `seq <= last_seq` (descartar sem contar abuso). `NetConfig.parse(args, env={})` aceita também `--k=v`; `NetConfig.from_environment()` lê `OS.get_cmdline_user_args()` + env; campo `errors`.

## Esclarecimentos de integração (E3)
- `c_input.yaw` é o **yaw da câmera** (WASD é relativo à câmera); o servidor calcula a direção com `PlayerMotion.world_direction(move, yaw)`. O facing do personagem é derivado do movimento no servidor.
- Entregas atrasadas pelo `NetSim` para um peer já desconectado são descartadas sem erro.

## Extensão E5.1 — Quests e diálogo (aditiva; `VERSION` continua 2)
Quatro RPCs novos, todos `reliable`. Clientes/servidores antigos simplesmente não os usam; nenhuma mensagem existente mudou. O progresso de quest **nunca** viaja do cliente: só avança por eventos do servidor (abate, item, área, fala). O cliente só envia *comandos* validados.

- `c_quest_cmd(req_id:int, op:int, quest_id:String)` any_peer — `op`: `QUEST_OP_ACCEPT=1`, `QUEST_OP_ABANDON=2`, `QUEST_OP_TURN_IN=3`. Entregar/aceitar exige o jogador perto do NPC da quest (validado no servidor com a posição autoritativa).
- `c_dialogue_cmd(req_id:int, op:int, npc_id:String, choice:int)` any_peer — `op`: `DIALOGUE_OP_OPEN=1` (exige `npc_id`, `choice=0`), `DIALOGUE_OP_CHOOSE=2` (`npc_id` vazio, `choice` 0..`MAX_DIALOGUE_CHOICE=15`), `DIALOGUE_OP_CLOSE=3` (`npc_id` vazio, `choice=0`).
- `s_quest(kind:int, data:Dictionary)` authority — `QUEST_SYNC=1 {quests:{active,completed}}`, `QUEST_ACCEPTED=2 {quest_id}`, `QUEST_PROGRESS=3 {quest_id, objective_id, value, required}`, `QUEST_READY=4 {quest_id}`, `QUEST_COMPLETED=5 {quest_id, xp, items}`, `QUEST_ABANDONED=6 {quest_id}`, `QUEST_ERROR=7 {req_id, op, quest_id, code}`.
- `s_dialogue(kind:int, data:Dictionary)` authority — `DIALOGUE_VIEW=1 {npc_id, dialogue_id, node_id, speaker, text, text_key, choices:[{index,text,text_key}], terminal}`, `DIALOGUE_END=2 {npc_id}`, `DIALOGUE_ERROR=3 {req_id, op, code}`.

Validação (`Protocol.validate_quest_cmd/validate_dialogue_cmd`): `req_id` inteiro 0..`MAX_REQ_ID`; `op` no intervalo; ids de conteúdo `[a-z][a-z0-9_]*` até `MAX_CONTENT_ID_LEN=48`; tipos exatos (Variant do fio). Payload inválido conta como abuso (`_count_invalid`) e acima do limite de abuso o peer é desconectado. Antes do `s_welcome` o comando é rejeitado com `REJECT_NOT_AUTHENTICATED`. Rate limit por peer: `quest_rate_per_sec=5`, `quest_burst=10` (`ServerSettings`), compartilhado por quest e diálogo; excedido => `REJECT_RATE_LIMIT`/abuso. Sinais em `NetRpc`: `quest_cmd_received`, `dialogue_cmd_received`, `quest_update_received`, `dialogue_received`; senders `send_quest_cmd`, `send_dialogue_cmd`, `send_quest_update`, `send_dialogue`.

Persistência: o estado de quests vai junto do checkpoint do personagem (`state.quests`); a recompensa usa `POST /internal/characters/:id/rewards` com `quest_id` e `idempotency_key = quest:<quest_id>:<character_id>` (ver `docs/E5_QUESTS.md` e `docs/E4_CHARACTERS.md`).

## Extensão E5.3 — Mundo em zonas (aditiva; `VERSION` continua 2)
Nenhum RPC novo e nenhuma mensagem existente mudou: o mundo usa 4 *kinds* novos em `s_event(event_id, kind, data)` (reliable). Clientes antigos ignoram kinds desconhecidos. Só o servidor decide zona, puzzle, chefe e respawn; o cliente apenas apresenta. Modo opt-in: `--world greenwood` (padrão continua a arena).

- `EVENT_ZONE=8 {id:int, zone:String, phase:int, pos:[x,y,z]}` — `ZONE_PHASE_LEAVING=0` (transição iniciada, jogador parado) e `ZONE_PHASE_ARRIVED=1` (teleportado; `pos` = chegada). Também enviado no join (zona inicial).
- `EVENT_PUZZLE=9 {zone, puzzle:String, plates:[bool] (1..MAX_PLATES=8), open:bool, state:int}` — `PUZZLE_IDLE=0, PUZZLE_PARTIAL=1, PUZZLE_OPEN=2`; enviado só quando muda e como catch-up a quem chega à zona.
- `EVENT_RESPAWN=10 {id, zone, pos}` — jogador reanimado no checkpoint da zona.
- `EVENT_BOSS=11 {zone, encounter:String, boss:String, state:int}` — `BOSS_ARMED=0, BOSS_ACTIVE=1, BOSS_DEFEATED=2`; wipe volta a `ARMED`.

Validação: `Protocol.validate_zone_event/validate_puzzle_event/validate_respawn_event/validate_boss_event` e o despachante `Protocol.validate_world_event(kind, data)` (tipos exatos, ids `[a-z][a-z0-9_]*` até 48, vetores finitos, `plates` limitado). `ClientSession` descarta eventos malformados (`world_events_rejected`).

Audiência: eventos de combate/drop/spawn/puzzle/chefe/respawn/zona vão **só aos jogadores da zona** (`ServerWorld.event_targets`); `player_joined/left` seguem globais. Ao entrar numa zona o jogador recebe catch-up (enemy_spawn da zona, puzzle, chefe). Snapshots em modo mundo contêm apenas jogadores da zona do peer e inimigos da zona dentro de `ServerSettings.aoi_radius` (50 m). Na arena (`world_id` vazio) nada disso muda. Detalhes em `docs/E5_WORLD.md`; esquema dos dados em `shared/content_schemas/world.schema.json`.
