# E6 — Gate de fechamento (E6.5)

Estado: validação **automatizada** concluída; **playtest humano pendente** (seção 6). Legenda: **OK** = coberto por teste/execução citada; **parcial** = coberto só em parte (limite explicado); **não verificado** = não exercitado.

Tudo abaixo vem de execuções reais nesta VM (Linux, Godot 4.7.2 headless, backend Node com PGlite em memória). Nada foi inferido. Detalhes de balanceamento, métricas e exploits: [`docs/E6_BALANCE.md`](E6_BALANCE.md).

## 1. O que o E6.5 acrescentou
- **Simulador de balanceamento** headless e determinístico (`tools/balance/`, faixas-alvo em `data/balance/balance_config.json`): DPS efetivo, TTK, sobrevivência, uso de habilidades/pontos, builds, escada de raridade, únicos, talentos, curva de XP por fonte e taxas de drop por raridade. 67 critérios; medidos antes e depois (`docs/balance/e6_before.json`, `e6_after.json`).
- **Ajustes só em dados** (lista em `E6_BALANCE.md` seção 4): dos 67 critérios, 9 reprovavam com os dados originais e nenhum reprova depois. Stats de classe, curva de XP e saves não mudaram.
- **Telemetria essencial** do servidor (`ServerMetrics`, linha de log `[metrics]` a cada `--metrics-interval`, padrão 60 s, e no desligamento), sem PII/segredos.
- **Suíte de exploits/anti-duplicação**: `backend/test/exploits.test.ts` (20 testes, backend real) e `tests/e6_balance/test_exploits.gd` (14 verificações, servidor Godot).
- Guardas de compatibilidade: `tests/e6_balance/test_balance_data.gd` (stats persistidos congelados).

## 2. Critérios de aceite do roadmap (E6)
| Critério | Status | Evidência |
|---|---|---|
| Builds diferentes têm decisões e resultados distintos | **OK** (modelo) / **parcial** (sensação) | Simulador: 5 builds por classe (nível 10 e 20) diferem em DPS e índice de poder; nenhuma build inútil nem obrigatória pelos critérios C2/C2b/C2c/C2d (R4). Pior caso conhecido: `hunter_rain` (índice 103,4 contra 117,9-127,8 das outras do arqueiro). Que as escolhas "pareçam" diferentes: **não verificado** (playtest). |
| Itens não quebram fórmulas nem persistência | **OK** | `tests/e6_items` 253 checks; backend `items.test.ts` 16 e `exploits.test.ts` 20 (uid duplicado, checkpoint forjado/alterado); `e6_items_integration.py items` OK com reconexão (instância equipada volta; revision só avança); `test_balance_data.gd` congela os stats persistidos. |
| Conteúdo é carregado por dados validados | **OK** | `node tools/validate_content.mjs`: 0 erros; geradores `--check` em dia (items, classes, talents, quests, recipes); `content_validation.test.ts` 10 (negativos). A configuração de balanceamento tem teste próprio (janelas ordenadas, builds alocam sem nó desconhecido). |
| Quests e recompensas são reproduzíveis em testes | **OK** | `tests/e5_quests` 414, `tests/e6_quests` 301, backend `quests.test.ts` 20 + `exploration.test.ts` 11; integração `adventure` OK (3 quests, replay `replayed=true`, corpo diferente 400). |
| Não existem exploits óbvios de duplicação | **OK** com lacunas listadas | `exploits.test.ts`: replay de recompensa, chave nova/forjada, paralelismo, uid duplicado/forjado, equipar×craft×checkpoint×recompensa simultâneos, replay e excesso de `talent_cmd`, descoberta repetida. Lacunas em `E6_BALANCE.md` seção 8 (uid global entre personagens depende da origem; sem multi-processo real). |

