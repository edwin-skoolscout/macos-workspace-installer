import { test } from "node:test";
import assert from "node:assert/strict";
import { explainCloneFailure, isAuthFailure } from "./git-errors.mts";

const url = "git@github.com:skoolscout/skoolscout-com.git";

test("GitHub's refusals for private repos are recognised as authentication failures", () => {
  for (const out of [
    "git@github.com: Permission denied (publickey).\nfatal: Could not read from remote repository.",
    "remote: Repository not found.\nfatal: repository 'https://github.com/skoolscout/skoolscout-com.git/' not found",
    "fatal: could not read Username for 'https://github.com': terminal prompts disabled",
    "remote: Invalid username or token. Password authentication is not supported for Git operations.\nfatal: Authentication failed for 'https://github.com/...'",
    "Host key verification failed.\nfatal: Could not read from remote repository.",
  ]) assert.equal(isAuthFailure(out), true, out.split("\n")[0]);
  assert.equal(isAuthFailure("fatal: destination path 'x' already exists and is not an empty directory."), false);
  assert.equal(isAuthFailure("error: RPC failed; curl 56 Recv failure"), false);
});

test("explainCloneFailure tells the user how to get credentials for an auth failure", () => {
  const msg = explainCloneFailure(url, "git@github.com: Permission denied (publickey).\nfatal: Could not read from remote repository.");
  assert.match(msg, /skoolscout-com/);
  assert.match(msg, /github-auth/);
  assert.match(msg, /PAT/);
  assert.match(msg, /gh auth login/);
});

test("explainCloneFailure passes other failures through with git's output", () => {
  const msg = explainCloneFailure(url, "error: RPC failed; curl 56 Recv failure");
  assert.match(msg, /RPC failed/);
  assert.doesNotMatch(msg, /PAT/);
});

const saml = "ERROR: The 'skoolscout' organization has enabled or enforced SAML SSO.\nTo access this repository, you must use the HTTPS remote with a personal access token or SSH with an SSH key and passphrase that has been authorized for this organization.\nfatal: Could not read from remote repository.";

test("a SAML SSO refusal is explained with the Configure SSO step, not the credentials one", () => {
  const msg = explainCloneFailure(url, saml);
  assert.match(msg, /Configure SSO/);
  assert.match(msg, /github\.com\/settings\/tokens/);
  assert.doesNotMatch(msg, /github-auth/);
});
