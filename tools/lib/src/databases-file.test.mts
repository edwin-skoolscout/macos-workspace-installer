import { test } from "node:test";
import assert from "node:assert/strict";
import { join } from "node:path";
import { parseDatabasesFile, readDatabasesFile } from "./databases-file.mts";

test("parses repo, database, port, user, password and an optional init dir; skips comments and blanks", () => {
  const text = "# <repo> <database> <port> <user> <password> [init-sql-dir]\n\nskoolscout-com skoolscout_db 5432 skoolscout admin123 app-service/init-scripts\n  msgmason-com msgmason 5433 postgres password\n";
  assert.deepEqual(parseDatabasesFile(text), [
    { repo: "skoolscout-com", database: "skoolscout_db", port: 5432, user: "skoolscout", password: "admin123", initDir: "app-service/init-scripts" },
    { repo: "msgmason-com", database: "msgmason", port: 5433, user: "postgres", password: "password", initDir: null },
  ]);
});

test("a short line or a bad port is an error that names the line", () => {
  assert.throws(() => parseDatabasesFile("# c\nskoolscout-com skoolscout_db\n"), /line 2/);
  assert.throws(() => parseDatabasesFile("a b notaport u p\n"), /line 1.*port/);
});

test("readDatabasesFile returns [] when the file is missing", () => {
  assert.deepEqual(readDatabasesFile(join("/nonexistent", "databases.txt")), []);
});
