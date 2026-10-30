import { execFile } from "node:child_process";
import fs from "node:fs";
import { promisify } from "node:util";
import { ESPRESSIF_VID, USB_SERIAL_JTAG_PID } from "../lib/plan.js";

const execFileAsync = promisify(execFile);

function portView(port) {
  const base = port.path.split(/[\\/]/).pop();
  const espressif = port.vendorID === ESPRESSIF_VID && port.productID === USB_SERIAL_JTAG_PID;
  const likely = espressif || /usbmodem|usbserial|wchusb|slab|jtag|usb serial/i.test(`${port.path} ${port.productName || ""}`);
  return {
    ...port,
    isEspressifJTAG: espressif,
    isLikelyDevice: likely,
    displayName: port.productName ? `${base} · ${port.productName}` : base,
    detail: [
      port.vendorID != null && port.productID != null
        ? `VID ${port.vendorID.toString(16).toUpperCase().padStart(4, "0")} / PID ${port.productID.toString(16).toUpperCase().padStart(4, "0")}`
        : "",
      port.serialNumber ? `USB 序列号 ${port.serialNumber}` : "",
    ].filter(Boolean).join(" · "),
  };
}

export async function scanPorts(showAll) {
  const found = process.platform === "win32" ? await scanWindows() : await scanMac();
  const views = found.map(portView).sort((a, b) => {
    if (a.isEspressifJTAG !== b.isEspressifJTAG) return a.isEspressifJTAG ? -1 : 1;
    if (a.isLikelyDevice !== b.isLikelyDevice) return a.isLikelyDevice ? -1 : 1;
    return a.path.localeCompare(b.path);
  });
  return showAll ? views : views.filter((port) => port.isLikelyDevice || port.isEspressifJTAG);
}

async function scanMac() {
  const names = fs.readdirSync("/dev").filter((name) => name.startsWith("cu."));
  const meta = await macUSBMeta();
  return names
    .filter((name) => name !== "cu.debug-console")
    .map((name) => {
      const pathName = `/dev/${name}`;
      const extra = meta.get(pathName) || {};
      return {
        path: pathName,
        productName: extra.productName || null,
        vendorID: extra.vendorID ?? null,
        productID: extra.productID ?? null,
        serialNumber: extra.serialNumber || null,
      };
    });
}

async function macUSBMeta() {
  const map = new Map();
  let output = "";
  try {
    output = (await execFileAsync("ioreg", ["-r", "-l", "-w", "0", "-c", "IOUSBHostDevice"], { maxBuffer: 8 * 1024 * 1024, timeout: 4000 })).stdout;
  } catch {
    return map;
  }
  const stack = [];
  for (const line of output.split("\n")) {
    const depth = line.match(/^\s*/)?.[0].length ?? 0;
    while (stack.length && stack[stack.length - 1].depth >= depth) stack.pop();
    const vendor = line.match(/"idVendor"\s*=\s*(\d+)/);
    const product = line.match(/"idProduct"\s*=\s*(\d+)/);
    const name = line.match(/"USB Product Name"\s*=\s*"([^"]*)"/);
    const serial = line.match(/"USB Serial Number"\s*=\s*"([^"]*)"/);
    const callout = line.match(/"IOCalloutDevice"\s*=\s*"([^"]+)"/);
    const current = { depth, vendorID: null, productID: null, productName: null, serialNumber: null };
    const parent = stack.at(-1);
    if (parent) Object.assign(current, parent, { depth });
    if (vendor) current.vendorID = Number(vendor[1]);
    if (product) current.productID = Number(product[1]);
    if (name) current.productName = name[1];
    if (serial) current.serialNumber = serial[1];
    stack.push(current);
    if (callout) map.set(callout[1], current);
  }
  return map;
}

async function scanWindows() {
  const script = `
$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$items = @(Get-CimInstance Win32_PnPEntity | Where-Object { $_.Name -match '\\(COM\\d+\\)' } | ForEach-Object {
  $match = [regex]::Match($_.Name, 'COM\\d+')
  $vid = $null; $pid = $null
  if ($_.PNPDeviceID -match 'VID_([0-9A-F]{4})') { $vid = [Convert]::ToInt32($Matches[1], 16) }
  if ($_.PNPDeviceID -match 'PID_([0-9A-F]{4})') { $pid = [Convert]::ToInt32($Matches[1], 16) }
  [pscustomobject]@{ path = $match.Value; productName = $_.Name; vendorID = $vid; productID = $pid; serialNumber = $null }
})
if ($items.Count -eq 0) { '[]' } else { $items | ConvertTo-Json -Compress }
`;
  try {
    const { stdout } = await execFileAsync("powershell.exe", ["-NoProfile", "-NonInteractive", "-Command", script], {
      timeout: 8000,
      windowsHide: true,
      maxBuffer: 2 * 1024 * 1024,
    });
    const parsed = JSON.parse(stdout.trim() || "[]");
    const rows = Array.isArray(parsed) ? parsed : [parsed];
    return rows.filter((row) => row?.path).map((row) => ({
      path: row.path,
      productName: row.productName || null,
      vendorID: row.vendorID ?? null,
      productID: row.productID ?? null,
      serialNumber: row.serialNumber || null,
    }));
  } catch {
    return [];
  }
}
