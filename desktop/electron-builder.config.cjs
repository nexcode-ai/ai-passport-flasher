const path = require("path");

const win = process.argv.includes("--win");
const repo = path.resolve(__dirname, "..");

const simulator = { from: path.join(repo, "Resources", "Simulator"), to: "simulator" };
const resources = win
  ? [
      simulator,
      { from: path.join(repo, "Vendor", "win", "esptool.exe"), to: "esptool/esptool.exe" },
      { from: path.join(repo, "Vendor", "esptool", "LICENSE"), to: "esptool/LICENSE" },
      { from: path.join(repo, "Vendor", "win", "node.exe"), to: "node/node.exe" },
      { from: path.join(repo, "Vendor", "node", "LICENSE"), to: "node/LICENSE" },
    ]
  : [
      simulator,
      { from: path.join(repo, "Vendor", "esptool", "esptool"), to: "esptool/esptool" },
      { from: path.join(repo, "Vendor", "esptool", "esptool-arm64"), to: "esptool/esptool-arm64" },
      { from: path.join(repo, "Vendor", "esptool", "esptool-x86_64"), to: "esptool/esptool-x86_64" },
      { from: path.join(repo, "Vendor", "esptool", "LICENSE"), to: "esptool/LICENSE" },
      { from: path.join(repo, "Vendor", "node", "node"), to: "node/node" },
      { from: path.join(repo, "Vendor", "node", "LICENSE"), to: "node/LICENSE" },
    ];

module.exports = {
  appId: "local.aipassport.flasher",
  productName: "AI Passport 刷机工具",
  executableName: "AIPassportFlasher",
  directories: { output: "dist", buildResources: "build" },
  files: ["electron/**", "lib/**", "renderer/**", "simulator/**", "package.json"],
  extraResources: resources,
  mac: {
    icon: path.join(repo, "Resources", "AppIcon.icns"),
    category: "public.app-category.developer-tools",
    identity: null,
    target: [{ target: "dmg", arch: ["universal"] }],
    x64ArchFiles: "Contents/Resources/{esptool,node,simulator}/**",
    artifactName: "AIPassportFlasher-${version}-mac-universal.${ext}",
  },
  dmg: {
    title: "AI Passport 刷机工具",
  },
  win: {
    icon: path.join(__dirname, "build", "icon.png"),
    target: [{ target: "zip", arch: ["x64"] }],
    artifactName: "AIPassportFlasher-${version}-windows-x64.${ext}",
    signAndEditExecutable: false,
  },
  asar: true,
};
