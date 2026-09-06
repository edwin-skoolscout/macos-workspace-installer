// sync.mts — "the databases the cloned repos need": for every config/databases.txt entry whose
// repo is on disk (or named in --repos), create/start its instance and run the repo's init
// scripts once, the way the repo's docker-compose Postgres container did on first start.
import { existsSync, readdirSync, rmSync } from "node:fs";
import { join } from "node:path";
import { readDatabasesFile } from "@workspace-installer/lib/databases-file";
import { parseRepoUrl, repoDirFor } from "@workspace-installer/lib/layout";
import { readReposFile } from "@workspace-installer/lib/repos-file";
import type { CreateOptions, CreateResult, Deps } from "./main.mts";
import { instanceDir, isInstance, readMajor } from "./instances.mts";
import { cmd } from "./postgres.mts";

export type SyncOptions = { repos?: string[]; dryRun: boolean };

export type SyncDeps = Deps & {
  reposFile: string;
  databasesFile: string;
  workspaceDir: string;
  create: (opts: CreateOptions, deps: Deps) => Promise<CreateResult>;
};

export type SyncResult = { repo: string; database: string; port: number; created: boolean; initScripts: number };

// clonedRepoDirs — repo name → directory, for every repos.txt entry that exists on disk
function clonedRepoDirs(deps: SyncDeps): Map<string, string> {
  const dirs = new Map<string, string>();
  for (const entry of readReposFile(deps.reposFile)) {
    const dir = repoDirFor(entry.url, deps.workspaceDir);
    if (existsSync(join(dir, ".git"))) dirs.set(parseRepoUrl(entry.url).name, dir);
  }
  return dirs;
}

export async function runSync(opts: SyncOptions, deps: SyncDeps): Promise<SyncResult[]> {
  const cloned = clonedRepoDirs(deps);
  const wanted = opts.repos ? new Set(opts.repos) : null;
  const results: SyncResult[] = [];
  for (const entry of readDatabasesFile(deps.databasesFile)) {
    if (wanted ? !wanted.has(entry.repo) : !cloned.has(entry.repo)) continue;
    const repoDir = cloned.get(entry.repo);
    if (!repoDir) {
      deps.log(`${entry.repo}: not cloned; skipping ${entry.database}`);
      continue;
    }
    deps.log(`${entry.repo}: database ${entry.database} on port ${entry.port}`);
    const result = await deps.create(
      { name: entry.database, user: entry.user, password: entry.password, port: entry.port, dryRun: opts.dryRun },
      deps,
    );
    let initScripts = 0;
    if (result.databaseCreated && entry.initDir) {
      const dir = join(repoDir, entry.initDir);
      const files = existsSync(dir) ? readdirSync(dir).filter((f) => f.endsWith(".sql")).sort() : [];
      const bin = deps.binDir(result.major);
      for (const file of files) {
        const [c, args] = cmd.psqlFile(bin, result.port, entry.user, entry.database, join(dir, file));
        if (opts.dryRun) deps.log(`[dry-run] ${c} ${args.join(" ")}`);
        else await deps.run(c, args);
        initScripts += 1;
      }
    }
    results.push({ repo: entry.repo, database: entry.database, port: result.port, created: result.databaseCreated, initScripts });
  }
  return results;
}

export type ResetDeps = SyncDeps & { confirm: (message: string) => Promise<boolean> };

// runReset — the `make db-reset` equivalent for a declared database: stop, delete the data
// directory, recreate through the sync flow so the init scripts run again. null when declined.
export async function runReset(database: string, opts: { dryRun: boolean }, deps: ResetDeps): Promise<SyncResult | null> {
  const entry = readDatabasesFile(deps.databasesFile).find((e) => e.database === database);
  if (!entry) throw new Error(`${database} is not declared in ${deps.databasesFile} (databases.txt); reset only knows the databases declared there`);
  if (!clonedRepoDirs(deps).has(entry.repo)) throw new Error(`${entry.repo} is not cloned; nothing to reset ${database} for`);
  const dataDir = instanceDir(deps.baseDir, database);
  if (isInstance(dataDir)) {
    if (!(await deps.confirm(`Delete ${dataDir} and recreate ${database} from scratch?`))) {
      deps.log("reset cancelled");
      return null;
    }
    const bin = deps.binDir(readMajor(dataDir));
    if (opts.dryRun) {
      deps.log(`[dry-run] ${cmd.stop(bin, dataDir).flat().join(" ")} (if running)`);
      deps.log(`[dry-run] rm -rf ${dataDir}`);
    } else {
      if ((await deps.status(...cmd.status(bin, dataDir))) === 0) await deps.run(...cmd.stop(bin, dataDir));
      rmSync(dataDir, { recursive: true, force: true });
      deps.log(`deleted ${dataDir}`);
    }
  }
  const results = await runSync({ repos: [entry.repo], dryRun: opts.dryRun }, deps);
  return results.find((r) => r.database === database) ?? null;
}
