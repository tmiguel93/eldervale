import type { Logger } from "./logger.ts";

/** Identidade autenticada. M2 pode estender via `claims`. */
export interface AuthPrincipal {
  accountId: string;
  claims?: Record<string, unknown>;
}

/**
 * Verificador injetado (implementacao real: M2 em auth/verifier.ts).
 * Recebe o bearer token CRU; devolve a identidade ou null se invalido/expirado/conta desativada.
 * Nao deve lancar para token invalido (lance apenas para falhas de infraestrutura).
 */
export type AuthVerifier = (token: string, req: Request) => Promise<AuthPrincipal | null>;

export interface RequestContext {
  req: Request;
  url: URL;
  /** Parametros do caminho, ex.: "/v1/characters/:id" => params.id. */
  params: Record<string, string>;
  requestId: string;
  log: Logger;
  /** Preenchido por requireAuth. */
  auth?: AuthPrincipal;
  /** Le o corpo como JSON com limite de tamanho. Lanca ApiError 400/413. Cache de uma leitura. */
  json<T = unknown>(): Promise<T>;
}

export type Handler = (ctx: RequestContext) => Promise<Response> | Response;
/** Handler que exige auth; `ctx.auth` garantido. */
export type AuthedContext = RequestContext & { auth: AuthPrincipal };
export type AuthedHandler = (ctx: AuthedContext) => Promise<Response> | Response;
