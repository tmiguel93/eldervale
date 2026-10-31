import { Errors } from "../http/errors.ts";

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export const isUuid = (v: unknown): v is string => typeof v === "string" && UUID_RE.test(v);

/** Valida um uuid vindo de caminho/corpo. 400 `invalid_id` (nunca ecoa o valor). */
export function uuid(v: unknown, field: string): string {
  if (!isUuid(v)) throw Errors.badRequest(`Campo invalido: ${field}`, "invalid_id");
  return v.toLowerCase();
}

/** Corpo precisa ser um objeto JSON simples. */
export function bodyObject(v: unknown): Record<string, unknown> {
  if (typeof v !== "object" || v === null || Array.isArray(v)) throw Errors.badRequest("Corpo deve ser um objeto JSON", "validation_error");
  return v as Record<string, unknown>;
}

export function intField(v: unknown, field: string, min: number, max: number): number {
  if (typeof v !== "number" || !Number.isInteger(v) || v < min || v > max) {
    throw Errors.badRequest(`Campo invalido: ${field}`, "validation_error");
  }
  return v;
}

export function strField(v: unknown, field: string, re: RegExp, maxLen: number): string {
  if (typeof v !== "string" || v.length === 0 || v.length > maxLen || !re.test(v)) {
    throw Errors.badRequest(`Campo invalido: ${field}`, "validation_error");
  }
  return v;
}

/** timestamptz volta como Date (PGlite/pg) ou string; normaliza para ISO-8601. */
export function iso(v: unknown): string {
  return (v instanceof Date ? v : new Date(String(v))).toISOString();
}

export const toIso = (ms: number): string => new Date(ms).toISOString();
