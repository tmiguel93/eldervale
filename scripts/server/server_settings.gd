class_name ServerSettings
extends RefCounted
## Parametros do servidor dedicado (E3). Valores de rede vem de NetConfig; o restante e ajustavel
## por argumentos extras do server_main (--max-invalid, --hello-timeout) ou diretamente em testes.

var tick_rate: int = 30
var snapshot_rate: int = 15
var max_players: int = 4
## Peer sem hello valido neste prazo e rejeitado (codigo 5) e desconectado.
var hello_timeout_sec: float = 5.0
## Inputs invalidos tolerados por janela; acima disso: reject(4) + disconnect.
var max_invalid_inputs: int = 30
var invalid_window_sec: float = 10.0
## Token buckets por peer e por tipo de mensagem (contrato: input <= 60/s, hello 1/s, ping <= 2/s).
var input_rate_per_sec: float = 75.0
var input_burst: int = 120
var hello_rate_per_sec: float = 1.0
var hello_burst: int = 3
var ping_rate_per_sec: float = 4.0
var ping_burst: int = 6
## E5.1: comandos de quest/dialogo (c_quest_cmd/c_dialogue_cmd): token bucket por peer.
var quest_rate_per_sec: float = 5.0
var quest_burst: int = 10
var session_seed: int = 0
## E4: com backend, o drop morto vai para o Inventory do matador (para o checkpoint nao apagar o que
## a recompensa persistiu). Sem backend (modo dev) o drop segue informativo como no E3.
var persist_drops: bool = false
## E4: resgates de ticket simultaneos aceitos (acima disso: reject 3) e prazo do resgate+carga.
var max_pending: int = 8
var redeem_timeout_sec: float = 8.0
## E5.3: id da regiao do mundo (data/areas/world/<id>_world.json). "" = arena de teste do E1/E3
## (padrao: comportamento anterior). O servidor dedicado liga com `--world greenwood`.
var world_id: String = ""
## E5.3: interesse por distancia dentro da zona: o snapshot de cada peer so leva inimigos a ate este raio (m)
## do jogador dele (jogadores da mesma zona sempre entram). 0 = sem limite (so filtro por zona).
var aoi_radius: float = 50.0
## E5.4: LOOT INDIVIDUAL. true = cada participante elegivel rola o proprio loot (pickups com dono, so visiveis e
## coletaveis por ele) em vez do drop ir direto ao matador. false (padrao) = comportamento E3/E4. O servidor dedicado liga
## com `--world greenwood` (ou `--individual-loot 1`). Ver docs/E5_LOOT_CRAFTING.md.
var individual_loot: bool = false
## Semente PRIVADA do loot (nunca enviada ao cliente; o `session_seed` do welcome e publico). -1 = aleatoria.
var loot_seed: int = -1
## Inimigo comum: so rola loot quem causou pelo menos esta fracao da vida maxima dele (o matador sempre rola).
## Mini-chefe e chefe: qualquer dano > 0 basta.
var loot_min_share: float = 0.05
## Pickup nao coletado some depois disso (inclusive quando o inventario esta cheio) e e coletado ao chegar a este raio (m).
var pickup_ttl_sec: float = 90.0
var pickup_radius: float = 1.8
## Maximo de pickups simultaneos por dono (o mais antigo e descartado quando passa).
var max_pickups_per_player: int = 24
## E5.4: XP tambem para os demais participantes elegiveis (so no modo individual; adds invocados nao repartem).
var xp_for_participants: bool = true
## E5.4: c_craft_cmd: token bucket por peer.
var craft_rate_per_sec: float = 2.0
var craft_burst: int = 4
## E5.6: inventario sincronizado (s_inventory): a cada N ticks o servidor compara o inventario/equipamento de cada jogador
## com o ultimo enviado e so manda se mudou (coalesce: no maximo tick_rate/N mensagens por segundo por jogador). 0 desliga.
var inventory_sync_ticks: int = 6
## E5.6: PARAMETROS SO DE TESTE (harness de integracao; o servidor so os honra com ELDERVALE_TEST_MODE=1, ver server_main).
## Multiplicam a vida dos inimigos / a velocidade dos jogadores para que a aventura inteira caiba num comando de 180 s na VM.
## O padrao (1.0) deixa o ritmo de combate APROVADO intacto; nenhum e enviado ao cliente.
var test_enemy_hp_mult: float = 1.0
var test_move_speed_mult: float = 1.0
## E5.6: mede o tamanho (aproximado) dos snapshots por peer (var_to_bytes) para o relatorio do gate. Desligado por padrao.
var measure_snapshots: bool = false
## Testes podem desligar os inimigos da arena.
var spawn_enemies: bool = true
var spawn_points: Array[Vector3] = [
	Vector3(0.0, 0.05, 0.0), Vector3(2.0, 0.05, 0.0), Vector3(-2.0, 0.05, 0.0), Vector3(0.0, 0.05, 2.0),
]


static func from_net_config(cfg: NetConfig) -> ServerSettings:
	var s: ServerSettings = ServerSettings.new()
	s.tick_rate = cfg.tick_rate
	s.snapshot_rate = cfg.snapshot_rate
	s.max_players = cfg.max_players
	return s


## Quantos ticks de simulacao entre snapshots (>= 1).
func snapshot_divisor() -> int:
	return maxi(1, int(round(float(tick_rate) / float(maxi(snapshot_rate, 1)))))