### Itens de tarefa do roadmap (E6)
| Tarefa | Status | Nota |
|---|---|---|
| Expandir a classe protótipo / outras duas classes | **OK** | Guerreiro, Mago, Patrulheiro (`tests/e6_classes` 693 checks). |
| Especializações iniciais | **parcial** | Uma implementada por classe (berserker, elementalist, hunter); as demais estão marcadas `planned` em `classes.json`. |
| Árvore de talentos / modificadores de habilidade | **OK** | 15 nós por classe; `tests/e6_talents` 275 + backend `talents.test.ts` 13. |
| Raridades e affixes / 3–5 únicos de teste | **OK** | 6 raridades, 5 únicos; números ajustados no E6.5. |
| Crafting básico | **OK** | E5.4 + integração `adventure` (craft concluído no servidor). |
| Quests 10–15 / exploração e segredos | **OK** | 12 quests, 9 pontos de exploração; arco do Greenwood = nível 8 no modelo. |
| Balanceamento de XP/dano/loot | **OK** (modelo) / **parcial** (jogo real) | Simulador + ajustes em dados; valores finais dependem de playtest. |
| Ferramenta de validação de conteúdo | **OK** | `tools/validate_content.mjs` (E6.4). |
| Medir distribuição de builds e uso de habilidades | **OK** (simulado + telemetria) / **não verificado** (jogadores reais) | `skill_use`, `talents`, `equips`, `kills`, `drops_*` no log `[metrics]`; coleta e agregação são manuais (stdout do servidor). |

## 3. Cenários de falha / exploits (backend real e servidor Godot)
| Cenário | Resultado | Evidência |
|---|---|---|
| Replay de recompensa (mesma chave, corpo adulterado, chave nova, 8 em paralelo) | **OK** (nada duplica) | `exploits.test.ts` exploit 1; `adventure` (replay + corpo diferente). |
| Duplicação de instância por uid / checkpoint forjado | **OK** | `exploits.test.ts` exploit 2 (409 `duplicate_instance`, 422 no forjado). |
| Equipar + craftar + checkpoint + recompensa simultâneos | **OK** | exploit 3 (3 rodadas; cada uid no máximo uma vez) e `test_exploits.gd` (`busy`). |
| Replay e excesso de `talent_cmd` | **OK** | exploit 4; `test_exploits.gd` (12 rodadas, gasto ≤ pontos). |
| Descoberta repetida | **OK** | exploit 5; `test_exploits.gd` (entrar/sair 4x = 1 pagamento). |
| Coleta duplicada do mesmo drop | **OK** | `test_exploits.gd`: pickup some do mundo; replay da chave loot x2 não altera o inventário. |
| Segredos em logs (inclui as novas linhas `[metrics]`) | **OK** | `test_telemetry.gd` (sem ticket, id de personagem, nome, e-mail); todos os cenários de integração varrem os logs. |
| `ERROR` nos logs do servidor | **OK** | `happy`, `adventure` e `items` sem `ERROR`. |

## 4. Balanceamento: resumo medido (nível 5, sem talentos, equipamento Comum)
| Métrica | Guerreiro | Mago | Patrulheiro |
|---|---|---|---|
| DPS contra o chefe antes -> depois | 37,4 -> 37,3 | 39,7 -> 39,0 | 28,9 -> 29,6 |
| TTK do chefe, 1 jogador (s) antes -> depois | 32,0 -> 48,3 | 30,2 -> 46,1 | 41,5 -> 60,8 |
| TTK do chefe, 4 jogadores (s) antes -> depois | 26,0 -> 39,1 | 24,7 -> 37,4 | 33,6 -> 49,1 |

Chefe: Lendário+ a cada 1,7 -> 6,3 abates; Épico+ 0,8 -> 1,5; Místico 9,5 -> 177,3. Únicos: 3,3-5,0 -> 8,3-16,7 abates da melhor fonte. Inimigo comum (pior caso): Raro+ 4,17% -> 1,66% por abate; Épico+ 1,19% -> 0,48%. Maior ganho de DPS de um único: 70,0% -> 28,4% (limite 30%). Tabelas completas em `E6_BALANCE.md`.

## 5. Riscos conhecidos (E6.5)
- **Faixas-alvo são propostas** (DEC-0026) e o modelo é relativo: não mede movimento, telégrafos, adds, kiting nem sensação. Os números são ponto de partida para playtest, não valores finais.
- Margem pequena em dois critérios: emberfang no patrulheiro +28,4% (limite 30%) e Épico+ de inimigo comum 0,475% (limite 0,5%). Mudanças futuras nesses dados exigem reexecutar o simulador (o teste `test_balance_sim.gd` falha se violarem).
- Algumas fórmulas de critério foram refinadas depois de ver resultados ruidosos (`E6_BALANCE.md` seção 3); as faixas de balanceamento não foram afrouxadas, mas a definição final dos critérios foi do agente.
- Instâncias de únicos já guardadas em saves passam a valer os números novos (mais fracos). Sem saves de produção; aceitável, mas precisa de ciência do proprietário (DEC-0027).
- Telemetria: contadores zeram a cada reinício e só existem no log do processo; sem agregação entre servidores nem retenção. A linha final só sai em desligamento limpo (num SIGKILL fica o último snapshot periódico).
- Talentos de utilidade (vida, recurso, velocidade, controle) são subvalorizados pelo modelo: 23 dos 45 nós não têm efeito de DPS medido.
- Unicidade global de `uid` entre personagens depende de só o servidor de sessão emitir instâncias, não de constraint no banco.
- Execução: o teste `migrate.test.ts` passa seus 5 testes, mas o `afterAll` falha com `EPERM` ao apagar `backend/.data/test-tmp` (a VM bloqueia `rm`); é artefato do ambiente, igual ao baseline. `content_validation.test.ts` leva ~83 s.

