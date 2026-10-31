# ELDERVALE — IMPLEMENTATION ROADMAP
**Versão:** 0.1.0  
**Objetivo:** entregar um vertical slice cooperativo persistente e jogável, não construir o jogo inteiro de uma vez.

## Regras de execução
- Uma fase por vez.
- Não iniciar fase seguinte sem critérios de aceite aprovados.
- Cada tarefa termina com build/teste executável.
- Priorizar risco técnico: câmera 3D, combate responsivo, autoridade do servidor, persistência.
- Conteúdo adicional não pode atrasar validação do loop principal.
- Datas são estimativas; estimar novamente após cada marco.

## Marcos

| Marco | Resultado | Estimativa inicial |
|---|---|---:|
| E0 | Repositório, engine e documentação prontos | 2–4 dias |
| E1 | Protótipo 3D single-client | 2–3 semanas |
| E2 | Combate e primeiro loop ARPG local | 3–5 semanas |
| E3 | Servidor dedicado e coop de 2 jogadores | 4–7 semanas |
| E4 | Persistência, party e reconexão | 3–5 semanas |
| E5 | Greenwood vertical slice | 4–7 semanas |
| E6 | Progressão, quests e conteúdo ampliado | 4–8 semanas |
| E7 | Alpha fechada e hardening | 4–8 semanas |

As estimativas se sobrepõem parcialmente dependendo da disponibilidade, mas não devem ser tratadas como prazo garantido. Multiplayer e arte 3D podem ampliar significativamente o cronograma.

---

# E0 — Fundação do repositório

### Objetivo
Criar uma base limpa, importável e versionada.

### Tarefas
- [ ] Criar repositório Git.
- [ ] Fixar versão exata da Godot 4.x estável.
- [ ] Criar projeto Godot vazio e importar sem erros.
- [ ] Configurar `.gitignore`.
- [ ] Criar `README.md` com requisitos e comandos.
- [ ] Adicionar GDD, AGENTS, arquitetura e roadmap.
- [ ] Criar `docs/ASSET_CREDITS.md`.
- [ ] Definir convenções de branch e commit.
- [ ] Criar cena de boot mínima.
- [ ] Registrar versão do editor e export templates.

### Critérios de aceite
- Projeto abre em máquina limpa com versão documentada.
- Git não rastreia cache, builds ou segredos.
- Cena inicial executa.
- Documentos estão no repositório.

### Não fazer
- Não criar backend, banco, classes, mapas extensos ou conteúdo final nesta etapa.

---

# E1 — Protótipo 3D e câmera

### Objetivo
Validar a direção artística 3D, câmera top-down e controle do personagem.

### Tarefas
- [ ] Criar uma pequena arena de teste 3D.
- [ ] Implementar câmera ortográfica inclinada.
- [ ] Comparar perspectiva de baixa distorção e registrar decisão.
- [ ] Implementar personagem temporário 3D.
- [ ] Implementar movimento WASD relativo à câmera.
- [ ] Implementar colisão com cenário.
- [ ] Implementar orientação do personagem para direção de movimento/mira.
- [ ] Implementar oclusão/fade de objetos.
- [ ] Criar piso, obstáculos, rampa e escada de teste.
- [ ] Adicionar iluminação, sombras e pós-processamento moderado.
- [ ] Criar opções de qualidade básicas.

### Critérios de aceite
- Movimento previsível em todas as direções.
- Personagem não atravessa obstáculos.
- Câmera mantém leitura em ambientes abertos e estreitos.
- Oclusão não esconde permanentemente o jogador.
- Desempenho medido em hardware-alvo de referência.
- Cena executa após importação limpa.

### Gate de decisão
Aprovar câmera, escala do personagem, unidade de mundo e direção artística antes de produzir assets em quantidade.

---

# E2 — Combate e loop ARPG local

### Objetivo
Provar que explorar, lutar, receber loot e evoluir é divertido antes de integrar rede.

### Tarefas
- [ ] Criar máquina de estados do personagem.
- [ ] Ataque básico e hitbox/hurtbox.
- [ ] Esquiva e invulnerabilidade configurável.
- [ ] Recurso de habilidade (mana/stamina).
- [ ] Cooldowns.
- [ ] 2–4 habilidades da classe protótipo.
- [ ] Inimigo melee com IA simples.
- [ ] Inimigo ranged ou caster simples.
- [ ] Vida, dano, resistência e morte.
- [ ] Feedback visual/sonoro de acerto.
- [ ] Inventário local de teste.
- [ ] Equipar/desequipar item.
- [ ] Drop e XP de teste.
- [ ] Dados de habilidade/inimigo/item separados de lógica.
- [ ] Testes unitários das fórmulas e estados.

### Critérios de aceite
- Combate funciona repetidamente sem softlock.
- Cooldown e custo são respeitados.
- Hitbox não causa dano múltiplo indevido.
- Equipamento altera atributos calculados.
- Loot/XP são consistentes no modo local de protótipo.
- Não há dependência de UI para executar lógica de combate.

