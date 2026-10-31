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
