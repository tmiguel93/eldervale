import { createApp } from "../src/http/app.ts";
import { createLogger } from "../src/http/logger.ts";
import { registerPartiesRoutes } from "../src/parties/routes.ts";
import { registerSessionsRoutes } from "../src/sessions/routes.ts";
import { DEFAULT_SESSIONS_OPTIONS, type SessionsOptions } from "../src/sessions/service.ts";
import { DEFAULT_PARTIES_OPTIONS, type PartiesOptions } from "../src/parties/service.ts";
import { freshDb, mkAccount, mkCharacter, testConfig } from "./helpers.ts";

export const T0 = Date.parse("2026-01-01T00:00:00Z");

export interface CallOpts { token?: string; body?: unknown; internal?: boolean; secret?: string }

/** App completo (rotas de party + sessoes) com relogio injetado e verificador de teste ("acct:<uuid>"). */
export async function setup(over: { sessions?: Partial<SessionsOptions>; parties?: Partial<PartiesOptions>; env?: Record<string, string> } = {}) {
  const db = await freshDb();
  const config = testConfig(over.env);
  const clock = { t: T0 };
  const lines: string[] = [];
  const app = createApp({
    config,
    db,
    log: createLogger({ level: "debug", sink: (l) => lines.push(l) }),
    now: () => clock.t,
    authVerifier: async (tok) => (tok.startsWith("acct:") ? { accountId: tok.slice(5) } : null),
    register: (r, d) => {
      registerPartiesRoutes(r, d, { ...DEFAULT_PARTIES_OPTIONS, ...over.parties });
      registerSessionsRoutes(r, d, { ...DEFAULT_SESSIONS_OPTIONS, ticketRateCapacity: 1000, listRateCapacity: 1000, heartbeatTimeoutSeconds: 3600, ...over.sessions });
    },
  });
  async function call(method: string, path: string, o: CallOpts = {}) {
    const headers: Record<string, string> = {};
    if (o.token) headers.authorization = `Bearer ${o.token}`;
    if (o.internal) headers.authorization = `Bearer ${o.secret ?? config.gameSessionInternalSecret}`;
    let body: string | undefined;
    if (o.body !== undefined) {
      headers["content-type"] = "application/json";
      body = JSON.stringify(o.body);
    }
    const res = await app.handle(new Request(`http://t${path}`, { method, headers, body }));
    const text = await res.text();
    let json: any;
    try { json = JSON.parse(text); } catch { json = text; }
    return { status: res.status as number, json, headers: res.headers };
  }
  let n = 0;
  const user = async () => {
    n++;
    const account = await mkAccount(db, `u${n}@example.com`);
    const char = await mkCharacter(db, account, `Hero${n}x`);
    return { account, char, token: `acct:${account}` };
  };
  const extraChar = (account: string) => mkCharacter(db, account, `Alt${++n}x`);
  const advance = (ms: number) => { clock.t += ms; };
  return { db, config, clock, lines, call, user, extraChar, advance };
}
export type Harness = Awaited<ReturnType<typeof setup>>;

export const REG = { region: "sa-east", capacity: 4, protocol_version: 1, endpoint: "127.0.0.1:7777" };
