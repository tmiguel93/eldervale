# ELDERVALE — ADENDO DE FERRAMENTAS, CLAUDE CODE, GITHUB E VERCEL
**Versão:** 0.2.0  
**Objetivo:** padronizar o fluxo de desenvolvimento com Claude Code, GitHub e Vercel sem colocar componentes de tempo real do jogo em uma plataforma inadequada.

---

## 1. Decisão de infraestrutura

Eldervale usará GitHub como repositório central e Vercel para publicar os componentes web do projeto.

**Atenção: Vercel não será o host do servidor de gameplay multiplayer.** O servidor dedicado Godot usa comunicação realtime por ENet/UDP e mantém sessões persistentes. Vercel Functions não oferecem servidor WebSocket e não são adequadas para manter processos de sessão Godot/UDP. O servidor de jogo deverá rodar em VPS/host próprio ou provedor de game server.

### Distribuição de responsabilidades

| Componente | Onde ficará | Responsabilidade |
|---|---|---|
| Código-fonte | GitHub | Repositório, branches, PRs e histórico |
| Site oficial | Vercel | Landing page, notícias, links e suporte |
| Painel web/admin | Vercel | Interface web, ferramentas administrativas protegidas |
| Documentação web | Vercel (opcional) | Guias e changelog público |
| API HTTP leve | Vercel Functions ou backend dedicado | Login/conta/consultas HTTP, se compatível com o desenho final |
| PostgreSQL | Serviço PostgreSQL externo | Dados persistentes |
| Servidor de sessão Godot | VPS/servidor dedicado | Mundo, combate, IA, loot, party e simulação autoritativa |
| Builds do jogo | Releases do GitHub ou storage/CDN | Distribuição do cliente Windows |
| Claude Code | Máquina de desenvolvimento / ambiente autorizado | Implementação, testes e revisão assistidos por IA |

### Regra de arquitetura
A API HTTP não deve se tornar um atalho para contornar o servidor autoritativo. Operações de gameplay e transações importantes devem ser validadas pelo servidor de sessão/backend confiável. Nunca expor credenciais do banco ou segredos no cliente Godot ou no frontend.

---

## 2. Links oficiais necessários

### Claude Code
- Página oficial do Claude Code: https://claude.com/product/claude-code
- Documentação e instalação: https://code.claude.com/docs/en/quickstart
- Documentação geral: https://code.claude.com/docs
- `CLAUDE.md`, memória e instruções de projeto: https://code.claude.com/docs/en/memory
- Boas práticas: https://www.anthropic.com/research/claude-code-best-practices
- Segurança: https://code.claude.com/docs/en/security
- Integração GitHub no Claude: https://support.claude.com/en/articles/10167454-use-the-github-integration
- Plugin oficial Vercel para Claude: https://claude.com/plugins/vercel

### GitHub
- Criar repositório: https://github.com/new
- GitHub Desktop: https://desktop.github.com/
- GitHub CLI: https://cli.github.com/
- Documentação GitHub Actions: https://docs.github.com/actions

### Vercel
- Criar conta: https://vercel.com/signup
- Dashboard: https://vercel.com/dashboard
- Integração Git: https://vercel.com/docs/git
- Vercel para GitHub: https://vercel.com/docs/git/vercel-for-github
- Vercel CLI: https://vercel.com/docs/cli
- Vercel Functions: https://vercel.com/docs/functions
- Limitações das Functions: https://vercel.com/docs/functions/limitations
- Limites da plataforma (inclui WebSockets): https://vercel.com/docs/limits
- Variáveis de ambiente: https://vercel.com/docs/environment-variables

### Godot
- Download oficial: https://godotengine.org/download/
- Documentação: https://docs.godotengine.org/
- Exportação: https://docs.godotengine.org/en/stable/tutorials/export/

---

## 3. Preparação recomendada no Windows

1. Instalar Git: https://git-scm.com/download/win
2. Instalar GitHub Desktop (opcional, facilita visualizar commits e branches).
3. Instalar Claude Code conforme o guia oficial. No Windows, seguir a opção Windows/PowerShell ou WSL descrita na documentação atual.
4. Instalar Godot 4.x e fixar a versão exata aprovada no `README.md`.
5. Instalar Vercel CLI somente quando o primeiro projeto web estiver pronto para ser ligado.
6. Criar uma pasta de trabalho para o repositório e abrir Claude Code a partir da raiz.

Verificação inicial no terminal:
```powershell
git --version
claude --version
godot --version
```
O comando de Godot pode variar conforme o nome/caminho do executável instalado. Não declarar ferramenta instalada sem verificar.

Para iniciar Claude Code:
```powershell
cd caminho\para\Eldervale
claude
```

Não instalar ferramentas ou dependências globais sem necessidade. Registrar versões no `docs/DEV_ENVIRONMENT.md`.

