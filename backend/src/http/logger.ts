/**
 * Logger estruturado (JSON por linha). NUNCA registra tokens, senhas, segredos ou e-mails completos:
 * a redacao e aplicada recursivamente a todos os campos antes de escrever.
 */
export type LogLevel = "debug" | "info" | "warn" | "error";
const ORDER: Record<LogLevel, number> = { debug: 10, info: 20, warn: 30, error: 40 };

export interface Logger {
  debug(msg: string, fields?: Record<string, unknown>): void;
  info(msg: string, fields?: Record<string, unknown>): void;
  warn(msg: string, fields?: Record<string, unknown>): void;
  error(msg: string, fields?: Record<string, unknown>): void;
  child(fields: Record<string, unknown>): Logger;
}

const SENSITIVE_KEY = /pass(word|wd)?|secret|token|authorization|cookie|credential|api[-_]?key|private|jwt|signature|hash|database_?url/i;
const EMAIL_KEY = /e-?mail/i;
const EMAIL_RE = /[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/g;
const JWT_RE = /\beyJ[A-Za-z0-9_-]{5,}\.[A-Za-z0-9_-]{5,}\.[A-Za-z0-9_-]*/g;
const BEARER_RE = /\bBearer\s+[A-Za-z0-9._~+/=-]+/gi;
const URL_CREDS_RE = /([a-z][a-z0-9+.-]*:\/\/)[^\s/@:]+:[^\s/@]+@/gi;

export const REDACTED = "[REDACTED]";

export function maskEmail(email: string): string {
  const at = email.indexOf("@");
  if (at < 1) return "***";
  const domain = email.slice(at + 1);
  const dot = domain.lastIndexOf(".");
  const tld = dot >= 0 ? domain.slice(dot) : "";
  return `${email[0]}***@${domain[0] ?? ""}***${tld}`;
}

export function redactString(s: string): string {
  return s
    .replace(URL_CREDS_RE, `$1${REDACTED}@`)
    .replace(BEARER_RE, `Bearer ${REDACTED}`)
    .replace(JWT_RE, REDACTED)
    .replace(EMAIL_RE, (m) => maskEmail(m));
}

export function redact(value: unknown, key = "", depth = 0): unknown {
  if (SENSITIVE_KEY.test(key)) return REDACTED;
  if (typeof value === "string") return EMAIL_KEY.test(key) ? maskEmail(value) : redactString(value);
  if (value === null || typeof value !== "object") return typeof value === "bigint" ? value.toString() : value;
  if (depth >= 6) return "[depth]";
  if (value instanceof Error) return { name: value.name, message: redactString(value.message) };
  if (Array.isArray(value)) return value.slice(0, 50).map((v) => redact(v, key, depth + 1));
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(value as Record<string, unknown>)) out[k] = redact(v, k, depth + 1);
  return out;
}

export type LogSink = (line: string) => void;

export function createLogger(opts: { level?: LogLevel; sink?: LogSink; base?: Record<string, unknown> } = {}): Logger {
  const min = ORDER[opts.level ?? "info"];
  const sink: LogSink = opts.sink ?? ((line) => process.stdout.write(line + "\n"));
  const base = opts.base ?? {};
  const emit = (level: LogLevel, msg: string, fields?: Record<string, unknown>) => {
    if (ORDER[level] < min) return;
    const rec = redact({ ...base, ...fields }) as Record<string, unknown>;
    sink(JSON.stringify({ time: new Date().toISOString(), level, msg: redactString(msg), ...rec }));
  };
  return {
    debug: (m, f) => emit("debug", m, f),
    info: (m, f) => emit("info", m, f),
    warn: (m, f) => emit("warn", m, f),
    error: (m, f) => emit("error", m, f),
    child: (fields) => createLogger({ level: opts.level, sink, base: { ...base, ...fields } }),
  };
}
