import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

/** Raiz de `backend/` (src/persistence/ -> ../..). */
export const BACKEND_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..", "..");
export const MIGRATIONS_DIR = resolve(BACKEND_ROOT, "migrations");
/** Diretorio persistente do PGlite em desenvolvimento (ignorado pelo Git). */
export const DEV_PGLITE_DIR = resolve(BACKEND_ROOT, ".data", "pglite");
