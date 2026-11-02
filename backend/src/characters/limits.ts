/** Limites configuraveis do modulo de personagens. Defaults documentados em docs/E4_CHARACTERS.md. */
export interface CharacterLimits {
  maxCharactersPerAccount: number;
  inventoryCapacity: number;
  /** Maximo de XP que um checkpoint pode somar em relacao ao estado persistido. */
  checkpointMaxXpGain: number;
  /** Maximo de unidades de UM item_id que um checkpoint pode somar (inventario+equipado). */
  checkpointMaxItemGain: number;
  /** Maximo de XP por request de recompensa. */
  rewardMaxXp: number;
  /** Maximo de linhas de item por request de recompensa. */
  rewardMaxItems: number;
  /** Maximo de qty por linha de item. */
  rewardMaxQty: number;
  /** M5: janela (s) do orcamento de XP por recompensa. */
  rewardXpWindowSeconds: number;
  /** M5: XP total que recompensas podem pagar a UM personagem dentro da janela (freia servidor comprometido; legitimo: chefe 1200). */
  rewardXpPerWindow: number;
  /** M5: teto relativo de stats: cada stat <= max(persistido, base_da_classe * (1 + pct/100 * (nivel-1)) + folga). */
  statCapPercentPerLevel: number;
  /** Maximo de quests ativas por personagem (E5.1). */
  maxActiveQuests: number;
}

export const DEFAULT_LIMITS: CharacterLimits = {
  maxCharactersPerAccount: 5,
  inventoryCapacity: 24,
  checkpointMaxXpGain: 100_000,
  checkpointMaxItemGain: 500,
  rewardMaxXp: 1_000_000,
  rewardMaxItems: 20,
  rewardMaxQty: 999,
  rewardXpWindowSeconds: 60,
  rewardXpPerWindow: 20_000,
  statCapPercentPerLevel: 10,
  maxActiveQuests: 10,
};

const ENV_MAP: Record<string, [keyof CharacterLimits, number, number]> = {
  CHARACTER_MAX_PER_ACCOUNT: ["maxCharactersPerAccount", 1, 50],
  CHARACTER_INVENTORY_CAPACITY: ["inventoryCapacity", 1, 200],
  CHARACTER_CHECKPOINT_MAX_XP_GAIN: ["checkpointMaxXpGain", 0, 1_000_000_000],
  CHARACTER_CHECKPOINT_MAX_ITEM_GAIN: ["checkpointMaxItemGain", 0, 100_000],
  CHARACTER_REWARD_XP_PER_WINDOW: ["rewardXpPerWindow", 0, 1_000_000_000],
  CHARACTER_REWARD_XP_WINDOW_SECONDS: ["rewardXpWindowSeconds", 1, 86_400],
  CHARACTER_STAT_CAP_PERCENT_PER_LEVEL: ["statCapPercentPerLevel", 0, 1000],
  CHARACTER_MAX_ACTIVE_QUESTS: ["maxActiveQuests", 1, 50],
};

export function loadCharacterLimits(env: Record<string, string | undefined> = process.env, over: Partial<CharacterLimits> = {}): CharacterLimits {
  const out: CharacterLimits = { ...DEFAULT_LIMITS };
  for (const [name, [key, min, max]] of Object.entries(ENV_MAP)) {
    const raw = env[name]?.trim();
    if (!raw) continue;
    if (!/^\d+$/.test(raw) || Number(raw) < min || Number(raw) > max) throw new Error(`${name} invalido (${min}..${max})`);
    out[key] = Number(raw);
  }
  return { ...out, ...over };
}
