# ELDERVALE — GAME DESIGN DOCUMENT MASTER
**Versão:** 0.1.0  
**Status:** Documento-base aprovado para prototipagem  
**Gênero:** Action RPG de fantasia, exploração e progressão  
**Plataforma inicial:** Windows PC  
**Engine:** Godot 4.x (versão estável fixada no repositório)  
**Câmera / arte:** 3D estilizado, câmera top-down inclinada/isométrica  
**Multiplayer:** Cooperativo online persistente, inicialmente grupos de até 4 jogadores

> Eldervale é um Action RPG cooperativo de fantasia. A exploração e a descoberta têm o espírito de aventuras top-down clássicas; o combate é em tempo real com decisões táticas; a evolução, os itens e as builds oferecem profundidade de ARPG. As referências são direcionais, não especificações para copiar conteúdo, personagens, interface, nomes, mapas ou assets de terceiros.

---

## 1. Visão e pilares

### High concept
Explore um mundo de fantasia interconectado, descubra regiões e histórias, enfrente inimigos e chefes em combate híbrido, construa uma identidade de personagem por meio de classes, habilidades, talentos e equipamentos, e avance com amigos em um mundo persistente.

### Pilares de design
1. **Combate responsivo:** leitura clara de ataques, movimento preciso, esquiva e habilidades com propósito.
2. **Builds expressivas:** equipamentos e modificadores mudam decisões e estilos de jogo.
3. **Exploração recompensadora:** segredos, atalhos, puzzles, NPCs, dungeons e histórias ambientais.
4. **Cooperação persistente:** cada jogador mantém personagem e progresso; grupos podem jogar juntos sem perder a autonomia.
5. **Conteúdo orientado a dados:** itens, habilidades, inimigos, quests e encontros configuráveis sem scripts exclusivos por conteúdo.
6. **Escopo sustentável:** primeiro vertical slice pequeno e polido; expansão por regiões e pacotes de conteúdo.

### Não objetivos do MVP
- MMORPG de centenas de jogadores por mapa.
- PvP competitivo, guild wars, leilão global ou economia entre jogadores.
- Geração procedural de todo o mundo.
- Suporte a consoles ou mobile no primeiro lançamento.
- Monetização, loja premium ou pay-to-win antes de validar o jogo.
- Conteúdo de campanha com dezenas de horas no primeiro marco.

## 2. Público e experiência
Público-alvo: jogadores de ARPGs, aventuras de ação top-down e RPGs cooperativos que valorizam exploração, loot, progressão e jogo com amigos.

Experiência desejada:
- Sessões curtas de 20–40 minutos que também possam se estender.
- Objetivos claros, mas liberdade para explorar.
- Cooperação útil sem tornar obrigatório jogar em grupo.
- Combate legível em tela mesmo com quatro jogadores e efeitos simultâneos.
- Recompensas compreensíveis e comparáveis.

## 3. Plataforma e apresentação

### Câmera e mundo 3D
- Cenários, personagens, criaturas, equipamentos e efeitos em 3D estilizado.
- Câmera ortográfica ou perspectiva de baixa distorção, inclinada em top-down/isométrico.
- Movimento relativo ao plano do mundo, com orientação visual consistente.
- Profundidade visual por geometria, iluminação, sombras, materiais e camadas de cenário.
- Evitar câmera livre que prejudique leitura de combate.
- Testar oclusão de personagens por árvores, paredes e estruturas; usar transparência/occlusion fade quando necessário.

### Direção artística
- Fantasia autoral com silhuetas claras, paleta coerente e leitura imediata de inimigos.
- Cenários ricos, mas sem excesso de ruído visual na área de combate.
- Efeitos de habilidade com limites de intensidade, duração e quantidade.
- Não usar assets sem licença comercial compatível; registrar origem, licença e alterações em `docs/ASSET_CREDITS.md`.

