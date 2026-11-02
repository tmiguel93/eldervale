/**
 * Metricas operacionais em memoria (E7.1). Sem servico externo, sem PII: so contadores nomeados por categoria e latencias.
 * Estado por INSTANCIA (em serverless cada instancia tem o seu); o snapshot sai em `GET /internal/metrics` (segredo interno).
 */
const RING = 1024;

export interface MetricsSnapshot {
  uptime_s: number;
  requests_total: number;
  status: Record<string, number>;
  latency_ms: { count: number; p50: number; p95: number; max: number };
  counters: Record<string, number>;
}

export class Metrics {
  private readonly startedAt: number;
  private readonly counters = new Map<string, number>();
  private readonly ring: number[] = [];
  private ringPos = 0;
  private total = 0;

  constructor(private readonly now: () => number = Date.now) {
    this.startedAt = now();
  }

  inc(name: string, by = 1): void {
    if (this.counters.size >= 256 && !this.counters.has(name)) return; // teto de cardinalidade
    this.counters.set(name, (this.counters.get(name) ?? 0) + by);
  }

  observeRequest(status: number, durationMs: number): void {
    this.total++;
    this.inc(`status_${Math.floor(status / 100)}xx`);
    if (this.ring.length < RING) this.ring.push(durationMs);
    else {
      this.ring[this.ringPos] = durationMs;
      this.ringPos = (this.ringPos + 1) % RING;
    }
  }

  snapshot(): MetricsSnapshot {
    const sorted = [...this.ring].sort((a, b) => a - b);
    const pct = (p: number) => (sorted.length === 0 ? 0 : sorted[Math.min(sorted.length - 1, Math.floor(p * sorted.length))]!);
    const status: Record<string, number> = {};
    const counters: Record<string, number> = {};
    for (const [k, v] of this.counters) (k.startsWith("status_") ? status : counters)[k.startsWith("status_") ? k.slice(7) : k] = v;
    return {
      uptime_s: Math.floor((this.now() - this.startedAt) / 1000),
      requests_total: this.total,
      status,
      latency_ms: { count: sorted.length, p50: pct(0.5), p95: pct(0.95), max: sorted.length ? sorted[sorted.length - 1]! : 0 },
      counters,
    };
  }
}
