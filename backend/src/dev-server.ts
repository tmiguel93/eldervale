import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { Readable } from "node:stream";
import { buildApp } from "./app.ts";
import { loadConfig } from "./config.ts";
import { createLogger } from "./http/logger.ts";
import { migrate } from "./persistence/migrate.ts";
import { openDb } from "./persistence/open.ts";
import { DEV_PGLITE_DIR } from "./persistence/paths.ts";

/** Servidor de desenvolvimento local (node:http -> app.handle). Nao use em producao. */
const config = loadConfig();
if (config.isProduction) {
  console.error("dev-server nao deve rodar em production");
  process.exit(1);
}
const log = createLogger({ level: config.logLevel });
const db = await openDb(config, DEV_PGLITE_DIR);
const mig = await migrate(db);
const app = buildApp({ config, db, log });

function toRequest(req: IncomingMessage): Request {
  const headers = new Headers();
  for (const [k, v] of Object.entries(req.headers)) {
    if (k === "x-real-ip") continue; // nunca confiar no cliente; definido abaixo a partir do socket
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
  app
    .handle(toRequest(req))
    .then((r) => send(res, r))
    .catch(() => {
      res.statusCode = 500;
      res.end();
    });
});

server.listen(config.port, "127.0.0.1", () => {
  log.info("dev_server_listening", { port: config.port, migrations_applied: mig.applied, generated_keys: config.ephemeralSecrets });
});

const stop = () => {
  server.close(() => void db.close().finally(() => process.exit(0)));
};
process.on("SIGINT", stop);
process.on("SIGTERM", stop);
