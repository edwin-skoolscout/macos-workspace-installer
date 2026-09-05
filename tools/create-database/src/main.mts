// main.mts — create-database CLI: local Postgres instances, one data dir each under DATABASES_DIR.
// Run through ./create-database.sh at the repo root, which finds Node and installs dependencies.
import { execFileSync } from "node:child_process";
import { accessSync, appendFileSync, constants, existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { createServer } from "node:net";
import { userInfo } from "node:os";
import { basename, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { Command, InvalidArgumentError } from "commander";
import { input, select } from "@inquirer/prompts";
import { runCapture, runStatus as exitCodeOf } from "@workspace-installer/lib/proc";
import { readPin } from "@workspace-installer/lib/versions-env";
import {
  chooseFreePort, DEFAULT_PORT, instanceDir, isInstance, listInstances, readMajor, readPort,
  renderConfAdditions, renderHba, withPort, type Instance,
} from "./instances.mts";
import { cmd, connectionHint, DEFAULT_MAJOR, resolveBinDir, type Cmd } from "./postgres.mts";

// Everything with a side effect is injected so the flows are testable without a Postgres.
export type Deps = {
  baseDir: string;
  osUser: string; // initdb makes the OS user a superuser; it bootstraps the roles over the socket
  binDir: (major: number | null) => string;
  run: (cmd: string, args: string[]) => Promise<string>;
  status: (cmd: string, args: string[]) => Promise<number>;
  isPortBusy: (port: number) => boolean | Promise<boolean>;
  sleep: (ms: number) => Promise<void>;
  log: (msg: string) => void;
};

export type CreateOptions = { name: string; user: string; password: string; port?: number; dryRun: boolean };
export type CreateResult = {
  name: string; dataDir: string; port: number; user: string; major: number; initialized: boolean; started: boolean;
};
export type InstanceStatus = { name: string; dataDir: string; major: number | null; port: number; running: boolean };

const sqlLiteral = (s: string) => s.replace(/'/g, "''");

export async function runCreate(opts: CreateOptions, deps: Deps): Promise<CreateResult> {
  const dry = opts.dryRun;
  const dataDir = instanceDir(deps.baseDir, opts.name);
  const initialized = !isInstance(dataDir);
  const major = initialized ? DEFAULT_MAJOR : (readMajor(dataDir) ?? DEFAULT_MAJOR);
  const bin = deps.binDir(initialized ? null : major);
  const exec = async ([c, args]: Cmd): Promise<string> => {
    if (dry) { deps.log(`[dry-run] ${c} ${args.join(" ")}`); return ""; }
    return deps.run(c, args);
  };
  const check = async ([c, args]: Cmd): Promise<number> => (dry ? 3 : deps.status(c, args)); // 3: not running
  const confPath = join(dataDir, "postgresql.conf");

  let port: number;
  let running = false;
  if (initialized) {
    if (!dry) mkdirSync(dataDir, { recursive: true });
    await exec(cmd.initdb(bin, dataDir));
    port = opts.port ?? (await chooseFreePort(deps.isPortBusy));
    if (dry) {
      deps.log(`[dry-run] write ${join(dataDir, "pg_hba.conf")}; set listen_addresses = 'localhost', port = ${port}`);
    } else {
      writeFileSync(join(dataDir, "pg_hba.conf"), renderHba());
      appendFileSync(confPath, renderConfAdditions(port)); // initdb wrote the rest; last port wins
    }
  } else {
    const conf = existsSync(confPath) ? readFileSync(confPath, "utf8") : "";
    const saved = readPort(conf);
    running = (await check(cmd.status(bin, dataDir))) === 0;
    if (running) {
      port = saved ?? DEFAULT_PORT;
      if (opts.port !== undefined && opts.port !== port) deps.log(`already running on ${port}; --port ${opts.port} ignored`);
    } else {
      if (opts.port !== undefined) port = opts.port;
      else if (saved !== null && !(await deps.isPortBusy(saved))) port = saved;
      else port = await chooseFreePort(deps.isPortBusy);
      if (port !== saved) {
        if (saved !== null) deps.log(`port ${saved} is busy; using ${port}`);
        if (dry) deps.log(`[dry-run] append port = ${port} to ${confPath}`);
        else writeFileSync(confPath, withPort(conf, port));
      }
    }
  }

  let started = false;
  if (!running) {
    await exec(cmd.start(bin, dataDir));
    started = true;
    if (!dry) await waitReady(bin, port, dataDir, deps);
  }

  const psql = (sql: string) => exec(cmd.psql(bin, port, deps.osUser, sql));
  const exists = async (sql: string) => (await psql(sql)).trim() === "1";
  if (!(await exists("SELECT 1 FROM pg_roles WHERE rolname='postgres'"))) {
    await psql("CREATE ROLE postgres WITH LOGIN SUPERUSER;");
  }
  if (!(await exists(`SELECT 1 FROM pg_roles WHERE rolname='${sqlLiteral(opts.user)}'`))) {
    await psql(`CREATE ROLE "${opts.user}" WITH LOGIN SUPERUSER PASSWORD '${sqlLiteral(opts.password)}';`);
  }
  if (!(await exists(`SELECT 1 FROM pg_database WHERE datname='${sqlLiteral(opts.name)}'`))) {
    await psql(`CREATE DATABASE "${opts.name}" OWNER "${opts.user}";`);
  }
  return { name: opts.name, dataDir, port, user: opts.user, major, initialized, started };
}

async function waitReady(bin: string, port: number, dataDir: string, deps: Deps): Promise<void> {
  for (let attempt = 0; attempt < 40; attempt += 1) {
    if ((await deps.status(...cmd.isReady(bin, port))) === 0) return;
    await deps.sleep(250);
  }
  throw new Error(`Postgres did not accept connections on localhost:${port}; see ${join(dataDir, "server.log")}`);
}

export async function runStop(name: string, deps: Deps): Promise<"stopped" | "not-running" | "missing"> {
  const dataDir = instanceDir(deps.baseDir, name);
  if (!isInstance(dataDir)) return "missing";
  const bin = deps.binDir(readMajor(dataDir));
  if ((await deps.status(...cmd.status(bin, dataDir))) !== 0) return "not-running";
  await deps.run(...cmd.stop(bin, dataDir));
  return "stopped";
}

async function statusOf(instance: Instance, deps: Deps): Promise<InstanceStatus> {
  const major = readMajor(instance.dataDir);
  const confPath = join(instance.dataDir, "postgresql.conf");
  const port = (existsSync(confPath) ? readPort(readFileSync(confPath, "utf8")) : null) ?? DEFAULT_PORT;
  const running = (await deps.status(...cmd.status(deps.binDir(major), instance.dataDir))) === 0;
  return { name: instance.name, dataDir: instance.dataDir, major, port, running };
}

export async function runStatus(name: string, deps: Deps): Promise<InstanceStatus> {
  const dataDir = instanceDir(deps.baseDir, name);
  if (!isInstance(dataDir)) throw new Error(`no instance named ${name} in ${deps.baseDir}`);
  return statusOf({ name, dataDir }, deps);
}

export async function runList(deps: Deps): Promise<InstanceStatus[]> {
  const out: InstanceStatus[] = [];
  for (const instance of listInstances(deps.baseDir)) out.push(await statusOf(instance, deps));
  return out;
}

// ---- CLI ---------------------------------------------------------------------------------------

function repoRoot(): string {
  return fileURLToPath(new URL("../../../", import.meta.url));
}

function brewPrefix(formula: string): string | null {
  try {
    return execFileSync("brew", ["--prefix", formula], { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] }).trim() || null;
  } catch {
    return null;
  }
}

function isExecutable(path: string): boolean {
  try { accessSync(path, constants.X_OK); return true; } catch { return false; }
}

function isPortBusy(port: number): Promise<boolean> {
  return new Promise((done) => {
    const server = createServer();
    server.once("error", () => done(true));
    server.listen({ port, host: "127.0.0.1" }, () => server.close(() => done(false)));
  });
}

function realDeps(baseDir: string): Deps {
  return {
    baseDir,
    osUser: userInfo().username,
    binDir: (major) => resolveBinDir(major, { env: process.env, brewPrefix, isExecutable }),
    run: runCapture,
    status: exitCodeOf,
    isPortBusy,
    sleep: (ms) => new Promise((done) => setTimeout(done, ms)),
    log: (msg) => console.log(msg),
  };
}

function parsePort(value: string): number {
  const port = Number(value);
  if (!Number.isInteger(port) || port < 1 || port > 65535) throw new InvalidArgumentError("port must be 1-65535");
  return port;
}

async function pickInstance(message: string, deps: Deps): Promise<string> {
  const instances = listInstances(deps.baseDir);
  if (instances.length === 0) throw new Error(`no instances in ${deps.baseDir}`);
  if (!process.stdin.isTTY) throw new Error(`name required; instances: ${instances.map((i) => i.name).join(", ")}`);
  return select({ message, choices: instances.map((i) => ({ name: i.name, value: i.name })) });
}

function printStatus(rows: InstanceStatus[]): void {
  for (const s of rows) {
    console.log(`${s.name.padEnd(28)} pg${String(s.major ?? "?").padEnd(4)} port ${String(s.port ?? "?").padEnd(6)} ${s.running ? "running" : "stopped"}  ${s.dataDir}`);
  }
}

const invokedDirectly =
  process.argv[1] !== undefined && resolve(process.argv[1]) === fileURLToPath(import.meta.url);

if (invokedDirectly) {
  const program = new Command()
    .name("create-database")
    .description("Local Postgres instances, one data dir each under DATABASES_DIR/<name>.")
    .option("--base-dir <dir>", "where instances live (default: DATABASES_DIR from config/versions.env)");
  const deps = (): Deps => {
    const versionsEnv = join(repoRoot(), "config", "versions.env");
    const fromFile = existsSync(versionsEnv) ? readFileSync(versionsEnv, "utf8") : null;
    const baseDir = (program.opts<{ baseDir?: string }>().baseDir) ?? readPin("DATABASES_DIR", process.env, fromFile, "$HOME/Development/Databases");
    return realDeps(baseDir);
  };

  program
    .command("create")
    .description("initialise if needed, start, ensure the roles and database, print how to connect")
    .argument("[name]", "instance and database name (default: the current directory's name)")
    .option("--user <name>", "application role (superuser)", "user")
    .option("--password <pw>", "its password", "pass")
    .option("--port <n>", "fixed port instead of the first free one from 5433", parsePort)
    .option("--dry-run", "print what would happen; change nothing", false)
    .action(async (nameArg: string | undefined, o: { user: string; password: string; port?: number; dryRun: boolean }) => {
      const d = deps();
      const fallback = basename(process.cwd());
      const name = nameArg ?? (process.stdin.isTTY ? await input({ message: "Instance name", default: fallback }) : fallback);
      const r = await runCreate({ name, user: o.user, password: o.password, port: o.port, dryRun: o.dryRun }, d);
      if (o.dryRun) return;
      console.log(`\n✓ Postgres ${r.major} instance "${r.name}" ${r.initialized ? "created" : "ready"}${r.started ? " (started)" : ""}`);
      console.log(`  data dir: ${r.dataDir}`);
      console.log(`  log:      ${join(r.dataDir, "server.log")}`);
      console.log(`  port:     ${r.port}`);
      console.log(`  db/user:  ${r.name} / ${r.user} (password: ${o.password})`);
      console.log(`  connect:  ${connectionHint(r.port, r.user, o.password, r.name)}`);
      console.log(`  stop:     ./create-database.sh stop ${r.name}`);
    });

  program
    .command("stop")
    .description("stop a running instance (pg_ctl stop -m fast)")
    .argument("[name]")
    .action(async (nameArg: string | undefined) => {
      const d = deps();
      const name = nameArg ?? (await pickInstance("Instance to stop", d));
      const outcome = await runStop(name, d);
      if (outcome === "missing") throw new Error(`no instance named ${name} in ${d.baseDir}`);
      console.log(outcome === "stopped" ? `✓ ${name} stopped` : `${name} was not running`);
    });

  program
    .command("status")
    .description("data dir, version, port and whether it runs; all instances without a name")
    .argument("[name]")
    .action(async (nameArg: string | undefined) => {
      const d = deps();
      printStatus(nameArg ? [await runStatus(nameArg, d)] : await runList(d));
    });

  program
    .command("list")
    .description("every instance under the base dir")
    .action(async () => {
      const d = deps();
      const rows = await runList(d);
      if (rows.length === 0) console.log(`no instances in ${d.baseDir}`);
      printStatus(rows);
    });

  try {
    await program.parseAsync();
  } catch (err) {
    if (err instanceof Error && err.name === "ExitPromptError") process.exit(130);
    console.error(err instanceof Error ? err.message : String(err));
    process.exit(1);
  }
}
