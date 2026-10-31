import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    include: ["test/**/*.test.ts"],
    testTimeout: 30_000,
    hookTimeout: 60_000,
    // PGlite por arquivo de teste: limitar workers evita travamento observado com 2 CPUs.
    maxWorkers: 2,
  },
});
