# ELDERVALE — TECHNICAL ARCHITECTURE
**Versão:** 0.1.0  
**Status:** Arquitetura proposta para validação no protótipo  
**Engine:** Godot 4.x fixada  
**Modo:** Cliente 3D + servidor dedicado headless + API/backend + PostgreSQL

---

## 1. Objetivos arquiteturais
- Suportar coop persistente de até 4 jogadores por sessão no primeiro escopo.
- Manter autoridade do servidor sobre estado competitivo/econômico.
- Separar simulação de gameplay, apresentação, persistência e conteúdo.
- Permitir adicionar regiões, itens, quests e habilidades por dados.
- Evitar microserviços prematuros; iniciar com um backend modular e um servidor de sessão.
- Ser executável localmente com ferramentas gratuitas.

## 2. Visão de componentes

```text
                 HTTPS (auth / profile / party / APIs)
        +-----------------------------------------------+
        |                                               v
+----------------------+                     +----------------------+
| Godot Client         | <--- ENet/UDP ----> | Godot Dedicated      |
| - Rendering          |                     | Session Server       |
| - Input              |                     | - Authoritative sim  |
| - UI                 |                     | - Combat / AI        |
| - Cosmetic prediction|                     | - Loot / quests      |
+----------------------+                     | - Region instance    |
                                               +----------+-----------+
                                                          |
                                                Internal service API
                                                          |
                                               +----------v-----------+
                                               | Backend API          |
                                               | - Auth/session tokens|
                                               | - Accounts/characters|
                                               | - Party/session meta |
                                               | - Save orchestration |
                                               +----------+-----------+
                                                          |
                                               +----------v-----------+
                                               | PostgreSQL           |
                                               | - Accounts           |
                                               | - Characters         |
                                               | - Inventory          |
                                               | - Quest progress     |
                                               | - World state        |
                                               +----------------------+
```

O desenho é lógico. No primeiro protótipo, backend e PostgreSQL podem rodar no mesmo host do servidor para reduzir custo, mas devem permanecer separados por interfaces e responsabilidades.

## 3. Stack proposta

| Camada | Tecnologia | Observação |
|---|---|---|
| Cliente | Godot 4.x | 3D estilizado, câmera inclinada |
| Servidor de sessão | Godot headless | Mesma lógica de gameplay, sem renderização |
| Transporte realtime | ENet/UDP | Baixa latência; testar NAT/firewall |
| API | Go (proposta) ou serviço equivalente | REST/HTTPS para operações fora do combate |
| Banco | PostgreSQL | Persistência transacional |
| Migrações | SQL versionado | Executadas em pipeline controlado |
| Contratos | JSON versionado / DTO | Schemas explícitos |
| Versionamento | Git | Branches e tags |
| CI inicial | GitHub Actions ou execução local | Sem segredos no repositório |

**Decisão provisória:** Go para API por simplicidade de deploy e concorrência. Se o time preferir outra linguagem, registrar a decisão antes de implementar autenticação. Não implementar API em duas linguagens.

## 4. Organização do repositório

```text
eldervale/
├── project.godot
├── client/
│   ├── scenes/
│   │   ├── boot/
│   │   ├── world/
│   │   ├── characters/
│   │   ├── enemies/
│   │   ├── bosses/
│   │   ├── dungeons/
│   │   └── ui/
│   ├── scripts/
│   │   ├── camera/
│   │   ├── input/
│   │   ├── movement/
│   │   ├── combat/
│   │   ├── abilities/
│   │   ├── inventory/
│   │   ├── quests/
│   │   ├── networking/
│   │   └── presentation/
│   ├── resources/
│   └── assets/
├── server/
│   ├── scenes/
│   ├── scripts/
│   │   ├── bootstrap/
│   │   ├── networking/
│   │   ├── simulation/
│   │   ├── combat/
│   │   ├── ai/
│   │   ├── loot/
│   │   ├── quests/
│   │   ├── persistence/
│   │   └── security/
│   └── config/
├── backend/
│   ├── cmd/
│   ├── internal/
│   │   ├── auth/
│   │   ├── accounts/
│   │   ├── characters/
│   │   ├── parties/
│   │   ├── sessions/
│   │   └── persistence/
│   ├── migrations/
│   └── api/
├── shared/
│   ├── contracts/
│   ├── content_schemas/
│   └── docs/
├── content/
│   ├── classes/
│   ├── skills/
│   ├── items/
│   ├── enemies/
│   ├── quests/
│   └── regions/
├── tests/
├── docs/
├── tools/
├── AGENTS.md
├── GDD_MASTER.md
├── TECHNICAL_ARCHITECTURE.md
└── IMPLEMENTATION_ROADMAP.md
```

