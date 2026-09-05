// github.mts — list an owner's repos through the gh CLI (already logged in by the github-auth step).
import { runCapture } from "@workspace-installer/lib/proc";
import { sshUrlFor } from "./layout.mts";

export type GitHubRepo = {
  owner: string;
  name: string;
  url: string;
  branch: string | null; // null: empty repo, nothing to clone
  archived: boolean;
  private: boolean;
  pushedAt: string;
};

export type Runner = (cmd: string, args: string[]) => Promise<string>;

type GhRepoJson = {
  name: string;
  defaultBranchRef: { name: string } | null;
  isArchived: boolean;
  isPrivate: boolean;
  pushedAt: string;
};

const GH_FIELDS = "name,defaultBranchRef,isArchived,isPrivate,pushedAt";

export async function listRepos(owner: string, run: Runner = runCapture): Promise<GitHubRepo[]> {
  let out: string;
  try {
    out = await run("gh", ["repo", "list", owner, "--limit", "500", "--json", GH_FIELDS]);
  } catch (err) {
    const detail = err instanceof Error ? err.message : String(err);
    throw new Error(`gh repo list ${owner} failed. Is gh logged in? Try: gh auth login\n${detail}`);
  }
  const rows = JSON.parse(out) as GhRepoJson[];
  return rows.map((r) => ({
    owner,
    name: r.name,
    url: sshUrlFor(owner, r.name),
    branch: r.defaultBranchRef?.name || null, // gh reports an empty repo as { name: "" }
    archived: r.isArchived,
    private: r.isPrivate,
    pushedAt: r.pushedAt,
  }));
}

// cloneable — archived repos are read-only history; empty ones have no branch to clone.
export function cloneable(repos: GitHubRepo[]): GitHubRepo[] {
  return repos.filter((r) => !r.archived && r.branch !== null);
}
