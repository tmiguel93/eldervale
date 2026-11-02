# E7 — Gate de fechamento (E7.1 endurecimento da alpha)

Estado: **E7.1 (o que dispensa credenciais, produção e custo) concluído nesta VM; o gate E7 completo NÃO está fechado** (seção 5). Legenda: **OK** = coberto por teste/execução citada; **parcial** = coberto em parte; **não verificado** = não exercitado; **bloqueado por credenciais/dono** = exige conta, custo ou infraestrutura real.

Tudo vem de execuções reais nesta VM (Linux, Godot 4.7.2 headless, Node 22, PGlite em memória). Nada foi inferido.

## 1. O que o E7.1 acrescentou
- **A. Segurança:** M1, M2, M3, M5 (parcial), M7 e B4 corrigidos no código; partes de infraestrutura documentadas como abertas (`docs/E4_SECURITY_REVIEW.md`, seção "Correções do E7.1").
- **B. Build Windows reproduzível:** `export_presets.cfg`, `tools/build_windows.py`, versão/build id embutidos e visíveis, `docs/BUILD.md`.
- **C. Logs e métricas:** `ServerLog` estruturado (níveis, JSON, scrub), `ServerMetrics` operacional, health/ready no backend e arquivo de saúde no servidor Godot, `X-Request-Id`.
- **D. Falhas e carga leve:** cenários em `tools/e7_integration.py` (`party_base`, `party_net`, `client_crash`) e migrações em cópia sintética.
- **E. Documentos:** `BUILD.md`, `ASSET_CREDITS.md` (inventário real), `KNOWN_LIMITATIONS.md`, `legal/` (rascunhos), `FEEDBACK.md`, `BACKUP_RESTORE.md` + `tools/ops/`, DEC-0030..0035.

## 2. Critérios de aceite do roadmap (E7)
| Critério | Status | Evidência / limite |
|---|---|---|
| Build Windows do cliente e do servidor dedicado | **parcial** | Exportados (release) e hasheados; `.pck` do servidor roda no Godot Linux e imprime a versão. **`.exe` não executado no Windows; não assinado** (`docs/BUILD.md`). |
| Build reproduzível documentado | **OK** (script e doc) / **parcial** (bit a bit) | Dois builds consecutivos idênticos; um anterior diferiu (causa não investigada). |
| Versão/build id visíveis | **OK** | Tela de login, `--version`, log de boot (`tests/e7`, execução do `.pck`). |
| Logs sem PII/segredos, com id de requisição | **OK** | `ServerLog.scrub` (45 checks `tests/e7`), `e7_hardening` (request_id), varredura de segredos nas integrações. |
| Métricas operacionais e health/readiness | **OK** | `GET /v1/ready`, `/internal/metrics`, `--health-file`, `[metrics]` com p50/p95. Coleta/alerta externos: **bloqueado por dono**. |
| Segurança MÉDIA do E4 tratada | **OK** no código / **parcial** infra | Seção 4. WAF, proxy real e limite compartilhado: **bloqueado por dono**. |
| Teste com 4 jogadores sob latência/jitter/perda | **parcial** | Simulado (seção 3). Rede real: **não verificado**. |
| Reconexão e quedas (cliente e servidor) | **OK** (simulado) | `client_crash`, `server_crash`, `zone_drop`, `outage`. |
| Migrações 0001..0006 em cópia com dados sintéticos | **OK** | `backend/test/migrate_copy.test.ts` (7 testes: v1..v5 -> 0006, normalização de `class_id`, rollback 0006/0005 e reaplicação). PostgreSQL real: **não verificado**. |
| Backup com teste de restore | **bloqueado por dono** | Runbook e scripts prontos (`docs/BACKUP_RESTORE.md`); nunca executados. |
| Staging real, PostgreSQL gerenciado, Vercel, HTTPS/certificado | **bloqueado por credenciais/dono** | Não tocados. |
| Créditos de assets, limitações, legal, feedback | **OK** (rascunhos) | `docs/ASSET_CREDITS.md` (nenhum asset externo encontrado), `KNOWN_LIMITATIONS.md`, `legal/` (sem valor jurídico), `FEEDBACK.md`. |
| Playtest humano | **não verificado** | Nenhum jogador real. |

