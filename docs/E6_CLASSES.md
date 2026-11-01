# E6.1 — Classes e habilidades (data-driven)

Escopo: roadmap E6 "Expandir a classe protótipo; implementar as outras duas classes em etapas; criar especializações iniciais". Esta etapa entrega as
3 classes jogáveis do GDD §6 com 4 habilidades funcionais cada e UMA especialização inicial por classe (as demais registradas como dado `planned`).
Decisões: DEC-0010 a DEC-0013 (`docs/DECISIONS.md`, propostas pendentes de revisão humana). Protocolo: `shared/contracts/network_protocol.md` (Extensão E6.1).

## Modelo de dados
`data/classes/<class_id>.json` (nome do arquivo = `class_id`; `schema_version` 1), lido por `ClassDef.parse` / `ClassCatalog` (Godot) e por
`tools/gen_classes_catalog.mjs` (que gera `shared/content_schemas/classes.json` para o backend):

| Campo | Significado |
|---|---|
| `id` | `class_id` estável `[a-z][a-z0-9_]{0,47}` |
| `display_name`, `description` | apresentação |
| `resource.kind` | `stamina` ou `mana` (usa o `ResourcePool` existente: `max_resource`/`resource_regen`) |
| `base_stats` | 7 stats do `StatBlock` (mesmos limites do backend); valem na CRIAÇÃO do personagem |
| `growth_per_level` | bônus por nível acima do 1 (`CharacterProgress.bonus_per_level`); stats finais = base + crescimento×(nível−1) + equipamento |
| `skills` | `attack`, `skill_1`, `skill_2`, `dodge` → id de `data/skills/*.tres` |
| `specializations` | `{id, display_name, tags, description, planned}`; `planned: true` = só registro, sem mecânica nem seleção |

Habilidades continuam `SkillData` (`.tres`); novos campos: `projectile_speed/range/pierce` e `tags`.

## Classes e habilidades
| Classe (`class_id`) | Recurso | Base (vida/rec./regen/atq.) | Habilidades (slot: id — custo, cooldown, tipo) | Especialização inicial | Planejadas |
|---|---|---|---|---|---|
| Guerreiro (`warrior`) | stamina | 100 / 50 / 5 / 10 | LMB `basic_attack` 0, 0,35 s melee · Q `heavy_strike` 15, 3 s melee ×2,5 · E `whirlwind` 25, 6 s área ao redor ×1,5 · Espaço `dodge` 10, 0,8 s esquiva 4 m | `berserker` | `guardian`, `arcane_knight` |
| Mago (`mage`) | mana | 80 / 100 / 6 / 13 | LMB `arcane_bolt` 0, 0,5 s projétil 20 m/s alc. 14 · Q `fireball` 20, 3,5 s projétil 15 m/s alc. 16 ×2,4 · E `frost_nova` 30, 8 s área r 3,4 ×1,6 · Espaço `blink` 15, 2,5 s deslocamento 7 m | `elementalist` | `summoner`, `arcanist` |
| Patrulheiro (`ranger`) | stamina | 90 / 70 / 8 / 11 | LMB `quick_shot` 0, 0,45 s projétil 26 m/s alc. 18 · Q `piercing_arrow` 18, 4 s projétil 30 m/s, perfura 2 alvos ×1,8 · E `arrow_rain` 28, 9 s área r 3 a 6 m ×1,7 · Espaço `roll` 10, 0,9 s esquiva 4,5 m | `hunter` | `explorer`, `arcane_archer` |

Valores de balanceamento são provisórios (nenhuma medição de DPS/uso nesta etapa). O guerreiro usa exatamente os stats base históricos do backend
(saves existentes não mudam); `move_speed` por classe existe no dado mas o `Player` ainda não o consome.

## Como adicionar/alterar uma classe ou habilidade
1. Criar/editar `data/skills/<id>.tres` e `data/classes/<id>.json`.
2. `node tools/gen_classes_catalog.mjs` (valida e regenera `shared/content_schemas/classes.json`; `--check` falha se desatualizado — coberto pelo teste do backend).
3. `godot --headless --path . --import` se criou `class_name` novo; rodar `tests/e6_classes`.
Regras validadas (Godot em `ClassCatalog.validate_refs`, Node no gerador): habilidade existe e é válida, slot `dodge` exige esquiva e os demais ataque,
ataque básico sem custo, habilidade pertence a UMA classe, especializações únicas entre classes e ao menos uma inicial (`planned: false`), classe padrão `warrior` presente.

