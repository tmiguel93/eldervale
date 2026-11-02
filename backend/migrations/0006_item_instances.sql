-- 0006_item_instances
-- E6.3: instancias de item (raridade + affixes rolados no servidor de jogo). Uma instancia e um objeto JSON
--   {"uid": "<16 hex>", "rarity": "<id>", "ilvl": <int>, "affixes": [{"id": "<affix>", "tier": <int>, "value": <num>}]}
-- guardado AO LADO do item base (item_id continua a base; qty continua 1). Linhas sem `inst` (NULL) sao itens simples/Comum: todos os
-- saves existentes continuam validos e inalterados. As regras (raridade, faixas, orcamento) vivem em shared/content_schemas/items.json
-- e sao verificadas pela aplicacao (src/characters/instances.ts); o banco so garante a FORMA.
--
-- Decisoes:
--  * Colunas jsonb NULLable em character_inventory e character_equipment (nao tabela nova): a instancia pertence ao slot e e lida/gravada
--    junto do inventario sob o mesmo SELECT ... FOR UPDATE e a mesma `revision`.
--  * CHECK de tipo objeto (somente se ausente) e indice UNIQUE parcial por (character_id, uid) em cada tabela: o mesmo uid nao existe
--    duas vezes no inventario nem duas vezes no equipamento (a unicidade ENTRE as duas tabelas e checada pela aplicacao dentro da transacao).
--  * Idempotente: IF NOT EXISTS / DO $$ guardas; reexecutar o arquivo nao falha nem altera dados.
--  * Aditiva, sem backfill. O checkpoint nunca cria uid novo: so /rewards (loot:) cria instancias.
ALTER TABLE character_inventory ADD COLUMN IF NOT EXISTS inst jsonb;
ALTER TABLE character_equipment ADD COLUMN IF NOT EXISTS inst jsonb;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'character_inventory_inst_is_object' AND conrelid = 'character_inventory'::regclass) THEN
    ALTER TABLE character_inventory ADD CONSTRAINT character_inventory_inst_is_object CHECK (inst IS NULL OR jsonb_typeof(inst) = 'object');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'character_equipment_inst_is_object' AND conrelid = 'character_equipment'::regclass) THEN
    ALTER TABLE character_equipment ADD CONSTRAINT character_equipment_inst_is_object CHECK (inst IS NULL OR jsonb_typeof(inst) = 'object');
  END IF;
END
$$;

CREATE UNIQUE INDEX IF NOT EXISTS character_inventory_inst_uid_uniq ON character_inventory (character_id, (inst ->> 'uid')) WHERE inst IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS character_equipment_inst_uid_uniq ON character_equipment (character_id, (inst ->> 'uid')) WHERE inst IS NOT NULL;
