import { test } from "node:test";
import assert from "node:assert/strict";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { basename, join } from "node:path";
import { runCreate, runList, runStatus, runStop, type Deps } from "./main.mts";

type Call = string[];

// A fake Postgres: records every command, answers pg_ctl status / pg_isready from `running`,
// and answers psql SELECTs from `existing` (rows that already exist).
function harness(opts: { running?: Set<string>; existing?: Set<string>; busy?: number[] } = {}) {
  const baseDir = mkdtempSync(join(tmpdir(), "create-db-"));
  const calls: Call[] = [];
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
  return { deps, calls, logs, seed, baseDir, running };
}

const create = (name: string, over: Partial<Parameters<typeof runCreate>[0]> = {}) =>
  ({ name, user: "user", password: "pass", dryRun: false, ...over });

test("a fresh instance is initialised, configured, started and given its roles and database", async () => {
  const h = harness();
  const result = await runCreate(create("mydb"), h.deps);
  const dir = join(h.baseDir, "mydb");
  assert.deepEqual(h.calls[0], ["initdb", "-D", dir, "--auth-local=trust", "--auth-host=scram-sha-256", "--locale=en_US.UTF-8"]);
  assert.match(readFileSync(join(dir, "pg_hba.conf"), "utf8"), /scram-sha-256/);
  assert.match(readFileSync(join(dir, "postgresql.conf"), "utf8"), /^port = 5433$/m);
  assert.ok(h.calls.some((c) => c[0] === "pg_ctl" && c.includes("start") && c.includes(join(dir, "server.log"))));
  assert.ok(h.calls.some((c) => c[0] === "pg_isready"));
  const sql = h.calls.filter((c) => c[0] === "psql").map((c) => c.at(-1));
  assert.ok(sql.includes("CREATE ROLE postgres WITH LOGIN SUPERUSER;"));
  assert.ok(sql.includes(`CREATE ROLE "user" WITH LOGIN SUPERUSER PASSWORD 'pass';`));
  assert.ok(sql.includes(`CREATE DATABASE "mydb" OWNER "user";`));
  assert.ok(h.calls.every((c) => !c[0].startsWith("/pg") || c[0].startsWith("/pg15")), "a new cluster uses the default major");
  assert.deepEqual(result, { name: "mydb", dataDir: dir, port: 5433, user: "user", major: 15, initialized: true, started: true });
});

test("an existing running instance is reused: no initdb, no start, no re-creation, its own binaries", async () => {
  const h = harness({ existing: new Set(["rolname='postgres'", "rolname='user'", "datname='old'"]) });
  const dir = h.seed("old", 13, 5440);
  h.running.add(dir);
  const result = await runCreate(create("old"), h.deps);
  assert.ok(!h.calls.some((c) => c[0] === "initdb"));
  assert.ok(!h.calls.some((c) => c[0] === "pg_ctl" && c.includes("start")));
  assert.ok(!h.calls.some((c) => (c.at(-1) ?? "").startsWith("CREATE")));
  assert.equal(result.port, 5440);
  assert.equal(result.major, 13);
  assert.equal(result.initialized, false);
  assert.equal(result.started, false);
});

test("a stopped instance whose saved port is busy gets a new port appended, then starts", async () => {
  const h = harness({ busy: [5440] });
  const dir = h.seed("old", 15, 5440);
  const result = await runCreate(create("old"), h.deps);
  assert.equal(result.port, 5433);
  assert.match(readFileSync(join(dir, "postgresql.conf"), "utf8"), /port = 5440\nport = 5433\n$/);
  assert.equal(result.started, true);
});

test("--port pins the port for a new instance", async () => {
  const h = harness();
  const result = await runCreate(create("pinned", { port: 5500 }), h.deps);
  assert.equal(result.port, 5500);
  assert.ok(h.calls.some((c) => c[0] === "pg_isready" && c.includes("5500")));
});

test("--dry-run prints the plan and touches nothing", async () => {
  const h = harness();
  await runCreate(create("plan", { dryRun: true }), h.deps);
  assert.equal(h.calls.length, 0);
  assert.equal(existsSync(join(h.baseDir, "plan")), false);
  assert.ok(h.logs.some((l) => l.includes("[dry-run]") && l.includes("initdb")));
  assert.ok(h.logs.some((l) => l.includes("[dry-run]") && l.includes("start")));
  assert.ok(h.logs.some((l) => l.includes("[dry-run]") && l.includes('CREATE DATABASE "plan"')));
});

test("stop stops a running instance, reports not-running or missing otherwise", async () => {
  const h = harness();
  const dir = h.seed("db", 15, 5433);
  h.running.add(dir);
  assert.equal(await runStop("db", h.deps), "stopped");
  assert.ok(h.calls.some((c) => c[0] === "pg_ctl" && c.includes("stop") && c.includes("fast")));
  assert.equal(await runStop("db", h.deps), "not-running");
  assert.equal(await runStop("ghost", h.deps), "missing");
});

test("status and list report version, port and whether each instance runs", async () => {
  const h = harness();
  const a = h.seed("a", 13, 5440);
  h.seed("b", 15, 5441);
  h.running.add(a);
  assert.deepEqual(await runStatus("a", h.deps), { name: "a", dataDir: a, major: 13, port: 5440, running: true });
  const all = await runList(h.deps);
  assert.deepEqual(all.map((s) => [s.name, s.running]), [["a", true], ["b", false]]);
  await assert.rejects(runStatus("ghost", h.deps), /no instance named ghost/);
});

test("an instance whose config never set a port reports Postgres's default 5432", async () => {
  const h = harness();
  const dir = h.seed("legacy", 13, 5440);
  writeFileSync(join(dir, "postgresql.conf"), "#port = 5432\n");
  assert.equal((await runStatus("legacy", h.deps)).port, 5432);
  h.running.add(dir);
  assert.equal((await runCreate(create("legacy"), h.deps)).port, 5432, "a running instance without a port line is on 5432");
});
