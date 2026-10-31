# E3 — Biblioteca de rede (`scripts/net/`)

Contrato: `shared/contracts/network_protocol.md` (seção "NetRpc (sinais e senders)").

| Arquivo | Papel |
|---|---|
| `protocol.gd` (`Protocol`) | Constantes e validadores puros: `validate_hello`, `validate_input`, `validate_name`, `validate_entity_dict`. Entradas são `Variant`; tipo errado, NaN/inf, bits desconhecidos, nome inválido → `ok=false`. |
| `rate_limiter.gd` (`RateLimiter`) | Token bucket com tempo injetado: `new(rate, burst)`, `allow(now_msec)`. Um por peer e tipo de mensagem. |
| `net_sim.gd` (`NetSim`) | Latência/jitter/perda na camada de aplicação, determinístico por seed. Reliable só atrasa e preserva ordem; unreliable pode perder e reordenar (jitter). |
| `net_config.gd` (`NetConfig`) | `parse(args, env)` / `from_environment()`; `--chave valor`, `--chave=valor`, `ELDERVALE_*`. Inválido → default + `errors`. |
| `net_rpc.gd` (`NetRpc`) | Único nó com `@rpc`. Valida remetente/tipos básicos e emite sinais; métodos `send_*` com `sim` opcional. |

## Uso
```gdscript
var rpc: NetRpc = NetRpc.install(get_tree())   # nó "NetRpc" na raiz; idempotente
rpc.hello_received.connect(_on_hello)           # servidor
rpc.send_hello(Protocol.VERSION, build, name)   # cliente
rpc.sim = NetSim.new(); rpc.sim.configure(80, 20, 2.0, 1234)  # opcional
```
O peer (`ENetMultiplayerPeer`) é criado e atribuído a `multiplayer.multiplayer_peer` por S/C; `send_*` são ignorados sem conexão. Servidor: chame `Protocol.validate_*` nos handlers dos sinais, aplique `RateLimiter` por peer e `s_reject` + desconexão em reincidência.

## Limites conhecidos
- `install` adiciona filho direto à raiz; durante o setup da cena inicial (raiz "ocupada") use `NetRpc.install.call_deferred(get_tree())` e obtenha depois com `NetRpc.get_instance(tree)`.
- `NetSim` simula na aplicação (pump em `_process`); não substitui teste em rede real. Mensagens `reliable` simuladas preservam ordem entre si, mas não em relação às unreliable.
- Sinais não revalidam payloads com `Protocol` (responsabilidade de S/C). Limites duros no receptor: strings 256, entidades por snapshot 256, mensagem de reject 512.
- Entrega fora de ordem do snapshot é tratada pelo cliente (`server_tick` crescente).
- Testes: `tests/e3/test_net_*.gd`; `test_net_rpc.gd` faz RPC real via ENet em 127.0.0.1 (porta 24791, dois `SceneMultiplayer` em subárvores). Integração multi-processo (servidor e clientes em processos separados, perda real) fica para depois.
