# Registro de decisões

Formato por decisão: ID, data, contexto, opções consideradas, escolha, consequências, responsável/aprovação.

---

## DEC-0001 — Versão da engine Godot 4.7.2-stable
- **Data:** 2026-10-31
- **Status:** VERSÃO VERIFICADA (2026-10-31); export templates pendentes
- **Verificado:** `Godot_v4.7.2-stable_win64_console.exe --version` retornou `4.7.2.stable.official.ed1daf0bf` (informado pelo proprietário).
- **Contexto:** Os binários `Godot_v4.7.2-stable_win64.exe` e `Godot_v4.7.2-stable_win64_console.exe` estão na raiz do projeto. A versão foi inferida apenas do nome dos arquivos. O binário não executa no ambiente Linux usado pelo agente, portanto `--version` não foi rodado.
- **Opções consideradas:**
  1. Fixar 4.7.2-stable com base no nome do binário, pendente de confirmação.
  2. Adiar a fixação até verificar a versão por execução.
- **Escolha:** Registrar 4.7.2-stable como versão-alvo provisória (opção 1), sujeita a confirmação.
- **Consequências:** README e documentação citam 4.7.2-stable como não verificada. Export templates não registrados nem verificados. Se a verificação divergir, atualizar README e este registro.
- **Verificação necessária:** no Windows, executar `Godot_v4.7.2-stable_win64_console.exe --version` e registrar a saída aqui, junto com a versão dos export templates.
- **Responsável/aprovação:** Proprietário do projeto; aprovação pendente.

---

## DEC-0002 — GitHub/Vercel: conexão manual pelo proprietário
- **Data:** 2026-10-31
- **Status:** PROPOSTA
- **Contexto:** O roadmap (seção 8) define que a etapa E0 inclui documentação e Git local, e que a conexão de contas GitHub/Vercel é ação manual do proprietário. A Vercel serve frontend/site/painel e funções HTTP; não hospeda o servidor Godot ENet/UDP.
- **Opções consideradas:**
  1. Agentes configuram GitHub/Vercel (exige credenciais e autorização específica).
  2. Proprietário conecta manualmente as contas; agentes só documentam.
- **Escolha:** Opção 2.
- **Consequências:** Nenhum projeto Vercel, deploy, push ou token é criado/registrado por agentes na E0. O servidor Godot e o PostgreSQL ficam em infraestrutura separada.
- **Responsável/aprovação:** Proprietário do projeto; aprovação pendente.

---

## DEC-0003 — Câmera top-down: ortográfica inclinada como padrão (E1)
- **Data:** 2026-10-31
- **Status:** PROPOSTA — aguarda aprovação visual do proprietário (gate do E1)
- **Contexto:** O E1 exige comparar câmera ortográfica inclinada e perspectiva de baixa distorção e aprovar câmera, escala e unidade de mundo antes de produzir assets.
- **Opções consideradas:**
  1. Ortográfica, yaw 45°, pitch 50°, tamanho 14.
  2. Perspectiva de baixa distorção, FOV 28.
- **Escolha provisória:** Opção 1 como padrão; F3 alterna para a opção 2 na arena de teste.
- **Consequências:** Unidade de mundo 1 = 1 m, personagem ~1,8 m. A comparação NÃO foi observada visualmente pelos agentes (execução headless); a escolha final depende de o proprietário testar no editor.
- **Responsável/aprovação:** Proprietário do projeto; aprovação pendente.

---

## DEC-0004 — Multiplayer: servidor autoritativo por input, protocolo v1 (E3)
- **Data:** 2026-10-31
- **Status:** PROPOSTA — aguarda revisão humana do protocolo (roadmap/AGENTS)
- **Contexto:** E3 exige dois clientes na mesma sessão com validação server-side.
- **Opções consideradas:** (1) cliente envia posição e servidor valida; (2) cliente envia só input e o servidor simula.
- **Escolha provisória:** opção 2 (`shared/contracts/network_protocol.md`), ENet, tick 30 Hz, snapshots 15 Hz.
- **Consequências:** o cliente nunca decide posição/dano; predição local simples com reconciliação. Valores de tick/snapshot ainda não medidos em CPU/banda.
- **Responsável/aprovação:** Proprietário do projeto; aprovação pendente.

---

## DEC-0005 — Backend em Node.js/TypeScript; API deployável como Vercel Functions; PostgreSQL externo (E4)
- **Data:** 2026-10-31
- **Status:** APROVADA pelo proprietário (linguagem); hospedagem do banco pendente
- **Contexto:** A arquitetura previa Go como decisão provisória e exige registrar a escolha antes de implementar autenticação. O addendum Vercel permite API HTTP em Functions, mas mantém PostgreSQL em serviço externo e o servidor Godot (ENet/UDP) fora da Vercel.
- **Opções consideradas:** Go; Node/TypeScript; Python/FastAPI.
- **Escolha:** Node.js 22 + TypeScript (proprietário escolheu). API em handlers Web-standard (`Request` → `Response`), adaptáveis a Vercel Functions e a servidor Node local.
- **Banco:** PostgreSQL. Em dev/teste: PGlite (Postgres em WASM, dentro da pasta do projeto, sem instalar nada no sistema). Produção/staging: Postgres gerenciado (ex.: Neon via Marketplace da Vercel) conectado manualmente pelo proprietário via `DATABASE_URL` (segredo, fora do repositório).
- **Consequências:** mesmas migrações SQL numeradas em todos os ambientes; `node_modules` nativo é por plataforma (rodar `npm ci` no Windows). Nenhum deploy, conta ou segredo é criado por agentes.
- **Responsável/aprovação:** Proprietário do projeto.
