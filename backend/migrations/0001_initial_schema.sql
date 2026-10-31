-- 0001_initial_schema
-- Esquema completo usado por M2 (auth), M3 (personagens/inventario/recompensas)
-- e M4 (party/sessoes). PostgreSQL 14+ / PGlite. Sem BEGIN/COMMIT aqui: o runner
-- aplica cada arquivo dentro de uma transacao.
--
-- Convencoes:
--  * IDs: uuid gerado pela aplicacao OU por gen_random_uuid() (default).
--  * Timestamps: timestamptz, UTC. updated_at/revision sao mantidos pela aplicacao
--    (sem triggers, para ficar explicito e testavel).
--  * FKs usam o default NO ACTION (restritivo): nada e apagado em cascata.
--    Remocao de contas/personagens e logica (disabled / deleted_at).
--  * Indices so existem para consultas previstas, citadas em comentario.

-- ---------------------------------------------------------------- accounts
CREATE TABLE accounts (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  -- Decisao: o e-mail e armazenado JA normalizado (trim + lower-case) pela aplicacao.
  -- O CHECK impede gravar valor nao normalizado, tornando UNIQUE case-insensitive.
  email         text NOT NULL,
  -- Formato do hash definido por M2 (ex.: "scrypt$N$r$p$salt$hash"). Nunca texto puro.
  password_hash text NOT NULL,
  created_at    timestamptz NOT NULL DEFAULT now(),
  disabled      boolean NOT NULL DEFAULT false,
  CONSTRAINT accounts_email_normalized CHECK (email = lower(btrim(email)) AND length(email) BETWEEN 3 AND 254),
  CONSTRAINT accounts_email_key UNIQUE (email)
);

-- ---------------------------------------------------------- refresh_tokens
CREATE TABLE refresh_tokens (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id  uuid NOT NULL REFERENCES accounts(id),
  -- Apenas o HASH (ex.: sha256 hex) do token e guardado; o token em si nunca.
  token_hash  text NOT NULL,
  expires_at  timestamptz NOT NULL,
  revoked_at  timestamptz,
  -- Rotacao: token que substituiu este. Reuso de um token ja substituido = sinal de roubo
  -- (M2 revoga a cadeia). Sem FK para permitir limpeza independente de linhas antigas.
  replaced_by uuid,
  created_at  timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT refresh_tokens_token_hash_key UNIQUE (token_hash)
);
-- Consulta: revogar/listar todos os tokens de uma conta (logout geral, conta desativada).
CREATE INDEX refresh_tokens_account_idx ON refresh_tokens (account_id);

-- -------------------------------------------------------------- characters
CREATE TABLE characters (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id     uuid NOT NULL REFERENCES accounts(id),
  name           text NOT NULL,
  class_id       text NOT NULL,
  level          integer NOT NULL DEFAULT 1 CHECK (level >= 1),
  -- bigint: o driver pg devolve int8 como string; a camada Db padroniza string em ambos os drivers.
  xp             bigint NOT NULL DEFAULT 0 CHECK (xp >= 0),
  stats          jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(stats) = 'object'),
  -- Versao do formato de `stats`/saves (AGENTS 2.12: compatibilidade de saves).
  schema_version integer NOT NULL DEFAULT 1 CHECK (schema_version >= 1),
  -- Controle otimista de concorrencia: UPDATE ... WHERE id=$1 AND revision=$2 SET revision=revision+1.
  revision       bigint NOT NULL DEFAULT 0,
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now(),
  -- Soft delete: preserva historico e permite reaproveitar o nome (ver indice parcial abaixo).
  deleted_at     timestamptz,
  CONSTRAINT characters_name_len CHECK (length(btrim(name)) BETWEEN 2 AND 24 AND name = btrim(name))
);
-- Unicidade do nome case-insensitive, global (nome unico no servidor), apenas entre nao apagados.
CREATE UNIQUE INDEX characters_name_lower_uniq ON characters (lower(name)) WHERE deleted_at IS NULL;
-- Consulta: GET /v1/characters (personagens ativos da conta).
CREATE INDEX characters_account_idx ON characters (account_id) WHERE deleted_at IS NULL;

-- ------------------------------------------------------ character_inventory
CREATE TABLE character_inventory (
  character_id uuid NOT NULL REFERENCES characters(id),
  slot         integer NOT NULL CHECK (slot >= 0),
  item_id      text NOT NULL,   -- ID estavel de item data-driven (ex.: "item.potion_small")
  qty          integer NOT NULL CHECK (qty > 0),  -- slot vazio = linha inexistente
  PRIMARY KEY (character_id, slot)
);

CREATE TABLE character_equipment (
  character_id uuid NOT NULL REFERENCES characters(id),
  slot_name    text NOT NULL,   -- ex.: "weapon", "head"
  item_id      text NOT NULL,
  PRIMARY KEY (character_id, slot_name)
);

