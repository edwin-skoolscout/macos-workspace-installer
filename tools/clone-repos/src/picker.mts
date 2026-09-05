// picker.mts — searchable multi-select over an owner's repos, built on @inquirer/core.
// The stock checkbox prompt cannot filter as you type, so this is a small custom prompt:
// type to narrow, ↑↓ to move, Tab to toggle, Ctrl+A to toggle everything shown, Enter to confirm.
import {
  createPrompt,
  isDownKey,
  isEnterKey,
  isTabKey,
  isUpKey,
  makeTheme,
  useKeypress,
  usePagination,
  usePrefix,
  useState,
  type Status,
} from "@inquirer/core";
import { styleText } from "node:util";
import type { GitHubRepo } from "./github.mts";

// filterRepos — every whitespace-separated term must appear in the name, case-insensitively.
export function filterRepos(repos: GitHubRepo[], query: string): GitHubRepo[] {
  const terms = query.toLowerCase().split(/\s+/).filter(Boolean);
  return repos.filter((r) => terms.every((t) => r.name.toLowerCase().includes(t)));
}

export function formatRepoLine(repo: GitHubRepo, cloned: boolean): string {
  const parts = [
    repo.name.padEnd(36),
    (repo.branch ?? "-").padEnd(10),
    (repo.private ? "private" : "public").padEnd(8),
    repo.pushedAt.slice(0, 10),
  ];
  if (cloned) parts.push(styleText("dim", "cloned"));
  return parts.join(" ");
}

type PickerConfig = {
  message: string;
  repos: GitHubRepo[];
  clonedUrls: ReadonlySet<string>;
  pageSize?: number;
};

const pickPrompt = createPrompt<GitHubRepo[], PickerConfig>((config, done) => {
  const theme = makeTheme();
  const [status, setStatus] = useState<Status>("idle");
  const [query, setQuery] = useState("");
  const [active, setActive] = useState(0);
  const [checked, setChecked] = useState<ReadonlySet<string>>(new Set<string>());
  const prefix = usePrefix({ status, theme });

  const visible = filterRepos(config.repos, query);
  const cursor = Math.min(active, Math.max(visible.length - 1, 0));

  useKeypress((key, rl) => {
    if (isEnterKey(key)) {
      setStatus("done");
      done(config.repos.filter((r) => checked.has(r.url)));
      return;
    }
    if (isUpKey(key) || isDownKey(key)) {
      rl.clearLine(0);
      rl.write(query); // arrows must leave the typed query alone
      if (visible.length > 0) {
        const offset = isUpKey(key) ? -1 : 1;
        setActive((cursor + offset + visible.length) % visible.length);
      }
      return;
    }
    if (isTabKey(key)) {
      rl.clearLine(0);
      rl.write(query); // drop the tab character readline just inserted
      const item = visible[cursor];
      if (item) {
        const next = new Set(checked);
        if (next.has(item.url)) next.delete(item.url);
        else next.add(item.url);
        setChecked(next);
      }
      return;
    }
    if (key.ctrl && key.name === "a") {
      rl.clearLine(0);
      rl.write(query);
      const allOn = visible.length > 0 && visible.every((r) => checked.has(r.url));
      const next = new Set(checked);
      for (const r of visible) {
        if (allOn) next.delete(r.url);
        else next.add(r.url);
      }
      setChecked(next);
      return;
    }
    setQuery(rl.line);
    setActive(0);
  });

  const page = usePagination({
    items: visible,
    active: cursor,
    pageSize: config.pageSize ?? 12,
    loop: true,
    renderItem: ({ item, isActive }) => {
      const box = checked.has(item.url) ? styleText("green", "◉") : "◯";
      const line = `${isActive ? "❯" : " "} ${box} ${formatRepoLine(item, config.clonedUrls.has(item.url))}`;
      return isActive ? theme.style.highlight(line) : line;
    },
  });

  const message = theme.style.message(config.message, status);
  if (status === "done") {
    return `${prefix} ${message} ${theme.style.answer(`${checked.size} selected`)}`;
  }
  const body = visible.length > 0 ? page : theme.style.error("no repos match");
  const help = theme.style.help("type to search • ↑↓ move • tab select • ctrl+a all shown • ⏎ confirm");
  return [`${prefix} ${message} ${query}`, body, `${checked.size} selected`, help].join("\n");
});

export function pickRepos(repos: GitHubRepo[], clonedUrls: ReadonlySet<string>): Promise<GitHubRepo[]> {
  return pickPrompt({ message: "Select repos to clone", repos, clonedUrls });
}
