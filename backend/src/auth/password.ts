import { randomBytes, scrypt, timingSafeEqual } from "node:crypto";

/**
 * Hash de senha: scrypt (node:crypto), salt aleatorio de 16 bytes por usuario.
 * Formato versionado (campos separados por "$", binarios em base64url sem padding):
 *
 *   scrypt$1$<log2N>$<r>$<p>$<salt>$<hash>
 *
 * Padrao v1: N=2^15 (32768), r=8, p=1, saida de 32 bytes (~32 MiB de memoria, dezenas de ms).
 * Os parametros ficam no proprio hash, entao subir o custo (ou trocar de algoritmo, nova versao)
 * nao invalida hashes antigos: `passwordNeedsRehash` indica quando regravar apos um login valido.
 */
export interface ScryptParams {
  logN: number;
  r: number;
  p: number;
}

export const DEFAULT_SCRYPT_PARAMS: Readonly<ScryptParams> = Object.freeze({ logN: 15, r: 8, p: 1 });
const KEY_LEN = 32;
const SALT_LEN = 16;
/** Teto aceito ao VERIFICAR (um hash vindo do banco nao pode forcar custo arbitrario). */
const MAX_LOG_N = 17;
const MAX_R = 16;
const MAX_P = 4;

function derive(password: string, salt: Buffer, params: ScryptParams, keyLen: number): Promise<Buffer> {
  const N = 2 ** params.logN;
  return new Promise((resolve, reject) => {
    scrypt(
      password,
      salt,
      keyLen,
      { N, r: params.r, p: params.p, maxmem: 256 * N * params.r + 128 * params.r * params.p + (1 << 20) },
      (err, key) => (err ? reject(err) : resolve(key)),
    );
  });
}

export async function hashPassword(password: string, params: ScryptParams = DEFAULT_SCRYPT_PARAMS): Promise<string> {
  const salt = randomBytes(SALT_LEN);
  const key = await derive(password, salt, params, KEY_LEN);
  return `scrypt$1$${params.logN}$${params.r}$${params.p}$${salt.toString("base64url")}$${key.toString("base64url")}`;
}

interface Parsed {
  params: ScryptParams;
  salt: Buffer;
  key: Buffer;
}

function parse(stored: string): Parsed | null {
  if (typeof stored !== "string" || stored.length > 512) return null;
  const parts = stored.split("$");
  if (parts.length !== 7 || parts[0] !== "scrypt" || parts[1] !== "1") return null;
  const logN = Number(parts[2]);
  const r = Number(parts[3]);
  const p = Number(parts[4]);
  if (!Number.isInteger(logN) || logN < 10 || logN > MAX_LOG_N) return null;
  if (!Number.isInteger(r) || r < 1 || r > MAX_R) return null;
  if (!Number.isInteger(p) || p < 1 || p > MAX_P) return null;
  const salt = Buffer.from(parts[5]!, "base64url");
  const key = Buffer.from(parts[6]!, "base64url");
  if (salt.length < 8 || key.length < 16 || key.length > 64) return null;
  return { params: { logN, r, p }, salt, key };
}

/** Compara em tempo constante. Hash malformado => false (nunca lanca por dado ruim). */
export async function verifyPassword(password: string, stored: string): Promise<boolean> {
  const parsed = parse(stored);
  if (!parsed) return false;
  const key = await derive(password, parsed.salt, parsed.params, parsed.key.length);
  return key.length === parsed.key.length && timingSafeEqual(key, parsed.key);
}

export function passwordNeedsRehash(stored: string, target: ScryptParams = DEFAULT_SCRYPT_PARAMS): boolean {
  const parsed = parse(stored);
  if (!parsed) return true;
  const p = parsed.params;
  return p.logN < target.logN || p.r < target.r || p.p < target.p || parsed.key.length !== KEY_LEN;
}

let dummy: Promise<string> | undefined;
/** Hash descartavel (senha aleatoria) para igualar o custo quando a conta nao existe. */
export function dummyPasswordHash(): Promise<string> {
  return (dummy ??= hashPassword(randomBytes(24).toString("base64url")));
}
