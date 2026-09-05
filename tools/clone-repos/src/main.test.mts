import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { runCloneRepos, type Deps } from "./main.mts";
import { readReposFile } from "./repos-file.mts";
import type { GitHubRepo } from "./github.mts";

const repo = (name: string, extra: Partial<GitHubRepo> = {}): GitHubRepo => ({
  owner: "acme", name, url: `git@github.com:acme/${name}.git`, branch: "develop",
  archived: false, private: true, pushedAt: "2026-09-04T10:00:00Z", ...extra,
});

function harness(repos: GitHubRepo[], clonedDirs: string[] = []) {
  const dir = mkdtempSync(join(tmpdir(), "clone-repos-"));
  const clones: string[] = [];
  const logs: string[] = [];
  let picked: GitHubRepo[] | null = null;
  const deps: Deps = {
    listRepos: async () => repos,
    pick: async (candidates) => { picked = candidates; return candidates.slice(0, 1); },
    clone: async (entry, target) => { clones.push(`${entry.url}@${entry.branch} -> ${target}`); },
    isCloned: (target) => clonedDirs.includes(target),
    reposFile: join(dir, "config", "repos.txt"),
    workspaceDir: join(dir, "ws"),
    log: (msg) => logs.push(msg),
  };
  return { deps, clones, logs, get picked() { return picked; }, dir };
}

test("--all records every cloneable repo and clones the ones not on disk", async () => {
  const h = harness([repo("app"), repo("docs"), repo("old", { archived: true }), repo("empty", { branch: null })],
    [join("", "never")]);
  const result = await runCloneRepos({ owner: "acme", all: true, dryRun: false }, h.deps);
  assert.equal(h.picked, null, "the picker is not shown under --all");
  assert.deepEqual(readReposFile(h.deps.reposFile).map((e) => e.url), ["git@github.com:acme/app.git", "git@github.com:acme/docs.git"]);
  assert.deepEqual(h.clones, [
    `git@github.com:acme/app.git@develop -> ${join(h.deps.workspaceDir, "acme", "app")}`,
    `git@github.com:acme/docs.git@develop -> ${join(h.deps.workspaceDir, "acme", "docs")}`,
  ]);
  assert.deepEqual(result, { selected: 2, cloned: 2, skipped: 0 });
});

test("the picker sees cloneable repos only and its choice is what gets recorded", async () => {
  const h = harness([repo("app"), repo("docs"), repo("old", { archived: true })]);
  await runCloneRepos({ owner: "acme", all: false, dryRun: false }, h.deps);
  assert.deepEqual(h.picked?.map((r) => r.name), ["app", "docs"]);
  assert.deepEqual(readReposFile(h.deps.reposFile).map((e) => e.url), ["git@github.com:acme/app.git"]);
  assert.equal(h.clones.length, 1);
});

test("--filter narrows the candidates before picking", async () => {
  const h = harness([repo("skoolscout-com"), repo("jefelabs-docs")]);
  await runCloneRepos({ owner: "acme", all: true, filter: "jefe", dryRun: false }, h.deps);
  assert.deepEqual(h.clones.map((c) => c.split("@")[1]), ["github.com:acme/jefelabs-docs.git"]);
});

test("repos already on disk are recorded but not cloned again", async () => {
  const h0 = harness([repo("app")]);
  const appDir = join(h0.deps.workspaceDir, "acme", "app");
  const h = harness([repo("app"), repo("docs")], [appDir]);
  h.deps.workspaceDir = h0.deps.workspaceDir;
  const result = await runCloneRepos({ owner: "acme", all: true, dryRun: false }, h.deps);
  assert.deepEqual(result, { selected: 2, cloned: 1, skipped: 1 });
  assert.equal(readReposFile(h.deps.reposFile).length, 2);
});

test("--dry-run prints what it would do and writes nothing", async () => {
  const h = harness([repo("app")]);
  await runCloneRepos({ owner: "acme", all: true, dryRun: true }, h.deps);
  assert.deepEqual(h.clones, []);
  assert.deepEqual(readReposFile(h.deps.reposFile), []);
  assert.ok(h.logs.some((l) => l.includes("[dry-run]") && l.includes("git@github.com:acme/app.git")));
});

test("an empty selection leaves the repos file untouched", async () => {
  const h = harness([repo("app")]);
  h.deps.pick = async () => [];
  const result = await runCloneRepos({ owner: "acme", all: false, dryRun: false }, h.deps);
  assert.deepEqual(result, { selected: 0, cloned: 0, skipped: 0 });
  assert.deepEqual(readReposFile(h.deps.reposFile), []);
});
