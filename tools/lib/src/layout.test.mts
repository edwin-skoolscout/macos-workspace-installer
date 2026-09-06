import { test } from "node:test";
import assert from "node:assert/strict";
import { parseRepoUrl, repoDirFor } from "./layout.mts";

test("parseRepoUrl handles ssh URLs", () => {
  assert.deepEqual(parseRepoUrl("git@github.com:skoolscout/skoolscout-com.git"), {
    owner: "skoolscout",
    name: "skoolscout-com",
  });
});

test("parseRepoUrl handles https URLs with or without .git", () => {
  assert.deepEqual(parseRepoUrl("https://github.com/acme/app.git"), { owner: "acme", name: "app" });
  assert.deepEqual(parseRepoUrl("https://github.com/acme/app"), { owner: "acme", name: "app" });
});

test("parseRepoUrl rejects URLs without an owner segment", () => {
  assert.throws(() => parseRepoUrl("app.git"), /owner/);
});

test("repoDirFor is <workspace>/<owner>/<name>", () => {
  assert.equal(repoDirFor("git@github.com:acme/app.git", "/ws"), "/ws/acme/app");
});
