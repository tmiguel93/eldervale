import { randomBytes } from "node:crypto";

export type NodeEnv = "development" | "test" | "production";

export interface Config {
  nodeEnv: NodeEnv;
  isProduction: boolean;
  port: number;
  /** Ausente fora de producao => PGlite. */
  databaseUrl: string | undefined;
  /** Segredo de assinatura dos JWT de acesso/join-ticket (M2). */
  authSecret: string;
  /** Segredo servico-a-servico entre servidor Godot e /internal/* (M3/M4). */
  gameSessionInternalSecret: string;
  accessTokenTtlSeconds: number;
  refreshTokenTtlSeconds: number;
  joinTicketTtlSeconds: number;
  reconnectWindowSeconds: number;
  maxBodyBytes: number;
  /** Confia em x-real-ip (so ative atras de proxy confiavel, ex.: Vercel). */
  trustProxy: boolean;
  logLevel: "debug" | "info" | "warn" | "error";
  /** true se algum segredo foi gerado em memoria (nunca em producao). */
  ephemeralSecrets: boolean;
}

export class ConfigError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ConfigError";
  }
}

const MIN_SECRET_LENGTH = 32;
type Env = Record<string, string | undefined>;

function intVar(env: Env, name: string, def: number, min: number, max: number): number {
  const raw = env[name]?.trim();
  if (!raw) return def;
  if (!/^\d+$/.test(raw)) throw new ConfigError(`${name} deve ser um inteiro`);
  const n = Number(raw);
  if (n < min || n > max) throw new ConfigError(`${name} fora do intervalo ${min}..${max}`);
  return n;
}

/** Valida o ambiente. Nunca inclui valores de segredos nas mensagens de erro. */
export function loadConfig(env: Env = process.env): Config {
  const rawEnv = (env.NODE_ENV?.trim() || "development") as string;
  if (rawEnv !== "development" && rawEnv !== "test" && rawEnv !== "production") {
    throw new ConfigError("NODE_ENV deve ser development, test ou production");
  }
  const nodeEnv: NodeEnv = rawEnv;
  const isProduction = nodeEnv === "production";

  const databaseUrl = env.DATABASE_URL?.trim() || undefined;
  if (isProduction && !databaseUrl) throw new ConfigError("DATABASE_URL e obrigatoria em production");

  let ephemeralSecrets = false;
  const secret = (name: string): string => {
    const v = env[name]?.trim();
    if (v) {
      if (v.length < MIN_SECRET_LENGTH) {
        if (isProduction) throw new ConfigError(`${name} deve ter ao menos ${MIN_SECRET_LENGTH} caracteres`);
        // Fora de producao um segredo curto e aceito (dev), mas avisado pelo chamador via config.
      }
      return v;
    }
    if (isProduction) throw new ConfigError(`${name} e obrigatorio em production`);
    ephemeralSecrets = true;
    return randomBytes(48).toString("base64url"); // so em memoria; reinicio invalida tokens
  };

  const authSecret = secret("AUTH_SECRET");
  const gameSessionInternalSecret = secret("GAME_SESSION_INTERNAL_SECRET");
  if (isProduction && authSecret === gameSessionInternalSecret) {
    throw new ConfigError("AUTH_SECRET e GAME_SESSION_INTERNAL_SECRET devem ser diferentes");
  }

  const level = (env.LOG_LEVEL?.trim() || (nodeEnv === "test" ? "error" : "info")) as Config["logLevel"];
  if (!["debug", "info", "warn", "error"].includes(level)) throw new ConfigError("LOG_LEVEL invalido");

  return {
    nodeEnv,
    isProduction,
    port: intVar(env, "PORT", 8787, 1, 65535),
    databaseUrl,
    authSecret,
    gameSessionInternalSecret,
    accessTokenTtlSeconds: intVar(env, "ACCESS_TOKEN_TTL_SECONDS", 900, 30, 86_400),
    refreshTokenTtlSeconds: intVar(env, "REFRESH_TOKEN_TTL_SECONDS", 30 * 86_400, 60, 365 * 86_400),
    joinTicketTtlSeconds: intVar(env, "JOIN_TICKET_TTL_SECONDS", 60, 5, 600),
    reconnectWindowSeconds: intVar(env, "RECONNECT_WINDOW_SECONDS", 90, 10, 600),
    maxBodyBytes: intVar(env, "MAX_BODY_BYTES", 64 * 1024, 1024, 1024 * 1024),
    trustProxy: env.TRUST_PROXY?.trim().toLowerCase() === "true",
    logLevel: level,
    ephemeralSecrets,
  };
}
