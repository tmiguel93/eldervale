# Como relatar problemas (alpha)

Nao ha coleta automatica de erros, telemetria enviada a terceiros nem crash reporter. Voce decide o que enviar.

## Modelo de relato
```
Titulo:
Versao/build (titulo da tela de login ou `--version`):
Sistema (Windows versao, CPU/GPU, resolucao):
Papel: cliente | servidor
O que voce fez (passos numerados):
O que esperava:
O que aconteceu:
Frequencia: sempre | as vezes | uma vez
Horario aproximado (com fuso):
Classe/nivel/quest/zona (se aplicavel):
```

## O que anexar (e o que NAO anexar)
- Log do cliente/servidor (`--log-format json` ajuda) e, no servidor, o arquivo `--health-file`. Logs sao filtrados (segredos, tokens, e-mails viram `[email]`), mas **revise antes de enviar**.
- Captura de tela do problema.
- O `request_id` (campo `request_id` no log) de uma chamada que falhou ajuda a achar o evento no backend.
- **Nunca envie**: senha, tokens, `ELDERVALE_INTERNAL_SECRET`, `.env`, arquivos fora da pasta do jogo.

## Prioridades sugeridas
P0 perda de progresso/duplicacao/travamento de conta; P1 crash ou desconexao repetida; P2 bug de jogabilidade; P3 texto/visual.
