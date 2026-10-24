#!/usr/bin/env node
// The token cache's keeper, given to the server as MS365_MCP_AUTH_CACHE_COMMAND:
//
//   cache-wrap load|save|delete token-cache|selected-account
//
// load prints {"found":false} or {"found":true,"value":"…"}; save reads
// {"value":"…"} on stdin; delete removes the entry. Each value is kept in
// MS365_CACHE_DIR as <name>.enc, AES-256-GCM under the 32-byte key in
// MS365_CACHE_KEY (base64), with a fresh 12-byte nonce per write and the
// entry's name as associated data, so one entry's file cannot stand in for
// another's. A file is written beside its final name and renamed over it, so
// a reader never sees half of one. Without a key of the right length it exits
// 3 before reading or writing anything: the server then refuses to start
// rather than keep a sign-in in the clear. Node's own crypto alone; no
// dependency.
import { createCipheriv, createDecipheriv, randomBytes } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, renameSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const OPS = new Set(["load", "save", "delete"]);
const NAMES = new Set(["token-cache", "selected-account"]);
// A value larger than this is not a token cache: refuse it rather than
// write it.
const MAX_VALUE = 1 << 20;

function fail(code, message) {
  process.stderr.write(`cache-wrap: ${message}\n`);
  process.exit(code);
}

const [op, name, ...rest] = process.argv.slice(2);
if (!OPS.has(op) || !NAMES.has(name) || rest.length > 0) {
  fail(2, "usage: cache-wrap load|save|delete token-cache|selected-account");
}
const key = Buffer.from(process.env.MS365_CACHE_KEY || "", "base64");
if (key.length !== 32) {
  fail(3, "MS365_CACHE_KEY is not a 32-byte key; nothing is read or written");
}
const dir = process.env.MS365_CACHE_DIR || "";
if (!dir.startsWith("/")) {
  fail(2, "MS365_CACHE_DIR is not an absolute path");
}
mkdirSync(dir, { recursive: true, mode: 0o700 });
const file = join(dir, `${name}.enc`);
const aad = Buffer.from(`agentry-ms365:${name}`);

if (op === "delete") {
  rmSync(file, { force: true });
  process.exit(0);
}

if (op === "load") {
  if (!existsSync(file)) {
    process.stdout.write('{"found":false}');
    process.exit(0);
  }
  const b = readFileSync(file);
  if (b.length < 28) {
    fail(4, `${name} is not a sealed entry`);
  }
  let value;
  try {
    const d = createDecipheriv("aes-256-gcm", key, b.subarray(0, 12));
    d.setAAD(aad);
    d.setAuthTag(b.subarray(12, 28));
    value = Buffer.concat([d.update(b.subarray(28)), d.final()]).toString("utf8");
  } catch {
    fail(4, `${name} does not open under this key`);
  }
  process.stdout.write(JSON.stringify({ found: true, value }));
  process.exit(0);
}

const chunks = [];
let size = 0;
process.stdin.on("data", (c) => {
  size += c.length;
  if (size > MAX_VALUE + 64) {
    fail(5, "the value is larger than a token cache");
  }
  chunks.push(c);
});
process.stdin.on("end", () => {
  let value;
  try {
    ({ value } = JSON.parse(Buffer.concat(chunks).toString("utf8")));
  } catch {
    fail(5, "save takes {\"value\": \"…\"} on stdin");
  }
  if (typeof value !== "string" || value.length > MAX_VALUE) {
    fail(5, "save takes {\"value\": \"…\"} on stdin");
  }
  const iv = randomBytes(12);
  const c = createCipheriv("aes-256-gcm", key, iv);
  c.setAAD(aad);
  const ct = Buffer.concat([c.update(value, "utf8"), c.final()]);
  const tmp = `${file}.${randomBytes(6).toString("hex")}.tmp`;
  writeFileSync(tmp, Buffer.concat([iv, c.getAuthTag(), ct]), { mode: 0o600 });
  renameSync(tmp, file);
  process.exit(0);
});
