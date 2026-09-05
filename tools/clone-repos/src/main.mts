// main.mts — clone-repos CLI: pick an owner's repos, record them in config/repos.txt, clone them.
// Run through ./clone-repos.sh at the repo root, which finds Node and installs dependencies.
import { existsSync, readFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { Command } from "commander";
import { readPin } from "@workspace-installer/lib/versions-env";
import { cloneable, listRepos, type GitHubRepo } from "./github.mts";
import { repoDirFor } from "./layout.mts";
import { filterRepos, pickRepos } from "./picker.mts";
import { runInherit } from "@workspace-installer/lib/proc";
import { mergeRepos, readReposFile, writeReposFile, type RepoEntry } from "./repos-file.mts";

export type Options = { owner: string; all: boolean; filter?: string; dryRun: boolean };

// Everything with a side effect is injected so the flow is testable without gh, git or a terminal.
export type Deps = {
  listRepos: (owner: string) => Promise<GitHubRepo[]>;
  pick: (repos: GitHubRepo[], clonedUrls: ReadonlySet<string>) => Promise<GitHubRepo[]>;
  clone: (entry: RepoEntry, dir: string) => Promise<void>;
  isCloned: (dir: string) => boolean;
  reposFile: string;
  workspaceDir: string;
  log: (msg: string) => void;
};

export type Summary = { selected: number; cloned: number; skipped: number };

export async function runCloneRepos(opts: Options, deps: Deps): Promise<Summary> {
  const none: Summary = { selected: 0, cloned: 0, skipped: 0 };
  let candidates = cloneable(await deps.listRepos(opts.owner));
  if (opts.filter) candidates = filterRepos(candidates, opts.filter);
  if (candidates.length === 0) {
    deps.log(`no cloneable repos for ${opts.owner}${opts.filter ? ` matching "${opts.filter}"` : ""}`);
    return none;
  }
  const clonedUrls = new Set(
    candidates.filter((r) => deps.isCloned(repoDirFor(r.url, deps.workspaceDir))).map((r) => r.url),
  );
  const selection = opts.all ? candidates : await deps.pick(candidates, clonedUrls);
  if (selection.length === 0) {
    deps.log("nothing selected");
    return none;
  }
  const entries: RepoEntry[] = selection.map((r) => ({ url: r.url, branch: r.branch ?? "main" }));
  const { entries: merged, added } = mergeRepos(readReposFile(deps.reposFile), entries);
  if (opts.dryRun) {
    deps.log(`[dry-run] would record ${added} new repo(s) in ${deps.reposFile}`);
  } else {
    writeReposFile(deps.reposFile, merged);
    deps.log(`recorded ${added} new repo(s) in ${deps.reposFile}`);
  }
  let cloned = 0;
  let skipped = 0;
  for (const entry of entries) {
    const dir = repoDirFor(entry.url, deps.workspaceDir);
    if (deps.isCloned(dir)) {
      deps.log(`${dir} exists; skipping`);
      skipped += 1;
      continue;
    }
    if (opts.dryRun) {
      deps.log(`[dry-run] git clone --branch ${entry.branch} --recurse-submodules ${entry.url} ${dir}`);
      continue;
    }
    deps.log(`cloning ${entry.url} (${entry.branch}) into ${dir}`);
    await deps.clone(entry, dir);
    cloned += 1;
  }
  return { selected: entries.length, cloned, skipped };
}

// ---- CLI ---------------------------------------------------------------------------------------

function repoRoot(): string {
  return fileURLToPath(new URL("../../../", import.meta.url));
}

function realDeps(): Deps {
  const root = repoRoot();
  const versionsEnv = join(root, "config", "versions.env");
  return {
    listRepos: (owner) => listRepos(owner),
    pick: pickRepos,
    clone: (entry, dir) =>
      runInherit("git", ["clone", "--branch", entry.branch, "--recurse-submodules", entry.url, dir]),
    isCloned: (dir) => existsSync(join(dir, ".git")),
    reposFile: process.env.WI_REPOS_FILE ?? join(root, "config", "repos.txt"),
    workspaceDir: readPin(
      "WORKSPACE_DIR",
      process.env,
      existsSync(versionsEnv) ? readFileSync(versionsEnv, "utf8") : null,
      "$HOME/Development/Workspaces",
    ),
    log: (msg) => console.log(msg),
  };
}

const invokedDirectly =
  process.argv[1] !== undefined && resolve(process.argv[1]) === fileURLToPath(import.meta.url);

if (invokedDirectly) {
  const program = new Command()
    .name("clone-repos")
    .description(
      "Pick repos of a GitHub owner, record them in config/repos.txt and clone them into WORKSPACE_DIR/<owner>/<repo>.",
    )
    .argument("<owner>", "GitHub user or organisation")
    .option("--all", "take every cloneable repo without asking", false)
    .option("--filter <text>", "only offer repos whose name contains every space-separated term")
    .option("--dry-run", "show what would be recorded and cloned; change nothing", false)
    .action(async (owner: string, o: { all: boolean; filter?: string; dryRun: boolean }) => {
      const summary = await runCloneRepos({ owner, all: o.all, filter: o.filter, dryRun: o.dryRun }, realDeps());
      console.log(`${summary.selected} selected, ${summary.cloned} cloned, ${summary.skipped} already present`);
    });
  try {
    await program.parseAsync();
  } catch (err) {
    if (err instanceof Error && err.name === "ExitPromptError") process.exit(130); // Ctrl-C in the picker
    console.error(err instanceof Error ? err.message : String(err));
    process.exit(1);
  }
}
