import { spawn } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { app, BrowserWindow, clipboard, dialog, ipcMain, nativeTheme, session, shell } from "electron";
import { createSegmentReader, flashSizeIn, macIn, summarize } from "../lib/esptool-output.js";
import { esptoolExecutable } from "./paths.js";
import { scanPorts } from "./serial.js";
import { downloadPlay, inspectFile, loadFeatured, loadPlays, prepareRestore } from "./services.js";
import { createSimulator } from "./simulator.js";
import { parseCredentials, validateCredentials } from "../lib/restore.js";

const snapshotDir = process.env.APF_SNAPSHOT_DIR || "";
let mainWindow = null;
let toolChild = null;
const simulator = createSimulator();

function toolEnv() {
  return {
    ...process.env,
    PYTHONUNBUFFERED: "1",
    PYTHONIOENCODING: "utf-8",
    NO_COLOR: "1",
    TERM: "dumb",
    COLUMNS: "200",
  };
}

function send(channel, payload) {
  if (!mainWindow || mainWindow.isDestroyed()) return;
  mainWindow.webContents.send(channel, payload);
}

function stopTool() {
  if (!toolChild || toolChild.killed) return;
  const child = toolChild;
  child.kill();
  setTimeout(() => {
    if (!child.killed) child.kill("SIGKILL");
  }, 3000).unref?.();
}

function runTool(args) {
  const exe = esptoolExecutable();
  if (!exe) return Promise.reject(new Error("找不到内置的 esptool，可执行文件可能已损坏，请重新构建应用。"));
  stopTool();
  return new Promise((resolve, reject) => {
    const child = spawn(exe, args, { env: toolEnv(), shell: false, windowsHide: true });
    toolChild = child;
    let settled = false;
    const reader = createSegmentReader((text, overwrite) => send("tool-output", { text, overwrite }));
    const finish = (error, transcript) => {
      if (settled) return;
      settled = true;
      if (toolChild === child) toolChild = null;
      if (error) reject(error);
      else resolve(transcript);
    };
    child.stdout.on("data", (chunk) => reader.feed(chunk));
    child.stderr.on("data", (chunk) => reader.feed(chunk));
    child.on("error", (error) => finish(new Error(`无法启动 esptool：${error.message}`)));
    child.on("exit", (code, signal) => {
      reader.flush();
      if (signal) finish(new Error("已取消"));
      else if (code) finish(new Error(summarize(reader.transcript) || `esptool 退出码 ${code}`));
      else finish(null, reader.transcript);
    });
  });
}

function createWindow() {
  nativeTheme.themeSource = snapshotDir ? "light" : "system";
  const win = new BrowserWindow({
    width: 1240,
    height: 860,
    minWidth: 1100,
    minHeight: 720,
    show: false,
    x: snapshotDir ? -2400 : undefined,
    y: snapshotDir ? -2400 : undefined,
    frame: false,
    title: "AI Passport 刷机工具",
    backgroundColor: "#f3f4f2",
    titleBarStyle: "hidden",
    trafficLightPosition: { x: -100, y: -100 },
    webPreferences: {
      preload: path.join(app.getAppPath(), "electron", "preload.cjs"),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: false,
      webviewTag: true,
    },
  });
  mainWindow = win;
  win.removeMenu?.();
  win.setWindowButtonVisibility?.(false);
  win.on("closed", () => {
    if (mainWindow === win) mainWindow = null;
  });
  win.once("ready-to-show", () => {
    if (snapshotDir) win.showInactive();
    else win.show();
  });
  win.webContents.setWindowOpenHandler(({ url }) => {
    shell.openExternal(url);
    return { action: "deny" };
  });
  win.webContents.on("will-navigate", (event, url) => {
    if (!url.startsWith("file:")) event.preventDefault();
  });
  return win.loadFile(path.join(app.getAppPath(), "renderer", "index.html"));
}

app.setName("AI Passport 刷机工具");
app.whenReady().then(async () => {
  if (snapshotDir) app.setActivationPolicy?.("accessory");
  session.defaultSession.setPermissionRequestHandler((_wc, permission, callback) => {
    callback(permission === "media" || permission === "mediaKeySystem" || permission === "clipboard-sanitized-write");
  });
  await createWindow();
  if (snapshotDir) {
    await mainWindow.webContents.executeJavaScript(`new Promise((resolve) => {
      const tick = () => window.__snapshot ? resolve(window.__snapshot()) : setTimeout(tick, 50);
      tick();
    })`);
  }
});

app.on("window-all-closed", () => app.quit());
app.on("before-quit", () => {
  stopTool();
  simulator.stop();
});

