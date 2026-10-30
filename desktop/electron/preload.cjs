const { contextBridge, ipcRenderer, webUtils } = require("electron");

const on = (channel, listener) => {
  const wrapped = (_event, payload) => listener(payload);
  ipcRenderer.on(channel, wrapped);
  return () => ipcRenderer.removeListener(channel, wrapped);
};

contextBridge.exposeInMainWorld("apf", {
  version: "0.0.1",
  platform: process.platform,
  getRuntime: () => ipcRenderer.invoke("runtime:get"),
  esptoolVersion: () => ipcRenderer.invoke("esptool:version"),
  window: {
    minimize: () => ipcRenderer.invoke("window:minimize"),
    toggleZoom: () => ipcRenderer.invoke("window:zoom"),
    close: () => ipcRenderer.invoke("window:close"),
  },
  ports: () => ipcRenderer.invoke("ports:scan"),
  pickFiles: (options) => ipcRenderer.invoke("files:pick", options),
  inspectFile: (filePath) => ipcRenderer.invoke("files:inspect", filePath),
  pathForFile: (file) => webUtils.getPathForFile(file),
  featured: () => ipcRenderer.invoke("community:featured"),
  plays: (query) => ipcRenderer.invoke("community:plays", query),
  downloadPlay: (play) => ipcRenderer.invoke("community:download", play),
  onDownload: (listener) => on("download-progress", listener),
  prepareRestore: (credentials) => ipcRenderer.invoke("restore:prepare", credentials),
  onRestore: (listener) => on("restore-progress", listener),
  readChip: (request) => ipcRenderer.invoke("flash:read", request),
  writeFlash: (request) => ipcRenderer.invoke("flash:write", request),
  cancelJob: () => ipcRenderer.invoke("flash:cancel"),
  onTool: (listener) => on("tool-output", listener),
  simulatorStart: () => ipcRenderer.invoke("simulator:start"),
  simulatorRestart: () => ipcRenderer.invoke("simulator:restart"),
  copyText: (text) => ipcRenderer.invoke("clipboard:write", text),
  saveText: (text) => ipcRenderer.invoke("files:save-text", text),
  openExternal: (url) => ipcRenderer.invoke("shell:open", url),
  capture: (name) => ipcRenderer.invoke("snapshot:capture", name),
  snapshotDone: () => ipcRenderer.invoke("snapshot:done"),
});
