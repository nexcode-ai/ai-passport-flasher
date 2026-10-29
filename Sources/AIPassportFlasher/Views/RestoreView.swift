import SwiftUI

struct RestoreView: View {
    @EnvironmentObject var app: AppState
    @State private var link = ""
    @State private var manualSN = ""
    @State private var manualKey = ""
    @State private var useManual = false
    @State private var status: String?
    @State private var errorText: String?
    @State private var productWarning: String?
    @State private var working = false
    @State private var fraction = 0.0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeader(
                    eyebrow: "安全恢复",
                    title: "恢复出厂固件",
                    subtitle: "恢复 AI Passport 默认系统与设备凭据，重新使用小程序的通行证功能。",
                    symbol: "arrow.counterclockwise.circle.fill"
                )
                StepCard(number: "01", title: "获取设备专属链接",
                         subtitle: "用手机扫描设备背面的二维码，打开设备专属页面，点击「复制设备链接到电脑」，通过私密方式发到这台电脑，然后粘贴到下面。") {
                    Picker("", selection: $useManual) {
                        Text("粘贴设备链接").tag(false)
                        Text("手动输入 SN / KEY").tag(true)
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 360)
                    if useManual {
                        HStack {
                            TextField("SN（12 位十六进制）", text: $manualSN).textFieldStyle(.roundedBorder).font(.body.monospaced()).frame(width: 220)
                            SecureField("KEY", text: $manualKey).textFieldStyle(.roundedBorder).frame(maxWidth: 360)
                        }
                    } else {
                        SecureField("https://ai-passport.folotoy.cn/…?s=…&k=…", text: $link)
                            .textFieldStyle(.roundedBorder)
                    }
                    Banner(kind: .warning, text: "链接中包含这台设备的 SN 和 KEY，请勿公开分享。本程序只在本机用它生成凭据分区，不会上传、保存或写入日志。")
                }
                StepCard(number: "02", title: "下载并校验默认固件",
                         subtitle: "从 ai-passport.folotoy.cn 下载公开的默认固件（bootloader、分区表、主程序、默认头像），逐个核对大小与 SHA-256，并检查分区表与 AI Passport 一致。") {
                    HStack(spacing: 12) {
                        Button {
                            prepare()
                        } label: {
                            Label("准备恢复固件", systemImage: "arrow.down.doc")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(working || app.job.isRunning || (useManual ? manualSN.isEmpty || manualKey.isEmpty : link.isEmpty))
                        if working { ProgressView(value: fraction).frame(width: 220) }
                    }
                    if let status { Text(status).foregroundStyle(.secondary) }
                    if let productWarning { Banner(kind: .warning, text: productWarning) }
                    if let errorText { Banner(kind: .error, text: errorText) }
                    Text("准备完成后会进入「连接与安装」页面：写入前会先读取设备 MAC，与二维码中的 SN 不一致时立即停止，不写入任何数据。")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
            .frame(maxWidth: 1040, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(AppTheme.pageBackground)
    }

    private func prepare() {
        errorText = nil
        productWarning = nil
        let creds: FactoryRestore.Credentials
        do {
            creds = useManual ? try FactoryRestore.validate(sn: manualSN, key: manualKey) : try FactoryRestore.parseCredentials(link: link)
        } catch {
            errorText = error.localizedDescription
            return
        }
        working = true
        fraction = 0
        status = "正在核对设备型号…"
        Task {
            defer { working = false }
            switch await FactoryRestore.lookupProduct(sn: creds.sn) {
            case .aiPassport:
                break
            case let .other(kind):
                errorText = "这台设备登记的型号是 \(kind)，不是 AI Passport。请使用该型号对应的官方恢复页面，本程序不会为它写入 AI Passport 默认固件。"
                status = nil
                return
            case let .unknown(reason):
                productWarning = "无法在线确认设备型号（\(reason)）。写入前仍会核对设备 MAC 与 SN。"
            }
            do {
                let prepared = try await FactoryRestore.prepare(credentials: creds) { msg, f in
                    Task { @MainActor in status = msg; fraction = f }
                }
                status = "默认固件 \(prepared.manifest.version)（\(prepared.manifest.firmwareCommit)）已就绪。"
                link = ""
                manualKey = ""
                app.useFactoryRestore(prepared, credentials: creds)
            } catch {
                errorText = error.localizedDescription
                status = nil
            }
        }
    }
}

struct AboutView: View {
    @EnvironmentObject var app: AppState
    @State private var esptoolVersion = "检测中…"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeader(
                    eyebrow: "应用信息",
                    title: "关于",
                    subtitle: "AI Passport 刷机工具的版本、数据来源与开源组件信息。",
                    symbol: "info.circle.fill"
                )
                StepCard(number: "", title: "AI Passport 刷机工具（macOS）") {
                    InfoPair(label: "应用版本", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版")
                    InfoPair(label: "目标设备", value: "FoloToy AI Passport · ESP32-C3 · 8 MB Flash · USB Serial/JTAG")
                    InfoPair(label: "刷写后端", value: "内置 esptool \(esptoolVersion)（Espressif 官方独立可执行文件，无需 Python）")
                    InfoPair(label: "esptool 路径", value: app.esptoolURL?.path ?? "缺失")
                }
                StepCard(number: "", title: "数据来源") {
                    Text("玩法社区：GET https://ai-passport.folotoy.cn/api/plays（公开、无需登录，分页）").font(.callout.monospaced())
                    Text("官方精选：GET https://ai-passport.folotoy.cn/api/plays/recommendations?limit=20").font(.callout.monospaced())
                    Text("固件下载：GET /api/download/community/<slug>，下载后核对大小与 SHA-256").font(.callout.monospaced())
                    Text("出厂固件：/assets/firmwares/ai-passport-default/manifest.json").font(.callout.monospaced())
                    Text("只有点击「安装」时才会下载固件（网站会统计一次下载）。本程序与 FoloToy 官方无关，数据接口可能随网站更新而变化。")
                        .font(.callout).foregroundStyle(.secondary)
                }
                StepCard(number: "", title: "许可") {
                    Text("esptool 以 GPL-2.0-or-later 许可发布，其许可证随应用一并提供（Resources/esptool/LICENSE）。").font(.callout)
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
            .frame(maxWidth: 1040, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(AppTheme.pageBackground)
        .task { esptoolVersion = await readVersion() }
    }

    private func readVersion() async -> String {
        guard app.esptoolURL != nil else { return "缺失" }
        let out = try? await EsptoolRunner().run(["version"]) { _, _ in }
        return out?.split(separator: "\n").last.map(String.init) ?? "未知"
    }
}
