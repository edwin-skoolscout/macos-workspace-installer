// layout.mts — where a repo URL lands on disk: <workspace>/<owner>/<repo>.
// Mirrors repo_dir_for_url in lib/common.sh; keep the two in step.
import { join } from "node:path";

export type RepoRef = { owner: string; name: string };

const SSH_URL = /^[\w.-]+@[\w.-]+:(?<owner>[^/\s]+)\/(?<name>[^/\s]+?)(?:\.git)?\/?$/;
const HTTP_URL = /^[a-z][a-z0-9+.-]*:\/\/[^/]+\/(?<owner>[^/\s]+)\/(?<name>[^/\s]+?)(?:\.git)?\/?$/i;

export function parseRepoUrl(url: string): RepoRef {
  const match = SSH_URL.exec(url) ?? HTTP_URL.exec(url);
  if (!match?.groups) throw new Error(`cannot find an owner and repo name in "${url}"`);
  return { owner: match.groups.owner, name: match.groups.name };
}

export function repoDirFor(url: string, workspaceDir: string): string {
  const { owner, name } = parseRepoUrl(url);
  return join(workspaceDir, owner, name);
}

export function sshUrlFor(owner: string, name: string): string {
  return `git@github.com:${owner}/${name}.git`;
}
