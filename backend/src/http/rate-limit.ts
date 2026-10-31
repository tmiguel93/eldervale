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

/** IP do cliente para chaves de rate limit. So confia no cabecalho se `trustProxy`. */
export function clientIp(req: Request, trustProxy: boolean): string {
  if (!trustProxy) return "unknown";
  const ip = req.headers.get("x-real-ip")?.trim() || req.headers.get("x-forwarded-for")?.split(",")[0]?.trim();
  return ip && ip.length <= 64 ? ip : "unknown";
}