-- ----------------------------------------------------------- reward_claims
-- Idempotencia de recompensas (AGENTS 7): a PK (character_id, idempotency_key) faz a segunda
-- tentativa falhar com unique_violation (ou INSERT ... ON CONFLICT DO NOTHING) na MESMA
-- transacao que aplica a recompensa. `payload` guarda o que foi concedido (auditoria/resposta repetida).
CREATE TABLE reward_claims (
  character_id    uuid NOT NULL REFERENCES characters(id),
  idempotency_key text NOT NULL CHECK (length(idempotency_key) BETWEEN 8 AND 128),
  payload         jsonb NOT NULL,
  created_at      timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (character_id, idempotency_key)
);

-- ----------------------------------------------------------------- parties
CREATE TABLE parties (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  leader_account_id uuid NOT NULL REFERENCES accounts(id),
  created_at        timestamptz NOT NULL DEFAULT now(),
  disbanded_at      timestamptz
);
-- Consulta: party ativa de um lider.
CREATE INDEX parties_leader_active_idx ON parties (leader_account_id) WHERE disbanded_at IS NULL;

-- LIMITE DE 4 MEMBROS: NAO e garantido por constraint (CHECK nao enxerga outras linhas).
-- Regra para M4: dentro de uma transacao, `SELECT ... FROM parties WHERE id=$1 FOR UPDATE`
-- (serializa entradas na mesma party), contar membros e so entao inserir se count < 4.
CREATE TABLE party_members (
  party_id     uuid NOT NULL REFERENCES parties(id),
  character_id uuid NOT NULL REFERENCES characters(id),
  joined_at    timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (party_id, character_id)
);
-- Decisao: um personagem pertence a no maximo UMA party por vez. Ao sair/dissolver, a linha
-- e removida (o historico fica em parties.disbanded_at, nao em party_members).
CREATE UNIQUE INDEX party_members_character_uniq ON party_members (character_id);

CREATE TABLE party_invites (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  party_id            uuid NOT NULL REFERENCES parties(id),
  target_character_id uuid NOT NULL REFERENCES characters(id),
  status              text NOT NULL DEFAULT 'pending'
                      CHECK (status IN ('pending','accepted','declined','expired','revoked')),
  expires_at          timestamptz NOT NULL,
  created_at          timestamptz NOT NULL DEFAULT now()
);
-- No maximo um convite pendente por (party, alvo): evita spam de convites.
CREATE UNIQUE INDEX party_invites_pending_uniq ON party_invites (party_id, target_character_id) WHERE status = 'pending';
-- Consulta: convites pendentes recebidos por um personagem.
CREATE INDEX party_invites_target_pending_idx ON party_invites (target_character_id) WHERE status = 'pending';

-- ----------------------------------------------------------- game_sessions
CREATE TABLE game_sessions (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  region           text NOT NULL,
  status           text NOT NULL DEFAULT 'starting'
                   CHECK (status IN ('starting','open','full','closing','closed')),
  capacity         integer NOT NULL CHECK (capacity BETWEEN 1 AND 64),
  protocol_version integer NOT NULL CHECK (protocol_version >= 1),
  -- host:porta ENet do servidor Godot; NULL ate o servidor se registrar.
  endpoint         text,
  created_at       timestamptz NOT NULL DEFAULT now(),
  closed_at        timestamptz
);
-- Consulta: sessoes abertas por regiao (matchmaking).
CREATE INDEX game_sessions_open_idx ON game_sessions (region) WHERE closed_at IS NULL;

-- ------------------------------------------------------------ join_tickets
CREATE TABLE join_tickets (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  -- Hash do jti do JWT do ticket (nunca o ticket). UNIQUE + used_at => uso unico:
  -- UPDATE join_tickets SET used_at=now() WHERE jti_hash=$1 AND used_at IS NULL AND expires_at>now() RETURNING ...
  jti_hash     text NOT NULL,
  character_id uuid NOT NULL REFERENCES characters(id),
  session_id   uuid NOT NULL REFERENCES game_sessions(id),
  expires_at   timestamptz NOT NULL,
  used_at      timestamptz,
  created_at   timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT join_tickets_jti_hash_key UNIQUE (jti_hash)
);

-- --------------------------------------------------------- character_locks
-- UMA sessao ativa por personagem: a PK em character_id e a garantia. Adquirir = INSERT
-- (ou INSERT ... ON CONFLICT DO UPDATE ... WHERE lock vencido, na mesma transacao).
CREATE TABLE character_locks (
  character_id    uuid PRIMARY KEY REFERENCES characters(id),
  session_id      uuid NOT NULL REFERENCES game_sessions(id),
  acquired_at     timestamptz NOT NULL DEFAULT now(),
  heartbeat_at    timestamptz NOT NULL DEFAULT now(),
  -- Janela de reconexao: enquanto reconnect_until > now() o lock e mantido para o mesmo jogador.
  reconnect_until timestamptz
);
-- Consulta: liberar todos os locks de uma sessao encerrada.
CREATE INDEX character_locks_session_idx ON character_locks (session_id);
