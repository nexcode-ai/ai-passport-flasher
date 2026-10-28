# AI Passport 刷机工具（macOS）

FoloToy AI Passport（ESP32-C3 · 8 MB Flash · USB Serial/JTAG）的原生 macOS 刷机应用，是
[网页刷机工具](https://ai-passport.folotoy.cn/tools/web-flasher/) 和 [tool.folotoy.com](https://tool.folotoy.com/) 的桌面版。
SwiftUI 编写，界面为简体中文。非官方工具。

## 功能

- **玩法社区（首页）**：浏览 ai-passport.folotoy.cn 的社区玩法（封面、作者、简介、操作说明、下载量），支持搜索、分类、标签、排序和分页；顶部是「官方精选」。点击「安装」会下载固件、核对大小和 SHA-256，然后进入「连接与安装」。
- **连接与安装**：三步流程：
  1. 连接设备：每 1.5 秒自动扫描 `/dev/cu.usbmodem*`，识别 Espressif USB JTAG/serial（VID 303A / PID 1001）；可选「读取芯片信息」（只读）。
  2. 选择固件：已选的社区玩法；或本地文件，可以是一个合并固件 `full.bin`（写入 0x0），也可以是最多 8 个分区 `.bin`（地址可编辑，默认依次为 0x0 / 0x8000 / 0x10000）。会检查 4 KB 对齐、区域重叠、8 MB 上限，以及 0x0 处的镜像头。
  3. 写入与重启：覆盖警告，必须勾选确认并在弹窗中再次确认；之后显示进度条和日志，写入完成后硬件复位，设备自动重启。
- **恢复出厂固件**：粘贴设备二维码中的专属链接（`?s=SN&k=KEY`），下载公开的默认固件并校验，在本机生成 `cardid` 凭据分区。写入前先核对设备 MAC 是否等于 SN，不一致就停止。

## 构建与运行

需要 Xcode（Swift 5.9+，已在 Xcode 27.1 / Swift 6.4 / macOS 26 arm64 上验证）。不需要 Python 或 ESP-IDF。

```bash
cd ~/ai-passport-flasher
./scripts/build-app.sh          # 首次会下载并校验 esptool，然后生成 build/AIPassportFlasher.app
open build/AIPassportFlasher.app
```

- 用 Xcode 开发：`open Package.swift`，选择 `AIPassportFlasher` scheme 后运行；也可以执行 `xcodebuild -scheme AIPassportFlasher -destination 'platform=macOS,arch=arm64' build`。
- 测试：`swift test`；加上 `APF_NETWORK_TESTS=1` 会额外验证线上的社区接口和出厂固件清单。
- 截图：`./scripts/snapshots.sh [玩法 slug]` 会在后台把每个页面渲染到 `screenshots/`（通过 `APF_SNAPSHOT_DIR`），然后退出。这个过程不访问串口，也不写入设备。

应用使用本地 ad-hoc 签名，可以直接在本机打开；拷贝到其他 Mac 时会被 Gatekeeper 拦截，需要右键选择「打开」，或者使用开发者证书签名。目前只支持 Apple 芯片（arm64）。

## 工作原理

- **刷写后端**：应用内置 Espressif 官方发布的独立 esptool v5.6.0 可执行文件（PyInstaller 打包，带 Espressif 的 Developer ID 签名），位于 `Contents/Resources/esptool/`。`scripts/fetch-esptool.sh` 会核对下载包的 SHA-256。写入时执行的命令：
  `esptool --chip esp32c3 --port <port> --baud <baud> --before default-reset --after hard-reset write-flash --flash-mode keep --flash-freq keep --flash-size keep <addr> <file> …`
  这些参数与网页工具（esptool-js 的 `flashMode/Freq/Size: keep`，启用压缩）一致；恢复出厂固件时与官方恢复页一致，使用 `dio / 80m / 8MB`。esptool 的输出通过管道读取：stdout 不是终端时，每次进度更新都是完整的一行，应用据此解析进度。esptool 会自动处理 USB-Serial/JTAG 的复位时序和 stub 加载。
- **社区数据**（都是公开 GET 请求，无需登录，与网站页面发出的请求相同）：
  - 列表：`https://ai-passport.folotoy.cn/api/plays?tag=&bootstrap=false&q=<搜索>&category=<all|games|productivity|information|learning|media|social|developer>&sort=<newest|downloads|hearts|comments>&period=all&limit=24&offset=<n>`，返回 `plays[]`、`pagination{total,hasMore}`；标签使用 `tag=must-play|multiplayer|family`。
  - 官方精选：`/api/plays/recommendations?limit=20`（网页刷机工具的「官方精选」用的就是这个接口；`/api/plays?bootstrap=true` 中的 `recommendations` 是同一份数据）。
  - 每个玩法带有 `firmware{format:"esp-merged-0x0", size, sha256, url}`，下载地址为 `/api/download/community/<slug>`。只有点击「安装」才会下载（网站会把它计为一次下载），下载后核对大小、SHA-256 和镜像头 0xE9，缓存在 `~/Library/Caches/AIPassportFlasher/firmware/`。
- **出厂恢复**：`/assets/firmwares/ai-passport-default/manifest.json` 中有 4 个文件（bootloader 0x0、partition-table 0x8000、trae_card 0x10000、imgava 0x3FA000），应用逐个核对 SHA-256，并检查分区表（factory / cardid / imgava / imguser）。另外在 0x356000 写入 16 KB 的 `cardid` NVS 分区，内容为命名空间 `folotoy-key` 下的 DeviceKey=SN、DeviceSecret=KEY、ProductKey、HardwareVersion。生成器移植自官方恢复页的 JS，单元测试逐字节比对两者的输出。写入前会查询 `webapp.folotoy.cn/v1/toys/sn/<SN>/product`；若返回 TRAE、JD 等其他型号，应用会拒绝写入。KEY 不会保存，也不会写入日志。

## 目录

```
Package.swift                 SwiftPM 工程（Xcode 可直接打开）
Sources/AIPassportFlasher/    App/ Models/ Services/ Views/
Tests/AIPassportFlasherTests/ 单元测试（NVS 一致性、输出解析、地址校验、真实 esptool）
Resources/Info.plist
scripts/fetch-esptool.sh      下载并校验内置 esptool（Vendor/esptool，不入库）
scripts/build-app.sh          生成 build/AIPassportFlasher.app
scripts/snapshots.sh          重新生成截图
screenshots/                  各步骤截图
```

esptool 以 GPL-2.0-or-later 许可发布，其 LICENSE 随应用一起分发。
