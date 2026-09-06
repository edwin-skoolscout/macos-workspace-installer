import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, symlinkSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

const main = fileURLToPath(new URL("./main.mts", import.meta.url));
const root = fileURLToPath(new URL("../../../", import.meta.url));

test("the CLI runs when invoked through a symlink, as npm's .bin shims do", () => {
  const link = join(mkdtempSync(join(tmpdir(), "bin-")), "create-database");
  symlinkSync(main, link);
  const out = execFileSync(process.execPath, [link, "--help"], { encoding: "utf8" });
  assert.match(out, /^Usage: create-database/);
});

test("npm installed a create-database shim that runs through its shebang", () => {
  const out = execFileSync(join(root, "node_modules", ".bin", "create-database"), ["--help"], { encoding: "utf8" });
  assert.match(out, /^Usage: create-database/);
});