A estrutura final pode mudar após o primeiro projeto importar na Godot. Não criar pastas vazias em massa antes de haver conteúdo.

## 5. Cliente Godot

### Responsabilidades
- Renderização 3D, câmera, áudio e interface.
- Captura de input e envio de comandos.
- Apresentação de snapshots/estado replicado.
- Predição visual local limitada (animação, feedback, movimento quando validado).
- Cache de conteúdo e preferências locais.
- Nunca decidir recompensas, dano final ou persistência autoritativa.

### Câmera
- Câmera ortográfica como ponto inicial; comparar com perspectiva de baixa distorção.
- Rotação e inclinação fixas no MVP.
- Follow suave com limites e colisão opcional.
- Oclusão por fade de estruturas entre câmera e personagem.
- Testar legibilidade em áreas estreitas, interiores e bosses grandes.

### Mundo 3D
- Usar `CharacterBody3D` para personagem controlado; física simplificada para mobs quando apropriado.
- Separar navegação, colisão e malha visual.
- Usar NavigationRegion3D/NavigationAgent3D para IA, com limites e validação no servidor.
- Usar setores/regions como unidades de carregamento e ativação.
- Evitar carregar o mundo inteiro simultaneamente.

## 6. Servidor dedicado

### Execução
- Export headless da Godot, iniciado com configuração de ambiente.
- Um processo de sessão atende até 4 jogadores inicialmente.
- Cada sessão tem região, seed/estado necessário e participantes.
- Servidor não carrega cenas de UI nem assets cosméticos desnecessários.
- Configuração de portas, limites e logs externos ao código.

### Autoridade
Servidor determina:
- Movimento válido e limites de velocidade.
- Estado de combate, alvo e alcance.
- Cooldowns e consumo de recursos.
- Dano, mitigação, críticos e efeitos.
- IA e estado dos inimigos.
- Morte, XP e drops.
- Inventário, equipamento e crafting.
- Estado e recompensas de quests.
- Transições de região e checkpoints.

O cliente pode antecipar efeitos cosméticos, mas deve reconciliar com a resposta do servidor.

### Simulação
- Definir tick rate inicial em teste (por exemplo, 20–30 ticks/s) e medir CPU/banda antes de fixar.
- Snapshot/delta de entidades relevantes.
- Interpolação no cliente para entidades remotas.
- Predição local somente para o próprio movimento, com reconciliação.
- Eventos confiáveis para transações e ações importantes; snapshots podem usar canal não confiável/ordenado conforme necessidade.
- Não enviar estado de cada objeto a cada frame.

## 7. Modelo de multiplayer persistente

### Identidade e sessão
1. Cliente autentica na API via HTTPS.
2. API emite token de acesso curto e token/credencial de sessão com escopo limitado.
3. Cliente solicita entrada em party/sessão.
4. Match/session service retorna endpoint e credencial temporária de conexão.
5. Cliente conecta ao servidor dedicado por ENet.
6. Servidor valida credencial, personagem e versão de protocolo.
7. Servidor carrega estado persistido e inicia replicação.
8. Logout/disconnect aciona checkpoint e liberação segura.

Nunca colocar senha de conta em RPC ENet. Nunca usar token permanente como credencial de sessão.

