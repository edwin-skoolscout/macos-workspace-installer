import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { parseReposFile, mergeRepos, renderReposFile, readReposFile, writeReposFile } from "./repos-file.mts";

const app = { url: "git@github.com:acme/app.git", branch: "develop" };
const docs = { url: "git@github.com:acme/docs.git", branch: "main" };

test("parseReposFile skips comments and blank lines and defaults the branch to main", () => {
  const text = "# url branch\n\ngit@github.com:acme/app.git develop\n  git@github.com:acme/docs.git\n";
  assert.deepEqual(parseReposFile(text), [app, docs]);
});

test("mergeRepos appends unknown URLs, keeps existing entries and their branches", () => {
  const { entries, added } = mergeRepos([app], [{ ...app, branch: "main" }, docs]);
  assert.deepEqual(entries, [app, docs]);
  assert.equal(added, 1);
});

test("renderReposFile writes a header and one line per entry", () => {
  const text = renderReposFile([app, docs]);
  assert.match(text, /^# <git url> <branch>/);
  assert.match(text, /\ngit@github.com:acme\/app.git develop\ngit@github.com:acme\/docs.git main\n$/);
});

test("readReposFile returns [] for a missing file; writeReposFile creates the directory and round-trips", () => {
  const dir = mkdtempSync(join(tmpdir(), "repos-file-"));
  const file = join(dir, "config", "repos.txt");
  assert.deepEqual(readReposFile(file), []);
  writeReposFile(file, [app, docs]);
  assert.ok(existsSync(file));
  assert.deepEqual(readReposFile(file), [app, docs]);
  assert.match(readFileSync(file, "utf8"), /^#/);
});
