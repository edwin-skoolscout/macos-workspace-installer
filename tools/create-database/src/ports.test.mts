import { test } from "node:test";
import assert from "node:assert/strict";
import { createServer, type AddressInfo } from "node:net";
import { isPortBusy } from "./ports.mts";

function listen(host: string): Promise<{ port: number; close: () => Promise<void> }> {
  return new Promise((resolve, reject) => {
    const server = createServer();
    server.once("error", reject);
    server.listen({ port: 0, host }, () => {
      const { port } = server.address() as AddressInfo;
      resolve({ port, close: () => new Promise((done) => server.close(() => done())) });
    });
  });
}

test("a port nobody listens on is free", async () => {
  const probe = await listen("127.0.0.1");
  await probe.close();
  assert.equal(await isPortBusy(probe.port), false);
});

test("a listener on 127.0.0.1 makes the port busy", async () => {
  const server = await listen("127.0.0.1");
  try { assert.equal(await isPortBusy(server.port), true); } finally { await server.close(); }
});

test("a listener on ::1 only (Docker Desktop's port publishing does this) also makes it busy", async () => {
  const server = await listen("::1");
  try { assert.equal(await isPortBusy(server.port), true); } finally { await server.close(); }
});
