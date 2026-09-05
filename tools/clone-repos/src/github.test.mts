import { test } from "node:test";
import assert from "node:assert/strict";
import { listRepos, cloneable, type GitHubRepo } from "./github.mts";

const fixture = JSON.stringify([
  { name: "app", isArchived: false, isPrivate: true, pushedAt: "2026-09-04T10:00:00Z", defaultBranchRef: { name: "develop" } },
  { name: "old", isArchived: true, isPrivate: true, pushedAt: "2024-01-01T00:00:00Z", defaultBranchRef: { name: "main" } },
  { name: "empty", isArchived: false, isPrivate: false, pushedAt: "2026-01-01T00:00:00Z", defaultBranchRef: null, isEmpty: true },
  { name: "blank", isArchived: false, isPrivate: false, pushedAt: "2026-01-01T00:00:00Z", defaultBranchRef: { name: "" }, isEmpty: true },
]);

test("listRepos asks gh for the owner's repos and maps them to ssh URLs and branches", async () => {
  const calls: string[][] = [];
  const run = async (cmd: string, args: string[]) => { calls.push([cmd, ...args]); return fixture; };
  const repos = await listRepos("acme", run);
  assert.deepEqual(calls[0]?.slice(0, 4), ["gh", "repo", "list", "acme"]);
  assert.deepEqual(repos.map((r) => r.name), ["app", "old", "empty", "blank"]);
  assert.equal(repos[0]?.url, "git@github.com:acme/app.git");
  assert.equal(repos[0]?.branch, "develop");
  assert.equal(repos[2]?.branch, null);
  assert.equal(repos[3]?.branch, null, "gh reports an empty repo as defaultBranchRef.name \"\"");
  assert.equal(repos[1]?.archived, true);
});

test("cloneable drops archived repos and empty ones, whether gh says null or a blank branch name", async () => {
  const repos = await listRepos("acme", async () => fixture);
  assert.deepEqual(cloneable(repos).map((r: GitHubRepo) => r.name), ["app"]);
});

test("listRepos turns a gh failure into a hint to log in", async () => {
  await assert.rejects(
    listRepos("acme", async () => { throw new Error("gh: not logged in"); }),
    /gh auth login/,
  );
});
