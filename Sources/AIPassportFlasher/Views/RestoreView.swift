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
                    eyebrow: "回到默认状态",
                    title: "恢复设备",
                    subtitle: "装过社区玩法后，可在这里恢复出厂系统与设备身份，重新使用小程序功能。",
                    symbol: "arrow.counterclockwise.circle.fill"
                )
                RestoreReasonCard()
                StepCard(number: "01", title: "扫描设备二维码",
                         subtitle: "用手机扫描设备背面的二维码，打开专属页面并复制设备链接，然后通过私密方式发送到这台 Mac。") {
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
                    Banner(kind: .info, text: "设备链接仅用于在本机生成身份分区；应用不会上传、保存，也不会把 SN / KEY 写入日志。")
                }
                StepCard(number: "02", title: "准备恢复内容",
                         subtitle: "应用会下载官方默认固件并逐项校验，随后带你进入熟悉的设备连接与写入流程。") {
                    HStack(spacing: 12) {
                        Button {
                            prepare()
                        } label: {
                            Label("校验并继续", systemImage: "checkmark.shield")
                        }
                        .buttonStyle(PrimaryButtonStyle(size: .large))
                        .disabled(working || app.job.isRunning || (useManual ? manualSN.isEmpty || manualKey.isEmpty : link.isEmpty))
                        if working { ProgressView(value: fraction).frame(width: 220) }
                    }
                    if let status { Text(status).foregroundStyle(.secondary) }
                    if let productWarning { Banner(kind: .warning, text: productWarning) }
                    if let errorText { Banner(kind: .error, text: errorText) }
                    Text("写入前会读取设备 MAC 并与二维码中的 SN 核对；信息不一致时流程会自动停止。")
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

struct RestoreReasonCard: View {
    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Brand.accent)
                .frame(width: 48, height: 48)
                .background(Brand.accentSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 6) {
                Text("什么时候需要恢复？").font(.headline)
                Text("想回到设备原有功能、重新使用小程序，或准备安装另一个社区玩法时，都可以从这里开始。恢复会替换当前玩法。")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Label("约 3–5 分钟", systemImage: "clock")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .card()
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
                    Text("玩法模拟器基于 VOID001/FoloToy-Passport-Simulator（MIT）及 ESP-EMU，许可证随应用一并提供（Resources/simulator/LICENSE）。")
                        .font(.callout)
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
