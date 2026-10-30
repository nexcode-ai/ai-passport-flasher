import { spawn } from "node:child_process";
import fs from "node:fs";
import http from "node:http";
import net from "node:net";
import path from "node:path";
import { bridgeDir, nodeExecutable, simulatorRuntimeDir } from "./paths.js";

function freePort() {
  return new Promise((resolve, reject) => {
    const server = net.createServer();
    server.once("error", reject);
    server.listen(0, "127.0.0.1", () => {
      const { port } = server.address();
      server.close(() => resolve(port));
    });
  });
}

export function createSimulator() {
  let child = null;
  let proxy = null;
  let backendPort = 0;

  async function start() {
    if (proxy) return { url: proxy.url };
    const runtime = simulatorRuntimeDir();
    const serverScript = path.join(runtime, "server.mjs");
    const node = nodeExecutable();
    if (!fs.existsSync(serverScript) || !node) {
      throw new Error("应用包中的模拟器运行时不完整，请重新安装应用。");
    }
    backendPort = await freePort();
    const proxyPort = await freePort();
    child = spawn(node, [serverScript, "--allow-local-firmware-upload"], {
      cwd: runtime,
      env: {
        ...process.env,
        HOST: "127.0.0.1",
        PORT: String(backendPort),
        EMULATOR_ALLOW_LOCAL_FIRMWARE_UPLOAD: "1",
        EMULATOR_TRAFFIC_ANALYTICS: "0",
      },
      stdio: "ignore",
      windowsHide: true,
    });
    child.on("exit", () => {
      child = null;
    });
    await waitForHealth(backendPort);
    proxy = await startProxy(proxyPort, backendPort);
    return { url: proxy.url };
  }

  function stop() {
    proxy?.close();
    proxy = null;
    if (child && !child.killed) child.kill();
    child = null;
  }

  return {
    start,
    async restart() {
      stop();
      return start();
    },
    stop,
  };
}

function waitForHealth(port) {
  return new Promise((resolve, reject) => {
    const started = Date.now();
    const tick = () => {
      const req = http.get(`http://127.0.0.1:${port}/healthz`, (res) => {
        res.resume();
        if (res.statusCode === 200) resolve();
        else retry();
      });
      req.on("error", retry);
      req.setTimeout(500, () => req.destroy());
    };
    const retry = () => {
      if (Date.now() - started > 12000) reject(new Error("本地运行时启动超时，请重新启动模拟器。"));
      else setTimeout(tick, 150);
    };
    tick();
  });
}

function startProxy(proxyPort, targetPort) {
  const theme = fs.readFileSync(path.join(bridgeDir(), "apf-theme.css"));
  const bridge = fs.readFileSync(path.join(bridgeDir(), "apf-bridge.js"), "utf8").replace(
    "window.webkit.messageHandlers.apf.postMessage(message);",
    "window.webkit.messageHandlers.apf.postMessage(message);} catch (_) {} try { console.log('APFMSG ' + JSON.stringify(message));",
  );
  const server = http.createServer((req, res) => {
    const url = new URL(req.url, "http://127.0.0.1");
    if (url.pathname === "/apf-theme.css") return send(res, 200, "text/css; charset=utf-8", theme);
    if (url.pathname === "/apf-bridge.js") return send(res, 200, "application/javascript; charset=utf-8", bridge);
    const headers = { ...req.headers, host: `127.0.0.1:${targetPort}` };
    const upstream = http.request({
      hostname: "127.0.0.1",
      port: targetPort,
      path: req.url,
      method: req.method,
      headers,
    }, (upstreamResponse) => {
      const chunks = [];
      upstreamResponse.on("data", (chunk) => chunks.push(chunk));
      upstreamResponse.on("end", () => {
        let body = Buffer.concat(chunks);
        const type = String(upstreamResponse.headers["content-type"] || "");
        if (type.startsWith("text/html")) {
          const html = body.toString("utf8").replace(
            "</head>",
            "  <link rel=\"stylesheet\" href=\"/apf-theme.css\">\n  <script src=\"/apf-bridge.js\"></script>\n</head>",
          );
          body = Buffer.from(html);
        } else if (url.pathname.endsWith("/qemu-worker.js")) {
          body = Buffer.from(body.toString("utf8").replaceAll("__APF_BRIDGE_PORT__", String(targetPort)));
        }
        const responseHeaders = { ...upstreamResponse.headers, "content-length": body.length };
        delete responseHeaders["transfer-encoding"];
        res.writeHead(upstreamResponse.statusCode || 502, responseHeaders);
        res.end(body);
      });
    });
    upstream.on("error", () => {
      if (!res.headersSent) res.writeHead(502);
      res.end();
    });
    req.pipe(upstream);
  });
  return new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(proxyPort, "127.0.0.1", () => {
      resolve({
        url: `http://127.0.0.1:${proxyPort}/`,
        close: () => server.close(),
      });
    });
  });
}

function send(res, status, type, body) {
  const data = Buffer.isBuffer(body) ? body : Buffer.from(body);
  res.writeHead(status, {
    "content-type": type,
    "content-length": data.length,
    "cache-control": "no-store",
    "cross-origin-resource-policy": "same-origin",
  });
  res.end(data);
}
