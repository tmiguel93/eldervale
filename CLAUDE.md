# CLAUDE.md — Eldervale

Leia `AGENTS.md` antes de qualquer tarefa. Ele contém as regras permanentes para todos os agentes.

## Fontes de verdade
- `GDD_MASTER.md`: produto, gameplay, conteúdo e escopo.
- `TECHNICAL_ARCHITECTURE.md`: arquitetura técnica.
- `IMPLEMENTATION_ROADMAP.md`: fases e critérios de aceite.
- `VERCEL_CLAUDE_GITHUB_ADDENDUM.md`: Claude Code, GitHub, Vercel e divisão de infraestrutura.

## Regras rápidas
- Execute somente a etapa explicitamente autorizada.
- Inspecione o repositório antes de editar.
- Faça plano curto antes de mudanças relevantes.
- Não faça deploy, push para `main`, force push ou operações destrutivas sem autorização.
- Não leia, copie, imprima ou versione segredos.
- Não coloque o servidor Godot realtime/ENet na Vercel.
- Vercel é para frontend/site/painel e, se adequado, HTTP Functions.
- Servidor de sessão Godot e PostgreSQL ficam em infraestrutura apropriada separada.
- Não declare testes aprovados sem executá-los.
- Ao concluir, informe arquivos alterados, comandos, testes, limitações e próximo passo.

## Contexto de implementação
O projeto está em fase de fundação. Não presumir que exista código de jogo, backend, banco ou frontend até confirmar no repositório.
