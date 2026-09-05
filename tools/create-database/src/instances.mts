// instances.mts — the on-disk layout: DATABASES_DIR/<name> is one Postgres data directory
// (the layout of jefelabs-scripts/tools/setup-database.sh), its port saved in postgresql.conf.
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";

export type Instance = { name: string; dataDir: string };

export const PORT_RANGE = { from: 5433, to: 5599 };
export const DEFAULT_PORT = 5432; // what postgres listens on when postgresql.conf sets no port

export function instanceDir(baseDir: string, name: string): string {
  return join(baseDir, name);
}

export function isInstance(dataDir: string): boolean {
  return existsSync(join(dataDir, "PG_VERSION"));
}

export function listInstances(baseDir: string): Instance[] {
  if (!existsSync(baseDir)) return [];
  return readdirSync(baseDir, { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .map((entry) => ({ name: entry.name, dataDir: join(baseDir, entry.name) }))
    .filter((instance) => isInstance(instance.dataDir))
    .sort((a, b) => a.name.localeCompare(b.name));
}

// readMajor — PG_VERSION holds "13" (or "9.6" for the pre-10 numbering).
export function readMajor(dataDir: string): number | null {
  const file = join(dataDir, "PG_VERSION");
  if (!existsSync(file)) return null;
  const major = Number.parseInt(readFileSync(file, "utf8").trim().split(".")[0] ?? "", 10);
  return Number.isNaN(major) ? null : major;
}

// readPort — the last uncommented "port = N" wins, as it does for postgres itself.
export function readPort(confText: string): number | null {
  let port: number | null = null;
  for (const line of confText.split("\n")) {
    const match = /^\s*port\s*=\s*(\d+)/.exec(line);
    if (match) port = Number(match[1]);
  }
  return port;
}

export function withPort(confText: string, port: number): string {
  const separator = confText === "" || confText.endsWith("\n") ? "" : "\n";
  return `${confText}${separator}port = ${port}\n`;
}

// Trust on the unix socket so the tool can bootstrap roles without a password; scram over TCP.
export function renderHba(): string {
  return [
    "# TYPE  DATABASE        USER            ADDRESS                 METHOD",
    "local   all             all                                     trust",
    "host    all             all             127.0.0.1/32            scram-sha-256",
    "host    all             all             ::1/128                 scram-sha-256",
    "",
  ].join("\n");
}

export function renderConfAdditions(port: number): string {
  return `listen_addresses = 'localhost'\nport = ${port}\n`;
}

export async function chooseFreePort(
  isBusy: (port: number) => boolean | Promise<boolean>,
  from = PORT_RANGE.from,
  to = PORT_RANGE.to,
): Promise<number> {
  for (let port = from; port <= to; port += 1) {
    if (!(await isBusy(port))) return port;
  }
  throw new Error(`no free port between ${from} and ${to}`);
}
