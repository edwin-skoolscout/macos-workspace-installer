// repos-file.mts — config/repos.txt: "<git url> <branch>" per line, "#" comments.
// The same format steps/70-clone-repos.sh and doctor.sh read.
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname } from "node:path";

export type RepoEntry = { url: string; branch: string };

export const REPOS_FILE_HEADER =
  "# <git url> <branch> — cloned with --recurse-submodules into WORKSPACE_DIR/<owner>/<repo>";

export function parseReposFile(text: string): RepoEntry[] {
  const entries: RepoEntry[] = [];
  for (const raw of text.split("\n")) {
    const line = raw.trim();
    if (line === "" || line.startsWith("#")) continue;
    const [url, branch] = line.split(/\s+/);
    entries.push({ url, branch: branch ?? "main" });
  }
  return entries;
}

// Existing entries win: a hand-edited branch is not overwritten by GitHub's default.
export function mergeRepos(
  existing: RepoEntry[],
  additions: RepoEntry[],
): { entries: RepoEntry[]; added: number } {
  const seen = new Set(existing.map((e) => e.url));
  const entries = [...existing];
  let added = 0;
  for (const entry of additions) {
    if (seen.has(entry.url)) continue;
    seen.add(entry.url);
    entries.push(entry);
    added += 1;
  }
  return { entries, added };
}

export function renderReposFile(entries: RepoEntry[]): string {
  return [REPOS_FILE_HEADER, ...entries.map((e) => `${e.url} ${e.branch}`)].join("\n") + "\n";
}

export function readReposFile(file: string): RepoEntry[] {
  return existsSync(file) ? parseReposFile(readFileSync(file, "utf8")) : [];
}

export function writeReposFile(file: string, entries: RepoEntry[]): void {
  mkdirSync(dirname(file), { recursive: true });
  writeFileSync(file, renderReposFile(entries));
}