### Gate
Playtest interno de pelo menos 30 minutos. Ajustar resposta, câmera, leitura e duração dos encontros antes da rede.

---

# E3 — Servidor dedicado e multiplayer inicial

### Objetivo
Dois clientes entram na mesma sessão e compartilham uma área de teste com servidor autoritativo.

### Tarefas
- [ ] Criar bootstrap headless.
- [ ] Separar configuração de cliente e servidor.
- [ ] Criar protocolo de mensagens documentado.
- [ ] Conectar cliente ao servidor via ENet.
- [ ] Validar versão do protocolo.
- [ ] Implementar spawn/remoção de jogadores.
- [ ] Sincronizar movimento com snapshots.
- [ ] Implementar interpolação de jogadores remotos.
- [ ] Implementar validação server-side de movimento.
- [ ] Replicar inimigo e estado básico.
- [ ] Executar ataque validado no servidor.
- [ ] Replicar eventos de combate.
- [ ] Implementar rate limit e validação de payload.
- [ ] Testar dois clientes em LAN e pela internet.
- [ ] Simular latência e perda de pacotes.

### Critérios de aceite
- Dois clientes conectam e se veem.
- Movimento remoto é visualmente estável.
- Servidor rejeita velocidade/ação inválida.
- Dano só é aplicado pelo servidor.
- Desconexão remove ou coloca personagem em estado seguro.
- Cliente incompatível é recusado com mensagem compreensível.

### Gate
Não avançar para quatro jogadores até dois clientes funcionarem em condições de rede variáveis.

---

# E4 — Backend, persistência, party e reconexão

### Objetivo
Cada jogador mantém conta/personagem e consegue voltar ao mundo sem perder progresso.

### Tarefas
- [ ] Escolher e fixar linguagem/API backend.
- [ ] Criar PostgreSQL local.
- [ ] Criar migrations iniciais.
- [ ] Implementar cadastro/login seguro em ambiente de teste.
- [ ] Implementar token de acesso e ticket de sessão curto.
- [ ] Criar personagens e ownership.
- [ ] Implementar carregamento de personagem pelo servidor.
- [ ] Implementar checkpoint e autosave.
- [ ] Implementar transações de inventário.
- [ ] Implementar idempotência para recompensas.
- [ ] Impedir duas sessões simultâneas do mesmo personagem.
- [ ] Criar party de até 4 membros.
- [ ] Implementar convite e entrada.
- [ ] Implementar reconexão e janela de recuperação.
- [ ] Testar restart abrupto e recuperação de save.
- [ ] Testar migração e restauração de backup.

### Critérios de aceite
- Login e criação de personagem funcionam em ambiente de teste.
- Personagem/inventário sobrevivem ao restart.
- Repetição de uma requisição de recompensa não duplica item.
- Um personagem não fica ativo em duas sessões.
- Party permite entrar na mesma sessão.
- Reconexão segue regras documentadas.

### Gate
Revisão de segurança e integridade antes de testes externos mais amplos.

---

# E5 — Greenwood vertical slice

### Objetivo
Entregar uma pequena aventura completa em coop.

### Tarefas
- [ ] Criar hub/vila.
- [ ] Criar área selvagem conectada.
- [ ] Criar ruína/dungeon.
- [ ] Criar um puzzle ambiental.
- [ ] Criar 5–8 tipos de inimigos.
- [ ] Criar mini-chefe e chefe.
- [ ] Criar NPCs e sistema de diálogo.
- [ ] Criar 5 quests end-to-end.
- [ ] Criar recompensas de quest server-side.
- [ ] Criar loot individual.
- [ ] Criar ponto de crafting simples.
- [ ] Criar mapa/minimapa básico.
- [ ] Criar UI mínima de inventário/party/quests.
- [ ] Validar sessão com 4 jogadores.
- [ ] Testar troca de região e falha de conexão.

### Critérios de aceite
- Grupo conclui uma pequena sequência de aventura.
- Quests persistem por personagem.
- Loot individual é correto.
- Boss funciona com 1–4 jogadores.
- Dificuldade escala de forma controlada.
- Nenhuma recompensa é concedida duas vezes por replay de mensagem.
- Região pode ser concluída sem softlock conhecido.

---

# E6 — Progressão e conteúdo

### Objetivo
Transformar o vertical slice em uma base de RPG com builds.

### Tarefas
- [ ] Expandir a classe protótipo.
- [ ] Implementar as outras duas classes em etapas.
- [ ] Criar especializações iniciais.
- [ ] Criar árvore de talentos.
- [ ] Criar modificadores de habilidade.
- [ ] Expandir raridades e affixes.
- [ ] Criar 3–5 itens únicos de teste.
- [ ] Criar crafting básico.
- [ ] Expandir quests para 10–15.
- [ ] Criar atividades de exploração e segredos.
- [ ] Criar balanceamento de XP/dano/loot.
- [ ] Criar ferramenta simples de validação de conteúdo.
- [ ] Medir distribuição de builds e uso de habilidades.

