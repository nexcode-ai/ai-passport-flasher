import { createHash } from "node:crypto";
import fs from "node:fs/promises";
import path from "node:path";

const UA = "AIPassportFlasher/0.0.1";

export async function fetchJSON(url) {
  const response = await fetch(url, { headers: { Accept: "application/json", "User-Agent": UA } });
  const text = await response.text();
  let body = null;
  try { body = JSON.parse(text); } catch { body = null; }
  if (!response.ok) {
    const detail = body?.detail ? `服务器返回：${body.detail}` : `下载失败（HTTP ${response.status}）`;
    throw new Error(detail);
  }
  return body;
}

export async function downloadVerified(url, dest, { expectedSize, expectedSHA, onProgress, requireESP = false } = {}) {
  const response = await fetch(url, { headers: { Accept: "*/*", "User-Agent": UA } });
  if (!response.ok) throw new Error(`下载失败（HTTP ${response.status}）`);
  const total = expectedSize || Number(response.headers.get("content-length")) || 0;
  const reader = response.body.getReader();
  const chunks = [];
  let received = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    chunks.push(Buffer.from(value));
    received += value.byteLength;
    if (total && onProgress) onProgress(Math.min(1, received / total));
  }
  const data = Buffer.concat(chunks);
  if (expectedSize && data.length !== expectedSize) {
    throw new Error(`文件大小校验失败：应为 ${expectedSize} 字节，实际 ${data.length} 字节`);
  }
  const sha256 = createHash("sha256").update(data).digest("hex");
  if (expectedSHA && sha256 !== expectedSHA.toLowerCase()) throw new Error("SHA-256 校验失败，文件可能已损坏，已丢弃");
  if (requireESP && data[0] !== 0xe9) throw new Error("不是有效的 ESP 固件镜像");
  await fs.mkdir(path.dirname(dest), { recursive: true });
  await fs.writeFile(dest, data);
  if (onProgress) onProgress(1);
  return { path: dest, size: data.length, sha256, firstByte: data[0] ?? null };
}
