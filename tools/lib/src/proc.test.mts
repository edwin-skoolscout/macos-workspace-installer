import { test } from "node:test";
import assert from "node:assert/strict";
import { runCapture, runInheritCapture, runStatus } from "./proc.mts";

test("runCapture returns stdout and rejects on a non-zero exit", async () => {
  assert.equal(await runCapture("bash", ["-c", "printf hi"]), "hi");
  await assert.rejects(runCapture("bash", ["-c", "exit 2"]));
});

test("runStatus returns the exit code instead of rejecting", async () => {
  assert.equal(await runStatus("bash", ["-c", "exit 3"]), 3);
  assert.equal(await runStatus("bash", ["-c", "true"]), 0);
});

test("runInheritCapture rejects with the child's stderr in the message", async () => {
  await assert.rejects(runInheritCapture("bash", ["-c", "echo oops-from-stderr >&2; exit 3"]), /oops-from-stderr/);
  await runInheritCapture("bash", ["-c", "true"]);
});
