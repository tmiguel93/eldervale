-- 0004_character_class_default
-- E6.1: classes jogaveis (warrior, mage, ranger). A coluna `characters.class_id text NOT NULL` ja existe desde a 0001; esta migracao
-- a torna segura para o catalogo de classes sem mudar o formato de saves (schema_version continua 1):
--   1. backfill: valores de class_id FORA do formato de id estavel (nao ocorrem pela API, que so aceita ids do catalogo) viram 'warrior';
--      ids bem formados (inclusive de classes futuras/removidas) NAO sao tocados. A validacao contra o catalogo de classes
--      (shared/content_schemas/classes.json) e feita na aplicacao: o conjunto de classes cresce sem nova migracao.
--   2. DEFAULT 'warrior': personagens/linhas criados sem class_id (codigo antigo, fixtures) ficam como guerreiro.
--   3. CHECK de formato (id estavel `[a-z][a-z0-9_]{0,47}`), adicionado de forma idempotente.
-- Aditiva e idempotente: reexecutar nao altera nada (UPDATE sem linhas, SET DEFAULT repetivel, constraint so se ausente).
UPDATE characters SET class_id = 'warrior' WHERE class_id !~ '^[a-z][a-z0-9_]{0,47}$';

ALTER TABLE characters ALTER COLUMN class_id SET DEFAULT 'warrior';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'characters_class_id_format' AND conrelid = 'characters'::regclass
  ) THEN
    ALTER TABLE characters ADD CONSTRAINT characters_class_id_format CHECK (class_id ~ '^[a-z][a-z0-9_]{0,47}$');
  END IF;
END
$$;
