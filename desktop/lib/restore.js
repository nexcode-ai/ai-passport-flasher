import { buildCardid } from "./nvs.js";

export const CARDID_OFFSET = 0x356000;
export const EXPECTED_FILES = {
  "bootloader.bin": 0x0,
  "partition-table.bin": 0x8000,
  "trae_card.bin": 0x10000,
  "imgava.bin": 0x3fa000,
};
export const FLASH_ORDER = ["bootloader.bin", "partition-table.bin", "trae_card.bin", "imgava.bin"];

export function parseCredentials(link) {
  const text = String(link ?? "").trim();
  let query = text;
  try {
    const url = new URL(text);
    if (url.search) query = url.search.slice(1);
  } catch {
    const q = text.indexOf("?");
    if (q >= 0) query = text.slice(q + 1);
  }
  const hash = query.indexOf("#");
  if (hash >= 0) query = query.slice(0, hash);
  const params = new URLSearchParams(query);
  const sn = params.get("s");
  const key = params.get("k");
  if (!sn || !key) throw new Error("无法从链接中读取 SN 和 KEY。请粘贴设备专属页面的完整链接（包含 ?s=…&k=…）。");
  return validateCredentials(sn, key);
}

export function validateCredentials(sn, key) {
  const serial = String(sn ?? "").trim().slice(0, 80).toLowerCase();
  const secret = String(key ?? "").trim().slice(0, 256);
  if (!/^[0-9a-f]{12}$/.test(serial)) throw new Error("SN 格式无效：应为 12 位十六进制字符（即设备 MAC 地址）。");
  if (!secret || Buffer.from(secret, "utf8").length > 64 || secret.includes("\0")) {
    throw new Error("KEY 无效：长度应为 1–64 字节。");
  }
  return { sn: serial, key: secret };
}

function norm(value) {
  if (typeof value !== "string") return null;
  const text = value.trim().toLowerCase().replaceAll("_", "-").replaceAll(" ", "-");
  if (!text) return null;
  if (text === "jd-passport" || text === "watcha-passport") return text;
  if (text === "trae" || text === "traecard" || text.startsWith("trae-") || text.includes("trae-card")) return "trae";
  return "ai-passport";
}

export function classifyProduct(json) {
  if (!json || typeof json !== "object") return { kind: "unknown", detail: "响应格式未知" };
  const data = json.data && typeof json.data === "object" ? json.data : null;
  const product = data?.device || data?.product || json.device || json.product || data || json;
  const keys = ["product_key", "productKey", "product_type", "productType", "type", "product_code", "productCode"];
  if (keys.some((key) => norm(product?.[key]) === "watcha-passport")) return { kind: "other", detail: "watcha-passport" };
  let kind = null;
  const productKey = norm(product?.product_key ?? product?.productKey);
  if (productKey) kind = productKey;
  else if (typeof (product?.is_trae ?? product?.isTrae) === "boolean") kind = (product.is_trae ?? product.isTrae) ? "trae" : "ai-passport";
  else kind = keys.map((key) => norm(product?.[key])).find(Boolean) ?? null;
  if (!kind) return { kind: "unknown", detail: "未返回产品型号" };
  return kind === "ai-passport" ? { kind: "aiPassport" } : { kind: "other", detail: kind };
}

export function parsePartitionTable(data) {
  const bytes = Buffer.from(data);
  const out = {};
  let i = 0;
  const u32 = (offset) => bytes[offset] | (bytes[offset + 1] << 8) | (bytes[offset + 2] << 16) | (bytes[offset + 3] << 24);
  while (i + 32 <= bytes.length && bytes[i] === 0xaa && bytes[i + 1] === 0x50) {
    const raw = bytes.subarray(i + 12, i + 28);
    const end = raw.indexOf(0);
    const name = raw.subarray(0, end < 0 ? raw.length : end).toString("utf8");
    out[name] = { type: bytes[i + 2], subtype: bytes[i + 3], offset: u32(i + 4), size: u32(i + 8), name };
    i += 32;
  }
  return out;
}

export function checkImages(blobs) {
  const boot = blobs["bootloader.bin"];
  const table = blobs["partition-table.bin"];
  const app = blobs["trae_card.bin"];
  const ava = blobs["imgava.bin"];
  if (!boot || !table || !app || !ava) throw new Error("固件清单异常：缺少文件");
  if (boot[0] !== 0xe9 || app[0] !== 0xe9) throw new Error("bootloader.bin / trae_card.bin 不是有效的 ESP 固件镜像");
  if (table.length !== 3072) throw new Error("默认固件分区表与 AI Passport 不匹配：分区表大小应为 3072 字节");
  const parts = parsePartitionTable(table);
  const expect = (name, offset, size) => {
    const part = parts[name];
    if (!part || part.offset !== offset || part.size !== size) {
      throw new Error(`默认固件分区表与 AI Passport 不匹配：${name} 分区位置不符`);
    }
  };
  expect("factory", 0x10000, 0x300000);
  expect("cardid", CARDID_OFFSET, 0x4000);
  expect("imgava", 0x3fa000, 0x100000);
  expect("imguser", 0x35a000, 0x20000);
  if (parts.recovery) throw new Error("默认固件分区表与 AI Passport 不匹配：包含不兼容的 recovery 分区");
  if (ava.length !== 0x100000 || ava.subarray(0, 4).toString("utf8") !== "AVA1") {
    throw new Error("默认固件分区表与 AI Passport 不匹配：默认头像资源无效");
  }
}

export function buildCardidPartition(credentials, manifest) {
  return buildCardid({
    sn: credentials.sn,
    deviceSecret: credentials.key,
    productKey: manifest.productKey,
    hardwareVersion: manifest.hardwareVersion,
  });
}
