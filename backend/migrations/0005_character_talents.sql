-- 0005_character_talents
-- E6.2: especializacao escolhida + talentos alocados por personagem. Formato (validado em src/talents/rules.ts, normalizado na leitura):
--   {"spec": "<spec_id>" | "", "ranks": {"<node_id>": <int 1..max_rank>}, "respecs": <int>}
-- A arvore (nos, custos, pre-requisitos) vem de shared/content_schemas/talents.json (gerado de data/talents/*.json) e a curva de
-- pontos por nivel do mesmo catalogo; nada disso entra no banco, so as escolhas do jogador.
--
-- Decisoes:
--  * Coluna jsonb unica em `characters` (e nao tabela nova), como `quests` (0003): estado pequeno (<= 40 nos), sempre lido/gravado
--    junto do personagem, sob o mesmo SELECT ... FOR UPDATE e a mesma `revision` (concorrencia otimista ja existente).
--  * NOT NULL DEFAULT '{}': personagens existentes ficam sem talentos (a aplicacao normaliza '{}' para spec "", ranks {}, respecs 0).
--    Migracao aditiva e sem backfill.
--  * CHECK de tipo objeto: o conteudo e validado na aplicacao (depende do catalogo de talentos e do nivel).
--  * Idempotente: coluna com IF NOT EXISTS e constraint so se ausente (reexecutar o arquivo nao falha nem altera dados).
--  * O checkpoint do servidor de jogo NAO grava esta coluna: so o endpoint /internal/characters/:id/talents (comandos validados).
ALTER TABLE characters ADD COLUMN IF NOT EXISTS talents jsonb NOT NULL DEFAULT '{}'::jsonb;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'characters_talents_is_object' AND conrelid = 'characters'::regclass
  ) THEN
    ALTER TABLE characters ADD CONSTRAINT characters_talents_is_object CHECK (jsonb_typeof(talents) = 'object');
  END IF;
END
$$;
