import { createRequire } from "node:module";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const require = createRequire(import.meta.url);
const dest = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../renderer/fonts");
fs.mkdirSync(dest, { recursive: true });
const root = path.dirname(require.resolve("@fontsource/noto-sans-sc/package.json"));
const files = fs.readdirSync(path.join(root, "files"));
for (const weight of [400, 500, 600, 700]) {
  const name = files.find((file) => file.includes(`chinese-simplified-${weight}-normal`) && file.endsWith(".woff2"));
  if (!name) throw new Error(`缺少 Noto Sans SC ${weight}`);
  fs.copyFileSync(path.join(root, "files", name), path.join(dest, `noto-sans-sc-${weight}.woff2`));
}
console.log(`fonts -> ${dest}`);
