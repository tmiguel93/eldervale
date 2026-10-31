import { Errors } from "../http/errors.ts";

export const PASSWORD_MIN = 10;
export const PASSWORD_MAX = 128;
export const EMAIL_MAX = 254;

/** Normalizacao identica a coluna: trim + minusculas (ASCII apenas; ver validateEmail). */
export function normalizeEmail(raw: string): string {
  return raw.trim().toLowerCase();
}

const isAlnum = (c: number) => (c >= 48 && c <= 57) || (c >= 97 && c <= 122);
// Caracteres permitidos na parte local (RFC 5322 "atext" + ponto), sem aspas/comentarios.
const LOCAL_EXTRA = "!#$%&'*+/=?^_`{|}~-.";

/**
 * Valida (ja normalizado, ASCII). Varredura linear, sem regex: sem risco de backtracking.
 * Nao aceita IDN/Unicode, aspas, comentarios nem IP literal (limitacao documentada).
 */
export function isValidEmail(email: string): boolean {
  if (email.length < 3 || email.length > EMAIL_MAX) return false;
  const at = email.indexOf("@");
  if (at < 1 || at !== email.lastIndexOf("@")) return false;
  const local = email.slice(0, at);
  const domain = email.slice(at + 1);
  if (local.length > 64 || local.startsWith(".") || local.endsWith(".") || local.includes("..")) return false;
  for (let i = 0; i < local.length; i++) {
    const c = local.charCodeAt(i);
    if (!isAlnum(c) && !LOCAL_EXTRA.includes(local[i]!)) return false;
  }
  const labels = domain.split(".");
  if (labels.length < 2) return false;
  for (const l of labels) {
    if (l.length < 1 || l.length > 63 || l.startsWith("-") || l.endsWith("-")) return false;
    for (let i = 0; i < l.length; i++) {
      const c = l.charCodeAt(i);
      if (!isAlnum(c) && c !== 45) return false;
    }
  }
  const tld = labels[labels.length - 1]!;
  return tld.length >= 2 && !/^\d+$/.test(tld);
}

function asObject(body: unknown): Record<string, unknown> {
  if (typeof body !== "object" || body === null || Array.isArray(body)) {
    throw Errors.badRequest("Corpo deve ser um objeto JSON", "invalid_body");
  }
  return body as Record<string, unknown>;
}

/** E-mail do corpo, normalizado e validado. */
export function readEmail(body: unknown): string {
  const v = asObject(body).email;
  if (typeof v !== "string" || v.length > 1024) throw Errors.badRequest("E-mail invalido", "invalid_email");
  const email = normalizeEmail(v);
  if (!isValidEmail(email)) throw Errors.badRequest("E-mail invalido", "invalid_email");
  return email;
}

/** Senha de LOGIN: so tipo/tamanho (a politica vale no registro; senhas antigas continuam logando). */
export function readLoginPassword(body: unknown): string {
  const v = asObject(body).password;
  if (typeof v !== "string" || v.length === 0 || v.length > 1024) throw Errors.badRequest("Senha invalida", "invalid_password");
  return v;
}

/** Politica de registro: 10..128 caracteres, diferente do e-mail. Sem regras de composicao (NIST 800-63B). */
export function readNewPassword(body: unknown, email: string): string {
  const v = asObject(body).password;
  if (typeof v !== "string") throw Errors.badRequest("Senha invalida", "invalid_password");
  const len = [...v].length;
  if (len < PASSWORD_MIN || len > PASSWORD_MAX) {
    throw Errors.badRequest(`Senha deve ter entre ${PASSWORD_MIN} e ${PASSWORD_MAX} caracteres`, "weak_password");
  }
  if (v.trim().toLowerCase() === email) throw Errors.badRequest("Senha nao pode ser igual ao e-mail", "weak_password");
  return v;
}

const REFRESH_RE = /^[A-Za-z0-9_-]{43}$/;
export function readRefreshToken(body: unknown): string {
  const v = asObject(body).refresh_token;
  // Formato invalido e tratado como 400 (nao revela nada sobre tokens reais).
  if (typeof v !== "string" || !REFRESH_RE.test(v)) throw Errors.badRequest("refresh_token invalido", "invalid_refresh_token");
  return v;
}