ipcMain.handle("runtime:get", () => ({
  version: app.getVersion(),
  platform: process.platform,
  esptool: Boolean(esptoolExecutable()),
  esptoolPath: esptoolExecutable(),
}));
ipcMain.handle("window:minimize", () => mainWindow?.minimize());
ipcMain.handle("window:zoom", () => {
  if (!mainWindow) return;
  if (mainWindow.isMaximized()) mainWindow.unmaximize();
  else mainWindow.maximize();
});
ipcMain.handle("window:close", () => mainWindow?.close());
ipcMain.handle("ports:scan", (_event, showAll) => scanPorts(Boolean(showAll)));
ipcMain.handle("files:pick", async (_event, options) => {
  const result = await dialog.showOpenDialog(mainWindow, {
    title: options?.title || "选择固件",
    filters: [{ name: "固件", extensions: ["bin"] }],
    properties: options?.multiple ? ["openFile", "multiSelections"] : ["openFile"],
  });
  return result.canceled ? [] : result.filePaths;
});
ipcMain.handle("files:inspect", (_event, filePath) => inspectFile(filePath));
ipcMain.handle("community:featured", () => loadFeatured());
ipcMain.handle("community:plays", (_event, query) => loadPlays(query || {}));
ipcMain.handle("community:download", (event, play) => downloadPlay(play, (fraction) => {
  event.sender.send("download-progress", { id: play.id, fraction });
}));
ipcMain.handle("restore:prepare", async (event, input) => {
  const credentials = input.link
    ? parseCredentials(input.link)
    : validateCredentials(input.sn, input.key);
  return prepareRestore(credentials, (message, fraction) => {
    event.sender.send("restore-progress", { message, fraction });
  });
});
ipcMain.handle("esptool:version", async () => {
  if (snapshotDir) return "esptool";
  const text = await runTool(["version"]);
  return text.split("\n").map((line) => line.trim()).filter(Boolean).at(-1) || "未知";
});
ipcMain.handle("flash:read", (_event, request) => runTool([
  "--chip", "esp32c3", "--port", request.port, "--baud", String(request.baud || 460800),
  "--before", "default-reset", "--after", "hard-reset", "flash-id",
]));
ipcMain.handle("flash:write", async (_event, request) => {
  const base = ["--chip", "esp32c3", "--port", request.port, "--baud", String(request.baud || 460800), "--before", "default-reset"];
  if (request.expectedMAC) {
    const checked = await runTool([...base, "--after", "no-reset", "flash-id"]);
    const mac = macIn(checked)?.replaceAll(":", "");
    if (!mac) throw new Error("无法读取设备 MAC，已停止，未写入任何数据。");
    if (mac !== request.expectedMAC) {
      throw new Error(`设备不匹配：二维码 SN 为 ${request.expectedMAC}，当前连接的设备为 ${mac}。已停止，未写入任何数据。`);
    }
    const flash = flashSizeIn(checked);
    const mb = flash ? Number(String(flash).replace(/MB/i, "")) : null;
    if (mb && mb < 8) throw new Error(`Flash 容量不足：检测到 ${flash}，默认固件需要 8MB。已停止，未写入任何数据。`);
    send("tool-output", { text: `设备核对通过：MAC 与二维码 SN 一致（${mac}）。`, overwrite: false, kind: "success" });
  }
  const settings = request.settings || { flashMode: "keep", flashFreq: "keep", flashSize: "keep" };
  const args = [...base, "--after", "hard-reset", "write-flash", "--flash-mode", settings.flashMode, "--flash-freq", settings.flashFreq, "--flash-size", settings.flashSize];
  for (const image of request.images) args.push(image.offsetText, image.path);
  const transcript = await runTool(args);
  return { transcript };
});
ipcMain.handle("flash:cancel", () => stopTool());
ipcMain.handle("simulator:start", () => simulator.start());
ipcMain.handle("simulator:restart", () => simulator.restart());
ipcMain.handle("clipboard:write", (_event, text) => clipboard.writeText(String(text ?? "")));
ipcMain.handle("files:save-text", async (_event, text) => {
  const result = await dialog.showSaveDialog(mainWindow, { defaultPath: "ai-passport-flash-log.txt" });
  if (result.canceled || !result.filePath) return false;
  await fs.promises.writeFile(result.filePath, String(text ?? ""), "utf8");
  return true;
});
ipcMain.handle("shell:open", (_event, url) => shell.openExternal(url));
ipcMain.handle("snapshot:capture", async (_event, name) => {
  if (!snapshotDir || !mainWindow) return;
  fs.mkdirSync(snapshotDir, { recursive: true });
  const image = await mainWindow.webContents.capturePage();
  fs.writeFileSync(path.join(snapshotDir, name), image.toPNG());
});
ipcMain.handle("snapshot:done", () => app.quit());
