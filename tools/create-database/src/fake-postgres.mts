// fake-postgres.mts — test double for Deps: records every command, answers pg_ctl status and
// pg_isready from `running`, and answers psql SELECTs from `existing` (rows that already exist).
// Only imported by *.test.mts files.
import { mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { basename, join } from "node:path";
import type { Deps } from "./main.mts";

export type FakePostgres = ReturnType<typeof fakePostgres>;

export function fakePostgres(opts: { running?: Set<string>; existing?: Set<string>; busy?: number[] } = {}) {
  const baseDir = mkdtempSync(join(tmpdir(), "create-db-"));
  const calls: string[][] = [];
  const logs: string[] = [];
  const running = opts.running ?? new Set<string>();
  const existing = opts.existing ?? new Set<string>();
  const deps: Deps = {
    baseDir,
    osUser: "me",
    binDir: (major) => `/pg${major ?? 15}/bin`,
    run: async (cmd, args) => {
      calls.push([basename(cmd), ...args]);
      const sql = args.at(-1) ?? "";
      if (basename(cmd) === "psql" && sql.startsWith("SELECT")) return [...existing].some((e) => sql.includes(e)) ? "1\n" : "";
      if (basename(cmd) === "pg_ctl" && args.includes("start")) running.add(args[1] ?? "");
      if (basename(cmd) === "pg_ctl" && args.includes("stop")) running.delete(args[1] ?? "");
      return "";
    },
    status: async (cmd, args) => {
      calls.push([basename(cmd), ...args]);
      if (basename(cmd) === "pg_ctl") return running.has(args[1] ?? "") ? 0 : 3;
      if (basename(cmd) === "pg_isready") return 0;
      return 1;
    },
    isPortBusy: (port) => (opts.busy ?? []).includes(port),
    sleep: async () => {},
    log: (msg) => logs.push(msg),
  };
  const seed = (name: string, major: number, port: number) => {
    const dir = join(baseDir, name);
    mkdirSync(dir, { recursive: true });
    writeFileSync(join(dir, "PG_VERSION"), `${major}\n`);
    writeFileSync(join(dir, "postgresql.conf"), `listen_addresses = 'localhost'\nport = ${port}\n`);
    return dir;
  };
  return { deps, calls, logs, seed, baseDir, running, existing };
}
