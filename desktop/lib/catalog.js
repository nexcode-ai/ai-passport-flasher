export const CATEGORIES = [
  ["all", "全部"],
  ["games", "游戏与互动"],
  ["productivity", "效率与工具"],
  ["information", "信息与展示"],
  ["learning", "学习与创作"],
  ["media", "音乐与影像"],
  ["social", "活动与社交"],
  ["developer", "开发者实验"],
];

export const TAGS = [
  ["", "不限"],
  ["must-play", "必玩精选"],
  ["multiplayer", "多人玩法"],
  ["family", "亲子益智"],
];

export const SORTS = [
  ["newest", "最新发布"],
  ["downloads", "下载最多"],
  ["hearts", "最多喜欢"],
  ["comments", "讨论最多"],
];

const SUBCATEGORIES = {
  "games-strategy": "策略战术", "games-seek": "寻宝互动", "games-collect": "抽卡收集", "games-divination": "抽签问答",
  "games-pet": "宠物养成", "games-relax": "解压互动", "games-narrative": "剧情冒险", "games-board": "桌游棋牌",
  "games-rhythm": "音乐节奏", "games-sports": "竞速体育", "games-simulation": "模拟经营", "games-rpg": "角色扮演",
  "games-puzzle": "益智解谜", "games-arcade": "动作街机", "games-collection": "游戏合集",
  "productivity-scoring": "计数记分", "productivity-decision": "日常决策", "productivity-focus": "计时专注",
  "productivity-tasks": "待办提醒", "productivity-voice": "语音记录", "productivity-control": "输入遥控",
  "productivity-health": "健康与生活", "productivity-ai": "AI 工作助手", "productivity-security": "安全与检测",
  "productivity-life": "日常记录", "productivity-toolbox": "综合工具",
  "information-dashboard": "综合看板", "information-finance": "行情财经", "information-monitor": "状态监控",
  "information-sports": "赛事资讯", "information-clock": "日期黄历", "information-weather": "天气环境",
  "information-reference": "图鉴速查", "information-identity": "身份展示", "information-reading": "资讯文字",
  "information-life": "生活看板",
  "learning-language": "语言单词", "learning-reading": "阅读经典", "learning-school": "学科练习",
  "learning-skills": "技能训练", "learning-knowledge": "知识探索", "learning-creative": "绘画设计",
  "learning-ai": "AI 问答", "learning-culture": "传统文化",
  "media-radio": "网络电台", "media-video": "视频播放", "media-sleep": "声景助眠", "media-music": "音乐播放",
  "media-sound": "音效互动", "media-visual": "影像展示", "media-projection": "拍照投屏", "media-instrument": "演奏节拍",
  "social-radio": "对讲通信", "social-nearby": "附近发现", "social-ai": "AI 陪伴", "social-identity": "名片交流",
  "social-expression": "社交表达", "social-party": "聚会互动", "social-community": "社区入口",
  "developer-installer": "安装管理", "developer-runtime": "脚本运行", "developer-wireless": "通信实验",
  "developer-benchmark": "设备调试", "developer-sensing": "交互实验", "developer-demo": "能力示例",
  "developer-accessory": "配件原型",
};

export function categoryLabel(key) {
  if (!key) return null;
  return SUBCATEGORIES[key] || CATEGORIES.find(([id]) => id === key)?.[1] || null;
}

export const BUILTIN_FIRMWARES = [
  { id: "official-demo", urlID: 3, name: "FoloToy 官方 Demo", detail: "默认演示 · 1.5 MB" },
  { id: "music-keychain", urlID: 1, name: "音乐钥匙扣", detail: "语音互动 · 8 MB" },
  { id: "answer-book", urlID: 2, name: "答案之书", detail: "随机回答 · 2.8 MB" },
  { id: "feishu-calendar-assistant", urlID: 4, name: "飞书日程助手", detail: "日程与待办 · 2.2 MB" },
];

export function displayText(value) {
  const zh = value?.zh?.trim() ?? "";
  return zh || value?.en || "";
}

export function formatBytes(n) {
  const value = Number(n) || 0;
  if (value < 1000) return `${value} 字节`;
  const units = ["KB", "MB", "GB"];
  let size = value / 1000;
  let index = 0;
  while (size >= 1000 && index < units.length - 1) {
    size /= 1000;
    index += 1;
  }
  const digits = size >= 10 || Number.isInteger(size) ? 0 : 1;
  return `${size.toFixed(digits)} ${units[index]}`;
}

export function playIsInstallable(play) {
  const firmware = play.firmware ?? {};
  const format = firmware.format || "esp-merged-0x0";
  const sha = (firmware.sha256 || play.firmwareSha256 || "").toLowerCase();
  const size = firmware.size || play.firmwareSize || 0;
  const url = firmware.url || play.downloadUrl;
  return (firmware.available ?? true) && format === "esp-merged-0x0" && Boolean(url) && sha.length === 64 && size > 0;
}

export function absoluteURL(path) {
  if (!path) return null;
  if (path.startsWith("http://") || path.startsWith("https://")) return path;
  return new URL(path, "https://ai-passport.folotoy.cn").href;
}

export function instructionSteps(play) {
  const raw = displayText(play.instructions).trim();
  if (!raw) return [];
  const numbered = raw.replace(/(?:^|\s)(?:步骤\s*)?\d+[.、)）:：]\s*/g, "\n");
  let parts = numbered.split(/\n+/).map((part) => part.trim()).filter(Boolean);
  if (parts.length === 1 && raw.length > 100) {
    parts = raw.split(/[；;]/).map((part) => part.trim()).filter(Boolean);
  }
  return parts;
}
