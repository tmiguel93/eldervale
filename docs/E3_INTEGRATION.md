# E3 — Integração multi-processo

Harness: `python3 tools/e3_integration.py <baseline|latency|cheat|flood|badversion|all> [--godot CAMINHO] [--port N]`.
Sobe 1 servidor headless + bots (processos separados, ENet em 127.0.0.1) e valida os critérios abaixo. Saída 0 = OK.

| Cenário | Verifica |
|---|---|
| baseline | 2 clientes conectam, ids distintos, cada um vê o outro, snapshots contínuos (intervalo máx. < 250 ms), velocidade observada dentro do limite do servidor, servidor sem ERROR |
| latency | idem com 120 ms ± 30 ms de latência e 5% de perda simulados na camada de aplicação (RTT médio medido ≥ 100 ms) |
| cheat | bot envia move de módulo 10; velocidade observada continua ≈ velocidade do servidor |
| flood | inputs inválidos em excesso → `reject(4)` e desconexão |
| badversion | versão errada → `reject(1)` |

## O que NÃO está verificado
- Rede real (internet/LAN entre máquinas): só loopback + simulação na aplicação.
- Render do cliente, predição sob latência alta, CPU/banda a 30/15 Hz.
- O jogador morto não renasce no servidor (reconectar cria outro jogador).
- SIGTERM não encerra o servidor de forma limpa (use `--max-seconds`/`--quit-after`).
