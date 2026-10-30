import {
  BUILTIN_FIRMWARES, CATEGORIES, SORTS, TAGS, absoluteURL, categoryLabel, displayText, formatBytes,
  instructionSteps, playIsInstallable,
} from "../lib/catalog.js";
import { eventsIn, chipIn, flashSizeIn, macIn } from "../lib/esptool-output.js";
import { BAUD_OPTIONS, defaultOffset, formatOffset, parseOffset, planIssues, createProgressTracker } from "../lib/plan.js";

const $ = (selector) => document.querySelector(selector);
const esc = (value) => String(value ?? "").replace(/[&<>"']/g, (char) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[char]));
const icon = (name) => `<svg class="i" width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">${ICONS[name] || ICONS.info}</svg>`;
const ICONS = {
  grid: '<rect x="3" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="3" width="7" height="7" rx="1.5"/><rect x="3" y="14" width="7" height="7" rx="1.5"/><rect x="14" y="14" width="7" height="7" rx="1.5"/>',
  game: '<rect x="2" y="7" width="20" height="11" rx="4"/><path d="M8 12v4M6 14h4M16 13h.01M18 15h.01"/>',
  bolt: '<path d="M13 2 4 14h7l-1 8 9-12h-7l1-8z"/>',
  restore: '<path d="M3 12a9 9 0 1 0 3-6.7"/><path d="M3 4v5h5"/>',
  info: '<circle cx="12" cy="12" r="9"/><path d="M12 11v6M12 8h.01"/>',
  spark: '<path d="M12 3l1.6 4.8L18 9.4l-4.4 1.6L12 16l-1.6-5L6 9.4l4.4-1.6L12 3z"/>',
  search: '<circle cx="11" cy="11" r="6"/><path d="m20 20-3.5-3.5"/>',
  down: '<circle cx="12" cy="12" r="9"/><path d="M12 8v8M8.5 12.5 12 16l3.5-3.5"/>',
  close: '<path d="M6 6l12 12M18 6 6 18"/>',
  check: '<path d="m5 12 5 5L20 7"/>',
  cable: '<path d="M8 7v5a4 4 0 0 0 8 0V7"/><path d="M9 4h2M13 4h2M10 20h4"/>',
  refresh: '<path d="M20 12a8 8 0 1 1-2.2-5.5"/><path d="M20 4v5h-5"/>',
  doc: '<path d="M7 3h7l5 5v13a1 1 0 0 1-1 1H7a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1z"/><path d="M14 3v6h6"/>',
  cpu: '<rect x="7" y="7" width="10" height="10" rx="2"/><path d="M9 1v3M15 1v3M9 20v3M15 20v3M1 9h3M1 15h3M20 9h3M20 15h3"/>',
  heart: '<path d="M12 20s-7-4.4-7-9a4 4 0 0 1 7-2 4 4 0 0 1 7 2c0 4.6-7 9-7 9z"/>',
  play: '<path d="m8 6 10 6-10 6V6z"/>',
  warn: '<path d="m12 3 10 18H2L12 3z"/><path d="M12 10v4M12 17h.01"/>',
  shield: '<path d="M12 3 5 6v6c0 4.5 3 7.5 7 9 4-1.5 7-4.5 7-9V6l-7-3z"/>',
  clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7v6l4 2"/>',
  power: '<path d="M12 3v8"/><path d="M7 6.5A7 7 0 1 0 17 6.5"/>',
  mic: '<rect x="9" y="3" width="6" height="11" rx="3"/><path d="M6 11a6 6 0 0 0 12 0M12 17v4"/>',
  camera: '<path d="M4 8h3l2-2h6l2 2h3v11H4V8z"/><circle cx="12" cy="13" r="3"/>',
  speaker: '<path d="M4 10v4h4l5 4V6L8 10H4z"/>',
  trash: '<path d="M4 7h16M9 7V4h6v3M7 7l1 13h8l1-13"/>',
  plus: '<path d="M12 5v14M5 12h14"/>',
  sidebar: '<rect x="3" y="4" width="18" height="16" rx="2"/><path d="M9 4v16"/>',
  chevron: '<path d="m9 6 6 6-6 6"/>',
};

const state = {
  tab: "community",
  featured: [],
  plays: [],
  total: 0,
  hasMore: false,
  loading: false,
  featuredError: "",
  listError: "",
  query: { search: "", category: "all", tag: "", sort: "newest" },
  detail: null,
  showAllSteps: false,
  showTech: false,
  downloading: null,
  downloadProgress: 0,
  downloadError: "",
  ports: [],
  showAllPorts: false,
  selectedPort: null,
  deviceInfo: null,
  mode: "merged",
  merged: null,
  partitions: [],
  planLabel: "本地文件",
  settings: { flashMode: "keep", flashFreq: "keep", flashSize: "keep" },
  expectedMAC: null,
  selectedPlay: null,
  baud: 460800,
  consent: false,
  job: { type: "idle" },
  progress: 0,
  log: [],
  showLog: false,
  confirm: null,
  completion: false,
  link: "",
  manual: false,
  manualSN: "",
  manualKey: "",
  restoreStatus: "",
  restoreError: "",
  restoreWarning: "",
  restoreWorking: false,
  restoreFraction: 0,
  esptoolReady: false,
  esptoolVersion: "检测中…",
  simURL: "",
  simError: "",
  simItem: { kind: "builtin", id: BUILTIN_FIRMWARES[0].id },
  simQuery: "",
  recents: loadRecents(),
  simStatus: { phase: "waiting", stage: "", percent: 0, audio: false, mic: false, recording: false },
  notice: localStorage.getItem("simulator.noticeDismissed") !== "1",
  library: true,
  version: "0.0.1",
};

let searchTimer = 0;
let tracker = null;
let pageScroll = 0;

function loadRecents() {
  try { return JSON.parse(localStorage.getItem("simulator.recentPlays.v1") || "[]"); } catch { return []; }
}
function saveRecents() { localStorage.setItem("simulator.recentPlays.v1", JSON.stringify(state.recents.slice(0, 8))); }

function appendLog(text, kind = "info", overwrite = false) {
  if (!text?.trim()) return;
  const last = state.log.at(-1);
  if (overwrite && last?.progress) last.text = text;
  else if (!overwrite && last?.progress && kind === "tool" && last.text.includes("%") && text.includes("%") && last.text.slice(0, 10) === text.slice(0, 10)) last.text = text;
  else state.log.push({ text, kind, progress: overwrite });
  if (state.log.length > 4000) state.log.splice(0, state.log.length - 4000);
}

function blockers() {
  const images = currentImages();
  const issues = planIssues(images);
  const list = [];
  if (!state.esptoolReady) list.push("内置 esptool 缺失");
  if (!state.selectedPort) list.push("尚未选择设备串口");
  if (!images.length) list.push("尚未选择固件");
  if (issues.some((issue) => issue.level === "error")) list.push("固件设置有错误");
  if (!state.consent) list.push("请先勾选确认覆盖设备内容");
  return list;
}
function currentImages() {
  return state.mode === "merged" ? (state.merged ? [state.merged] : []) : state.partitions;
}
function jobRunning() { return state.job.type === "running"; }

function boot() {
  $("#app").innerHTML = `
    <header class="titlebar">
      <div class="lights">
        <button class="light close" data-action="win-close" aria-label="关闭"></button>
        <button class="light min" data-action="win-min" aria-label="最小化"></button>
        <button class="light zoom" data-action="win-zoom" aria-label="缩放"></button>
      </div>
      <div class="spacer"></div>
      <button class="pill" id="pill" data-action="pill"></button>
    </header>
    <div class="body">
      <aside class="sidebar" id="sidebar"></aside>
      <div class="content page-bg">
        <div class="page" id="page"></div>
        <section class="sim" id="sim" hidden></section>
      </div>
    </div>
    <div id="modal"></div>
    <div id="popover"></div>`;
  document.body.addEventListener("click", onClick);
  document.body.addEventListener("input", onInput);
  document.body.addEventListener("change", onChange);
  document.body.addEventListener("dragover", (event) => { if (event.target.closest(".drop")) event.preventDefault(); });
  document.body.addEventListener("drop", onDrop);
  window.apf.onTool(onTool);
  window.apf.onDownload(({ fraction }) => { state.downloadProgress = fraction; render(); });
  window.apf.onRestore(({ message, fraction }) => { state.restoreStatus = message; state.restoreFraction = fraction; render(); });
  refreshPorts();
  setInterval(refreshPorts, 1500);
  loadLibrary();
  window.apf.getRuntime().then((info) => {
    state.esptoolReady = info.esptool;
    state.version = info.version || "0.0.1";
    appendLog(info.esptool ? `内置 esptool 已就绪：${info.esptoolPath}` : "未找到内置 esptool，无法刷写。", info.esptool ? "info" : "error");
    if (info.esptool) window.apf.esptoolVersion().then((version) => { state.esptoolVersion = version || "未知"; render(); }).catch(() => { state.esptoolVersion = "未知"; });
    render();
  });
  window.__snapshot = snapshot;
  render();
}

async function loadLibrary() {
  state.loading = true;
  render();
  try { state.featured = await window.apf.featured(); state.featuredError = ""; }
  catch (error) { state.featuredError = `官方精选加载失败：${error.message}`; }
  await reloadPlays();
}
async function reloadPlays() {
  state.loading = true; state.plays = []; state.listError = "";
  render();
  try {
    const page = await window.apf.plays({ ...state.query, offset: 0 });
    state.plays = page.plays; state.total = page.total; state.hasMore = page.hasMore;
  } catch (error) { state.listError = error.message; }
  state.loading = false;
  render();
}
async function loadMore() {
  if (!state.hasMore || state.loading) return;
  state.loading = true;
  try {
    const page = await window.apf.plays({ ...state.query, offset: state.plays.length });
    const known = new Set(state.plays.map((play) => play.id));
    state.plays.push(...page.plays.filter((play) => !known.has(play.id)));
    state.total = page.total; state.hasMore = page.hasMore;
  } catch (error) { state.listError = error.message; }
  state.loading = false;
  render();
}
async function refreshPorts() {
  const ports = await window.apf.ports(state.showAllPorts);
  const changed = JSON.stringify(ports) !== JSON.stringify(state.ports);
  state.ports = ports;
  if (state.selectedPort && !ports.some((port) => port.path === state.selectedPort) && !jobRunning()) {
    state.selectedPort = null; state.deviceInfo = null;
  }
  if (!state.selectedPort) state.selectedPort = ports.find((port) => port.isEspressifJTAG || port.isLikelyDevice)?.path || null;
  if (changed) render();
  else updatePill();
}

function render() {
  const page = $("#page");
  if (page) pageScroll = page.scrollTop;
  const active = document.activeElement;
  const focusId = active?.id;
  const caret = active?.selectionStart;
  $("#sidebar").innerHTML = sidebar();
  $("#sim").hidden = state.tab !== "simulator";
  page.hidden = state.tab === "simulator";
  if (state.tab === "simulator") renderSimulator();
  else page.innerHTML = `<div class="page-inner ${state.tab === "community" ? "wide" : "narrow"}">${view()}</div>`;
  page.scrollTop = pageScroll;
  $("#modal").innerHTML = modal();
  updatePill();
  if (focusId) {
    const next = document.getElementById(focusId);
    if (next) { next.focus(); if (caret != null) next.selectionStart = next.selectionEnd = caret; }
  }
  const sentinel = document.getElementById("more");
  if (sentinel && !sentinel.dataset.bound) {
    sentinel.dataset.bound = "1";
    new IntersectionObserver((entries) => { if (entries.some((entry) => entry.isIntersecting)) loadMore(); }, { root: page }).observe(sentinel);
  }
}

function sidebar() {
  const item = (tab, title, glyph) => `<button class="nav-row ${state.tab === tab ? "active" : ""}" data-action="tab" data-tab="${tab}"><span class="glyph">${icon(glyph)}</span><span>${title}</span>${state.tab === tab ? '<i class="mark"></i>' : ""}</button>`;
  const port = state.ports.find((entry) => entry.path === state.selectedPort);
  return `
    <div class="brand"><div class="icon-tile sm">${icon("spark")}</div><div><b>AI Passport</b><span>探索 · 试用 · 安装</span></div></div>
    <div class="nav">
      <div class="nav-label">开始</div>
      ${item("community", "发现玩法", "grid")}
      ${item("simulator", "玩法模拟器", "game")}
      <div class="nav-label">我的设备</div>
      ${item("flash", "安装到设备", "bolt")}
      ${item("restore", "恢复设备", "restore")}
      <div class="nav-label">支持</div>
      ${item("about", "关于", "info")}
    </div>
    <div class="side-foot ${port ? "ok" : ""}">${port ? `${icon("cable")} ${esc(port.path.split(/[\\/]/).pop())}` : `${icon("cable")} 未连接设备`}${jobRunning() ? `<div class="progress" style="margin-top:8px"><span style="width:${Math.round(state.progress * 100)}%"></span></div>` : ""}</div>`;
}

function updatePill() {
  const port = state.ports.find((entry) => entry.path === state.selectedPort);
  let title = port ? "设备已连接" : "设备未连接";
  let detail = port ? port.path.split(/[\\/]/).pop() : "连接后即可安装";
  let color = port ? "var(--green)" : "var(--secondary)";
  let glyph = port ? "cable" : "cable";
  if (jobRunning()) { title = "正在安装"; detail = `${Math.round(state.progress * 100)}%`; color = "var(--accent)"; glyph = "bolt"; }
  else if (state.job.type === "succeeded") { title = "安装完成"; detail = "查看下一步"; color = "var(--green)"; glyph = "check"; }
  $("#pill").innerHTML = `<span class="dot" style="--pill:${color}">${icon(glyph)}</span><span><b>${title}</b><small>${esc(detail)}</small></span>${icon("chevron")}`;
  const pop = $("#popover");
  pop.innerHTML = state.completion && state.job.type === "succeeded" ? `
    <div class="popover">
      <div class="row"><div class="ring" style="width:34px;height:34px;margin:0">${icon("check")}</div><div><b>安装已完成</b><div class="meta">${esc(state.selectedPlay ? displayText(state.selectedPlay.title) : "固件已写入设备")}</div></div></div>
      <p class="muted">设备已自动重启。你可以继续安装其他玩法，或前往完成页查看使用提示。</p>
      <button class="btn primary" data-action="another" style="width:100%">安装其他玩法</button>
      <div class="row" style="margin-top:8px"><button class="btn secondary sm" data-action="tab" data-tab="flash">查看完成页</button><button class="btn secondary sm" data-action="another-restore">恢复设备</button></div>
    </div>` : "";
}

function view() {
  if (state.tab === "community") return community();
  if (state.tab === "flash") return flash();
  if (state.tab === "restore") return restore();
  return about();
}

function head(eyebrow, title, subtitle, glyph, extra = "") {
  return `<div class="head"><div class="icon-tile">${icon(glyph)}</div><div class="copy"><div class="eyebrow accent">${eyebrow}</div><h1>${title}</h1><p class="sub">${subtitle}</p></div>${extra}</div>`;
}

function community() {
  const hero = state.featured[0];
  return `
    ${head("从这里开始", "发现新玩法", "浏览官方精选与社区创作，先了解玩法，再跟随引导安装到你的 AI Passport。", "grid", `<button class="btn secondary lg" data-action="local-bin">${icon("doc")} 安装本地 .bin 固件</button>`)}
    ${state.downloadError ? `<div class="banner err">${esc(state.downloadError)} <button class="btn tertiary sm" data-action="clear-error">关闭</button></div>` : ""}
    <div class="section-title"><h2>${icon("spark")} 官方精选</h2><span>FoloToy 官方推荐</span></div>
    ${state.featuredError ? `<div class="card" style="padding:18px">${esc(state.featuredError)} <button class="btn secondary sm" data-action="reload-featured">重新加载</button></div>` : hero ? heroCard(hero) + `<div class="grid featured">${state.featured.slice(1, 7).map(card).join("")}</div>` : `<div class="hero"><div class="skeleton"></div></div>`}
    <div class="section-title" style="margin-top:28px"><h2>${icon("grid")} 全部玩法</h2><span>${state.total ? `${state.total} 个作品` : ""}</span></div>
    <div class="card filters">
      <div class="row">
        <label class="search">${icon("search")}<input id="search" placeholder="搜索玩法名称、作者或简介" value="${esc(state.query.search)}">${state.query.search ? `<button class="icon-btn sm" data-action="clear-search">${icon("close")}</button>` : ""}</label>
        ${select("tag", TAGS, state.query.tag)}
        ${select("sort", SORTS, state.query.sort)}
      </div>
      <div class="chips">${CATEGORIES.map(([key, title]) => `<button class="chip ${state.query.category === key ? "on" : ""}" data-action="category" data-value="${key}">${title}</button>`).join("")}</div>
    </div>
    ${state.listError ? `<div class="card empty"><b>玩法社区连接失败</b><div class="muted">请检查网络连接后重试。已经下载的固件不会受到影响。</div><div class="meta">${esc(state.listError)}</div><button class="btn primary" data-action="reload">重新连接</button></div>` : ""}
    ${!state.plays.length && state.loading ? `<div class="grid">${Array.from({ length: 6 }, () => '<div class="play"><div class="skeleton" style="height:178px"></div><div style="padding:15px"><div class="skeleton" style="height:16px;width:60%"></div></div></div>').join("")}</div>` : ""}
    ${!state.plays.length && !state.loading && !state.listError ? `<div class="card empty"><b>没有找到相关玩法</b><div class="muted">换一个关键词，或清除筛选条件后再看看。</div><button class="btn tertiary" data-action="clear-filters">清除搜索</button></div>` : ""}
    <div class="grid">${state.plays.map((play) => card(play, false)).join("")}</div>
    <div id="more" class="center muted">${state.loading ? "正在加载…" : state.hasMore ? "继续下滑加载更多" : state.plays.length ? `已显示全部 ${state.plays.length} 个玩法` : ""}</div>`;
}

function select(name, options, value) {
  return `<select class="select" data-field="${name}">${options.map(([key, title]) => `<option value="${esc(key)}" ${key === value ? "selected" : ""}>${esc(title)}</option>`).join("")}</select>`;
}
function cover(play, height) {
  const url = absoluteURL(play.image || play.thumbnail);
  return `<div class="cover" style="${height ? `height:${height}px` : ""}">${url ? `<img src="${esc(url)}" alt="">` : ""}<div class="tags"><span class="tag on-dark">${esc(play.categoryLabel || categoryLabel(play.categoryKey) || categoryLabel(play.category) || "玩法")}</span>${play.mustPlay ? '<span class="tag on-dark">必玩</span>' : ""}</div></div>`;
}
function heroCard(play) {
  return `<article class="hero"><div class="hero-cover" data-action="detail" data-id="${play.id}">${absoluteURL(play.image || play.thumbnail) ? `<img src="${esc(absoluteURL(play.image || play.thumbnail))}" alt="">` : ""}<div class="badge">${icon("spark")} 本周官方精选</div></div>
    <div class="hero-body">
      <div class="tags"><span class="tag">${esc(categoryLabel(play.categoryKey) || categoryLabel(play.category) || "玩法")}</span>${play.mustPlay ? '<span class="tag orange">必玩</span>' : ""}</div>
      <h3>${esc(displayText(play.title))}</h3>
      <div class="muted">开发者 ${esc(play.author || "—")}</div>
      <div class="clamp-4 muted">${esc(displayText(play.description))}</div>
      ${stats(play)}
      <div class="row actions"><button class="btn secondary sm" data-action="try" data-id="${play.id}">${icon("game")} 先试用</button><button class="btn tertiary sm" data-action="detail" data-id="${play.id}">${icon("info")} 查看详情</button><span style="flex:1"></span>${installButton(play, true)}</div>
    </div></article>`;
}
function card(play) {
  const when = play.updatedAt || play.publishedAt;
  const date = when ? new Date(when) : null;
  const stamp = date && !Number.isNaN(date.getTime()) ? `${date.getMonth() + 1}月${date.getDate()}日` : "";
  return `<article class="play">${cover(play)}<div class="play-body">
      <div class="row"><h3>${esc(displayText(play.title))}</h3><span class="meta" style="margin-left:auto">${stamp}</span></div>
      <div class="meta">开发者 ${esc(play.author || "—")}</div>
      <div class="clamp-2 muted">${esc(displayText(play.description))}</div>
      <div class="row"><div class="stats">${stats(play)}</div><span style="flex:1"></span>
        <button class="icon-btn sm" title="先试用" data-action="try" data-id="${play.id}">${icon("game")}</button>
        <button class="icon-btn sm" title="查看详情" data-action="detail" data-id="${play.id}">${icon("chevron")}</button>
        ${installButton(play, false)}
      </div>
    </div></article>`;
}
function stats(play) {
  const size = play.firmware?.size || play.firmwareSize;
  return `${play.downloads != null ? `<span>${icon("down")} ${play.downloads}</span>` : ""}${play.hearts != null ? `<span>${icon("heart")} ${play.hearts}</span>` : ""}${size ? `<span>${formatBytes(size)}</span>` : ""}`;
}
function installButton(play, compact) {
  const busy = state.downloading === play.id;
  const label = busy ? `下载中 ${Math.round(state.downloadProgress * 100)}%` : playIsInstallable(play) ? (compact ? "安装" : "查看并安装") : "暂无固件";
  return `<button class="btn primary ${compact ? "sm" : ""}" data-action="install-open" data-id="${play.id}" ${!playIsInstallable(play) || state.downloading || jobRunning() ? "disabled" : ""}>${busy ? "" : icon("down")} ${label}</button>`;
}
function findPlay(id) {
  return [...state.featured, ...state.plays, ...state.recents].find((play) => String(play.id) === String(id));
}

function flash() {
  const images = currentImages();
  const issues = planIssues(images);
  const step = !state.selectedPort ? 1 : (!images.length || issues.some((issue) => issue.level === "error") ? 2 : 3);
  if (state.job.type === "succeeded") {
    return `${head("安装完成", "玩法已安装", "设备已经自动重启，可以拔下数据线开始体验。", "check")}
      <div class="card success"><div class="ring">${icon("check")}</div><h1>安装成功</h1><p class="muted">${state.selectedPlay ? `“${esc(displayText(state.selectedPlay.title))}”已经写入 AI Passport` : "固件已经写入 AI Passport"}</p>
      <div class="row" style="justify-content:center;margin:18px 0"><div><b>设备已重启</b><div class="meta">等待指示灯恢复</div></div><div><b>可以拔线</b><div class="meta">开始体验新玩法</div></div><div><b>随时可恢复</b><div class="meta">回到出厂系统</div></div></div>
      <button class="btn primary lg" data-action="another">安装其他玩法</button> <button class="btn secondary lg" data-action="another-restore">恢复出厂固件</button></div>`;
  }
  return `${head("设备工作台", "安装到 AI Passport", "跟随步骤连接设备、确认玩法并安全写入。", "cable")}
    <div class="card steps">${[ "连接设备", "选择固件", "写入与重启" ].map((title, index) => {
      const n = index + 1;
      const done = n < step;
      return `${index ? `<div class="step-line ${done ? "done" : ""}"></div>` : ""}<div class="step-item"><div class="bubble ${done ? "done" : n === step ? "on" : ""}">${done ? icon("check") : n}</div><div>${title}</div></div>`;
    }).join("")}</div>
    ${state.selectedPlay ? `<div class="card" style="padding:14px;margin-top:16px;display:flex;gap:14px;align-items:center">${coverThumb(state.selectedPlay)}<div><div class="eyebrow accent">准备安装</div><b>${esc(displayText(state.selectedPlay.title))}</b></div><span style="margin-left:auto" class="meta">${icon("shield")} 固件已下载并通过校验</span></div>` : ""}
    <section class="step"><div class="row"><div class="step-no">01</div><div><b>连接设备</b><div class="meta">串口每 1.5 秒自动刷新。AI Passport 在 macOS 上显示为 /dev/cu.usbmodem…，在 Windows 上显示为 COMx（USB JTAG/serial debug unit）。</div></div></div>
      ${state.ports.length ? state.ports.map((port) => `<button class="nav-row" data-action="port" data-path="${esc(port.path)}" style="margin-top:8px;background:${port.path === state.selectedPort ? "var(--accent-soft)" : "transparent"}"><span>${esc(port.displayName)}</span>${port.isEspressifJTAG ? '<span class="tag green">ESP32-C3 USB JTAG</span>' : ""}<span class="meta">${esc(port.detail)}</span></button>`).join("") : `<div class="wait" style="margin-top:12px"><div class="bubble on">${icon("cable")}</div><div><b>正在等待设备</b><div class="meta">请确认设备已开机，并使用支持数据传输的 Type-C 线。</div></div></div>`}
      <div class="row" style="margin-top:12px"><button class="btn secondary sm" data-action="refresh-ports">${icon("refresh")} 刷新</button><label class="check"><input type="checkbox" data-field="showAllPorts" ${state.showAllPorts ? "checked" : ""}>显示全部串口</label><span style="flex:1"></span><button class="btn secondary sm" data-action="read-chip" ${!state.selectedPort || jobRunning() ? "disabled" : ""}>${icon("cpu")} 读取芯片信息</button></div>
      ${state.deviceInfo ? `<div class="row meta" style="margin-top:8px"><span>芯片 ${esc(state.deviceInfo.chip || "—")}</span><span>MAC / SN ${esc(state.deviceInfo.mac || "—")}</span><span>Flash ${esc(state.deviceInfo.flashSize || "—")}</span></div>` : ""}
    </section>
    <section class="step"><div class="row"><div class="step-no">02</div><b>选择固件</b><span style="flex:1"></span><button class="btn tertiary sm" data-action="tab" data-tab="community">去玩法社区</button></div>
      ${state.selectedPlay ? selectedPlay() : state.expectedMAC ? `<div class="banner info">${esc(state.planLabel)}。写入前会核对设备 MAC。</div>${fileTable(false)}<button class="btn tertiary sm" data-action="clear-plan">清除</button>` : localPicker()}
      ${issues.map((issue) => `<div class="${issue.level === "error" ? "banner err" : "banner warn"}">${esc(issue.message)}</div>`).join("")}
    </section>
    <section class="step"><div class="row"><div class="step-no">03</div><b>写入与重启</b></div>
      <div class="banner warn">写入会替换设备中的现有玩法和相关数据。之后可随时通过“恢复出厂固件”回到默认状态；写入期间请保持连接。</div>
      <div class="row"><label>波特率 <select class="select" data-field="baud" ${jobRunning() ? "disabled" : ""}>${BAUD_OPTIONS.map((baud) => `<option ${baud === state.baud ? "selected" : ""}>${baud}</option>`).join("")}</select></label><span class="meta">Flash 参数：${state.settings.flashMode} / ${state.settings.flashFreq} / ${state.settings.flashSize}</span></div>
      <label class="check"><input type="checkbox" data-field="consent" ${state.consent ? "checked" : ""} ${jobRunning() ? "disabled" : ""}>我已了解：写入会覆盖这台设备上的现有内容</label>
      <div class="row" style="margin-top:12px"><button class="btn primary lg" data-action="ask-write" ${blockers().length || jobRunning() ? "disabled" : ""}>${icon("bolt")} ${jobRunning() ? "正在写入…" : "开始写入"}</button>${jobRunning() ? `<button class="btn danger" data-action="cancel">取消</button>` : `<span class="meta">${esc(blockers().join(" · "))}</span>`}</div>
      <div style="margin-top:12px"><div class="row"><b>${esc(statusText())}</b><span style="margin-left:auto">${Math.round(state.progress * 100)}%</span></div><div class="progress"><span style="width:${Math.round(state.progress * 100)}%"></span></div></div>
      ${state.job.type === "failed" ? `<div class="banner err">安装没有完成：${esc(state.job.message.split("\n")[0])}<br>请重新插拔数据线、关闭其他串口工具，然后再次尝试。</div>` : ""}
      <button class="btn tertiary sm" data-action="toggle-log">${state.showLog ? "收起" : "展开"}设备日志</button>
      ${state.showLog ? logView() : ""}
    </section>`;
}
function coverThumb(play) {
  const url = absoluteURL(play.thumbnail || play.image);
  return url ? `<img src="${esc(url)}" alt="" style="width:54px;height:54px;object-fit:cover;border-radius:11px">` : `<div class="ph" style="width:54px;height:54px"></div>`;
}
function selectedPlay() {
  const play = state.selectedPlay;
  return `<div class="row" style="align-items:flex-start;margin-top:12px">${coverThumb(play)}<div><div class="tags"><span class="tag">${esc(categoryLabel(play.categoryKey) || "玩法")}</span><span class="tag green">已校验 SHA-256</span></div><b>${esc(displayText(play.title))}</b><div class="meta">开发者 ${esc(play.author || "—")}</div><div class="meta">合并固件 · 写入 0x0 · ${formatBytes(play.firmware?.size || play.firmwareSize || 0)}</div></div><span style="flex:1"></span><button class="btn secondary sm" data-action="tab" data-tab="community">更换玩法</button><button class="btn tertiary sm" data-action="clear-plan">改用本地固件</button></div>`;
}
function localPicker() {
  return `<p class="muted">推荐从“玩法社区”挑选并安装；已有 .bin 文件也可以在这里选择本地固件。文件只在本机读取。</p>
    <div class="row"><button class="chip ${state.mode === "merged" ? "on" : ""}" data-action="mode" data-value="merged">合并固件（full.bin @ 0x0）</button><button class="chip ${state.mode === "partitions" ? "on" : ""}" data-action="mode" data-value="partitions">分区文件（最多 8 个）</button></div>
    <div class="drop" id="drop">${state.mode === "merged" ? `<button class="btn secondary" data-action="pick-one">${icon("doc")} ${state.merged ? "重新选择…" : "选择 full.bin…"}</button> ${state.merged ? `<button class="btn tertiary sm" data-action="clear-plan">清除</button>` : ""} <span class="meta">合并固件固定写入 0x0</span>${state.merged ? fileTable(false) : ""}` : `${state.partitions.length ? fileTable(true) : ""}<button class="btn secondary" data-action="pick-many">${icon("plus")} 添加 .bin 文件…</button> ${state.partitions.length ? `<button class="btn tertiary sm" data-action="clear-plan">全部清除</button>` : ""} <span class="meta">可重复添加，最多 8 个；默认地址依次为 0x0、0x8000、0x10000</span>`}</div>
    <div class="meta">也可以把 .bin 文件拖到上面的虚线框中。</div>`;
}
function fileTable(editable) {
  const images = currentImages();
  return `<table class="files"><tr><th>写入地址</th><th>文件</th><th>大小</th></tr>${images.map((image, index) => `<tr><td>${editable ? `<input data-offset="${index}" value="${esc(image.offsetText)}">` : esc(image.offsetText)}</td><td>${esc(image.name)}</td><td>${formatBytes(image.size)}${editable ? ` <button class="icon-btn sm" data-action="remove-part" data-index="${index}">${icon("close")}</button>` : ""}</td></tr>`).join("")}</table>`;
}
function statusText() {
  if (state.job.type === "running") return state.job.message;
  if (state.job.type === "succeeded") return "安装完成，设备已自动重启";
  if (state.job.type === "failed") return `失败：${state.job.message.split("\n")[0]}`;
  if (state.job.type === "cancelled") return "已取消";
  const images = currentImages();
  if (!images.length) return "等待选择固件";
  return `${images.length} 个文件 · ${formatBytes(images.reduce((sum, image) => sum + image.size, 0))}`;
}
function logView() {
  return `<div class="log" id="log">${state.log.map((line) => `<div class="${line.kind}">${esc(line.text)}</div>`).join("") || '<div class="tool">还没有日志</div>'}</div><div class="row"><button class="btn tertiary sm" data-action="copy-log">复制</button><button class="btn tertiary sm" data-action="save-log">保存…</button><button class="btn tertiary sm" data-action="clear-log">清空</button></div>`;
}

function restore() {
  return `${head("回到默认状态", "恢复设备", "装过社区玩法后，可在这里恢复出厂系统与设备身份，重新使用小程序功能。", "restore")}
    <div class="card" style="padding:20px;display:flex;gap:16px"><div class="icon-tile">${icon("restore")}</div><div><b>什么时候需要恢复？</b><div class="muted">想回到设备原有功能、重新使用小程序，或准备安装另一个社区玩法时，都可以从这里开始。恢复会替换当前玩法。</div></div><span class="meta">${icon("clock")} 约 3–5 分钟</span></div>
    <section class="step"><div class="row"><div class="step-no">01</div><div><b>扫描设备二维码</b><div class="meta">用手机扫描设备背面的二维码，打开专属页面并复制设备链接，然后通过私密方式发送到这台电脑。</div></div></div>
      <div class="row" style="margin:12px 0"><button class="chip ${!state.manual ? "on" : ""}" data-action="manual" data-value="0">粘贴设备链接</button><button class="chip ${state.manual ? "on" : ""}" data-action="manual" data-value="1">手动输入 SN / KEY</button></div>
      ${state.manual ? `<div class="row"><label class="field" style="width:240px"><input id="manualSN" placeholder="SN（12 位十六进制）" value="${esc(state.manualSN)}"></label><label class="field" style="flex:1"><input id="manualKey" type="password" placeholder="KEY" value="${esc(state.manualKey)}"></label></div>` : `<label class="field"><input id="link" type="password" placeholder="https://ai-passport.folotoy.cn/…?s=…&k=…" value="${esc(state.link)}"></label>`}
      <div class="banner info">设备链接仅用于在本机生成身份分区；应用不会上传、保存，也不会把 SN / KEY 写入日志。</div>
    </section>
    <section class="step"><div class="row"><div class="step-no">02</div><div><b>准备恢复内容</b><div class="meta">应用会下载官方默认固件并逐项校验，随后带你进入熟悉的设备连接与写入流程。</div></div></div>
      <div class="row"><button class="btn primary lg" data-action="prepare" ${state.restoreWorking || jobRunning() ? "disabled" : ""}>${icon("shield")} 校验并继续</button>${state.restoreWorking ? `<div class="progress" style="width:220px"><span style="width:${Math.round(state.restoreFraction * 100)}%"></span></div>` : ""}</div>
      ${state.restoreStatus ? `<div class="meta">${esc(state.restoreStatus)}</div>` : ""}
      ${state.restoreWarning ? `<div class="banner warn">${esc(state.restoreWarning)}</div>` : ""}
      ${state.restoreError ? `<div class="banner err">${esc(state.restoreError)}</div>` : ""}
      <div class="meta">写入前会读取设备 MAC 并与二维码中的 SN 核对；信息不一致时流程会自动停止。</div>
    </section>`;
}

function about() {
  const row = (glyph, label, value) => `<div class="about-row"><div class="about-ico">${icon(glyph)}</div><div><b>${label}</b><div class="meta">${value}</div></div></div>`;
  return `${head("应用信息", "关于", "AI Passport 刷机工具的版本、数据来源与开源组件信息。", "info")}
    <section class="step"><b>AI Passport 刷机工具</b>${row("info", "应用版本", esc(state.version))}<hr>${row("cpu", "目标设备", "FoloToy AI Passport · ESP32-C3 · 8 MB Flash")}<hr>${row("bolt", "刷写后端", `内置 esptool ${esc(state.esptoolVersion)}，无需安装 Python`)}<hr>${row("grid", "界面", "macOS 与 Windows 使用同一套窗口、颜色、字体和组件")}</section>
    <section class="step"><b>数据来源</b>${row("grid", "玩法社区", "公开目录，无需登录")}<hr>${row("spark", "官方精选", "FoloToy 推荐作品")}<hr>${row("shield", "固件校验", "下载后核对文件大小与 SHA-256")}<hr>${row("restore", "出厂固件", "官方清单与四个默认分区")}<p class="meta">只有点击“安装”时才会下载固件（网站会统计一次下载）。本程序与 FoloToy 官方无关。</p></section>
    <section class="step"><b>许可</b>${row("doc", "esptool", "GPL-2.0-or-later · Espressif")}<hr><div class="about-row"><div class="about-ico">${icon("game")}</div><div><button class="btn tertiary" data-action="open" data-url="https://github.com/VOID001/FoloToy-Passport-Simulator">FoloToy Passport Simulator</button><div class="meta">MIT · VOID001 / ESP-EMU</div></div></div></section>`;
}

function modal() {
  if (state.confirm) {
    return `<div class="modal"><div class="dialog"><h2>${esc(state.confirm.title)}</h2><p class="muted">${esc(state.confirm.message)}</p><div class="row" style="justify-content:flex-end"><button class="btn secondary" data-action="confirm-no">取消</button><button class="btn ${state.confirm.danger ? "danger" : "primary"}" data-action="confirm-yes">${esc(state.confirm.confirm)}</button></div></div></div>`;
  }
  const play = state.detail;
  if (!play) return "";
  const steps = instructionSteps(play);
  const visible = state.showAllSteps ? steps : steps.slice(0, 4);
  const text = `${displayText(play.description)} ${displayText(play.instructions)}`.toLowerCase();
  const wifi = ["wi-fi", "wifi", "网络", "在线", "电台"].some((word) => text.includes(word));
  return `<div class="modal"><div class="sheet">
    <header><div><b>安装玩法</b><div class="meta">确认玩法信息，试用后再安装到 AI Passport</div></div><span style="flex:1"></span><button class="icon-btn" data-action="close-detail">${icon("close")}</button></header>
    <div class="split"><div class="art">${absoluteURL(play.image || play.thumbnail) ? `<img src="${esc(absoluteURL(play.image || play.thumbnail))}" alt="" style="width:268px;height:280px;object-fit:cover;border-radius:16px">` : ""}<div class="tags" style="margin-top:12px"><span class="tag">${esc(categoryLabel(play.categoryKey) || "玩法")}</span></div><h2>${esc(displayText(play.title))}</h2><div class="muted">开发者 ${esc(play.author || "—")}</div>${stats(play)}</div>
    <div class="detail"><b>玩法简介</b><p class="muted">${esc(displayText(play.description) || "这个玩法暂时没有介绍。")}</p>
      <div class="row"><span class="tag">${wifi ? "需要 Wi-Fi" : "设备本地运行"}</span><span class="tag">${formatBytes(play.firmware?.size || play.firmwareSize || 0)}</span><span class="tag">实体按键操控</span></div>
      ${steps.length ? `<h3>怎么玩</h3><ol>${visible.map((step) => `<li>${esc(step)}</li>`).join("")}</ol>${steps.length > 4 ? `<button class="btn tertiary sm" data-action="toggle-steps">${state.showAllSteps ? "收起步骤" : `展开全部 ${steps.length} 步`}</button>` : ""}` : ""}
      <button class="btn tertiary sm" data-action="toggle-tech">固件与更新信息</button>
      ${state.showTech ? `<div class="meta">格式：合并固件，写入地址 0x0<br>大小：${formatBytes(play.firmware?.size || play.firmwareSize || 0)}<br>SHA-256：${esc((play.firmware?.sha256 || play.firmwareSha256 || "").toLowerCase())}</div>` : ""}
      ${state.downloadError ? `<div class="banner err">${esc(state.downloadError)}</div>` : ""}
    </div></div>
    <footer><button class="btn tertiary" data-action="open" data-url="${esc(play.pageURL || `https://ai-passport.folotoy.cn/plays/${play.id}`)}">网页详情</button><button class="btn secondary" data-action="try" data-id="${play.id}">先在模拟器中体验</button><span style="flex:1"></span>${state.downloading === play.id ? `<span class="meta">正在下载并校验 ${Math.round(state.downloadProgress * 100)}%</span>` : `<button class="btn primary" data-action="install" data-id="${play.id}" ${!playIsInstallable(play) || state.downloading || jobRunning() ? "disabled" : ""}>${icon("down")} 下载并安装</button>`}</footer>
  </div></div>`;
}

function renderSimulator() {
  const sim = $("#sim");
  if (!sim.dataset.ready) {
    sim.dataset.ready = "1";
    sim.innerHTML = `<aside class="sim-library"><div class="pad"><b>玩法库</b><label class="search" style="margin-top:8px">${icon("search")}<input id="sim-search" placeholder="搜索玩法"></label></div><div class="sim-list" id="sim-list"></div></aside><div class="sim-main"><div class="now" id="now"></div><div class="stage"><div class="center" id="sim-stage">正在启动本地模拟器</div></div><div class="sim-bar" id="sim-bar"></div></div>`;
    startSimulator();
  }
  const query = state.simQuery.toLowerCase();
  const match = (text) => !query || String(text).toLowerCase().includes(query);
  const builtins = BUILTIN_FIRMWARES.filter((item) => match(item.name));
  const recents = state.recents.filter((play) => match(displayText(play.title)) || match(play.author || ""));
  const featured = state.featured.filter((play) => match(displayText(play.title)) || match(play.author || ""));
  const row = (title, detail, id, kind, image) => `<button class="sim-row ${state.simItem.kind === kind && String(state.simItem.id) === String(id) ? "active" : ""}" data-action="sim-select" data-kind="${kind}" data-id="${esc(id)}">${image ? `<img src="${esc(image)}" alt="">` : `<span class="ph"></span>`}<span><b>${esc(title)}</b><div class="meta">${esc(detail)}</div></span></button>`;
  $("#sim-list").innerHTML = `${recents.length ? `<div class="nav-label">最近试用 <button class="btn tertiary sm" data-action="clear-recents">清除</button></div>${recents.map((play) => row(displayText(play.title), play.author || "", play.id, "play", absoluteURL(play.thumbnail || play.image))).join("")}` : ""}${featured.length ? `<div class="nav-label">官方精选</div>${featured.map((play) => row(displayText(play.title), play.author || "", play.id, "play", absoluteURL(play.thumbnail || play.image))).join("")}` : ""}<div class="nav-label">内置示例 · 无需联网</div>${builtins.map((item) => row(item.name, item.detail, item.id, "builtin", "")).join("")}`;
  const current = currentSim();
  $("#now").innerHTML = `<div class="ph"></div><div style="flex:1"><div class="eyebrow accent">正在试用</div><b>${esc(current.title)}</b><div class="meta">${esc(state.simStatus.stage || current.detail || "等待启动")}</div></div><button class="btn primary" data-action="install-current" ${current.play && playIsInstallable(current.play) ? "" : "disabled"}>${icon("down")} 安装到我的设备</button>`;
  $("#sim-bar").innerHTML = `<span class="k">↑ ↓</span><span class="meta">切换</span><span class="k">↩</span><span class="meta">确认</span><span class="k">P</span><span class="meta">电源</span><span style="flex:1"></span>
    <button class="icon-btn ${state.simStatus.audio ? "active" : ""}" data-action="sim-click" data-id="audio-enable">${icon("speaker")}</button>
    <button class="icon-btn ${state.simStatus.mic ? "active" : ""}" data-action="sim-click" data-id="microphone-toggle">${icon("mic")}</button>
    <button class="icon-btn" data-action="sim-click" data-id="recording-toggle">${icon("camera")}</button>
    <button class="icon-btn" data-action="sim-click" data-id="fullscreen-toggle">${icon("sidebar")}</button>
    <button class="btn secondary sm" data-action="sim-click" data-id="restart-runtime">${icon("power")} 重启设备</button>`;
  const stage = $("#sim-stage");
  if (state.simError) stage.innerHTML = `<div class="center"><b>模拟器没有启动</b><div class="muted">${esc(state.simError)}</div><button class="btn primary" data-action="sim-restart">重新启动模拟器</button></div>`;
  else if (state.simURL && !stage.querySelector("webview")) {
    stage.innerHTML = `<webview src="${esc(simSrc())}" allowpopups="false"></webview>${state.notice ? `<div class="notice"><div><b>模拟器用于快速体验，不是完整的硬件模拟</b><div class="meta">屏幕、声音与按键可用；Wi-Fi 为虚拟网络；BLE、NFC 与电池不支持。安装前请以真机表现为准。</div></div><button class="btn secondary sm" data-action="dismiss-notice">知道了</button></div>` : ""}`;
    stage.querySelector("webview").addEventListener("console-message", (event) => {
      if (!event.message?.startsWith("APFMSG ")) return;
      try { applySimStatus(JSON.parse(event.message.slice(7))); } catch { /* ignore */ }
    });
  }
}
function currentSim() {
  if (state.simItem.kind === "play") {
    const play = findPlay(state.simItem.id);
    return { title: play ? displayText(play.title) : "社区玩法", detail: play?.author ? `开发者 ${play.author}` : "", play };
  }
  const firmware = BUILTIN_FIRMWARES.find((item) => item.id === state.simItem.id) || BUILTIN_FIRMWARES[0];
  const play = [...state.featured, ...state.plays, ...state.recents].find((item) => displayText(item.title) === firmware.name);
  return { title: firmware.name, detail: firmware.detail, play };
}
function simSrc() {
  const url = new URL(state.simURL);
  if (state.simItem.kind === "play") url.searchParams.set("play", state.simItem.id);
  else url.searchParams.set("id", String((BUILTIN_FIRMWARES.find((item) => item.id === state.simItem.id) || BUILTIN_FIRMWARES[0]).urlID));
  return url.href;
}
function applySimStatus(message) {
  if (message.type !== "state") return;
  state.simStatus = {
    phase: message.failed ? "failed" : message.state || "waiting",
    stage: message.stage || message.detail || "",
    percent: message.percent || 0,
    audio: Boolean(message.audio),
    mic: Boolean(message.mic),
    recording: Boolean(message.recording),
  };
  if (state.tab === "simulator") renderSimulator();
}
async function startSimulator() {
  try {
    const started = await window.apf.simulatorStart();
    state.simURL = started.url;
    state.simError = "";
  } catch (error) { state.simError = error.message; }
  renderSimulator();
}

function clearPlan(keepMode = false) {
  if (!jobRunning()) { state.job = { type: "idle" }; state.progress = 0; state.completion = false; }
  state.merged = null; state.partitions = []; state.planLabel = "本地文件"; state.settings = { flashMode: "keep", flashFreq: "keep", flashSize: "keep" };
  state.expectedMAC = null; state.selectedPlay = null; state.consent = false;
  if (!keepMode) state.mode = "merged";
}
async function addFiles(paths, multiple) {
  const files = [];
  for (const filePath of paths) {
    if (!filePath.toLowerCase().endsWith(".bin")) continue;
    files.push(await window.apf.inspectFile(filePath));
  }
  if (!files.length) return;
  if (!multiple && files.length === 1) {
    clearPlan(true);
    state.mode = "merged";
    state.merged = { ...files[0], offsetText: "0x0" };
  } else {
    if (state.selectedPlay || state.expectedMAC) clearPlan(true);
    state.mode = "partitions";
    for (const file of files) {
      if (state.partitions.length >= 8) { appendLog("最多支持 8 个分区文件，多余文件已忽略。", "error"); break; }
      state.partitions.push({ ...file, offsetText: defaultOffset(state.partitions.length) });
    }
  }
  render();
}

async function install(play) {
  if (!play || !playIsInstallable(play) || state.downloading || jobRunning()) return;
  state.downloading = play.id; state.downloadProgress = 0; state.downloadError = "";
  appendLog(`正在获取 “${displayText(play.title)}” 固件…`);
  render();
  try {
    const file = await window.apf.downloadPlay(play);
    clearPlan();
    state.merged = { name: `${play.slug}.bin`, path: file.path, size: file.size, offsetText: "0x0", firstByte: file.firstByte };
    state.mode = "merged";
    state.planLabel = `社区玩法：${displayText(play.title)}`;
    state.selectedPlay = play;
    state.detail = null;
    state.tab = "flash";
    appendLog(`已载入 “${displayText(play.title)}”，大小与 SHA-256 校验通过。请连接设备并确认后开始安装。`, "success");
  } catch (error) {
    state.downloadError = `下载 “${displayText(play.title)}” 失败：${error.message}`;
    appendLog(state.downloadError, "error");
  }
  state.downloading = null;
  render();
}

function onTool(payload) {
  appendLog(payload.text, payload.kind || "tool", payload.overwrite);
  if (payload.kind) { render(); return; }
  for (const event of eventsIn(payload.text)) {
    if (event.type === "phase") state.job = { type: "running", message: event.value };
    if (event.type === "progress" && tracker) {
      const [index, overall] = tracker.update(event.value);
      const images = currentImages();
      state.progress = Math.max(state.progress, 0.02 + 0.96 * overall);
      state.job = { type: "running", message: `正在写入 ${images[index]?.name || "固件"}（${index + 1}/${images.length}）` };
    }
    if (event.type === "fileWritten") tracker?.fileFinished();
    if (event.type === "verified") state.job = { type: "running", message: "数据校验通过" };
    if (event.type === "resetting") state.job = { type: "running", message: "正在重启设备…" };
    if (event.type === "mac") state.deviceInfo = { ...(state.deviceInfo || {}), mac: event.value };
    if (event.type === "chip") state.deviceInfo = { ...(state.deviceInfo || {}), chip: event.value };
    if (event.type === "flashSize") state.deviceInfo = { ...(state.deviceInfo || {}), flashSize: event.value };
  }
  if (state.tab === "flash" || state.tab === "about") render();
  else updatePill();
}

async function startWrite() {
  const images = currentImages().map((image) => ({ ...image, offsetText: formatOffset(parseOffset(image.offsetText) ?? 0) }));
  state.progress = 0;
  state.job = { type: "running", message: "准备中…" };
  state.showLog = true;
  tracker = createProgressTracker(images.map((image) => image.size));
  appendLog(`———— 开始写入 ${images.length} 个文件（${formatBytes(images.reduce((sum, image) => sum + image.size, 0))}）到 ${state.selectedPort} ————`);
  for (const image of images) appendLog(`  ${image.offsetText}  ${image.name}  ${image.size} 字节`);
  render();
  try {
    await window.apf.writeFlash({
      port: state.selectedPort,
      baud: state.baud,
      images,
      settings: state.settings,
      expectedMAC: state.expectedMAC,
    });
    state.progress = 1;
    state.job = { type: "succeeded" };
    state.consent = false;
    state.completion = true;
    appendLog("写入完成，已发送硬件复位，设备正在重启。", "success");
  } catch (error) {
    if (error.message === "已取消") {
      state.job = { type: "cancelled" };
      appendLog("已取消。若写入中途被打断，设备可能无法启动，重新刷写即可恢复（芯片 ROM 下载模式不会被破坏）。", "error");
    } else {
      state.job = { type: "failed", message: error.message };
      state.showLog = true;
      appendLog(`写入失败：${error.message}`, "error");
    }
  }
  tracker = null;
  render();
}

function onClick(event) {
  const node = event.target.closest("[data-action]");
  if (!node) return;
  const action = node.dataset.action;
  if (action === "win-close") window.apf.window.close();
  if (action === "win-min") window.apf.window.minimize();
  if (action === "win-zoom") window.apf.window.toggleZoom();
  if (action === "tab") { state.tab = node.dataset.tab; state.completion = false; render(); }
  if (action === "pill") { if (state.job.type === "succeeded") state.completion = !state.completion; else state.tab = "flash"; render(); }
  if (action === "detail") { state.detail = findPlay(node.dataset.id); state.showAllSteps = false; render(); }
  if (action === "close-detail") { state.detail = null; render(); }
  if (action === "install-open") { state.detail = findPlay(node.dataset.id); state.showAllSteps = false; render(); }
  if (action === "install") install(findPlay(node.dataset.id));
  if (action === "try") tryPlay(findPlay(node.dataset.id));
  if (action === "category") { state.query.category = node.dataset.value; reloadPlays(); }
  if (action === "clear-search") { state.query.search = ""; reloadPlays(); }
  if (action === "clear-filters") { state.query = { ...state.query, search: "", category: "all", tag: "" }; reloadPlays(); }
  if (action === "reload" || action === "reload-featured") loadLibrary();
  if (action === "clear-error") { state.downloadError = ""; render(); }
  if (action === "local-bin") { clearPlan(); state.tab = "flash"; render(); }
  if (action === "toggle-steps") { state.showAllSteps = !state.showAllSteps; render(); }
  if (action === "toggle-tech") { state.showTech = !state.showTech; render(); }
  if (action === "open") window.apf.openExternal(node.dataset.url);
  if (action === "port" && !jobRunning()) { state.selectedPort = node.dataset.path; state.deviceInfo = null; render(); }
  if (action === "refresh-ports") refreshPorts();
  if (action === "mode" && !jobRunning()) { state.mode = node.dataset.value; render(); }
  if (action === "pick-one") pick(false);
  if (action === "pick-many") pick(true);
  if (action === "clear-plan") { clearPlan(true); render(); }
  if (action === "remove-part") { state.partitions.splice(Number(node.dataset.index), 1); render(); }
  if (action === "read-chip") readChip();
  if (action === "ask-write") { state.confirm = { title: "确认写入固件？", message: `将向 ${state.selectedPort} 写入 ${currentImages().length} 个文件，覆盖设备 Flash 中对应区域的现有内容。写入过程中请勿拔线。`, confirm: "开始写入（覆盖设备内容）", danger: true, yes: startWrite }; render(); }
  if (action === "confirm-no") { state.confirm = null; render(); }
  if (action === "confirm-yes") { const yes = state.confirm?.yes; state.confirm = null; render(); yes?.(); }
  if (action === "cancel") window.apf.cancelJob();
  if (action === "toggle-log") { state.showLog = !state.showLog; render(); }
  if (action === "copy-log") window.apf.copyText(state.log.map((line) => line.text).join("\n"));
  if (action === "save-log") window.apf.saveText(state.log.map((line) => line.text).join("\n"));
  if (action === "clear-log" && !jobRunning()) { state.log = []; render(); }
  if (action === "another") { clearPlan(); state.downloadError = ""; state.tab = "community"; render(); }
  if (action === "another-restore") { clearPlan(); state.tab = "restore"; render(); }
  if (action === "manual") { state.manual = node.dataset.value === "1"; render(); }
  if (action === "prepare") prepare();
  if (action === "sim-select") selectSim(node.dataset.kind, node.dataset.id);
  if (action === "sim-click") document.querySelector("webview")?.executeJavaScript(`window.__apf && window.__apf.click(${JSON.stringify(node.dataset.id)})`);
  if (action === "sim-restart") { state.simError = ""; $("#sim-stage").innerHTML = `<div class="center">正在重新启动模拟器</div>`; window.apf.simulatorRestart().then((started) => { state.simURL = started.url; const stage = $("#sim-stage"); stage.innerHTML = ""; renderSimulator(); }).catch((error) => { state.simError = error.message; renderSimulator(); }); }
  if (action === "dismiss-notice") { state.notice = false; localStorage.setItem("simulator.noticeDismissed", "1"); const note = document.querySelector(".notice"); note?.remove(); }
  if (action === "clear-recents") { state.recents = []; saveRecents(); renderSimulator(); }
  if (action === "install-current") { const play = currentSim().play; if (play) { state.detail = play; state.tab = "community"; render(); } }
}

function onInput(event) {
  if (event.target.id === "search") {
    state.query.search = event.target.value;
    clearTimeout(searchTimer);
    searchTimer = setTimeout(reloadPlays, 400);
  }
  if (event.target.id === "sim-search") { state.simQuery = event.target.value; renderSimulator(); }
  if (event.target.id === "link") state.link = event.target.value;
  if (event.target.id === "manualSN") state.manualSN = event.target.value;
  if (event.target.id === "manualKey") state.manualKey = event.target.value;
  if (event.target.dataset.offset != null) state.partitions[Number(event.target.dataset.offset)].offsetText = event.target.value;
}
function onChange(event) {
  const field = event.target.dataset.field;
  if (field === "tag" || field === "sort") { state.query[field] = event.target.value; reloadPlays(); }
  if (field === "showAllPorts") { state.showAllPorts = event.target.checked; refreshPorts(); }
  if (field === "consent") state.consent = event.target.checked;
  if (field === "baud") state.baud = Number(event.target.value);
}
async function onDrop(event) {
  const zone = event.target.closest(".drop");
  if (!zone) return;
  event.preventDefault();
  const paths = [...event.dataTransfer.files].map((file) => window.apf.pathForFile(file));
  await addFiles(paths, state.mode !== "merged" || paths.length !== 1);
}
async function pick(multiple) {
  const paths = await window.apf.pickFiles({ multiple, title: multiple ? "选择分区 .bin 文件（最多 8 个）" : "选择合并固件 full.bin" });
  await addFiles(paths, multiple);
}
async function readChip() {
  if (!state.selectedPort || jobRunning()) return;
  state.job = { type: "running", message: "正在读取芯片信息…" };
  appendLog(`读取芯片信息（只读，不写入 Flash）：${state.selectedPort}`);
  render();
  try {
    const transcript = await window.apf.readChip({ port: state.selectedPort, baud: state.baud });
    state.deviceInfo = { chip: chipIn(transcript), mac: macIn(transcript), flashSize: flashSizeIn(transcript) };
    state.job = { type: "idle" };
    appendLog("读取完成，设备已重启。", "success");
  } catch (error) {
    state.job = { type: "idle" };
    appendLog(`读取失败：${error.message}`, "error");
  }
  render();
}
function tryPlay(play) {
  if (!play) return;
  state.recents = [play, ...state.recents.filter((item) => item.id !== play.id)].slice(0, 8);
  saveRecents();
  state.detail = null;
  state.simItem = { kind: "play", id: play.id };
  state.tab = "simulator";
  const view = document.querySelector("webview");
  if (view && state.simURL) view.src = simSrc();
  render();
}
function selectSim(kind, id) {
  state.simItem = { kind, id: kind === "builtin" ? id : Number(id) };
  if (kind === "play") {
    const play = findPlay(id);
    if (play) { state.recents = [play, ...state.recents.filter((item) => item.id !== play.id)].slice(0, 8); saveRecents(); }
  }
  const view = document.querySelector("webview");
  if (view) view.src = simSrc();
  renderSimulator();
}
async function prepare() {
  state.restoreError = ""; state.restoreWarning = ""; state.restoreWorking = true; state.restoreFraction = 0;
  render();
  try {
    const prepared = await window.apf.prepareRestore(state.manual ? { sn: state.manualSN, key: state.manualKey } : { link: state.link });
    clearPlan();
    state.partitions = prepared.images;
    state.mode = "partitions";
    state.planLabel = `恢复出厂固件 ${prepared.version}（设备 ${prepared.sn}）`;
    state.settings = { flashMode: "dio", flashFreq: "80m", flashSize: "8MB" };
    state.expectedMAC = prepared.sn;
    state.restoreWarning = prepared.warning || "";
    state.link = ""; state.manualKey = "";
    state.tab = "flash";
    appendLog(`已准备恢复出厂固件 ${prepared.version}（${prepared.images.length} 个分区，所有文件 SHA-256 校验通过）。`, "success");
  } catch (error) { state.restoreError = error.message; }
  state.restoreWorking = false;
  render();
}

async function snapshot() {
  const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
  const until = async (predicate, timeout = 20000) => {
    const start = Date.now();
    while (!predicate()) {
      if (Date.now() - start > timeout) return;
      await wait(250);
    }
  };
  const imagesReady = () => {
    const images = [...document.querySelectorAll(".hero img, .grid.featured img, .play img")];
    return images.length >= 4 && images.slice(0, 4).every((img) => img.complete && img.naturalWidth > 0);
  };
  await until(() => document.querySelector(".hero h3") && state.plays.length && imagesReady(), 25000);
  await wait(400);
  await window.apf.capture("01-community.png");
  state.detail = state.featured.find(playIsInstallable) || state.plays[0];
  render();
  await wait(700);
  await window.apf.capture("02-play-detail.png");
  state.detail = null; state.tab = "flash"; render();
  await wait(400);
  await window.apf.capture("03-connect.png");
  state.tab = "restore"; render();
  await wait(300);
  await window.apf.capture("04-restore.png");
  state.tab = "about"; render();
  await wait(300);
  await window.apf.capture("05-about.png");
  state.tab = "simulator"; render();
  await until(() => state.simURL || state.simError, 15000);
  document.querySelector("[data-action='dismiss-notice']")?.click();
  await wait(2800);
  await window.apf.capture("06-simulator.png");
  await window.apf.snapshotDone();
}

boot();