### Party e mundo
- Party tem líder e membros, limite 4.
- Convite deve ser validado pela API.
- Sessão tem ID, região, estado, capacidade e versão.
- O líder pode solicitar mudança de região; servidor valida todos os participantes.
- Jogador mantém progresso pessoal. Objetivos compartilhados devem ser explicitamente marcados.
- Em caso de saída do líder, definir eleição/transferência ou encerramento ordenado da sessão.
- Reconexão: janela inicial configurável (ex.: 60–120 s); o personagem desconectado fica em estado seguro, sem continuar vulnerável indefinidamente.

### Persistência e autoridade
- Servidor solicita ao backend salvar operações/estado.
- Backend valida ownership e aplica transações.
- Autosave em intervalos e em eventos críticos; não depender apenas de save no logout.
- Inventário e moeda devem usar transações e idempotency keys.
- Registrar `character_version` ou revision para evitar gravações concorrentes.
- Se duas sessões tentarem carregar o mesmo personagem, negar a segunda ou transferir ownership de forma explícita.

## 8. Contratos de rede

Todos os RPCs devem constar em `shared/contracts/network_protocol.md` antes de implementação.

Exemplos conceituais:
- `client_move_input(sequence, direction, client_tick)`
- `client_use_ability(request_id, ability_id, target_ref, aim)`
- `client_interact(request_id, entity_ref)`
- `server_world_snapshot(server_tick, entities_delta)`
- `server_combat_event(event_id, source_ref, target_ref, result)`
- `server_inventory_delta(revision, changes)`
- `server_quest_update(quest_id, state, objective_delta)`

Regras:
- `request_id` para ações que não podem ser aplicadas duas vezes.
- `sequence` para detectar replay/ordenação inválida.
- Validar tamanho, tipo, enum, intervalo e ownership.
- Limitar mensagens por cliente.
- Rejeitar IDs desconhecidos ou referências fora da sessão.
- Não aceitar campos de dano, XP, loot, preço ou recompensa enviados pelo cliente.

## 9. API backend

Endpoints iniciais sugeridos (contratos a detalhar antes de produção):
- `POST /v1/auth/login`
- `POST /v1/auth/refresh`
- `GET /v1/account`
- `GET /v1/characters`
- `POST /v1/characters`
- `GET /v1/characters/{id}`
- `POST /v1/parties`
- `POST /v1/parties/{id}/invites`
- `POST /v1/parties/{id}/join`
- `POST /v1/sessions/{id}/join-ticket`
- `POST /internal/characters/{id}/checkpoint`
- `POST /internal/inventory/transactions`

Endpoints `/internal/*` nunca ficam expostos publicamente sem autenticação serviço-a-serviço, autorização e restrição de rede.

## 10. PostgreSQL — modelo lógico inicial

Tabelas propostas:
- `accounts(id, email_normalized, password_hash, status, created_at)`
- `characters(id, account_id, name, class_id, level, xp, revision, created_at, updated_at)`
- `character_stats(character_id, stat_key, stat_value)`
- `character_skills(character_id, skill_id, rank)`
- `item_instances(id, owner_character_id, item_def_id, rolled_affixes, quantity, location, slot, revision)`
- `quest_progress(character_id, quest_id, state, objective_state, updated_at)`
- `world_states(scope_id, state_key, state_value, revision)`
- `parties(id, leader_character_id, created_at)`
- `party_members(party_id, character_id, joined_at, status)`
- `sessions(id, region_id, host_process_id, state, capacity, created_at)`
- `session_members(session_id, character_id, joined_at, last_seen_at)`
- `inventory_transactions(idempotency_key, character_id, operation, result, created_at)`
- `schema_migrations(version, applied_at)`

Observações:
- Tipos, constraints, índices e normalização serão detalhados na primeira tarefa de backend.
- Não armazenar senha em texto; usar hash moderno apropriado (Argon2id ou biblioteca mantida).
- Não guardar segredos no banco em texto sem necessidade.
- `rolled_affixes` pode ser JSONB no início; migrar apenas com evidência de necessidade.
- IDs devem ser UUID ou outro formato estável definido antes da primeira migração.
- Definir política de exclusão, retenção e exportação de dados antes de beta público.

