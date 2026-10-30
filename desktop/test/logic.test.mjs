import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import test from "node:test";
import { chipIn, eventsIn, flashSizeIn, macIn, stripANSI, summarize } from "../lib/esptool-output.js";
import { buildCardid } from "../lib/nvs.js";
import { createProgressTracker, planIssues } from "../lib/plan.js";
import { classifyProduct, parseCredentials, validateCredentials } from "../lib/restore.js";

function sha256(buffer) {
  return createHash("sha256").update(buffer).digest("hex");
}

test("cardid NVS matches the official generator", () => {
  const cases = [
    ["348518a1b2c3", "TestKey-ABCdef0123456789", "folotoy", "v1.0.0", "5512a73e0ed3cd0b64dd8002a014e018282db58773c3fbed76f5ab19801eace5"],
    ["00ff00ff00ff", "k".repeat(64), "p".repeat(16), "12345678", "af5904d76dcdc25ed022c129753b4e92063309d44427b392313fb57f259fb33e"],
    ["abcdefabcdef", "密钥测试🙂", "folotoy", "v1", "6e7d1fec32972e67ba66b20b73d49685400bddeb23caec1e7eb1f7641231f551"],
  ];
  for (const [sn, deviceSecret, productKey, hardwareVersion, digest] of cases) {
    const data = buildCardid({ sn, deviceSecret, productKey, hardwareVersion });
    assert.equal(data.length, 0x4000);
    assert.equal(sha256(data), digest, sn);
  }
});

test("cardid NVS rejects bad input", () => {
  assert.throws(() => buildCardid({ sn: "348518A1B2C3", deviceSecret: "k", productKey: "p", hardwareVersion: "v" }));
  assert.throws(() => buildCardid({ sn: "348518a1b2c3", deviceSecret: "k".repeat(65), productKey: "p", hardwareVersion: "v" }));
  assert.throws(() => buildCardid({ sn: "348518a1b2c3", deviceSecret: "k", productKey: "p", hardwareVersion: "123456789" }));
});

test("esptool output parser matches the macOS app", () => {
  const header = `Connected to ESP32-C3 on /dev/cu.usbmodem1101:
Chip type:          ESP32-C3 (QFN32) (revision v0.4)
MAC:                34:85:18:AA:BB:CC
Detected flash size: 8MB
`;
  assert.equal(macIn(header), "34:85:18:aa:bb:cc");
  assert.equal(flashSizeIn(header), "8MB");
  assert.equal(chipIn(header), "ESP32-C3 (QFN32) (revision v0.4)");
  assert.deepEqual(eventsIn("Writing at 0x00010000 [=====>      ]  42.5% 212992/501234 bytes..."), [{ type: "progress", value: 0.425 }]);
  assert.equal(eventsIn("Wrote 834624 bytes (501234 compressed) at 0x00000000 in 6.1 seconds.").some((event) => event.type === "fileWritten"), true);
  assert.equal(eventsIn("Hard resetting via RTS pin...").some((event) => event.type === "resetting"), true);
  assert.equal(chipIn("Chip is ESP32-C3 (QFN32) (revision v0.4)"), "ESP32-C3 (QFN32) (revision v0.4)");
  assert.deepEqual(eventsIn("Writing at 0x0001c000... (12 %)"), [{ type: "progress", value: 0.12 }]);
  assert.equal(stripANSI("\u001B[1;32mOK\u001B[0m done"), "OK done");
  assert.match(summarize("A fatal error occurred: Failed to connect to ESP32-C3: No serial data received."), /下载模式/);
  assert.match(summarize("Could not exclusively lock port /dev/cu.usbmodem1: Resource temporarily unavailable"), /占用/);
});

test("write progress spans files", () => {
  const tracker = createProgressTracker([100, 300]);
  assert.equal(tracker.update(0.5)[1], 0.125);
  tracker.fileFinished();
  const [index, overall] = tracker.update(0.5);
  assert.equal(index, 1);
  assert.equal(overall, 0.625);
});

test("plan validator flags overlap and bad headers", () => {
  const issues = planIssues([
    { name: "a.bin", size: 0x2000, offsetText: "0x0", firstByte: 0x00 },
    { name: "b.bin", size: 0x1000, offsetText: "0x1000", firstByte: 0xe9 },
  ]);
  assert.equal(issues.some((issue) => issue.level === "warning"), true);
  assert.equal(issues.some((issue) => issue.message.includes("重叠")), true);
});

test("restore credentials and product classification", () => {
  assert.deepEqual(parseCredentials("https://ai-passport.folotoy.cn/d?s=348518a1b2c3&k=secret-key"), {
    sn: "348518a1b2c3",
    key: "secret-key",
  });
  assert.throws(() => validateCredentials("zz", "k"));
  assert.deepEqual(classifyProduct({ data: { product: { product_key: "trae" } } }), { kind: "other", detail: "trae" });
  assert.deepEqual(classifyProduct({ data: { product: { productKey: "ai-passport" } } }), { kind: "aiPassport" });
});
