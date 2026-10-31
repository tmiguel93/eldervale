export function json(status: number, data: unknown, headers?: Record<string, string>): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", ...headers },
  });
}

export const ok = (data: unknown) => json(200, data);
export const created = (data: unknown) => json(201, data);
export const noContent = () => new Response(null, { status: 204 });

export function errorBody(code: string, message: string) {
  return { error: { code, message } };
}

export const SECURITY_HEADERS: Record<string, string> = {
  "x-content-type-options": "nosniff",
  "x-frame-options": "DENY",
  "referrer-policy": "no-referrer",
  "cache-control": "no-store",
  "content-security-policy": "default-src 'none'; frame-ancestors 'none'",
  "strict-transport-security": "max-age=63072000; includeSubDomains",
  "cross-origin-resource-policy": "same-origin",
};