## Autoridade do servidor
- `PlayerCombat.apply_class(def)` troca os 4 slots e restringe `try_use` aos ids da classe (`not_allowed`, sem custo/cooldown). Jogador sem classe (cena offline/testes antigos) segue sem restrição.
- `ServerWorld.add_player` aplica a classe padrão (`ServerSettings.default_class_id`, `--default-class <id>` só no servidor de desenvolvimento; padrão `warrior`; classe ≠ guerreiro usa os stats base da classe, guerreiro mantém os da cena).
- Com backend, `CharacterCodec.apply` lê `class_id` do personagem (ausente = `warrior`; desconhecido = `validate` recusa e a entrada é rejeitada), define stats base salvos e `PlayerLoadout.apply_class` aplica habilidades + crescimento da classe.
- O cliente só envia bits de ação (1/2/4/8, máscara 15 inalterada); o servidor resolve o bit pela classe. `s_class({class_id})` (só o dono) informa o HUD.
- `CharacterCodec.capture` NÃO inclui `class_id` (a classe é imutável e o backend rejeita campo desconhecido no estado).

## Backend
- Migração `backend/migrations/0004_character_class_default.sql` (aditiva, idempotente; rollback em `backend/migrations/README.md`): `DEFAULT 'warrior'`, CHECK de formato de id, normaliza só ids malformados.
- `backend/src/characters/classes.ts` (`createClassCatalog`/`loadClassCatalogFromDisk`); `validateClassId(raw, classes)`; `createCharacter` grava `stats` = `base_stats` da classe. `POST /v1/characters` aceita `warrior|mage|ranger` (`invalid_class` para o resto).

## Cliente
- `LoginScreen`: seletor de classe (OptionButton, código) na criação; a lista mostra `nome (Classe nv N)`. O backend valida de novo.
- `SkillBar` (`scripts/ui/client/skill_bar.gd`, Control criado só por `ClientUi`, nunca em bot/headless): classe, recurso e 4 habilidades com tecla/custo/cooldown, a partir do `s_class` do servidor e do catálogo local.
- Projéteis/áreas não têm apresentação no cliente (não são entidades do snapshot): só se vê o efeito (vida, números de dano).

## Testes
- Godot `tests/e6_classes/` (693 checks): `test_class_data` (carga, validação, referências cruzadas, payload inválido, paridade com `classes.json`), `test_class_stats` (stats por classe/nível, recurso, codec), `test_class_skills` (as 12 habilidades: custo, cooldown, estados, alcance, dano, projétil/perfuração/parede, áreas à distância, mobilidade), `test_class_authority` (habilidade de outra classe recusada, slots resolvidos no servidor via backend falso, `s_class`, `class_id` desconhecido, protocolo), `test_class_ui`.
- Backend `backend/test/classes.test.ts` (16): catálogo + gerador, migração do zero / da versão anterior / idempotência / rollback documentado, criação com `class_id` válido/ inválido, leitura e checkpoint preservando `class_id`. `migrate.test.ts` atualizado para 4 migrações (e o caso "migração ruim" passou a usar `0005_bad.sql`).
- Integração real: `python3 tools/e4_integration.py mage|ranger` (personagem de outra classe via API → servidor Godot → bot; `s_class` recebido, abate com a habilidade da classe, `class_id` intacto no backend), além de `happy` e `e5_adventure_integration.py adventure`.

## Limitações conhecidas
- 4 habilidades por classe (4 bits de ação); mais exigem novos bits aditivos.
- Especializações: só dado; sem escolha, persistência nem efeito.
- Sem troca de classe; sem nível mínimo por habilidade; sem apresentação de projéteis/áreas; `move_speed` de classe não aplicado ao movimento.
- Compatibilidade de um cliente/bot de build anterior com o RPC novo `s_class` não verificada (atualizar servidor e cliente juntos).
- `backend/test/migrate.test.ts` termina com `EPERM` no `afterAll` (limpeza do diretório temporário) quando a pasta do projeto bloqueia `unlink` (ambiente do agente); os 5 testes passam.
