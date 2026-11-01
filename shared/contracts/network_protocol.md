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
| `c_caps` | C→S | reliable | `caps:int` | 1 por conexão (rate limit 1/s, burst 3) | E5.7: inteiro 0..0xFFFF; só após o welcome; bits desconhecidos mascarados |
| `s_snapshot_c` | S→C | unreliable_ordered | `server_tick:int, last_input_seq:int, part:int, parts:int, blob:PackedByteArray` | tick_rate/2..tick_rate por s × `parts` | E5.7 (só para quem declarou `CAP_SNAPSHOT_COMPACT`): ver seção "Extensão E5.7" |
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

## Extensão E5.4 — Loot individual e crafting (aditiva; `VERSION` continua 2)
Opt-in (`ServerSettings.individual_loot`; ligado por `--world` != arena, `--individual-loot 0|1` força). Com o modo desligado nada muda.

- **Entidade `KIND_PICKUP=3`** em snapshots: `{id, kind:3, pos, yaw, hp:0, max_hp:0, state:0, type:<item_id>, qty:1..999}`. O snapshot de cada peer contém **apenas os pickups cujo dono é o próprio peer** (e só na zona do drop); pickups alheios nunca são enviados. `Protocol.validate_entity_dict` aceita kind 3 (type = id de conteúdo, `qty` inteiro 1..`MAX_PICKUP_QTY`). Clientes antigos ignoram kinds desconhecidos.
- **`EVENT_DROP=6`** ganha o campo opcional `id` (id do pickup, int). Com loot individual é enviado **só ao dono**. `Protocol.validate_drop_event`.
- **`EVENT_PICKUP=12 {id, item_id, qty}`** — pickup coletado (só ao dono). `Protocol.validate_pickup_event`.
- **Coleta é server-side** (encostar no pickup, `ServerSettings.pickup_radius`); não existe RPC de coleta. Persistência pela recompensa idempotente com chave `loot:<sessão>:<id_do_drop>:<personagem>` (xp 0, 1 item).
- **Crafting**: `c_craft_cmd(req_id:int, recipe_id:String)` (cliente→servidor, reliable) e `s_craft(kind, data)` (servidor→cliente). `CRAFT_OK=1 {req_id, recipe_id, results:[{item_id, qty}]}`; `CRAFT_ERROR=2 {req_id, recipe_id, code}` com `code` em `not_ready, not_available, duplicate_request, unknown_recipe, busy, no_station, too_far, insufficient_ingredients, inventory_full, session_fenced, backend_error`. O cliente só envia o id da receita: ingredientes, resultado, estação e distância são decididos pelo servidor.
- **Validação/limites**: `Protocol.validate_craft_cmd` / `validate_craft_update` (tipos exatos, `req_id` int >= 0, `recipe_id` id de conteúdo <= 48). Payload inválido conta como abuso (`max_invalid_inputs`, depois desconexão). Rate limit por peer: `craft_rate_per_sec=2`, `craft_burst=4` (excesso é descartado e conta como inválido). Comando antes do welcome = rejeição `NOT_AUTHENTICATED`.
Detalhes e regras em `docs/E5_LOOT_CRAFTING.md`.

## Extensão E5.6 — Inventário sincronizado (aditiva; `VERSION` continua 2)
- **`s_inventory(data:Dictionary)`** (servidor→cliente, `reliable`, **só para o dono**): `{capacity:int 1..200, slots:[{item_id:String(id de conteúdo), qty:int 1..999}] (<= capacity), equipment:{weapon?|armor?|trinket?: item_id}}` (<= 3 chaves). Representa o inventário/equipamento **autoritativo do servidor** (o mesmo estado que o checkpoint persiste). O cliente só exibe; não existe comando de inventário.
- **Quando**: ao fim do join (sempre, forçado) e depois de cada mudança. A mudança é detectada por assinatura (JSON) comparada a cada `ServerSettings.inventory_sync_ticks` (6 ticks = no máximo 5 msgs/s/jogador, mudanças no intervalo são **coalescidas**); sem mudança nada é enviado. Só é enviado a peers com welcome concluído.
- **Validação**: `Protocol.validate_inventory_update` (tipos exatos, limites acima, ids de conteúdo `[a-z][a-z0-9_]*` <= 48). No cliente, payload inválido é descartado e contado (`ClientSession.inventory_rejected`), nunca chega à UI. Compatibilidade com um cliente de build anterior (que não declara o método `s_inventory`) **não foi verificada**: o RPC de alto nível do Godot exige o mesmo conjunto de métodos nos dois lados, então servidor e cliente devem ser atualizados juntos (`VERSION` não foi incrementado).
- **Efeito na UI**: com o inventário sincronizado `ClientInventory.complete = true` (some o aviso "Estimativa desta sessão") e as estimativas locais (pickup/craft) viram no-ops; a grade tem 25 slots (`SLOT_COUNT`).
- Testes: `tests/e5_gate/test_inventory_sync.gd`; integração real em `tools/e5_adventure_integration.py` (o inventário do cliente é comparado ao persistido no backend). Detalhes e evidências em `docs/E5_GATE.md`.

