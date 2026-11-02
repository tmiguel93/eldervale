# Limitacoes conhecidas da alpha (E7.1)

Honestas e verificaveis. "VM" = ambiente de desenvolvimento Linux; nada foi testado em producao.

## Infra e operacao (dependem do dono)
- **Nunca rodou em producao**: sem staging real, sem Vercel, sem PostgreSQL gerenciado, sem HTTPS/certificado, sem DNS. Testes de backend usam PGlite (conexao unica): concorrencia real de `FOR UPDATE` em PostgreSQL com varias conexoes nao foi exercitada.
- **Backups**: runbook e scripts existem (`docs/BACKUP_RESTORE.md`, `tools/ops/`) mas **nao foram executados** contra um PostgreSQL real; nenhum restore foi testado.
- **Windows**: `.exe` gerados e importados/exportados com sucesso, mas **nao executados no Windows**; nao assinados.
- **Rede real**: latencia/perda/jitter foram simulados no processo (`--sim-*`); nao ha teste em internet real nem com jogadores externos.
- **Rate limit por instancia** (memoria): em serverless os limites multiplicam pelo numero de instancias; sem store compartilhado.
- **Sem WAF / anti-DDoS**: flood volumetrico UDP/HTTP nao e mitigado pelo codigo.
- Servidor Godot e unico (sem escala horizontal, sem failover); queda do processo derruba as partidas (progresso ate o ultimo checkpoint e preservado).

## Seguranca (ver `docs/E4_SECURITY_REVIEW.md`)
- Segredo interno unico entre backend e servidor; chave por sessao reduz mas nao elimina o risco. Orcamento de XP e teto de stats sao heuristicos.
- Lockout distribuido: botnet contra um e-mail ainda esgota o balde global desse e-mail (60 tentativas).
- Sem verificacao de e-mail, sem recuperacao de senha, sem MFA, sem lista de senhas vazadas.
- Itens BAIXOS B1, B2, B3, B5, B6, B7, B8 continuam abertos.
- Sem revisao externa de seguranca nem teste de intrusao.

## Jogo
- **Sem playtest humano**: balanceamento e baseado em simulador (`docs/E6_BALANCE.md`); a sensacao de jogo, dificuldade e ritmo nao foram validadas.
- Uma especializacao por classe; demais marcadas `planned`.
- Arte, audio e UI sao placeholders (nenhum asset externo; ver `docs/ASSET_CREDITS.md`).
- Sem acessibilidade (daltonismo, remapeamento completo, legendas), sem localizacao alem de PT-BR, sem gamepad validado.
- Ate 4 jogadores por grupo; sem matchmaking; selecao de sessao manual.

## Rede e estabilidade (medido nesta VM)
- **Corrida conhecida de saida em massa**: quando varios clientes saem ao mesmo tempo o servidor Godot pode registrar `ERROR: Unable to send packet on channel 0, max channels: 0`. Observado em ~8 de 9 execucoes do cenario `party` (4 jogadores), inclusive no codigo anterior ao E7 (copia do HEAD), sem efeito funcional medido (todos os checks de jogo passam). O check "servidor sem ERROR" do cenario `party` falha por causa disso. Nao corrigido neste escopo; ver `docs/E7_GATE.md`.
- Deteccao de queda de cliente por SIGKILL leva ~7,6 s (timeout do ENet).
- Telemetria e logs sao arquivos/stdout do processo; coleta, rotacao e retencao sao manuais.

## Dados e privacidade
- Politica de privacidade e termos sao **rascunhos sem validade juridica** (`docs/legal/`).
- Nenhuma coleta automatica de feedback/crash; relato e manual (`docs/FEEDBACK.md`).
