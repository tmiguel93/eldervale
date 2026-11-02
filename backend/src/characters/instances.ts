import type { Catalog, CatalogItem } from "./catalog.ts";

/** E6.3: instancia de item (raridade + affixes rolados pelo servidor de jogo). A base e o `item_id` da entrada do inventario. */
export interface ItemInstance {
  uid: string;
  rarity: string;
  ilvl: number;
  affixes: { id: string; tier: number; value: number }[];
}

export const MAX_INSTANCE_BYTES = 512;
const UID_RE = /^[0-9a-f]{16}$/;
const EPS = 1e-6;
const isObj = (v: unknown): v is Record<string, unknown> => typeof v === "object" && v !== null && !Array.isArray(v);

/**
 * Valida UMA instancia contra o catalogo (espelha ItemRules.validate_instance do jogo). Devolve a forma canonica ou lanca Error com o
 * motivo (os chamadores convertem em 400/422). Regras: so equipavel nao-unico; raridade existente e nao Comum; ilvl 1..ilvl_max;
 * n de affixes dentro da raridade; affix existente, permitido no slot, grupo nao repetido, tier liberado pelo ilvl, valor dentro da
 * faixa do tier; prefixos/sufixos dentro do limite; soma dos custos <= orcamento da raridade; JSON <= MAX_INSTANCE_BYTES.
 */
export function parseInstance(raw: unknown, base: CatalogItem, catalog: Catalog): ItemInstance {
  const rules = catalog.rules;
  if (!rules) throw new Error("catalogo sem regras de raridade");
  if (!isObj(raw)) throw new Error("instancia deve ser um objeto");
  for (const k of Object.keys(raw)) if (!["uid", "rarity", "ilvl", "affixes"].includes(k)) throw new Error(`campo desconhecido "${k.slice(0, 40)}" na instancia`);
  if (base.slot === "none") throw new Error("base nao equipavel");
  if (rules.isUnique(base.id)) throw new Error("item unico nao leva instancia");
  if (typeof raw.uid !== "string" || !UID_RE.test(raw.uid)) throw new Error("uid invalido");
  if (typeof raw.rarity !== "string") throw new Error("rarity invalida");
  const rar = rules.rarity(raw.rarity);
  if (!rar || rar.id === "common") throw new Error("rarity invalida");
  if (typeof raw.ilvl !== "number" || !Number.isSafeInteger(raw.ilvl) || raw.ilvl < 1 || raw.ilvl > rules.ilvlMax) throw new Error("ilvl fora de faixa");
  if (!Array.isArray(raw.affixes)) throw new Error("affixes deve ser lista");
  const n = raw.affixes.length;
  if (n < rar.affix_min || n > rar.affix_max || n > rules.maxAffixes) throw new Error("numero de affixes fora da raridade");
  const groups = new Set<string>();
  let pre = 0, suf = 0, cost = 0;
  const affixes: ItemInstance["affixes"] = [];
  for (const a of raw.affixes as unknown[]) {
    if (!isObj(a)) throw new Error("affix invalido");
    for (const k of Object.keys(a)) if (!["id", "tier", "value"].includes(k)) throw new Error(`campo desconhecido "${k.slice(0, 40)}" no affix`);
    if (typeof a.id !== "string") throw new Error("affix.id invalido");
    const def = rules.affix(a.id);
    if (!def) throw new Error("affix desconhecido");
    if (!def.slots.includes(base.slot)) throw new Error("affix nao permitido no slot");
    if (groups.has(def.group)) throw new Error("affix repetido (mesmo grupo)");
    groups.add(def.group);
    if (typeof a.tier !== "number" || !Number.isSafeInteger(a.tier)) throw new Error("tier invalido");
    const t = def.tiers.find((x) => x.tier === a.tier);
    if (!t) throw new Error("tier inexistente");
    if (raw.ilvl < t.ilvl_min) throw new Error("tier acima do ilvl");
    if (typeof a.value !== "number" || !Number.isFinite(a.value)) throw new Error("valor invalido");
    if (a.value < t.min - EPS || a.value > t.max + EPS) throw new Error("valor fora da faixa do tier");
    if (def.kind === "prefix") pre++; else suf++;
    cost += t.cost;
    affixes.push({ id: def.id, tier: t.tier, value: a.value });
  }
  if (pre > rar.prefix_max || suf > rar.suffix_max) throw new Error("prefixos/sufixos acima do limite da raridade");
  if (cost > rar.budget) throw new Error("orcamento da raridade excedido");
  const out: ItemInstance = { uid: raw.uid, rarity: rar.id, ilvl: raw.ilvl, affixes };
  if (JSON.stringify(out).length > MAX_INSTANCE_BYTES) throw new Error("instancia grande demais");
  return out;
}

/** Igualdade de instancias (valores com tolerancia de arredondamento do JSON). */
export function sameInstance(a: ItemInstance, b: ItemInstance): boolean {
  if (a.uid !== b.uid || a.rarity !== b.rarity || a.ilvl !== b.ilvl || a.affixes.length !== b.affixes.length) return false;
  return a.affixes.every((x, i) => x.id === b.affixes[i]!.id && x.tier === b.affixes[i]!.tier && Math.abs(x.value - b.affixes[i]!.value) < EPS);
}