### Alvo técnico inicial
- Windows 10/11 64-bit.
- Meta de desempenho: 60 FPS em hardware intermediário a definir por benchmark; opção de qualidade reduzida.
- Resolução escalável e suporte a 16:9; validar ultrawide posteriormente.
- Teclado/mouse primeiro; controle como requisito planejado antes do beta.

## 4. Loop principal

**Explorar → descobrir atividade → combater/resolver puzzle → obter recompensa → melhorar build → desbloquear nova área/atividade → repetir.**

Loops secundários:
- Coletar materiais → fabricar/aprimorar → testar build.
- Aceitar quest → descobrir pistas → cumprir objetivos → receber recompensa e alterar estado do mundo.
- Entrar em dungeon → superar encontros → derrotar boss → obter loot específico.
- Jogar em grupo → combinar funções e habilidades → superar conteúdo de maior dificuldade.

## 5. Combate híbrido

### Princípios
- Ação em tempo real, sem pausa tática.
- Ataques básicos, habilidades com cooldown e/ou custo de recurso.
- Esquiva com janela curta de invulnerabilidade somente quando explicitamente configurada.
- Bloqueio/aparo apenas para armas e habilidades que suportem a mecânica.
- Stamina para ações físicas selecionadas; mana/energia para magia.
- Telegraphs claros para ataques inimigos.
- Hitboxes/hurtboxes consistentes e validadas no servidor.

### Controles padrão (remapeáveis)
| Ação | Tecla inicial |
|---|---|
| Movimento | WASD |
| Ataque primário | Mouse 1 |
| Ataque secundário / mira alternativa | Mouse 2 |
| Esquiva | Espaço |
| Habilidades | 1–4 |
| Poção rápida | Q |
| Interagir | F |
| Inventário | I |
| Personagem | C |
| Habilidades/talentos | K |
| Mapa | M |
| Missões | J |
| Social/party | P |
| Menu | Esc |

### Regras de combate
- O cliente envia intenção de ação; servidor valida estado, alcance, cooldown, recurso e alvo.
- O servidor calcula dano, efeitos, morte e recompensas.
- Predição local pode ser usada para resposta visual/movimento, nunca para conceder dano ou loot.
- Evitar habilidades que exijam precisão competitiva no MVP.
- Atributos e fórmulas devem ser configuráveis e versionados.

### Condições de estado iniciais
Queimadura, congelamento lento, atordoamento curto, veneno e vulnerabilidade elemental. Cada efeito define duração, intensidade, regra de acúmulo, imunidades e origem.

## 6. Personagens, classes e progressão

### Classes iniciais planejadas
1. **Guerreiro**
   - Berserker: agressão, dano físico e velocidade.
   - Guardião: mitigação, bloqueio e controle.
   - Cavaleiro Arcano: arma e magia.
2. **Mago**
   - Elementalista: fogo, gelo e raio.
   - Invocador: familiares e criaturas temporárias.
   - Arcanista: manipulação de energia e controle.
3. **Patrulheiro**
   - Caçador: precisão, crítico e marcação.
   - Explorador: armadilhas, mobilidade e venenos.
   - Arqueiro Arcano: projéteis elementais.

As classes e especializações são conteúdo planejado. O vertical slice pode iniciar com uma classe e uma especialização por classe, desde que a arquitetura suporte expansão.

### Progressão
- Nível inicial: 1.
- Meta inicial de campanha: nível 60; limite final ainda não definido.
- XP por quests, inimigos e encontros; regras anti-farm e contribuição definidas no servidor.
- Pontos de atributo/talento por marcos configuráveis.
- Respec pode existir como recurso controlado; custo e disponibilidade ficam para balanceamento.
- Evitar aumento linear infinito de números; usar curvas de XP e escalas de conteúdo testadas.

### Atributos base
Força, Destreza, Inteligência e Vitalidade. Atributos secundários: vida, mana/energia, stamina, armadura, resistências, velocidade de ataque, chance/dano crítico, velocidade de movimento e poder de habilidade.

