const percent = /(\d{1,3}(?:\.\d+)?)\s*%/;
const macRe = /^\s*MAC:\s*([0-9A-Fa-f]{2}(?::[0-9A-Fa-f]{2}){5})/m;
const flashRe = /Detected flash size:\s*(\S+)/;
const chipRe = /^\s*(?:Chip type:|Chip is)\s*(.+?)\s*$/m;
const ansi = /\u001B\[[0-9;?]*[ -/]*[@-~]|\u001B\][^\u0007\u001B]*(?:\u0007|\u001B\\)|\u001B[()][A-Za-z0-9]/g;

export function stripANSI(value) {
  return value.replace(ansi, "");
}

function firstGroup(re, text) {
  const match = re.exec(text);
  return match ? match[1] : null;
}

export function eventsIn(segment) {
  const out = [];
  const chip = firstGroup(chipRe, segment);
  const mac = firstGroup(macRe, segment);
  const flash = firstGroup(flashRe, segment);
  if (chip) out.push({ type: "chip", value: chip });
  if (mac) out.push({ type: "mac", value: mac.toLowerCase() });
  if (flash) out.push({ type: "flashSize", value: flash });

  if (segment.includes("Writing at") || (segment.includes("Erasing") && segment.includes("%"))) {
    const matches = [...segment.matchAll(new RegExp(percent, "g"))];
    const last = matches.at(-1);
    if (last) out.push({ type: "progress", value: Math.min(100, Math.max(0, Number(last[1]))) / 100 });
  }
  if (segment.startsWith("Wrote ") || segment.includes("\nWrote ")) out.push({ type: "fileWritten" });
  if (segment.includes("Hash of data verified")) out.push({ type: "verified" });
  if (segment.includes("Hard resetting")) out.push({ type: "resetting" });

  if (segment.includes("Connecting")) out.push({ type: "phase", value: "正在连接设备并进入下载模式…" });
  else if (segment.includes("Uploading stub") || segment.includes("Running stub")) out.push({ type: "phase", value: "正在加载刷写程序…" });
  else if (segment.includes("Configuring flash size") || segment.includes("Changing baud")) out.push({ type: "phase", value: "正在配置 Flash 参数…" });
  else if (segment.includes("Compressed ") && segment.includes(" bytes to ")) out.push({ type: "phase", value: "正在写入固件…" });
  return out;
}

export function macIn(text) {
  return firstGroup(macRe, text)?.toLowerCase() ?? null;
}
export function flashSizeIn(text) {
  return firstGroup(flashRe, text);
}
export function chipIn(text) {
  return firstGroup(chipRe, text);
}

export function summarize(output) {
  const lines = output.split("\n").map((line) => line.trim()).filter(Boolean);
  const fatal = [...lines].reverse().find((line) => line.toLowerCase().includes("error")) || lines.at(-1) || "";
  return [fatal, hint(output)].filter(Boolean).join("\n");
}

export function hint(output) {
  const text = output.toLowerCase();
  if (text.includes("busy or doesn't exist")) {
    return "提示：串口不存在或被占用。请重新插拔设备、刷新串口列表，并关闭正在使用该串口的浏览器刷机页面或串口监视器。";
  }
  if (text.includes("busy") || text.includes("resource busy") || text.includes("could not exclusively lock")) {
    return "提示：串口被占用。请关闭正在使用该设备的浏览器刷机页面、串口监视器或其他程序后重试。";
  }
  if (text.includes("no serial data received") || text.includes("failed to connect") || text.includes("wrong boot mode")) {
    return "提示：未能进入下载模式。请确认设备已开机、使用的是数据线，然后拔插数据线重试。";
  }
  if (text.includes("could not open") || text.includes("no such file") || text.includes("device not configured")) {
    return "提示：串口已断开或不存在。请重新连接设备并刷新串口列表。";
  }
  if (text.includes("this chip is") && text.includes("not")) {
    return "提示：连接的芯片不是 ESP32-C3，请确认选择的是 AI Passport 的串口。";
  }
  if (text.includes("doesn't fit") || text.includes("too big")) return "提示：固件超出 Flash 容量。";
  return "";
}

/** Split esptool output into newline records and bare-CR progress refreshes. */
export function createSegmentReader(onSegment) {
  let buffer = Buffer.alloc(0);
  let transcript = "";
  const emit = (chunk, overwrite) => {
    const text = stripANSI(chunk.toString("utf8"));
    if (!text.trim()) return;
    if (!overwrite) transcript += `${text}\n`;
    onSegment(text, overwrite);
  };
  return {
    feed(data) {
      buffer = Buffer.concat([buffer, data]);
      while (true) {
        const lf = buffer.indexOf(0x0a);
        const cr = buffer.indexOf(0x0d);
        if (lf < 0 && cr < 0) break;
        const idx = lf < 0 ? cr : cr < 0 ? lf : Math.min(lf, cr);
        const terminator = buffer[idx];
        const chunk = buffer.subarray(0, idx);
        let next = idx + 1;
        let overwrite = terminator === 0x0d;
        if (terminator === 0x0d && next < buffer.length && buffer[next] === 0x0a) {
          overwrite = false;
          next += 1;
        } else if (terminator === 0x0d && next === buffer.length) break;
        emit(chunk, overwrite);
        buffer = buffer.subarray(next);
      }
    },
    flush() {
      let rest = buffer;
      if (rest.length && rest[rest.length - 1] === 0x0d) rest = rest.subarray(0, -1);
      if (rest.length) emit(rest, false);
      buffer = Buffer.alloc(0);
    },
    get transcript() {
      return transcript;
    },
  };
}