---

## 4. Organização do GitHub

Criar um repositório privado chamado `eldervale` na conta pessoal do proprietário.

### Branches
- `main`: versão estável e protegida.
- `develop`: integração de tarefas aprovadas, se o fluxo exigir.
- `feat/nome-da-tarefa`: desenvolvimento isolado.
- `fix/nome-do-bug`: correções.

Para uma equipe pequena, pode-se simplificar e trabalhar com `main` + branches curtas. Não manter branches permanentes sem necessidade.

### Fluxo
1. Claude/Codex trabalha em branch de tarefa.
2. Executa testes e apresenta diff.
3. Responsável revisa alterações.
4. Abre Pull Request.
5. CI valida o projeto.
6. Merge em `main` somente após aprovação.

Nunca permitir que o agente faça push direto para `main`, apague branches ou force push sem autorização explícita.

### Arquivos obrigatórios na raiz
- `AGENTS.md`
- `CLAUDE.md`
- `GDD_MASTER.md`
- `TECHNICAL_ARCHITECTURE.md`
- `IMPLEMENTATION_ROADMAP.md`
- `README.md`
- `.gitignore`
- `.env.example` apenas para nomes de variáveis fictícias, sem valores secretos.

---

## 5. Claude Code: configuração do projeto

O Claude Code deve receber instruções de `CLAUDE.md`. O `AGENTS.md` continua sendo a regra compartilhada entre agentes. O `CLAUDE.md` deve apontar para ele e evitar duplicar o GDD inteiro.

### Conectar Claude ao repositório
Há dois fluxos distintos:
- **Claude Code local:** abrir a pasta clonada do repositório no terminal. O agente lê e altera os arquivos locais, respeitando permissões.
- **Claude com integração GitHub/Projects:** conectar GitHub nas configurações do Claude e selecionar o repositório/arquivos necessários. A sincronização do contexto deve ser atualizada quando o repositório mudar.

A integração GitHub de Claude Projects serve para fornecer contexto de arquivos; ela não substitui o Git local, revisão de código ou processo de Pull Request.

### Plugin Vercel
O plugin oficial Vercel para Claude Code pode ajudar a consultar deployments, logs, configuração e operações Vercel. Instalar somente depois de criar o projeto Vercel e revisar permissões. Não autorizar deploy de produção automático pelo agente no início.

### Permissões
- Começar no modo de permissões padrão/confirmado.
- Não conceder acesso amplo a shell, secrets, produção ou banco.
- Revisar cada diff.
- Proibir acesso do agente a `.env` real, tokens e chaves sempre que possível.
- Usar `.env.example` com placeholders.
- Deploy de produção exige confirmação humana.

---

## 6. Vercel: conexão com GitHub

### Configuração inicial
1. Criar conta Vercel.
2. Escolher **Add New → Project**.
3. Conectar a conta GitHub.
4. Autorizar acesso somente ao repositório `eldervale` ou ao repositório web separado.
5. Selecionar o repositório correto.
6. Definir o **Root Directory** correspondente ao site/painel web.
7. Configurar framework, comandos de build e diretório de saída conforme o framework escolhido.
8. Configurar variáveis de ambiente por ambiente.
9. Fazer deploy inicial.
10. Confirmar que pushes/PRs geram Preview Deployments e que `main` é a branch de produção.

### Recomendação de monorepo
Se site/painel e jogo estiverem no mesmo repositório, manter o frontend em uma pasta isolada, por exemplo:
```text
eldervale/
├── game/
│   ├── client/
│   └── server/
├── backend/
├── web/
│   ├── package.json
│   └── src/
├── docs/
└── ...
```
Nesse caso, configurar o Root Directory da Vercel para `web/`. Não configurar a raiz do repositório como aplicação web se o projeto Godot estiver ali.

Alternativa: criar repositórios separados `eldervale-game` e `eldervale-web`. Para um primeiro projeto com pouca gente, um monorepo pode simplificar a documentação, mas o frontend precisa continuar isolado.

### Ambientes
- Preview: deployments de branches e Pull Requests.
- Production: deploy após merge na branch `main`.
- Development/local: execução na máquina do desenvolvedor.

Não colocar tokens ou senhas em `vercel.json`, GitHub Actions YAML, commits, screenshots ou código frontend.

---

## 7. Variáveis de ambiente

Criar `.env.example` sem segredos reais. Nomes iniciais ilustrativos:
```dotenv
APP_ENV=development
PUBLIC_SITE_URL=http://localhost:3000
DATABASE_URL=
AUTH_SECRET=
GAME_SESSION_SERVICE_URL=
GAME_SESSION_INTERNAL_SECRET=
```

