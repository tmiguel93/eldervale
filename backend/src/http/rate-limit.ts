import { isIP } from "node:net";

/**
 * Token bucket em memoria, por chave (ex.: "login:ip:1.2.3.4" ou "acct:<id>").
 * LIMITE: o estado vive no processo. Em Vercel Functions (varias instancias, sem estado) ele
 * so reduz abuso por instancia; limite global exige store compartilhado (decisao futura).
 */
export interface RateLimitResult {
  allowed: boolean;
  remaining: number;
  /** Ms ate haver tokens suficientes (0 se permitido). */
  retryAfterMs: number;
}

export interface RateLimiterOptions {
  /** Rajada maxima. */
  capacity: number;
  /** Tokens repostos por segundo. */
  refillPerSecond: number;
  /** Maximo de chaves rastreadas (evita crescimento ilimitado). */
  maxKeys?: number;
  now?: () => number;
}

export class RateLimiter {
  private readonly buckets = new Map<string, { tokens: number; last: number }>();
  private readonly capacity: number;
  private readonly refill: number;
  private readonly maxKeys: number;
  private readonly now: () => number;

  constructor(opts: RateLimiterOptions) {
    if (opts.capacity <= 0 || opts.refillPerSecond <= 0) throw new Error("RateLimiter: capacity e refillPerSecond devem ser > 0");
    this.capacity = opts.capacity;
    this.refill = opts.refillPerSecond;
    this.maxKeys = opts.maxKeys ?? 10_000;
    this.now = opts.now ?? Date.now;
  }

  take(key: string, cost = 1): RateLimitResult {
    const t = this.now();
    let b = this.buckets.get(key);
    if (!b) {
      if (this.buckets.size >= this.maxKeys) this.evict(t);
      b = { tokens: this.capacity, last: t };
      this.buckets.set(key, b);
    } else {
      b.tokens = Math.min(this.capacity, b.tokens + ((t - b.last) / 1000) * this.refill);
      b.last = t;
      // Reinsere para manter ordem de uso recente (Map preserva insercao).
      this.buckets.delete(key);
      this.buckets.set(key, b);
    }
    if (b.tokens >= cost) {
      b.tokens -= cost;
      return { allowed: true, remaining: Math.floor(b.tokens), retryAfterMs: 0 };
    }
    return { allowed: false, remaining: 0, retryAfterMs: Math.ceil(((cost - b.tokens) / this.refill) * 1000) };
  }

  /** Consulta sem consumir: ha pelo menos 1 token na chave? (chave desconhecida = sim) */
  wouldAllow(key: string): boolean {
    const b = this.buckets.get(key);
    if (!b) return true;
    return Math.min(this.capacity, b.tokens + ((this.now() - b.last) / 1000) * this.refill) >= 1;
  }

  get size(): number {
    return this.buckets.size;
  }

  private evict(t: number): void {
    // Remove buckets ja cheios (equivalentes a ausentes); se ainda cheio, descarta o menos recente.
    for (const [k, b] of this.buckets) {
      if (b.tokens + ((t - b.last) / 1000) * this.refill >= this.capacity) this.buckets.delete(k);
    }
    while (this.buckets.size >= this.maxKeys) {
      const oldest = this.buckets.keys().next().value;
      if (oldest === undefined) break;
      this.buckets.delete(oldest);
    }
  }
}

/** Cabecalho de IP confiavel e numero de proxies confiaveis (M3). */
export interface ProxyTrust {
  /** Nome do cabecalho (minusculo) que o proxy confiavel SOBRESCREVE. */
  header: string;
  /** So para `x-forwarded-for`: quantos proxies confiaveis anexam; usa-se o item `hops` a partir do FIM. */
  hops: number;
}
export const DEFAULT_PROXY_TRUST: ProxyTrust = { header: "x-real-ip", hops: 1 };

/** Normaliza IP para chave de limite: ::ffff:a.b.c.d vira IPv4; IPv6 agrupa por /64 (atacante com um /64 nao rotaciona). */
export function normalizeIp(ip: string): string {
  const v4mapped = /^::ffff:(\d{1,3}(?:\.\d{1,3}){3})$/i.exec(ip);
  if (v4mapped && isIP(v4mapped[1]!) === 4) return v4mapped[1]!;
  if (isIP(ip) === 6) {
    // Expande abreviacao "::" e mantem os 4 primeiros grupos (/64).
    const [head = "", tail = ""] = ip.toLowerCase().split("::");
    const h = head ? head.split(":") : [];
    const t = tail ? tail.split(":") : [];
    const groups = ip.includes("::") ? [...h, ...Array(Math.max(0, 8 - h.length - t.length)).fill("0"), ...t] : h;
    return groups.slice(0, 4).map((g) => g.replace(/^0+(?=.)/, "")).join(":") + "::/64";
  }
  return ip;
}

/**
 * IP do cliente para chaves de rate limit. NUNCA confia em cabecalho sem `trust` (M2/M3).
 * `true` = cabecalho `x-real-ip` (o proxy confiavel precisa sobrescreve-lo). `x-forwarded-for` so e lido se configurado
 * explicitamente e entao usa o item `hops` contado a partir do FIM (o que o PROPRIO proxy anexou), nunca o primeiro (forjavel).
 * Valor ausente ou que nao seja um IP valido => "unknown".
 */
export function clientIp(req: Request, trust: boolean | ProxyTrust): string {
  if (trust === false) return "unknown";
  const t = trust === true ? DEFAULT_PROXY_TRUST : trust;
  const raw = req.headers.get(t.header);
  if (!raw || raw.length > 512) return "unknown";
  let cand: string | undefined;
  if (t.header === "x-forwarded-for") {
    const parts = raw.split(",").map((x) => x.trim()).filter(Boolean);
    cand = parts[parts.length - Math.max(1, t.hops)];
  } else {
    cand = raw.trim();
  }
  return cand && isIP(cand) !== 0 ? normalizeIp(cand) : "unknown";
}
