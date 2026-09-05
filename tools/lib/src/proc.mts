// proc.mts — the two ways this tool runs external commands.
import { execFile, spawn } from "node:child_process";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);

// runCapture — run and return stdout (gh JSON). Rejects on a non-zero exit.
export async function runCapture(cmd: string, args: string[]): Promise<string> {
  const { stdout } = await execFileAsync(cmd, args, { encoding: "utf8", maxBuffer: 16 * 1024 * 1024 });
  return stdout;
}

// runInherit — run with the terminal attached (git clone progress). Rejects on a non-zero exit.
export function runInherit(cmd: string, args: string[]): Promise<void> {
  return new Promise((resolve, reject) => {
    const child = spawn(cmd, args, { stdio: "inherit" });
    child.on("error", reject);
    child.on("exit", (code, signal) => {
      if (code === 0) resolve();
      else reject(new Error(`${cmd} ${args.join(" ")} exited with ${signal ?? code}`));
    });
  });
}

// runStatus — run quietly and return the exit code (pg_ctl status, pg_isready). Never rejects
// on a non-zero exit; a missing binary still rejects.
export function runStatus(cmd: string, args: string[]): Promise<number> {
  return new Promise((resolve, reject) => {
    const child = spawn(cmd, args, { stdio: "ignore" });
    child.on("error", reject);
    child.on("exit", (code) => resolve(code ?? 1));
  });
}
