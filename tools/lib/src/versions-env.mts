// versions-env.mts — read a pin the way install.sh does, without sourcing the file.
import { homedir } from "node:os";

// readPin — NAME from the environment, else the NAME="..." line of config/versions.env (trailing
// comments ignored), else the fallback. "$HOME" or "~" at the start is expanded.
export function readPin(
  name: string,
  env: Readonly<Record<string, string | undefined>>,
  versionsEnvText: string | null,
  fallback: string,
): string {
  const fromEnv = env[name];
  if (fromEnv) return fromEnv;
  const line = new RegExp(`^${name}="?([^"#\\n]+?)"?\\s*(?:#.*)?$`, "m");
  const raw = versionsEnvText?.match(line)?.[1]?.trim() ?? fallback;
  return raw.replace(/^(\$HOME|~)(?=\/|$)/, homedir());
}
