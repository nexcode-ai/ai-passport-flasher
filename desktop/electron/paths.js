import { app } from "electron";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));

export function repoRoot() {
  return path.resolve(here, "../..");
}

export function bridgeDir() {
  return path.join(app.getAppPath(), "simulator");
}

export function simulatorRuntimeDir() {
  return app.isPackaged
    ? path.join(process.resourcesPath, "simulator")
    : path.join(repoRoot(), "Resources", "Simulator");
}

export function esptoolExecutable() {
  if (process.platform === "win32") {
    const candidate = app.isPackaged
      ? path.join(process.resourcesPath, "esptool", "esptool.exe")
      : path.join(repoRoot(), "Vendor", "win", "esptool.exe");
    return fs.existsSync(candidate) ? candidate : null;
  }
  const candidate = app.isPackaged
    ? path.join(process.resourcesPath, "esptool", "esptool")
    : path.join(repoRoot(), "Vendor", "esptool", "esptool");
  return fs.existsSync(candidate) ? candidate : null;
}

export function nodeExecutable() {
  if (process.platform === "win32") {
    const candidate = app.isPackaged
      ? path.join(process.resourcesPath, "node", "node.exe")
      : path.join(repoRoot(), "Vendor", "win", "node.exe");
    return fs.existsSync(candidate) ? candidate : null;
  }
  const bundled = app.isPackaged
    ? path.join(process.resourcesPath, "node", "node")
    : path.join(repoRoot(), "Vendor", "node", "node");
  if (fs.existsSync(bundled)) return bundled;
  return null;
}

export function firmwareCacheDir() {
  const dir = process.platform === "win32"
    ? path.join(process.env.LOCALAPPDATA || path.join(os.homedir(), "AppData", "Local"), "AIPassportFlasher", "firmware")
    : path.join(os.homedir(), "Library", "Caches", "AIPassportFlasher", "firmware");
  fs.mkdirSync(dir, { recursive: true });
  return dir;
}

export function restoreWorkDir() {
  const dir = path.join(app.getPath("temp"), `apf-restore-${Date.now().toString(36)}`);
  fs.mkdirSync(dir, { recursive: true, mode: 0o700 });
  return dir;
}
