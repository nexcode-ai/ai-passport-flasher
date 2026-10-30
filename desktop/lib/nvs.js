/** 16 KB cardid NVS partition. Byte-for-byte match of the macOS app / official restore page. */

const PARTITION_SIZE = 0x4000;
const PAGE_SIZE = 4096;
const ENTRY_SIZE = 32;
const ENTRIES_PER_PAGE = 126;

const crcTable = Array.from({ length: 256 }, (_, i) => {
  let c = i;
  for (let n = 0; n < 8; n += 1) c = (c & 1) !== 0 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
  return c >>> 0;
});

export function crc32(bytes) {
  let crc = 0;
  for (const b of bytes) crc = crcTable[(crc ^ b) & 0xff] ^ (crc >>> 8);
  return (crc ^ 0xffffffff) >>> 0;
}

function putU16(buf, offset, value) {
  buf[offset] = value & 0xff;
  buf[offset + 1] = (value >> 8) & 0xff;
}

function putU32(buf, offset, value) {
  for (let i = 0; i < 4; i += 1) buf[offset + i] = (value >>> (8 * i)) & 0xff;
}

function utf8(value) {
  return Buffer.from(value, "utf8");
}

export function buildCardid({ sn, deviceSecret, productKey, hardwareVersion }) {
  if (!/^[0-9a-f]{12}$/.test(sn)) {
    throw new Error("SN 必须是 12 位小写十六进制字符（设备 MAC 地址）");
  }
  for (const [name, value, max] of [
    ["DeviceSecret", deviceSecret, 64],
    ["ProductKey", productKey, 16],
    ["HardwareVersion", hardwareVersion, 8],
  ]) {
    const count = utf8(value).length;
    if (count === 0 || count > max || value.includes("\0")) {
      throw new Error(`${name} 长度必须为 1–${max} 字节，且不能包含 NUL 字符`);
    }
  }

  const page = createPage(0);
  writeNamespace(page, "folotoy-key", 1);
  writeString(page, 1, "DeviceKey", sn);
  writeString(page, 1, "DeviceSecret", deviceSecret);
  writeString(page, 1, "ProductKey", productKey);
  writeString(page, 1, "HardwareVersion", hardwareVersion);

  const out = Buffer.alloc(PARTITION_SIZE, 0xff);
  Buffer.from(page.data).copy(out, 0, 0, PAGE_SIZE);
  return out;
}

function createPage(sequence) {
  const data = new Uint8Array(PAGE_SIZE).fill(0xff);
  const bitmap = new Uint8Array(32).fill(0xff);
  putU32(data, 0, 0xfffffffe);
  putU32(data, 4, sequence);
  data[8] = 0xfe;
  putU32(data, 28, crc32(data.subarray(4, 28)));
  return { data, bitmap, entryCount: 0 };
}

function append(page, bytes, span) {
  if (page.entryCount + span > ENTRIES_PER_PAGE) throw new Error("cardid NVS page is full");
  const start = 64 + page.entryCount * ENTRY_SIZE;
  page.data.set(bytes, start);
  for (let n = 0; n < span; n += 1) {
    const bit = page.entryCount * 2;
    page.bitmap[bit >> 3] &= ~((1 << (bit & 7)) & 0xff);
    page.data.set(page.bitmap, 32);
    page.entryCount += 1;
  }
}

function baseEntry(ns, type, span, key) {
  const keyBytes = utf8(key);
  if (keyBytes.length > 15) throw new Error(`NVS key is too long: ${key}`);
  const entry = new Uint8Array(ENTRY_SIZE).fill(0xff);
  entry[0] = ns;
  entry[1] = type;
  entry[2] = span;
  entry[3] = 0xff;
  entry.fill(0, 8, 24);
  entry.set(keyBytes, 8);
  return entry;
}

function entryCRC(entry) {
  const mixed = Buffer.concat([Buffer.from(entry.subarray(0, 4)), Buffer.from(entry.subarray(8, 32))]);
  return crc32(mixed);
}

function writeNamespace(page, name, id) {
  const entry = baseEntry(0, 0x01, 1, name);
  entry[24] = id;
  putU32(entry, 4, entryCRC(entry));
  append(page, entry, 1);
}

function writeString(page, namespace, key, value) {
  const bytes = Buffer.concat([utf8(value), Buffer.from([0])]);
  const dataEntries = Math.ceil(bytes.length / ENTRY_SIZE);
  const entry = baseEntry(namespace, 0x21, dataEntries + 1, key);
  putU16(entry, 24, bytes.length);
  putU32(entry, 28, crc32(bytes));
  putU32(entry, 4, entryCRC(entry));
  append(page, entry, 1);
  const payload = new Uint8Array(dataEntries * ENTRY_SIZE).fill(0xff);
  payload.set(bytes, 0);
  append(page, payload, dataEntries);
}
