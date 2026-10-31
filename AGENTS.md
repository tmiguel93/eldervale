# AGENTS.md — Regras permanentes para Claude Code e Codex

Este arquivo define como agentes de IA devem trabalhar no repositório Eldervale. Leia-o antes de qualquer alteração.

## 1. Missão
Construir Eldervale como um Action RPG 3D estilizado, câmera top-down inclinada, coop online persistente para até 4 jogadores no escopo inicial, usando Godot 4.x. O GDD_MASTER.md é a fonte de verdade de produto; TECHNICAL_ARCHITECTURE.md é a fonte de verdade técnica; IMPLEMENTATION_ROADMAP.md controla a sequência de trabalho.

## 2. Regras inegociáveis
1. **Trabalhe somente na etapa/tarefa explicitamente autorizada.** Não avance fases por iniciativa própria.
2. Antes de editar, inspecione a estrutura atual, leia os documentos relevantes e identifique dependências.
3. Não reescreva arquivos inteiros quando uma alteração localizada for suficiente.
4. Não remova funcionalidades existentes sem autorização explícita.
5. Não introduza dependências pagas, serviços externos ou licenças comerciais sem autorização.
6. Não copie personagens, nomes, mapas, histórias, interfaces ou assets protegidos de jogos de referência.
7. Não coloque segredos, senhas, tokens ou chaves em código, logs, arquivos versionados ou documentação pública.
8. Nunca confie no cliente para dano, loot, XP, inventário, quests, economia ou estado persistente.
9. Cliente e servidor devem permanecer separados por responsabilidades e configuração.
10. Não marque uma tarefa como concluída sem executar os testes aplicáveis e reportar os resultados reais.
11. Não invente resultados de teste, métricas, arquivos, integrações ou funcionalidades.
12. Preserve compatibilidade de saves; alterações de schema exigem migração versionada e plano de rollback.
13. Mantenha o projeto executável após cada entrega.
14. Não faça refatorações amplas “por limpeza” fora do escopo.
15. Prefira soluções simples, explícitas e testáveis a abstrações prematuras.

## 3. Fluxo obrigatório de trabalho
Para cada tarefa:
1. Ler `GDD_MASTER.md`, `TECHNICAL_ARCHITECTURE.md` e a seção aplicável de `IMPLEMENTATION_ROADMAP.md`.
2. Inspecionar arquivos e estado do Git.
3. Escrever um plano curto com arquivos a alterar, riscos e testes.
4. Implementar apenas o escopo autorizado.
5. Executar validação estática/importação do projeto e testes relevantes.
6. Revisar diff procurando regressões, arquivos gerados indevidos e segredos.
7. Atualizar documentação e changelog se a tarefa alterou comportamento, arquitetura, dados ou instruções.
8. Entregar resumo com:
   - O que foi feito.
   - Arquivos criados/alterados.
   - Comandos executados.
   - Testes aprovados/reprovados/não executados.
   - Limitações e riscos conhecidos.
   - Próxima tarefa sugerida (sem executá-la).

## 4. Critério de parada
Pare e peça orientação se:
- O requisito contradiz o GDD ou a arquitetura.
- A alteração exige mudar schema persistente sem migração aprovada.
- Há dependência externa, custo ou licença não aprovada.
- O projeto não importa/abre após uma mudança e a causa não é óbvia.
- Uma tarefa exige credenciais, acesso a produção ou alteração destrutiva.
- O pedido é ambíguo e diferentes interpretações mudam arquitetura, dados ou gameplay.

## 5. Padrões de código Godot
- Fixar a versão exata de Godot 4.x no README/CI; não atualizar engine no meio de uma tarefa sem autorização.
- Usar tipagem estática em GDScript sempre que viável.
- Nomes de classes/nós em PascalCase; variáveis e funções em snake_case; constantes em UPPER_SNAKE_CASE.
- Scripts devem ter responsabilidade única e tamanho razoável.
- Usar `Resource` para definições de conteúdo estático quando adequado; dados persistidos e enviados pela rede devem ter schema explícito e validação.
- Não usar `NodePath` ou referências frágeis espalhadas quando uma interface clara resolver.
- Evitar `get_node()` repetido em caminhos dinâmicos; validar referências no `_ready()` e tratar falhas.
- Não depender da ordem implícita de nós sem documentar.
- Usar sinais para comunicação desacoplada; evitar singletons globais que concentrem lógica.
- Separar lógica de gameplay de apresentação/animação.
- Não usar `await` sem tratar cancelamento, desconexão e ciclo de vida do nó.
- Não usar `call_deferred` como solução genérica para problemas de arquitetura.
- Não adicionar plugins sem aprovação e registro de licença.

