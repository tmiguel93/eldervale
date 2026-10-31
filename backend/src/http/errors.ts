/** Erro de API com status e codigo estavel (`{ error: { code, message } }`). */
export class ApiError extends Error {
  readonly status: number;
  readonly code: string;
  readonly headers: Record<string, string> | undefined;
  constructor(status: number, code: string, message: string, headers?: Record<string, string>) {
    super(message);
    this.name = "ApiError";
    this.status = status;
    this.code = code;
    this.headers = headers;
  }
}

export const Errors = {
  badRequest: (message = "Requisicao invalida", code = "bad_request") => new ApiError(400, code, message),
  unauthorized: (message = "Autenticacao necessaria") =>
    new ApiError(401, "unauthorized", message, { "www-authenticate": "Bearer" }),
  forbidden: (message = "Acesso negado") => new ApiError(403, "forbidden", message),
  notFound: (message = "Recurso nao encontrado") => new ApiError(404, "not_found", message),
  conflict: (message = "Conflito", code = "conflict") => new ApiError(409, code, message),
  tooManyRequests: (retryAfterSeconds: number) =>
    new ApiError(429, "rate_limited", "Muitas requisicoes", { "retry-after": String(Math.max(1, Math.ceil(retryAfterSeconds))) }),
};
