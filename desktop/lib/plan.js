export const FLASH_BYTES = 8 * 1024 * 1024;
export const SECTOR_SIZE = 0x1000;
export const MAX_PARTITION_FILES = 8;
export const ESPRESSIF_VID = 0x303a;
export const USB_SERIAL_JTAG_PID = 0x1001;
export const BAUD_OPTIONS = [115200, 230400, 460800, 921600];

export function parseOffset(text) {
  const value = String(text ?? "").trim().toLowerCase();
  if (!value) return null;
  if (value.startsWith("0x")) {
    const parsed = Number.parseInt(value.slice(2), 16);
    return Number.isFinite(parsed) ? parsed : null;
  }
  const parsed = Number.parseInt(value, 10);
  return Number.isFinite(parsed) ? parsed : null;
}

export function formatOffset(value) {
  return `0x${value.toString(16)}`;
}

export function defaultOffset(index) {
  if (index === 0) return "0x0";
  if (index === 1) return "0x8000";
  if (index === 2) return "0x10000";
  return "0x0";
}

export function planIssues(images) {
  const out = [];
  if (!images.length) return out;
  if (images.length > MAX_PARTITION_FILES) {
    out.push({ level: "error", message: `最多只能写入 ${MAX_PARTITION_FILES} 个文件` });
  }
  const ranges = [];
  for (const img of images) {
    const off = parseOffset(img.offsetText);
    if (off == null) {
      out.push({ level: "error", message: `${img.name}：地址 “${img.offsetText}” 无效，请使用 0x 开头的十六进制` });
      continue;
    }
    if (!img.size) out.push({ level: "error", message: `${img.name}：文件为空` });
    if (off % SECTOR_SIZE !== 0) {
      out.push({ level: "error", message: `${img.name}：地址 ${formatOffset(off)} 必须按 4 KB（0x1000）对齐` });
    }
    if (off + img.size > FLASH_BYTES) out.push({ level: "error", message: `${img.name}：超出 8 MB Flash 范围` });
    if (off === 0 && img.firstByte != null && img.firstByte !== 0xe9) {
      out.push({ level: "warning", message: `${img.name}：写入 0x0 的文件不是有效的 ESP 镜像（首字节应为 0xE9），设备可能无法启动` });
    }
    const end = off + Math.ceil(img.size / SECTOR_SIZE) * SECTOR_SIZE;
    for (const [range, other] of ranges) {
      if (range.start < end && off < range.end) {
        out.push({ level: "error", message: `${img.name} 与 ${other} 的写入区域重叠` });
      }
    }
    ranges.push([{ start: off, end: Math.max(end, off + 1) }, img.name]);
  }
  return out;
}

export function createProgressTracker(sizes) {
  const prefix = sizes.map((_, index) => sizes.slice(0, index).reduce((sum, n) => sum + n, 0));
  const total = Math.max(1, sizes.reduce((sum, n) => sum + n, 0));
  let index = 0;
  let last = 0;
  return {
    update(fraction) {
      if (fraction + 0.05 < last && index < sizes.length - 1) index += 1;
      last = fraction;
      const i = Math.min(index, sizes.length - 1);
      return [i, (prefix[i] + fraction * sizes[i]) / total];
    },
    fileFinished() {
      index = Math.min(index + 1, sizes.length - 1);
      last = 0;
    },
  };
}
