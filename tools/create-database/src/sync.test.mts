import { test } from "node:test";
import assert from "node:assert/strict";
import { existsSync, mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fakePostgres } from "./fake-postgres.mts";
import { runCreate } from "./main.mts";
import { runReset, runSync, type SyncDeps } from "./sync.mts";

// A workspace with skoolscout-com (init scripts) and acme/other cloned; ghost is listed but not cloned.
function workspace() {
  const root = mkdtempSync(join(tmpdir(), "sync-"));
  const ws = join(root, "ws");
  const app = join(ws, "skoolscout", "skoolscout-com");
  mkdirSync(join(app, ".git"), { recursive: true });
  mkdirSync(join(app, "app-service", "init-scripts"), { recursive: true });
  writeFileSync(join(app, "app-service", "init-scripts", "02-b.sql"), "");
  writeFileSync(join(app, "app-service", "init-scripts", "01-a.sql"), "");
  writeFileSync(join(app, "app-service", "init-scripts", "README.md"), "");
  mkdirSync(join(ws, "acme", "other", ".git"), { recursive: true });
  const reposFile = join(root, "repos.txt");
  writeFileSync(reposFile, "git@github.com:skoolscout/skoolscout-com.git develop\ngit@github.com:acme/other.git main\ngit@github.com:acme/ghost.git main\n");
  const databasesFile = join(root, "databases.txt");
  writeFileSync(databasesFile, [
    "skoolscout-com skoolscout_db 5432 skoolscout admin123 app-service/init-scripts",
    "other other_db 5433 postgres pw",
    "ghost ghost_db 5434 postgres pw",
    "",
  ].join("\n"));
  return { ws, reposFile, databasesFile, app };
}

function harness(existing?: Set<string>) {
  const pg = fakePostgres({ existing });
  const w = workspace();
  const deps: SyncDeps = { ...pg.deps, reposFile: w.reposFile, databasesFile: w.databasesFile, workspaceDir: w.ws, create: runCreate };
  return { ...pg, ...w, deps };
}

test("sync creates the databases of every cloned repo and runs their init scripts, in order, once", async () => {
  const h = harness();
  const results = await runSync({ dryRun: false }, h.deps);
  assert.deepEqual(results.map((r) => [r.repo, r.database, r.port, r.created, r.initScripts]), [
    ["skoolscout-com", "skoolscout_db", 5432, true, 2],
    ["other", "other_db", 5433, true, 0],
  ]);
  const files = h.calls.filter((c) => c[0] === "psql" && c.includes("-f")).map((c) => c.at(-1));
  assert.deepEqual(files, [join(h.app, "app-service/init-scripts/01-a.sql"), join(h.app, "app-service/init-scripts/02-b.sql")]);
  const initCall = h.calls.find((c) => c[0] === "psql" && c.includes("-f"));
  assert.ok(initCall?.includes("skoolscout_db") && initCall.includes("skoolscout"), "init runs as the app user against its database");
});

test("--repos limits the sync to the named repos", async () => {
  const h = harness();
  const results = await runSync({ repos: ["other"], dryRun: false }, h.deps);
  assert.deepEqual(results.map((r) => r.database), ["other_db"]);
});

test("a rerun on an existing database does not rerun the init scripts", async () => {
  const h = harness(new Set(["rolname='postgres'", "rolname='skoolscout'", "datname='skoolscout_db'"]));
  h.seed("skoolscout_db", 15, 5432);
  const results = await runSync({ repos: ["skoolscout-com"], dryRun: false }, h.deps);
  assert.equal(results[0]?.created, false);
  assert.equal(results[0]?.initScripts, 0);
  assert.ok(!h.calls.some((c) => c.includes("-f")));
});

test("--dry-run plans everything and runs nothing", async () => {
  const h = harness();
  await runSync({ dryRun: true }, h.deps);
  assert.equal(h.calls.length, 0);
  assert.ok(h.logs.some((l) => l.includes("[dry-run]") && l.includes("01-a.sql")));
});

test("reset stops, wipes and recreates the instance, then runs the init scripts again", async () => {
  const h = harness(new Set(["rolname='postgres'", "rolname='skoolscout'", "datname='skoolscout_db'"]));
  const dir = h.seed("skoolscout_db", 15, 5432);
  h.running.add(dir);
  h.existing.clear(); // after the wipe nothing exists any more
  const result = await runReset("skoolscout_db", { dryRun: false }, { ...h.deps, confirm: async () => true });
  assert.ok(result, "reset returns the recreated database");
  assert.ok(h.calls.some((c) => c[0] === "pg_ctl" && c.includes("stop")), "stopped first");
  assert.ok(h.calls.some((c) => c[0] === "initdb"), "recreated from scratch");
  assert.equal(h.calls.filter((c) => c[0] === "psql" && c.includes("-f")).length, 2, "init scripts run again");
  assert.deepEqual([result.repo, result.database, result.created, result.initScripts], ["skoolscout-com", "skoolscout_db", true, 2]);
});

test("reset refuses a database that is not in databases.txt, and does nothing when not confirmed", async () => {
  const h = harness();
  await assert.rejects(runReset("nope_db", { dryRun: false }, { ...h.deps, confirm: async () => true }), /databases\.txt/);
  h.seed("skoolscout_db", 15, 5432);
  const r = await runReset("skoolscout_db", { dryRun: false }, { ...h.deps, confirm: async () => false });
  assert.equal(r, null);
  assert.ok(!h.calls.some((c) => c[0] === "initdb"));
  assert.ok(existsSync(join(h.baseDir, "skoolscout_db", "PG_VERSION")), "data dir untouched");
});

test("reset --dry-run plans the wipe and the recreation without touching anything", async () => {
  const h = harness();
  h.seed("skoolscout_db", 15, 5432);
  await runReset("skoolscout_db", { dryRun: true }, { ...h.deps, confirm: async () => true });
  assert.equal(h.calls.length, 0);
  assert.ok(existsSync(join(h.baseDir, "skoolscout_db", "PG_VERSION")));
  assert.ok(h.logs.some((l) => l.includes("[dry-run]") && l.includes("rm -rf")));
});