## Extensão E5.7 — Snapshot compacto e particionado (aditiva; `VERSION` continua 2)
Motivo: o `s_snapshot` legado (array de `Dictionary` com chaves string, ~240 B/entidade) passava do MTU de payload (1392 B) na luta de chefe e nas ruínas (medido: até 4912 B / 4456 B); o ENet fragmenta `unreliable` acima do MTU e a perda de qualquer fragmento descarta o snapshot inteiro. O formato legado **continua existindo** e é o padrão para quem não declarar a capacidade.

**Negociação por capacidade** (sem mudar `c_hello`):
- `c_caps(caps:int)` C→S, `reliable`, `any_peer`. Máscara de capacidades; hoje `CAP_SNAPSHOT_COMPACT = 1`. O cliente envia uma vez, logo ao receber o `s_welcome`. Antes do welcome → `REJECT_NOT_AUTHENTICATED`. Validação (`Protocol.validate_caps`): inteiro `0..0xFFFF` (tipo/faixa inválidos = abuso: descartado, contado, reincidência → `REJECT_RATE_LIMIT`); bits desconhecidos são ignorados (mascarados). Rate limit 1/s com burst 3. Pode ser reenviado (ex.: `0` volta ao legado).
- Peer com `CAP_SNAPSHOT_COMPACT` (e `ServerSettings.compact_snapshots` ligado, padrão; `--compact-snapshots 0` é o kill-switch) recebe **só** `s_snapshot_c`; os demais continuam com `s_snapshot`. Entre o welcome e o `c_caps` (≈ 1 RTT) o peer ainda recebe o legado; o cliente aceita os dois formatos na mesma sessão (o interpolador descarta tick repetido/velho).
- Compatibilidade: bots/clientes de build anterior não enviam `c_caps` e seguem no legado. Como o RPC de alto nível do Godot exige o mesmo conjunto de métodos nos dois lados (mesma ressalva do `s_inventory`), servidor e cliente devem ser atualizados juntos; a negociação protege a *semântica* (formato), não a tabela de RPCs.

**`s_snapshot_c(server_tick:int, last_input_seq:int, part:int, parts:int, blob:PackedByteArray)`** S→C, `unreliable_ordered` (canal 1), `authority`.
- Um snapshot = `parts` mensagens (1..`MAX_SNAPSHOT_PARTS=16`) com o mesmo `server_tick`/`last_input_seq`; `0 <= part < parts`. Cada parte é **autocontida** (tabela de strings e origem de posição próprias): perder uma parte não impede ler as outras, e nada depende de estado enviado antes.
- Orçamento: `blob` <= `SnapshotCodec.MAX_PART_BYTES = 1200` B (servidor, `ServerSettings.snapshot_part_bytes`); o receptor aceita 1..`Protocol.MTU_PAYLOAD = 1392` B. Os 190 B de folga cobrem o cabeçalho do RPC e os 4 inteiros/cabeçalho Variant. Com ~16–20 B/entidade uma parte leva ~60–70 entidades; acima disso o servidor particiona.
- Interesse continua **por peer**: o servidor codifica exatamente a lista que antes enviava a esse peer (zona + AOI de 50 m em modo mundo; pickups só do dono). O cliente não decide nada.