## 6. Rede e segurança
- Servidor é autoridade para estado de gameplay.
- RPCs devem ter nome, direção, permissões, frequência e payload documentados.
- Validar todos os payloads: tipo, tamanho, intervalo, estado, ownership e rate limit.
- Não expor funções administrativas a clientes.
- Não serializar objetos arbitrários do cliente; usar DTOs/dicionários com schema permitido.
- Não confiar em posição, velocidade, dano, cooldown, custo, alvo ou recompensa calculados pelo cliente.
- Separar eventos cosméticos de comandos que alteram estado.
- Evitar broadcast de estado completo; enviar deltas e snapshots conforme necessário.
- Nunca salvar diretamente dados recebidos sem validação e autorização.
- Não logar tokens, senhas, e-mails completos ou dados sensíveis.

## 7. Banco de dados e migrações
- Toda alteração de schema deve ser uma migração numerada, idempotente quando possível e revisada.
- Usar transações para recompensas, transferências e mudanças de inventário.
- Operações críticas devem ter idempotency key ou mecanismo equivalente contra repetição.
- Índices devem corresponder a consultas reais; não criar índices especulativos em excesso.
- Não alterar dados reais de produção em desenvolvimento.
- Usar fixtures/dados de teste sintéticos.

## 8. Conteúdo e assets
- Conteúdo deve ser data-driven.
- IDs são estáveis e não devem depender de nomes de exibição.
- Validar referências entre habilidades, itens, inimigos, quests e regiões.
- Cada asset externo deve constar em `docs/ASSET_CREDITS.md` com origem, autor, licença e alterações.
- Não usar placeholder com licença desconhecida em build pública.
- Manter arte de placeholder claramente identificada.

## 9. Testes mínimos por área
- Gameplay: movimento, colisão, cooldown, custo de recurso, dano e estados.
- Inventário: equipar/desequipar, stack, limites, persistência e concorrência.
- Quests: pré-requisitos, objetivos, recompensa única, abandono e reconexão.
- Rede: dois clientes, latência simulada, desconexão, reconexão e payload inválido.
- Banco: migração do zero, migração de versão anterior, transação e idempotência.
- Build: importação limpa e exportação Windows.

## 10. Git
- Não executar `reset --hard`, `clean -fd`, force push ou apagar branches sem autorização.
- Não fazer commit automaticamente, a menos que solicitado.
- Commits recomendados: `feat:`, `fix:`, `test:`, `docs:`, `refactor:`, `build:`.
- Não versionar `.godot/`, builds, caches, secrets ou arquivos locais.
- Manter `.gitignore` atualizado.

## 11. Formato de resposta do agente
Sempre finalizar com:
### Resultado
### Arquivos alterados
### Validação executada
### Riscos / pendências
### Próximo passo recomendado

Se algo não foi executado, declarar explicitamente. Nunca dizer “funcionando” apenas porque o código foi escrito.

## 12. Integração Claude Code, GitHub e Vercel
- `CLAUDE.md` complementa este arquivo e aponta para as fontes de verdade; não duplicar o GDD nele.
- Consultar `VERCEL_CLAUDE_GITHUB_ADDENDUM.md` para links oficiais, instalação e fluxo GitHub/Vercel.
- Não executar deploy ou operações de produção sem autorização humana.
- Vercel hospeda frontend/site/painel e funções HTTP compatíveis; não hospeda o servidor Godot ENet/UDP nem sessões realtime persistentes.
- Não solicitar nem registrar tokens em prompts, commits ou documentação.