## 11. Conteúdo data-driven

Definições estáticas podem ser `Resource` Godot ou JSON validado. Persistência de instâncias é distinta de definição.

Exemplo de definição de habilidade:
```json
{
  "schema_version": 1,
  "id": "skill.fire_bolt",
  "display_name": "Fire Bolt",
  "tags": ["projectile", "fire"],
  "resource_cost": {"type": "mana", "amount": 25},
  "cooldown_seconds": 4.0,
  "range": 12.0,
  "base_damage": 80,
  "scaling": {"intelligence": 1.4},
  "effects": [{"id": "effect.burn", "chance": 0.2}]
}
```
Validar schema, IDs duplicados, referências e limites antes de carregar conteúdo.

## 12. Segurança, integridade e abuso
- TLS para API; rede realtime com credenciais de sessão curtas e validação.
- Hash de senha com algoritmo apropriado; proteção contra brute force.
- Rate limit por conta, IP e conexão, com cuidado para NAT compartilhado.
- Validação de movimento, velocidade, alcance, cooldown, recursos e estado.
- Limites de tamanho de pacote e frequência de RPC.
- Idempotência para recompensas, crafting e transações.
- Logs de auditoria para operações de inventário/economia.
- Backups automáticos e teste de restauração.
- Não incluir ferramentas administrativas no cliente.
- Política de atualização de protocolo e rejeição de clientes incompatíveis.

## 13. Observabilidade e operação
Métricas mínimas:
- Jogadores conectados por sessão.
- RTT/latência, perda e jitter.
- Tick time do servidor.
- CPU/RAM por processo.
- Erros de RPC e payloads rejeitados.
- Tempo de consulta/salvamento.
- Falhas de reconexão.
- Erros de persistência e transações.
Logs estruturados com correlation ID; sem tokens e dados sensíveis.

## 14. Ambientes
- `local`: cliente, servidor e banco locais.
- `test`: servidor remoto para testes com amigos, dados descartáveis.
- `staging`: ambiente semelhante à produção, sem dados reais.
- `production`: só após revisão de segurança, backup e plano de rollback.

Configuração via variáveis de ambiente/arquivos ignorados pelo Git. Incluir `.env.example` sem segredos.

## 15. Testes e qualidade
- Testes unitários para fórmulas, cooldown, inventário, quest e loot.
- Testes de integração para API e banco.
- Testes de rede com 2–4 clientes.
- Simular latência, jitter, perda de pacotes e desconexões.
- Testar duas sessões tentando carregar o mesmo personagem.
- Testar duplicação por repetição de RPC.
- Testar restart abrupto de servidor durante recompensa.
- Testar migração e restauração de backup.
- Testar exportação e inicialização headless em ambiente limpo.

## 16. Decisões técnicas a validar no protótipo
1. Câmera ortográfica vs perspectiva de baixa distorção.
2. Movimento livre vs movimento em plano com navegação 3D.
3. Tick rate e estratégia de snapshot.
4. Godot headless como servidor de sessão vs servidor dedicado separado no futuro.
5. Go como API.
6. Estratégia de streaming de regiões.
7. Regras de reconexão e transferência de liderança.
8. Região e fornecedor de hospedagem.

## 17. Integração GitHub e Vercel
- GitHub é o repositório central.
- Vercel publica somente o frontend/site/painel e endpoints HTTP adequados.
- O servidor dedicado Godot com ENet/UDP permanece em VPS/provedor de game server; PostgreSQL permanece em serviço de banco separado.
- Não usar Vercel Functions como servidor de sessão realtime. A plataforma documenta que Functions não podem atuar como servidor WebSocket; ENet/UDP também exige infraestrutura de processo/host apropriada.
- Para passos de conexão, variáveis de ambiente, CI/CD e links oficiais, consultar `VERCEL_CLAUDE_GITHUB_ADDENDUM.md`.
