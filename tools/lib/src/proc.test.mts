import { test } from "node:test";
import assert from "node:assert/strict";
import { runCapture, runStatus } from "./proc.mts";

test("runCapture returns stdout and rejects on a non-zero exit", async () => {
  assert.equal(await runCapture("bash", ["-c", "printf hi"]), "hi");
  await assert.rejects(runCapture("bash", ["-c", "exit 2"]));
});

test("runStatus returns the exit code instead of rejecting", async () => {
  assert.equal(await runStatus("bash", ["-c", "exit 3"]), 3);
  assert.equal(await runStatus("bash", ["-c", "true"]), 0);
});