## 6. Depende de playtest humano
- Sensação de dificuldade e duração do chefe sem knobs de teste (alvo: 40-120 s com 1 jogador no modelo; a luta real inclui fases, telégrafos e adds).
- Se as classes "parecem" equilibradas e se as builds oferecem decisões percebidas (principalmente `hunter_rain` e builds de utilidade).
- Ritmo de level-up e de drops por hora (o modelo conta uma ocorrência de cada fonte).
- Valor percebido de únicos e raridades; se "raro" é raro e "alcançável" é alcançável na frequência real de abates.
- Usabilidade da UI de talentos/equipamento (E6.2/E6.3) em cliente gráfico (nunca visto em cliente gráfico neste projeto).

## 7. Pendências para o E7
- Agregar/persistir telemetria (coleta do log, painel) e definir retenção; decidir se vale um endpoint protegido no backend.
- Rodar playtest com a lista da seção 6 e revisar `data/balance/balance_config.json` e os dados ajustados; reexecutar o simulador a cada mudança.
- Constraint ou verificação global de `uid` de instância; teste de concorrência com múltiplos processos do backend e banco real.
- Especializações `planned` (invocador, arcanista, etc.) e valorização de talentos de utilidade no modelo.
- Teste de carga/latência real com 4 jogadores e os snapshots compactos; hardening listado no roadmap E7.
- Revisar `.tools` e o `rm` bloqueado: o `afterAll` de `migrate.test.ts` precisa de diretório temporário removível (ou limpeza fora da VM).

## 8. Como reproduzir
```
node tools/validate_content.mjs
export npm_config_cache=$PWD/.tools/npm-cache
cd backend && npx tsc --noEmit && npx vitest run test/<arquivo>.test.ts      # um arquivo por vez
godot --headless --path . --script res://tests/run_tests.gd -- --only=tests/<pasta>/   # por pasta
godot --headless --path . --script res://tools/balance/balance_sim.gd -- --label=after --out=docs/balance/e6_after.json
python3 tools/balance/balance_report.py docs/balance/e6_before.json docs/balance/e6_after.json
python3 tools/e4_integration.py happy
python3 tools/e5_adventure_integration.py adventure
python3 tools/e6_items_integration.py items
```

## 9. Resultados da execução final (E6.5)
- `node tools/validate_content.mjs`: **OK (0 erros)**; `gen_{items,classes,talents,quests,recipes}_catalog.mjs --check`: em dia.
- `npx tsc --noEmit` (backend): sem erros.
- Backend (vitest, por arquivo): auth 23, characters 68, classes 16, constraints 9, content_validation 10, crafting 21, **exploits 20 (novo)**, exploration 11, http 10, items 16, migrate 5 (+ `EPERM` no `afterAll`, ambiente), misc 9, parties 9, quests 20, security_review 17, sessions 24, talents 13 — **todos passaram, 0 falharam**.
- Godot, por pasta: e1 34, e2 357, e3 334, e4 258, e5 317, e5_gate 59, e5_loot 172, e5_quests 414, e5_snapshot 208, e5_ui 251, e5_world 206, e6_classes 693, e6_talents 275, e6_items 253 (assert do emberfang ajustado), e6_quests 301, **e6_balance 82 (novo: telemetria 26, dados congelados 16, simulador 26, exploits 14)** — **4214 passaram, 0 falharam** (baseline 4132 + 82).
- Integração: e4 `happy` OK (47 s), `e5_adventure_integration.py adventure` OK (83 s, sem flake no passo `farm:scrap`), `e6_items_integration.py items` OK (76 s). O log do servidor da `adventure` trouxe a linha real `[metrics]` (60 s: 9 usos de `warrior.basic_attack`, 8 abates, 3 quests concluídas, 1 craft, `dropped_keys` 0).
- Simulador completo: `criterios: 67, falhas: 0` (depois); 9 falhas com os dados originais (antes).
