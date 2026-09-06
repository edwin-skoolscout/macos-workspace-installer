import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { mkdtempSync, symlinkSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

const main = fileURLToPath(new URL("./main.mts", import.meta.url));
const root = fileURLToPath(new URL("../../../", import.meta.url));

test("the CLI runs when invoked through a symlink, as npm's .bin shims do", () => {
  const link = join(mkdtempSync(join(tmpdir(), "bin-")), "clone-repos");
  symlinkSync(main, link);
  const out = execFileSync(process.execPath, [link, "--help"], { encoding: "utf8" });
  assert.match(out, /^Usage: clone-repos/);
});

test("npm installed a clone-repos shim that runs through its shebang", () => {
  const out = execFileSync(join(root, "node_modules", ".bin", "clone-repos"), ["--help"], { encoding: "utf8" });
  assert.match(out, /^Usage: clone-repos/);
});

test("without a terminal and without --all the CLI refuses before calling gh", () => {
  const result = spawnSync(process.execPath, [main, "acme"], { encoding: "utf8", input: "" });
  assert.equal(result.status, 1);
  assert.match(result.stderr, /no terminal/);
  assert.match(result.stderr, /--all/);
});
