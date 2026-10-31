import type { Handler } from "./context.ts";

export type Method = "GET" | "POST" | "PUT" | "PATCH" | "DELETE";

interface Route {
  method: Method;
  segments: string[];
  handler: Handler;
}

export type MatchResult =
  | { kind: "match"; handler: Handler; params: Record<string, string> }
  | { kind: "method_not_allowed"; allow: Method[] }
  | { kind: "not_found" };

/**
 * Router simples: metodo + caminho com parametros (`/v1/characters/:id`). Sem regex, sem wildcard.
 * Primeira rota registrada que casa vence; segmentos literais devem ser registrados antes de parametros se conflitarem.
 */
export class Router {
  private readonly routes: Route[] = [];

  add(method: Method, path: string, handler: Handler): this {
    if (!path.startsWith("/")) throw new Error(`Rota deve comecar com "/": ${path}`);
    this.routes.push({ method, segments: split(path), handler });
    return this;
  }
  get = (path: string, h: Handler) => this.add("GET", path, h);
  post = (path: string, h: Handler) => this.add("POST", path, h);
  put = (path: string, h: Handler) => this.add("PUT", path, h);
  patch = (path: string, h: Handler) => this.add("PATCH", path, h);
  delete = (path: string, h: Handler) => this.add("DELETE", path, h);

  match(method: string, pathname: string): MatchResult {
    const parts = split(pathname);
    const allow = new Set<Method>();
    for (const r of this.routes) {
      const params = matchSegments(r.segments, parts);
      if (!params) continue;
      if (r.method === method) return { kind: "match", handler: r.handler, params };
      allow.add(r.method);
    }
    if (allow.size > 0) return { kind: "method_not_allowed", allow: [...allow] };
    return { kind: "not_found" };
  }
}

function split(path: string): string[] {
  return path.split("/").filter((s) => s.length > 0);
}

function matchSegments(pattern: string[], actual: string[]): Record<string, string> | null {
  if (pattern.length !== actual.length) return null;
  const params: Record<string, string> = {};
  for (let i = 0; i < pattern.length; i++) {
    const p = pattern[i]!;
    const a = actual[i]!;
    if (p.startsWith(":")) {
      let decoded: string;
      try {
        decoded = decodeURIComponent(a);
      } catch {
        return null;
      }
      params[p.slice(1)] = decoded;
    } else if (p !== a) return null;
  }
  return params;
}
