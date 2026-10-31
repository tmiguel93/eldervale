// Servidor da API para o harness E2E (tools/e4_integration.py). Igual ao backend/src/dev-server.ts,
// mas o diretorio do PGlite vem de ELDERVALE_E4_DATA_DIR (temporario, dentro do projeto) em vez de
// backend/.data. Nao e usado em producao. Segredos vem so do ambiente (gerados pelo harness).
import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { Readable } from "node:stream";
import { buildApp } from "../backend/src/app.ts";
import { loadConfig } from "../backend/src/config.ts";
import { createLogger } from "../backend/src/http/logger.ts";
import { migrate } from "../backend/src/persistence/migrate.ts";
import { openDb } from "../backend/src/persistence/open.ts";


// PENDENCIA (M4): backend/src/sessions/service.ts ainda lista so o protocolo 1 e o servidor Godot agora
// fala o 2. Enquanto o backend nao for atualizado, este harness acrescenta o 2 EM MEMORIA (o array e
// compartilhado por referencia). Sem efeito no codigo do backend.

const T0 = Date.now();
const phase = (n: string) => console.error(`[e4_api] ${n} +${Date.now() - T0}ms`);
phase("imports");
const dataDir = process.env.ELDERVALE_E4_DATA_DIR;
if (!dataDir) {
  console.error("ELDERVALE_E4_DATA_DIR e obrigatorio");
  process.exit(1);
}
const config = loadConfig();
if (config.isProduction) {
  console.error("nao rode em production");
  process.exit(1);
}
const log = createLogger({ level: config.logLevel });
const db = await openDb(config, dataDir === "memory" ? undefined : dataDir);
phase("db aberto");
await migrate(db);
phase("migrado");
const app = buildApp({ config, db, log });

function toRequest(req: IncomingMessage): Request {
  const headers = new Headers();
  for (const [k, v] of Object.entries(req.headers)) {
    if (k === "x-real-ip") continue;
    if (Array.isArray(v)) v.forEach((x) => headers.append(k, x));
    else if (v !== undefined) headers.set(k, v);
  }
  headers.set("x-real-ip", req.socket.remoteAddress ?? "unknown");
  const method = req.method ?? "GET";
  const hasBody = method !== "GET" && method !== "HEAD";
  return new Request(`http://${req.headers.host ?? "localhost"}${req.url ?? "/"}`, {
    method,
    headers,
    body: hasBody ? (Readable.toWeb(req) as ReadableStream) : undefined,
    duplex: "half",
  });
}

async function send(res: ServerResponse, r: Response): Promise<void> {
  res.statusCode = r.status;
  r.headers.forEach((v, k) => res.setHeader(k, v));
  res.end(Buffer.from(await r.arrayBuffer()));
}

const server = createServer((req, res) => {
  app.handle(toRequest(req)).then((r) => send(res, r)).catch(() => {
    res.statusCode = 500;
    res.end();
  });
});
server.listen(config.port, "127.0.0.1", () => log.info("e4_api_listening", { port: config.port }));
const stop = () => server.close(() => void db.close().finally(() => process.exit(0)));
process.on("SIGINT", stop);
process.on("SIGTERM", stop);
