import fs from "node:fs/promises";
import path from "node:path";
import { absoluteURL } from "../lib/catalog.js";
import { buildCardidPartition, CARDID_OFFSET, checkImages, classifyProduct, EXPECTED_FILES, FLASH_ORDER } from "../lib/restore.js";
import { formatOffset } from "../lib/plan.js";
import { downloadVerified, fetchJSON } from "./net.js";
import { firmwareCacheDir, restoreWorkDir } from "./paths.js";

const SITE = "https://ai-passport.folotoy.cn";

export function loadFeatured() {
  return fetchJSON(`${SITE}/api/plays/recommendations?limit=20`).then((body) => body.plays ?? []);
}

export function loadPlays(query) {
  const params = new URLSearchParams({
    tag: query.tag || "",
    bootstrap: "false",
    q: (query.search || "").trim(),
    category: query.category || "all",
    sort: query.sort || "newest",
    period: "all",
    limit: "24",
    offset: String(query.offset || 0),
  });
  return fetchJSON(`${SITE}/api/plays?${params}`).then((body) => ({
    plays: body.plays ?? [],
    total: body.pagination?.total ?? body.plays?.length ?? 0,
    hasMore: body.pagination?.hasMore ?? false,
  }));
}

export async function downloadPlay(play, onProgress) {
  const firmware = play.firmware ?? {};
  const sha = (firmware.sha256 || play.firmwareSha256 || "").toLowerCase();
  const size = firmware.size || play.firmwareSize;
  const url = absoluteURL(firmware.url || play.downloadUrl);
  if (!url || sha.length !== 64 || !size) throw new Error("该玩法暂未提供可安装的合并固件");
  const dest = path.join(firmwareCacheDir(), `${play.slug}-${sha.slice(0, 12)}.bin`);
  try {
    const cached = await fs.readFile(dest);
    const { createHash } = await import("node:crypto");
    if (cached.length === size && createHash("sha256").update(cached).digest("hex") === sha) {
      onProgress?.(1);
      return { path: dest, size: cached.length, sha256: sha, firstByte: cached[0] };
    }
  } catch { /* download */ }
  return downloadVerified(url, dest, { expectedSize: size, expectedSHA: sha, onProgress, requireESP: true });
}

export async function prepareRestore(credentials, onProgress) {
  onProgress?.("正在核对设备型号…", 0);
  let warning = null;
  try {
    const product = await fetchJSON(`https://webapp.folotoy.cn/v1/toys/sn/${credentials.sn}/product`);
    const classified = classifyProduct(product);
    if (classified.kind === "other") {
      throw new Error(`这台设备登记的型号是 ${classified.detail}，不是 AI Passport。请使用该型号对应的官方恢复页面，本程序不会为它写入 AI Passport 默认固件。`);
    }
    if (classified.kind === "unknown") warning = `无法在线确认设备型号（${classified.detail}）。写入前仍会核对设备 MAC 与 SN。`;
  } catch (error) {
    if (String(error.message).includes("不是 AI Passport")) throw error;
    warning = `无法在线确认设备型号（${error.message}）。写入前仍会核对设备 MAC 与 SN。`;
  }

  onProgress?.("正在下载默认固件清单…", 0.02);
  const manifest = await fetchJSON(`${SITE}/assets/firmwares/ai-passport-default/manifest.json`);
  if (!manifest.version || !manifest.firmwareCommit || !manifest.productKey || !manifest.hardwareVersion) {
    throw new Error("固件清单异常：缺少版本或产品信息");
  }
  const names = new Set((manifest.files || []).map((file) => file.name));
  if (manifest.files?.length !== Object.keys(EXPECTED_FILES).length || [...names].some((name) => EXPECTED_FILES[name] == null)) {
    throw new Error("固件清单异常：文件列表与预期不一致");
  }
  const dir = restoreWorkDir();
  const blobs = {};
  const totalBytes = manifest.files.reduce((sum, file) => sum + file.size, 0);
  let done = 0;
  for (const file of manifest.files) {
    if (EXPECTED_FILES[file.name] !== file.address) throw new Error(`固件清单异常：${file.name} 的写入地址异常`);
    if (!/^[0-9a-f]{64}$/.test(file.sha256)) throw new Error(`固件清单异常：${file.name} 的 SHA-256 格式无效`);
    const fileURL = new URL(`${SITE}/assets/firmwares/ai-passport-default/${file.name}`);
    fileURL.searchParams.set("v", manifest.version);
    fileURL.searchParams.set("sha", file.sha256.slice(0, 12));
    const base = done;
    const saved = await downloadVerified(fileURL.href, path.join(dir, file.name), {
      expectedSize: file.size,
      expectedSHA: file.sha256,
      onProgress: (fraction) => onProgress?.(`正在下载 ${file.name}…`, (base + fraction * file.size) / totalBytes),
    });
    blobs[file.name] = await fs.readFile(saved.path);
    done += file.size;
  }
  onProgress?.("正在校验分区表…", 1);
  checkImages(blobs);
  const cardid = buildCardidPartition(credentials, manifest);
  const cardPath = path.join(dir, "cardid.bin");
  await fs.writeFile(cardPath, cardid, { mode: 0o600 });
  const images = [];
  for (const name of FLASH_ORDER) {
    images.push({
      name,
      path: path.join(dir, name),
      size: blobs[name].length,
      offsetText: formatOffset(EXPECTED_FILES[name]),
      firstByte: blobs[name][0],
    });
  }
  images.push({
    name: "cardid.bin（设备凭据，本机生成）",
    path: cardPath,
    size: cardid.length,
    offsetText: formatOffset(CARDID_OFFSET),
    firstByte: cardid[0],
  });
  return { version: manifest.version, commit: manifest.firmwareCommit, sn: credentials.sn, warning, images };
}

export async function inspectFile(filePath) {
  const data = await fs.readFile(filePath);
  return {
    name: path.basename(filePath),
    path: filePath,
    size: data.length,
    firstByte: data[0] ?? null,
  };
}
