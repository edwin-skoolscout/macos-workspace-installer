import { test } from "node:test";
import assert from "node:assert/strict";
import { cmd, connectionHint, resolveBinDir, type BinDeps } from "./postgres.mts";

const deps = (over: Partial<BinDeps> = {}): BinDeps => ({
  env: {},
  brewPrefix: (formula) => (formula === "postgresql@15" || formula === "postgresql@13" ? `/brew/opt/${formula}` : null),
  isExecutable: (path) => path.startsWith("/brew/opt/postgresql@1"),
  ...over,
});

test("PG_BIN in the environment wins", () => {
  assert.equal(resolveBinDir(13, deps({ env: { PG_BIN: "/custom/bin" } })), "/custom/bin");
});

test("an existing cluster's major picks the matching Homebrew formula; a new cluster gets 15", () => {
  assert.equal(resolveBinDir(13, deps()), "/brew/opt/postgresql@13/bin");
  assert.equal(resolveBinDir(null, deps()), "/brew/opt/postgresql@15/bin");
});

test("a missing formula is an error that says what to install", () => {
  assert.throws(() => resolveBinDir(14, deps()), /brew install postgresql@14/);
  assert.throws(() => resolveBinDir(null, deps({ brewPrefix: () => null })), /brew install postgresql@15/);
});

test("command lines match setup-database.sh", () => {
  assert.deepEqual(cmd.initdb("/bin", "/dbs/x"), ["/bin/initdb", ["-D", "/dbs/x", "--auth-local=trust", "--auth-host=scram-sha-256", "--locale=en_US.UTF-8"]]);
  assert.deepEqual(cmd.start("/bin", "/dbs/x"), ["/bin/pg_ctl", ["-D", "/dbs/x", "-l", "/dbs/x/server.log", "start"]]);
  assert.deepEqual(cmd.stop("/bin", "/dbs/x"), ["/bin/pg_ctl", ["-D", "/dbs/x", "stop", "-m", "fast"]]);
  assert.deepEqual(cmd.status("/bin", "/dbs/x"), ["/bin/pg_ctl", ["-D", "/dbs/x", "status"]]);
  assert.deepEqual(cmd.isReady("/bin", 5440), ["/bin/pg_isready", ["-h", "localhost", "-p", "5440"]]);
  assert.deepEqual(cmd.psql("/bin", 5440, "me", "SELECT 1"), ["/bin/psql", ["-p", "5440", "-U", "me", "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-tAc", "SELECT 1"]]);
});

test("connectionHint is a runnable psql line", () => {
  assert.equal(connectionHint(5440, "user", "pass", "mydb"), "PGPASSWORD=pass psql -h localhost -p 5440 -U user -d mydb");
});
