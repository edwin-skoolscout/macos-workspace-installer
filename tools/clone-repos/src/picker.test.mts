import { test } from "node:test";
import assert from "node:assert/strict";
import { filterRepos, formatRepoLine } from "./picker.mts";
import type { GitHubRepo } from "./github.mts";

const repo = (name: string, extra: Partial<GitHubRepo> = {}): GitHubRepo => ({
  owner: "acme", name, url: `git@github.com:acme/${name}.git`, branch: "develop",
  archived: false, private: true, pushedAt: "2026-09-04T10:00:00Z", ...extra,
});
const repos = [repo("skoolscout-com"), repo("skoolscout-com-tenants"), repo("jefelabs-docs")];

test("filterRepos matches every space-separated term, case-insensitively, against the name", () => {
  assert.deepEqual(filterRepos(repos, "").map((r) => r.name), ["skoolscout-com", "skoolscout-com-tenants", "jefelabs-docs"]);
  assert.deepEqual(filterRepos(repos, "com ten").map((r) => r.name), ["skoolscout-com-tenants"]);
  assert.deepEqual(filterRepos(repos, "JEFE").map((r) => r.name), ["jefelabs-docs"]);
  assert.deepEqual(filterRepos(repos, "zzz"), []);
});

test("formatRepoLine shows name, branch, visibility, last push date and whether it is cloned", () => {
  const line = formatRepoLine(repo("app", { private: false }), true);
  assert.match(line, /app/);
  assert.match(line, /develop/);
  assert.match(line, /public/);
  assert.match(line, /2026-09-04/);
  assert.match(line, /cloned/);
  assert.doesNotMatch(formatRepoLine(repo("app"), false), /cloned/);
});
