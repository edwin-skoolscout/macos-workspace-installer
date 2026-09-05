// postgres.mts — which Postgres binaries to use and the exact command lines the tool runs.
import { join } from "node:path";

export const DEFAULT_MAJOR = 15; // the installer's postgresql@15 pin (steps/51-postgres.sh)

export type BinDeps = {
  env: Readonly<Record<string, string | undefined>>;
  brewPrefix: (formula: string) => string | null;
  isExecutable: (path: string) => boolean;
};

// resolveBinDir — PG_BIN wins; else Homebrew's keg-only postgresql@<major> (an existing cluster
// must be served by its own major; a new one gets the default). Keg-only means nothing is on
// PATH by default, hence the explicit lookup.
export function resolveBinDir(major: number | null, deps: BinDeps): string {
  if (deps.env.PG_BIN) return deps.env.PG_BIN;
  const formula = `postgresql@${major ?? DEFAULT_MAJOR}`;
  const prefix = deps.brewPrefix(formula);
  const bin = prefix ? join(prefix, "bin") : null;
  if (bin && deps.isExecutable(join(bin, "initdb"))) return bin;
  throw new Error(`Postgres ${major ?? DEFAULT_MAJOR} binaries not found. Set PG_BIN, or: brew install ${formula}`);
}

export type Cmd = [string, string[]];

export const cmd = {
  initdb: (bin: string, dataDir: string): Cmd => [
    join(bin, "initdb"),
    ["-D", dataDir, "--auth-local=trust", "--auth-host=scram-sha-256", "--locale=en_US.UTF-8"],
  ],
  start: (bin: string, dataDir: string): Cmd => [
    join(bin, "pg_ctl"),
    ["-D", dataDir, "-l", join(dataDir, "server.log"), "start"],
  ],
  stop: (bin: string, dataDir: string): Cmd => [join(bin, "pg_ctl"), ["-D", dataDir, "stop", "-m", "fast"]],
  status: (bin: string, dataDir: string): Cmd => [join(bin, "pg_ctl"), ["-D", dataDir, "status"]],
  isReady: (bin: string, port: number): Cmd => [join(bin, "pg_isready"), ["-h", "localhost", "-p", String(port)]],
  psql: (bin: string, port: number, user: string, sql: string): Cmd => [
    join(bin, "psql"),
    ["-p", String(port), "-U", user, "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-tAc", sql],
  ],
};

export function connectionHint(port: number, user: string, password: string, db: string): string {
  return `PGPASSWORD=${password} psql -h localhost -p ${port} -U ${user} -d ${db}`;
}
