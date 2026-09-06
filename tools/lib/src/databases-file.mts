// databases-file.mts — config/databases.txt: which local Postgres database each repo needs.
//   <repo> <database> <port> <user> <password> [init-sql-dir, relative to the repo]
import { existsSync, readFileSync } from "node:fs";

export type DatabaseEntry = {
  repo: string;
  database: string;
  port: number;
  user: string;
  password: string;
  initDir: string | null;
};

export function parseDatabasesFile(text: string): DatabaseEntry[] {
  const entries: DatabaseEntry[] = [];
  text.split("\n").forEach((raw, index) => {
    const line = raw.trim();
    if (line === "" || line.startsWith("#")) return;
    const fields = line.split(/\s+/);
    if (fields.length < 5) {
      throw new Error(`databases file line ${index + 1}: expected "<repo> <database> <port> <user> <password> [init-sql-dir]", got "${line}"`);
    }
    const [repo, database, portText, user, password, initDir] = fields;
    const port = Number(portText);
    if (!Number.isInteger(port) || port < 1 || port > 65535) {
      throw new Error(`databases file line ${index + 1}: port must be 1-65535, got "${portText}"`);
    }
    entries.push({ repo, database, port, user, password, initDir: initDir ?? null });
  });
  return entries;
}

export function readDatabasesFile(file: string): DatabaseEntry[] {
  return existsSync(file) ? parseDatabasesFile(readFileSync(file, "utf8")) : [];
}
