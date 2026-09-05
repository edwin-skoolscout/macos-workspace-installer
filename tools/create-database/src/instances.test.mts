import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  chooseFreePort, instanceDir, isInstance, listInstances, readMajor, readPort,
  renderConfAdditions, renderHba, withPort,
} from "./instances.mts";

function base(): string {
  const dir = mkdtempSync(join(tmpdir(), "dbs-"));
  mkdirSync(join(dir, "beta"));
  writeFileSync(join(dir, "beta", "PG_VERSION"), "13\n");
  mkdirSync(join(dir, "alpha"));
  writeFileSync(join(dir, "alpha", "PG_VERSION"), "15\n");
  mkdirSync(join(dir, "not-a-cluster"));
  writeFileSync(join(dir, "stray-file"), "");
  return dir;
}

test("instanceDir joins the base dir and the name", () => {
  assert.equal(instanceDir("/dbs", "mydb"), "/dbs/mydb");
});

test("isInstance means a PG_VERSION file exists", () => {
  const dir = base();
  assert.equal(isInstance(join(dir, "alpha")), true);
  assert.equal(isInstance(join(dir, "not-a-cluster")), false);
  assert.equal(isInstance(join(dir, "missing")), false);
});

test("listInstances returns initialised clusters sorted by name, [] for a missing base", () => {
  const dir = base();
  assert.deepEqual(listInstances(dir).map((i) => i.name), ["alpha", "beta"]);
  assert.equal(listInstances(join(dir, "alpha")).length, 0);
  assert.deepEqual(listInstances(join(dir, "nope")), []);
});

test("readMajor parses PG_VERSION, including the old two-part form", () => {
  const dir = base();
  assert.equal(readMajor(join(dir, "beta")), 13);
  writeFileSync(join(dir, "beta", "PG_VERSION"), "9.6\n");
  assert.equal(readMajor(join(dir, "beta")), 9);
  assert.equal(readMajor(join(dir, "not-a-cluster")), null);
});

test("readPort takes the last uncommented port line, as postgres does", () => {
  assert.equal(readPort("port = 5433\nlisten_addresses = 'localhost'\nport = 5440\n"), 5440);
  assert.equal(readPort("#port = 5432\n  port=5434   # chosen\n"), 5434);
  assert.equal(readPort("#port = 5432\n"), null);
});

test("withPort appends a port line so it wins over earlier ones", () => {
  assert.equal(withPort("port = 5433\n", 5440), "port = 5433\nport = 5440\n");
  assert.equal(withPort("x = 1", 5440), "x = 1\nport = 5440\n");
});

test("renderHba trusts the socket and requires scram on localhost; conf additions bind localhost and the port", () => {
  const hba = renderHba();
  assert.match(hba, /^local\s+all\s+all\s+trust$/m);
  assert.match(hba, /^host\s+all\s+all\s+127\.0\.0\.1\/32\s+scram-sha-256$/m);
  assert.match(hba, /^host\s+all\s+all\s+::1\/128\s+scram-sha-256$/m);
  const conf = renderConfAdditions(5440);
  assert.match(conf, /^listen_addresses = 'localhost'$/m);
  assert.match(conf, /^port = 5440$/m);
});

test("chooseFreePort returns the first free port from 5433 and fails when the range is exhausted", async () => {
  assert.equal(await chooseFreePort(() => false), 5433);
  assert.equal(await chooseFreePort((p) => p < 5436), 5436);
  await assert.rejects(chooseFreePort(() => true), /5433.*5599/);
});
