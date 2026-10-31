/** Curva de XP espelhando scripts/progression/character_progress.gd: xp(L->L+1) = round(100 * L^1.5), nivel max 50. */
export const MAX_LEVEL = 50;
const XP_BASE = 100;
const XP_EXPONENT = 1.5;

export function xpToNext(level: number): number {
  if (level >= MAX_LEVEL) return 0;
  return Math.round(XP_BASE * Math.pow(Math.max(level, 1), XP_EXPONENT));
}

// CUM[L] = XP total necessario para ATINGIR o nivel L (L=1 => 0).
const CUM: number[] = [0, 0];
for (let l = 1; l < MAX_LEVEL; l++) CUM[l + 1] = CUM[l]! + xpToNext(l);

export function totalXpForLevel(level: number): number {
  return CUM[Math.min(Math.max(level, 1), MAX_LEVEL)]!;
}

/** XP total maximo (saturado no nivel maximo). */
export const MAX_TOTAL_XP = totalXpForLevel(MAX_LEVEL);

export function levelForXp(xp: number): number {
  let l = 1;
  while (l < MAX_LEVEL && xp >= CUM[l + 1]!) l++;
  return l;
}

/** Soma XP (ignora <= 0), satura em MAX_TOTAL_XP e devolve o novo estado. */
export function applyXp(xp: number, amount: number): { xp: number; level: number } {
  const next = amount > 0 ? Math.min(xp + amount, MAX_TOTAL_XP) : xp;
  return { xp: next, level: levelForXp(next) };
}