### Talentos e habilidades
- Árvore por classe/especialização com nós pequenos, notáveis e maestrias.
- Modificadores alteram comportamento: projéteis adicionais, conversão elemental, área, duração, custo, condição ou sinergia.
- Cada habilidade define tags, custo, cooldown, alcance, alvo, animação, efeito e escalamento.
- Não criar “centenas de habilidades” no MVP; criar poucas habilidades combináveis e bem testadas.

## 7. Itens, loot e crafting

### Slots
Arma principal, arma secundária/escudo quando aplicável, cabeça, peito, mãos, pernas, pés, dois anéis, amuleto e relíquia.

### Raridades
Comum, Mágico, Raro, Épico, Lendário e Mítico. A raridade controla orçamento de propriedades, não deve ser apenas cor.

### Propriedades
Atributos, vida, recursos, velocidade, crítico, dano físico/elemental, resistências, regeneração e modificadores de habilidade.

### Itens únicos
- Efeito especial autoral e legível.
- Drop table e condição de obtenção definidas em dados.
- Sem item “obrigatório” para uma build funcionar.
- Poder e raridade ajustados por telemetria/testes.

### Loot multiplayer
- Loot individual instanciado por jogador por padrão.
- Recompensas de quest individuais, exceto objetivos explicitamente compartilhados.
- Chefes e cofres podem usar tabela de recompensa por participante elegível.
- Não permitir que o cliente escolha ou declare o item recebido.
- Regras de elegibilidade e anti-abuso executadas no servidor.

### Crafting
Coleta, receitas, fabricação, desmontagem e aprimoramento. Crafting não deve ser necessário para concluir a campanha inicial. Receitas e custos são dados configuráveis.

## 8. Mundo e narrativa

### Estrutura macro
Mundo aberto composto por regiões conectadas, com streaming/ativação de setores e pontos de transição controlados. A primeira entrega de conteúdo é uma região: **Greenwood**.

Regiões planejadas:
- Greenwood: floresta, vila, ruínas e introdução.
- Frostheim: montanhas, gelo e cavernas.
- Ashen Desert: deserto e templos.
- The Blighted Lands: corrupção e encontros avançados.
- The Abyss: conteúdo de endgame.

Esses nomes são provisórios e podem mudar.

### Greenwood — vertical slice
Conteúdo sugerido:
- Vila/hub seguro.
- Área selvagem.
- Uma ruína/dungeon curta.
- Um puzzle ambiental.
- Um mini-chefe e um chefe.
- NPCs com diálogos.
- 10–15 quests curtas/médias no marco de conteúdo; não bloquear o primeiro teste técnico aguardando todas.
- Recursos de coleta e um ponto de crafting.

### Narrativa
Premissa provisória: cinco fragmentos antigos estão ligados a uma corrupção que altera regiões e criaturas. A campanha investiga a origem desses fragmentos e as escolhas de civilizações passadas. A história deve ser original, com personagens, nomes, lore e diálogos próprios.

### Quests
Tipos: principal, secundária, exploração, caça, coleta, dungeon, história, cooperação e oculta.

Cada quest deve ter:
- ID estável, título, descrição, região e NPC.
- Pré-requisitos.
- Objetivos tipados.
- Estado e progresso persistente.
- Recompensas validadas no servidor.
- Condições de falha/abandono quando aplicável.
- Localização e texto preparados para tradução futura.

## 9. Multiplayer cooperativo persistente

### Decisão de produto
Coop persistente: cada jogador possui conta, personagens, inventário e progresso próprios. Jogadores podem formar grupo, entrar na sessão de um líder e explorar juntos. O mundo e os personagens persistem no backend/servidor.

### Escopo inicial
- Até 4 jogadores por sessão.
- Convite/entrada por party.
- Sessões de região/dungeon hospedadas em servidor dedicado.
- Hub e progresso pessoal persistentes.
- Progresso de quests individuais por padrão; objetivos de grupo podem ser compartilhados por regra explícita.
- Loot individual.
- Reentrada após desconexão, com janela e regras configuráveis.
- Sem PvP, guildas, leilão ou mundo massivo no MVP.

