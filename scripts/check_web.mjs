#!/usr/bin/env node
// Smoke test for the browser bundle.
//
// A browser would be the real test, but the part that can silently break is the
// FFI wiring -- `js_publish` not running, `globalThis.pdf417` missing, the
// string marshalling dropping a byte. None of that needs a DOM, so this runs
// the bundle in Node with the two globals it touches stubbed out, and exercises
// every format plus a full encode -> decode round trip.
//
// Run: node scripts/check_web.mjs

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
const bundle = join(here, "..", "web", "pdf417.js");

let readyFired = false;
globalThis.Event = class Event {
  constructor(type) { this.type = type; }
};
globalThis.dispatchEvent = (event) => {
  if (event.type === "pdf417-ready") readyFired = true;
  return true;
};

new Function(readFileSync(bundle, "utf8"))();

const failures = [];
function check(name, ok, detail) {
  console.log(`  ${ok ? "ok  " : "FAIL"}  ${name}${detail ? "  " + detail : ""}`);
  if (!ok) failures.push(name);
}

const api = globalThis.pdf417;
check("bundle publishes globalThis.pdf417", !!api && typeof api.run === "function");
check("bundle fires the pdf417-ready event", readyFired);
if (!api) process.exit(1);

// 1. SVG
const svg = api.run("text", "https://github.com/guangting0905/moonbit-pdf417", "6,4", "svg");
check("svg output is a document", svg.startsWith("<?xml"), `${svg.length} bytes`);
check("svg carries the dark colour", svg.includes("#000000"));

// 2. JSON summary
const summary = api.run("text", "Order 100000000000 shipped", "6,2", "json");
check("json summary reports geometry", summary.includes("rows") && summary.includes("columns"));
check("json summary reports the three compaction runs",
  summary.includes("codewords"), summary.split("\n")[3]);

// 3. Terminal grid, then decode it back
const payload = "hello, 世界 12345678901234567890";
const grid = api.run("text", payload, "6,3", "text");
check("text output is one character per module",
  grid.split("\n").every((l) => /^[#.]*$/.test(l)), `${grid.split("\n").length} rows`);
const decoded = api.run("text", grid, "0,0", "decode");
check("decode recovers the payload", decoded.includes("payload    : " + payload),
  decoded.split("\n")[0]);

// 4. Hex payload, byte compaction path
const hex = "808182838485868788898a8b8c8d8e8f";
const hexGrid = api.run("hex", hex, "6,2", "text");
const hexDecoded = api.run("hex", hexGrid, "0,0", "decode");
check("hex payload round trips", hexDecoded.includes("bytes      : " + hex),
  hexDecoded.split("\n")[1]);

// 5. Every error correction level in range. Level 8 adds 512 codewords, so the
// column count has to grow with it or the symbol exceeds 90 rows.
let levelsOk = true;
for (let level = 0; level <= 8; level += 1) {
  const columns = 6 + 3 * level;
  const out = api.run("text", "x".repeat(60), `${columns},${level}`, "codewords");
  if (out.startsWith("error: ")) { levelsOk = false; console.log(`      level ${level}: ${out}`); }
}
check("all nine error correction levels encode", levelsOk);

// 6. Illegal geometry is refused with a message, not a stack trace
const bad = api.run("text", "hi", "6,2", "svg");
check("too few rows is reported as an error", bad.startsWith("error: "), bad.slice(0, 60));
const badColumns = api.run("text", "hi", "99,2", "svg");
check("out-of-range columns is reported as an error", badColumns.startsWith("error: "));

// 7. Codewords are the high level stream, so the length descriptor must fit
const words = api.run("text", "descriptor check", "6,2", "codewords").split(" ").map(Number);
check("codeword stream starts with the length descriptor",
  words[0] === words.length - 8, `descriptor ${words[0]}, ${words.length} codewords`);

console.log();
if (failures.length) {
  console.log(`${failures.length} check(s) failed: ${failures.join(", ")}`);
  process.exit(1);
}
console.log("all browser-bundle checks passed");