Regras:
- `PUBLIC_*` pode ser exposta ao navegador somente se o valor for realmente público.
- `DATABASE_URL`, `AUTH_SECRET` e `GAME_SESSION_INTERNAL_SECRET` são segredos.
- Não usar prefixos públicos (`NEXT_PUBLIC_`, `VITE_`, etc.) em segredos.
- Configurar valores separados para Development, Preview e Production no painel Vercel ou no ambiente do backend.
- Nunca commitar `.env`, `.env.local` ou arquivos equivalentes.
- Rotacionar imediatamente qualquer segredo que seja exposto por engano.

As variáveis acima são placeholders de arquitetura. Não implementar autenticação ou banco antes de definir os serviços e contratos finais.

---

## 8. O que a Vercel pode e não pode fazer neste projeto

### Usos adequados
- Site institucional e landing page.
- Página de notícias, changelog e documentação.
- Painel web de conta e ferramentas administrativas.
- Frontend web.
- Endpoints HTTP curtos e sem estado, quando compatíveis com Functions.
- Preview deployments para revisar mudanças.

### Não usar Vercel como
- Host do processo Godot headless.
- Servidor de sessão persistente.
- Servidor ENet/UDP.
- Servidor WebSocket realtime.
- Banco PostgreSQL embutido no processo do jogo.
- Host de simulação contínua de inimigos, combate ou mundo.

A documentação da Vercel informa que Functions não podem atuar como servidor WebSocket. Além disso, o protocolo ENet/UDP do jogo exige processo/host apropriado. Portanto, o multiplayer deve ficar em VPS ou provedor próprio de servidores de jogo.

---

## 9. CI/CD recomendado

### Primeira etapa
Usar integração nativa GitHub → Vercel para Preview e Production do frontend. Evitar criar GitHub Actions de deploy redundantes sem necessidade.

### Validações no GitHub Actions
Separar workflows por responsabilidade:
- `web-ci.yml`: lint, testes e build do frontend.
- `godot-ci.yml`: importação headless, testes automatizados disponíveis e validação/export do projeto Godot.
- `backend-ci.yml`: lint, testes e build da API/serviços.

Não fazer deploy do servidor de jogo automaticamente no primeiro MVP. Primeiro criar pipeline de staging, backup e rollback.

---

## 10. Prompt para Claude Code — configuração inicial

Copiar este prompt após criar/clonar o repositório e colocar todos os documentos na raiz:

> Leia `AGENTS.md`, `CLAUDE.md`, `GDD_MASTER.md`, `TECHNICAL_ARCHITECTURE.md`, `IMPLEMENTATION_ROADMAP.md` e `VERCEL_CLAUDE_GITHUB_ADDENDUM.md`. Execute somente E0. Inspecione o repositório e o ambiente antes de modificar qualquer arquivo. Prepare a estrutura Git/documentação e a configuração mínima do projeto Godot. Não crie ainda o site, painel, API, banco ou servidor multiplayer. Não faça deploy nem conecte contas. Não solicite, leia ou grave tokens e segredos. Registre no README quais passos dependem de ação manual do proprietário. Apresente plano antes de editar, execute validações disponíveis e reporte arquivos, comandos, testes e pendências. Não avance para E1 sem autorização.

---

## 11. Checklist manual do proprietário

- [ ] Criar repositório privado `eldervale` no GitHub.
- [ ] Instalar Git e Godot.
- [ ] Instalar e autenticar Claude Code.
- [ ] Colocar os documentos na raiz do repositório.
- [ ] Revisar `CLAUDE.md` e `AGENTS.md`.
- [ ] Criar conta Vercel.
- [ ] Conectar Vercel ao GitHub.
- [ ] Decidir se o frontend ficará no mesmo repositório ou em repositório separado.
- [ ] Só criar projeto Vercel quando existir um frontend para publicar.
- [ ] Escolher VPS/provedor para servidor Godot antes do teste multiplayer externo.
- [ ] Configurar secrets somente nos painéis seguros dos serviços.
- [ ] Exigir aprovação humana para deploy de produção.

## 12. Fontes oficiais
Links revisados para orientar a configuração; conferir as instruções atuais antes de executar comandos, pois ferramentas e limites podem mudar:
- Claude Code quickstart: https://code.claude.com/docs/en/quickstart
- Claude Code memory / CLAUDE.md: https://code.claude.com/docs/en/memory
- Claude Code security: https://code.claude.com/docs/en/security
- Claude + GitHub: https://support.claude.com/en/articles/10167454-use-the-github-integration
- Claude Vercel plugin: https://claude.com/plugins/vercel
- Vercel Git: https://vercel.com/docs/git
- Vercel GitHub: https://vercel.com/docs/git/vercel-for-github
- Vercel Functions: https://vercel.com/docs/functions
- Vercel limits / WebSockets: https://vercel.com/docs/limits
- Godot docs: https://docs.godotengine.org/