## 3. Testes de falha e carga leve (números reais, VM)
Cenário `party_net`: 4 jogadores, grupo, fase da ruína até o chefe e loot, com `--sim-latency-ms 50 --sim-jitter-ms 40 --sim-loss-pct 4` (perda só em pacotes não confiáveis; mensagens confiáveis apenas atrasam).
| Medida | Resultado |
|---|---|
| Jogadores concluindo fluxo (quest, zonas, puzzle, chefe, loot) | 4 de 4, 0 mortes, kills iguais |
| Tick do servidor (`tick_ms`, 600 amostras) | p50 0,95 ms, p95 1,87 ms, máx 7,42 ms |
| Intervalo entre ticks (`tick_dt_ms`) | p50 33,34 ms, p95 33,62 ms, máx 34,66 ms (alvo 33,3 ms) |
| Snapshot | 3 800 amostras, máx 792 B, máx 21 entidades, 0 acima do MTU |
| `snapshot_bytes` série | p50 246 B, p95 287 B, máx 292 B |
| Gauges ao final | 4 peers, 4 jogadores online |
`client_crash` (SIGKILL de um cliente): servidor detectou a queda em **7,6 s**; reconexão com novo ticket na mesma sessão; quest persistida visível; XP e itens iguais (sem perda/duplicação); `revision` 2 -> 11 sem regredir; métricas `reconnects={player:1}`, `disconnects={player:2}`; servidor sem ERROR.
`server_crash`, `zone_drop`, `outage` (cenários E5): OK nesta rodada.

**Falha conhecida e não corrigida (risco):** `ERROR: Unable to send packet on channel 0, max channels: 0` no log do servidor quando os 4 clientes saem juntos. Faz falhar o check "servidor sem ERROR" do cenário `party` (e dos `party_base`/`party_net`). Frequência observada: **8 execuções com erro em 9** do `party`. Foi reproduzida também numa cópia do `HEAD` anterior ao E7 (`git archive HEAD`, 1 execução com o erro) e numa cópia com os scripts do E7 que passou uma vez, portanto **não é regressão do E7.1**, mas o baseline E6.5 em que passou uma vez indica corrida, não determinismo. Todas as demais verificações (jogo, persistência, loot, segredos) passam. É a corrida conhecida do E5.6 (envio a peer já desconectado). Próximo passo sugerido: guardar `NetRpc` contra `peer.get_connection_status() != CONNECTED` na saída em massa.

## 4. Segurança (resumo)
Ver `docs/E4_SECURITY_REVIEW.md`. CORRIGIDO no código: M1 (balde e-mail+IP; residual distribuído), M2/M3 (config de proxy/IP), M5 (chave por sessão, orçamento de XP, teto de stats), M7 (limite ENet por IP), B4 (log e limite de falhas internas). ABERTO (infra/dono): WAF/anti-DDoS, proxy real, limite compartilhado entre instâncias, restrição de `/internal/*` por rede, segredo por servidor com rotação. Itens BAIXOS B1–B3, B5–B8 seguem abertos.

## 5. Validação executada (números reais)
- `node tools/validate_content.mjs`: 0 erros.
- Backend (por arquivo): auth 23, characters 68, classes 16, constraints 9, content_validation 10, crafting 21, exploits 20, exploration 11, http 10, items 16, migrate 5 (EPERM no `afterAll` ao limpar a pasta temporária, ignorado), misc 9, parties 9, quests 20, security_review 19, sessions 24, talents 13, **e7_hardening 11 (novo), migrate_copy 7 (novo)**; `npx tsc --noEmit` sem erros. Total 321 testes, 0 falhas.
- Godot (por diretório): e1 34, e2 357, e3 334, e4 258, e5 317, e5_gate 59, e5_loot 172, e5_quests 414, e5_snapshot 208, e5_ui 251, e5_world 206, e6_balance 82, e6_classes 693, e6_talents 275, e6_items 253, e6_quests 301, **e7 45 (novo)**; total 4 259, 0 falhas.
- Integrações: `e4_integration.py happy` OK, `e5_adventure_integration.py adventure` OK, `server_crash` OK, `zone_drop` OK, `outage` OK, `e7_integration.py client_crash` OK. `party`, `party_base`, `party_net`: funcionais OK, **falham só no check "servidor sem ERROR"** (seção 3).
- Build: `tools/build_windows.py` cliente e servidor OK (release).
- Ajustes de teste por mudança de contrato: `misc.test.ts` (production exige `TRUST_PROXY`), `auth.test.ts`, `characters.test.ts` (orçamento de XP), `security_review.test.ts` (seção A reescrita, M5 invertido).

## 6. O que depende do dono
1. Staging real (Vercel + PostgreSQL gerenciado + domínio + HTTPS/certificado) e testes contra ele (`sslmode`, pool, concorrência real).
2. Backups reais e **teste de restore** (`docs/BACKUP_RESTORE.md`).
3. Executar e, se desejado, assinar os `.exe` no Windows; teste em máquina limpa.
4. Testes de rede real (jogadores em outra rede) e playtest humano.
5. WAF/limite compartilhado e restrição de `/internal/*`; segredo por servidor.
6. Revisão jurídica dos rascunhos de `docs/legal/`.
7. Decidir retenção de logs/backups e como coletar `[metrics]`/health.
8. Aprovar DEC-0030..0035.

## 7. Próximo passo
Fechar a corrida de saída em massa do ENet, então staging real e a primeira rodada de playtest com o build do dono.