**Layout da parte** (little-endian): `u8 FORMAT(=1) | u8 n_strings | n_strings × (u8 len<=32, bytes ASCII 0x21..0x7E) | 3×s32 base (cm) | varint n_entidades | entidades`. Entidade: `u8 flags` (bits 0–1 `kind` 1..3; bit2 extras; bit3 posição larga; bit4 hp cheio; bits 5–7 = 0) · `varint id` · `u8 idx_type` (tabela) · `u8 state` · posição (`3×s16` em cm relativos à `base`, ou `3×float32` se bit3) · `u16 yaw` · `varint max_hp` · [`varint hp` se não cheio] · [`u8 phase`, `u8 atk` (0 = nenhum, i+1 = tabela) se bit2; só `kind` 2; emitido quando `phase != 0` ou `atk != ""`] · [`varint qty` se `kind` 3]. `varint` = LEB128 de até 4 bytes (28 bits). O `type` e o `atk` vão por **índice de uma tabela por parte** (sem estado entre mensagens).
- **Quantização** (documentada; o servidor continua com os valores exatos): posição 1 cm (erro <= 0,5 cm por eixo, <= 0,87 cm euclidiano; abaixo da zona morta de 5 cm da reconciliação, então nenhuma correção espúria — testado); yaw 2π/65536 (erro <= 4,8e-5 rad); `hp`/`max_hp` inteiros arredondados, com `hp > 0` nunca virando 0 (limite 268 435 455); posição fora de ±327 m da `base` (ou |cm| > 2·10⁹) usa o modo largo `float32` (exato). `Y` vem do servidor como antes (predição só prevê XZ).
- O decodificador devolve o mesmo `Dictionary` do formato legado (inimigos sempre com `phase`/`atk`; `qty` só em pickup; `hp`/`max_hp` como float inteiro), então `BossBar`, HUD de grupo, interpolador e `Protocol.validate_entity_dict` não mudam.

**Validação** (`SnapshotCodec.decode_part`, `Protocol.validate_snapshot_part`, `SnapshotAssembler`): cabeçalho com tipos exatos e faixas; blob 1..1392 B; decodificação **estrita** (formato desconhecido, truncamento, byte sobrando, flags reservadas, `kind` inválido, índice fora da tabela, `phase` > 15, `qty` fora de 1..999, posição não finita, id repetido, `extras` em não-inimigo → a parte inteira é recusada). `NetRpc.s_snapshot_c` descarta no RPC o que falhar no cabeçalho; o `SnapshotAssembler` conta o resto (`parts_malformed`).
- **Mescla no cliente** (`SnapshotAssembler`, usado por `ClientSession.on_snapshot_part`): o snapshot só é entregue quando todas as `parts` partes do mesmo tick chegaram (ordem livre); parte perdida ⇒ o tick é descartado (mesma semântica do legado, onde perder um fragmento descarta tudo — nunca entrega pela metade); duplicata e tick <= último entregue são ignorados (`parts_duplicate`/`parts_stale`); no máximo 4 montagens pendentes (a mais antiga é descartada, `snapshots_dropped_incomplete`); `parts`/`last_input_seq` divergentes entre partes, id repetido entre partes ou > 256 entidades no snapshot ⇒ parte recusada (`parts_malformed`).
- Medição: `--measure-snapshots` (só com `ELDERVALE_TEST_MODE=1`) conta **mensagens** (`samples`, `max_bytes`, `over_mtu`, `sum_bytes`) e também `snapshots`, `compact_snapshots`, `max_parts`, `encode_skipped`; o tamanho é o de `var_to_bytes` dos 5 argumentos (sem cabeçalho de RPC/ENet).
- API: `Protocol.CAP_SNAPSHOT_COMPACT/CAPS_KNOWN_MASK/MAX_SNAPSHOT_PARTS/MTU_PAYLOAD`, `validate_caps`, `validate_snapshot_part`; `SnapshotCodec.encode(entities, max_part_bytes) -> {parts, skipped, encoded}` / `decode_part(blob) -> {ok, entities, error}`; `SnapshotAssembler.push(...)`; `NetRpc`: `c_caps`, `s_snapshot_c`, `send_caps`, `send_snapshot_part`, sinais `caps_received`, `snapshot_part_received`; `ServerTransport.send_snapshot_part`; `ServerSession.on_caps`; `ClientSession.send_caps/on_snapshot_part`.
- Testes: `tests/e5_snapshot/` (codec, assembler, sessão ponta a ponta incl. RPC real em loopback). Resultados medidos em `docs/E5_GATE.md` seção 4.