### Autoridade e segurança
- Servidor autoritativo para combate, posição validada, inimigos, drops, XP, inventário, quests e economia.
- Cliente envia comandos/intenção, nunca resultados.
- Autenticação por token de curta duração e renovação segura.
- Validar distância, cadência, cooldown, linha de visão, estado do personagem e permissões.
- Limitar frequência e tamanho de mensagens.
- Persistência transacional para recompensas e operações de inventário.
- Não confiar em relógio, valores, IDs ou dados enviados pelo cliente.
- Logs de eventos importantes sem registrar segredos ou tokens.

### Persistência
Salvar checkpoints e transações críticas. Inventário, equipamento, XP e quests devem sobreviver a crash/desconexão. Definir política de rollback/reconciliação antes do teste público.

## 10. Interface e acessibilidade
HUD: vida, recurso, stamina, XP, habilidades, poções, minimapa, party e notificações. Menus: personagem, inventário, habilidades, talentos, quests, mapa, crafting, social e configurações.

Requisitos:
- Escala de UI.
- Remapeamento de teclas.
- Volume separado para música, efeitos e interface.
- Legibilidade de texto.
- Opções para reduzir flashes, tremor de câmera e intensidade de efeitos.
- Indicadores visuais e sonoros de ataques perigosos.

## 11. Áudio
Trilha original/licenciada, ambientes por região, feedback de habilidades, impactos, UI, diálogos e telegraphs de chefes. Registrar licença e origem de cada asset de áudio.

## 12. Conteúdo do MVP / vertical slice
O MVP não é o jogo completo. Deve provar o loop principal e a arquitetura online.

Escopo alvo:
- 1 região pequena (Greenwood).
- 1 hub e 1 dungeon.
- 1 classe jogável inicialmente; arquitetura para 3 classes.
- 4 jogadores por sessão, validando primeiro com 2.
- 4–6 habilidades funcionais para a classe inicial.
- 5–8 tipos de inimigos.
- 1 chefe com mecânicas claras.
- Inventário, equipamentos, loot, XP e salvamento.
- 5 quests funcionais como mínimo técnico; ampliar para 10–15 após o loop estar estável.
- Convite/party e reconexão básica.

### Critérios de aceite do MVP
1. Dois clientes externos conseguem entrar na mesma sessão e ver movimentos/combate de forma consistente.
2. O servidor valida ataques, dano, morte e loot.
3. Personagem e inventário persistem após logout e reinício do servidor.
4. Um jogador não consegue conceder itens/XP modificando o cliente.
5. A região pode ser explorada sem softlocks conhecidos.
6. Quests podem ser iniciadas, progredidas, concluídas e persistidas.
7. O jogo mantém desempenho aceitável no hardware-alvo definido.
8. Um teste de 30–60 minutos não revela perda de personagem/inventário.

## 13. Pós-MVP
- Segunda região.
- Mais classes/especializações.
- Dungeons e bosses adicionais.
- Crafting expandido.
- Eventos regionais.
- Guildas e social avançado.
- PvP somente após análise de design e segurança.
- Economia entre jogadores somente após controles contra duplicação e fraude.

## 14. Métricas de qualidade
- Taxa de conclusão de onboarding.
- Abandono por quest/região.
- Tempo até primeira habilidade significativa.
- Frequência de uso de habilidades.
- Distribuição de builds.
- Frequência de desconexão e reconexão.
- Latência e taxa de mensagens perdidas.
- Erros de persistência e duplicação de itens.
- FPS e tempo de frame.

## 15. Decisões ainda abertas
- Nome definitivo e identidade visual.
- Lore, personagens e tom narrativo final.
- Modelo comercial e preço.
- Limite de nível final.
- Fórmulas exatas de XP/dano/atributos.
- Plataforma de autenticação e provedor de hospedagem.
- Região geográfica dos servidores e política de privacidade.
- Política de moderação/chat e requisitos legais para lançamento.
