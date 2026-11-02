# Politica de Privacidade — Eldervale (alpha)
> **RASCUNHO — requer revisao juridica.** Sem valor legal. Controlador, contato do encarregado, base legal, prazos e transferencias internacionais: **[a definir pelo dono com apoio juridico]**.

## 1. Dados que o software coleta hoje
| Dado | Finalidade | Observacao tecnica |
|---|---|---|
| E-mail | criar e acessar a conta | guardado no banco; nos logs do servidor aparece mascarado (`[email]`) |
| Senha | autenticacao | **nunca guardada em texto**: apenas hash scrypt |
| Personagem (nome, classe, nivel, inventario, progresso, quests) | persistir o jogo | banco de dados |
| Grupos (party) e sessoes de jogo | multiplayer | banco de dados |
| Logs tecnicos (horario, rota, status, id de requisicao, contadores) | seguranca e diagnostico | sem senha/token; IP de falhas de segredo interno aparece apenas como prefixo de hash |
| Endereco IP | limites de abuso (rate limit), conexao ao servidor de jogo | em memoria nos limitadores; pode constar nos logs de infraestrutura do provedor **[confirmar com o provedor]** |

## 2. O que NAO e coletado pelo software
Sem anuncios, sem rastreadores de terceiros, sem envio automatico de crash ou telemetria a terceiros. Metricas do servidor sao contadores agregados sem identificar jogadores.

## 3. Itens a preencher/decidir (nao inventados)
Base legal; prazo de retencao de contas, logs e backups; direitos do titular e como exerce-los (acesso, correcao, exclusao); exclusao de conta (hoje o personagem e removido por soft delete; **nao existe exclusao completa da conta**); local do armazenamento; compartilhamento com provedores (hospedagem, banco); idade minima; cookies/armazenamento do site (nao ha site ainda); contato.
