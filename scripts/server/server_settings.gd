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