### Critérios de aceite
- Builds diferentes têm decisões e resultados distintos.
- Itens não quebram fórmulas nem persistência.
- Conteúdo é carregado por dados validados.
- Quests e recompensas são reproduzíveis em testes.
- Não existem exploits óbvios de duplicação.

---

# E7 — Alpha fechada e hardening

### Objetivo
Preparar um teste externo controlado.

### Tarefas
- [ ] Criar instalador/build Windows reproduzível.
- [ ] Configurar ambiente staging.
- [ ] Configurar backups e testar restauração.
- [ ] Adicionar logs e métricas essenciais.
- [ ] Testar 4 jogadores por sessão.
- [ ] Testar latência, jitter, perda e reconexão.
- [ ] Testar crash de cliente e servidor.
- [ ] Testar migrações em cópia de dados.
- [ ] Corrigir bugs bloqueadores.
- [ ] Revisar licenças de assets e áudio.
- [ ] Criar política de privacidade e termos antes de coletar dados de público.
- [ ] Criar canal de feedback e formulário de bugs.
- [ ] Documentar limitações conhecidas.

### Critérios de aceite
- Nenhuma perda conhecida de personagem/inventário em testes críticos.
- Sem duplicação reproduzível de itens/recompensas.
- Sessão coop estável em teste controlado.
- Backups restauráveis.
- Build instalável e atualizável.
- Problemas conhecidos documentados.

---

## 3. Definição de pronto (DoD)
Uma tarefa só está pronta quando:
- O requisito está implementado no escopo aprovado.
- O projeto importa/compila.
- Testes relevantes foram executados.
- Não há erros novos conhecidos no log.
- O comportamento foi validado no cliente e, quando aplicável, servidor.
- Documentação foi atualizada.
- Diff foi revisado.
- Limitações são declaradas.

## 4. Plano de testes por marco

| Área | Teste |
|---|---|
| Movimento | colisão, bordas, rampas, latência |
| Combate | alcance, cooldown, custo, hit duplicado |
| IA | navegação, alvo, reset, morte |
| Loot | elegibilidade, repetição, desconexão |
| Inventário | equipar, mover, stack, transação |
| Quests | pré-requisito, progresso, recompensa única |
| Persistência | logout, crash, restart, concorrência |
| Rede | perda, jitter, timeout, replay, payload inválido |
| Build | importação limpa, exportação e inicialização |

## 5. Ordem recomendada de execução com agentes
1. E0: agente de setup/documentação.
2. E1: agente Godot 3D/câmera.
3. E2: agente gameplay/combate.
4. E3: agente networking, com revisão humana de protocolo.
5. E4: agente backend/DB, com revisão humana de segurança.
6. E5: agente conteúdo/world.
7. E6: agente progressão/balanceamento.
8. E7: agente QA/build.

Não paralelizar dois agentes alterando os mesmos arquivos centrais. Paralelismo só em tarefas isoladas, com branches separados e integração revisada.

## 6. Prompt de início recomendado — E0

Use este prompt no Claude Code ou Codex depois de colocar os quatro documentos na raiz do repositório:

> Leia integralmente `AGENTS.md`, `GDD_MASTER.md`, `TECHNICAL_ARCHITECTURE.md` e `IMPLEMENTATION_ROADMAP.md`. Execute somente a etapa E0. Primeiro inspecione o ambiente e apresente um plano de arquivos e comandos. Não implemente gameplay, backend, banco de dados ou multiplayer nesta etapa. Crie a fundação mínima do repositório, fixe a versão da Godot 4.x disponível e estável, configure `.gitignore`, README, cena de boot mínima e documentação de assets. Não invente a versão instalada: verifique-a e registre o resultado. Execute importação/abertura headless quando disponível e reporte exatamente o que foi validado. Não avance para E1 sem autorização.

## 7. Registro de decisões
Manter `docs/DECISIONS.md` com:
- ID da decisão.
- Data.
- Contexto.
- Opções consideradas.
- Escolha.
- Consequências.
- Responsável/aprovação.

Decisões que exigem registro: engine minor version, câmera, linguagem backend, protocolo, tick rate, schema de save, modelo de sessão, hospedagem e monetização.

## 8. Integração de ferramentas e deploy web
- E0 inclui documentação e configuração Git local; conexão de contas GitHub/Vercel é ação manual do proprietário.
- Não criar frontend, API ou projeto Vercel durante E0 sem autorização específica.
- Quando o frontend existir, conectar o diretório web ao Vercel via GitHub e habilitar Preview/Production deployments.
- Não implantar servidor Godot multiplayer na Vercel.
- Consultar `VERCEL_CLAUDE_GITHUB_ADDENDUM.md` para sequência detalhada e checklist.
