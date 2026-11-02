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
  /** Confia no cabecalho de IP do proxy (so ative atras de proxy confiavel que o sobrescreve). Em production TRUST_PROXY e obrigatorio (M2). */
  trustProxy: boolean;
  /** Cabecalho de IP confiavel (padrao x-real-ip; x-forwarded-for usa TRUSTED_PROXY_HOPS contados do fim) (M3). */
  proxyIpHeader: string;
  trustedProxyHops: number;
  /** Exige `X-Session-Key` (derivada da sessao registrada) nas rotas /internal ligadas a sessao (M5). Padrao: ligado em production. */
  requireSessionKey: boolean;
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

  const tp = env.TRUST_PROXY?.trim().toLowerCase();
  if (tp !== undefined && tp !== "" && tp !== "true" && tp !== "false") throw new ConfigError("TRUST_PROXY deve ser true ou false");
  if (isProduction && !tp) throw new ConfigError("TRUST_PROXY deve ser definido (true|false) em production");
  const proxyIpHeader = (env.PROXY_IP_HEADER?.trim().toLowerCase() || "x-real-ip");
  if (!/^[a-z0-9-]{1,64}$/.test(proxyIpHeader)) throw new ConfigError("PROXY_IP_HEADER invalido");
  const rsk = env.REQUIRE_SESSION_KEY?.trim().toLowerCase();
  if (rsk !== undefined && rsk !== "" && rsk !== "true" && rsk !== "false") throw new ConfigError("REQUIRE_SESSION_KEY deve ser true ou false");
  const requireSessionKey = rsk ? rsk === "true" : isProduction;
  if (isProduction && !requireSessionKey) throw new ConfigError("REQUIRE_SESSION_KEY=false nao e permitido em production");

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
    trustProxy: tp === "true",
    proxyIpHeader,
    trustedProxyHops: intVar(env, "TRUSTED_PROXY_HOPS", 1, 1, 10),
    requireSessionKey,
    logLevel: level,
    ephemeralSecrets,
  };
}
