import { test } from "node:test";
import assert from "node:assert/strict";
import { homedir } from "node:os";
import { join } from "node:path";
import { readPin } from "./versions-env.mts";

const text = 'NODE_VERSION="24.18.0"\nWORKSPACE_DIR="$HOME/Development/Workspaces"   # parent of <owner>/<repo>\nDATABASES_DIR="$HOME/Development/Databases"\n';

test("the environment wins over the file", () => {
  assert.equal(readPin("WORKSPACE_DIR", { WORKSPACE_DIR: "/elsewhere" }, text, "/default"), "/elsewhere");
});

test("otherwise the pin is read from versions.env with $HOME expanded and comments ignored", () => {
  assert.equal(readPin("WORKSPACE_DIR", {}, text, "/default"), join(homedir(), "Development", "Workspaces"));
  assert.equal(readPin("DATABASES_DIR", {}, text, "/default"), join(homedir(), "Development", "Databases"));
});

test("an unpinned name falls back to the default, also with $HOME expanded", () => {
  assert.equal(readPin("NOPE", {}, text, "$HOME/x"), join(homedir(), "x"));
  assert.equal(readPin("NOPE", {}, null, "/plain"), "/plain");
});
