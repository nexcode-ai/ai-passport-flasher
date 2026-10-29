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
                    AppSegmentedControl(
                        [(false, "粘贴设备链接"), (true, "手动输入 SN / KEY")],
                        selection: $useManual
                    )
                    .frame(maxWidth: 380)
                    if useManual {
                        HStack(spacing: Space.s) {
                            TextField("SN（12 位十六进制）", text: $manualSN)
                                .font(.body.monospaced())
                                .appField()
                                .frame(width: 240)
                            SecureField("KEY", text: $manualKey)
                                .appField()
                                .frame(maxWidth: 380)
                        }
                    } else {
                        SecureField("https://ai-passport.folotoy.cn/…?s=…&k=…", text: $link)
                            .appField()
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
                        .buttonStyle(.app(.primary, size: .large))
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
            .overlayScrollers()
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
                    AboutInfoRow(symbol: "app.badge", label: "应用版本",
                                 value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版")
                    Divider()
                    AboutInfoRow(symbol: "cpu", label: "目标设备",
                                 value: "FoloToy AI Passport · ESP32-C3 · 8 MB Flash")
                    Divider()
                    AboutInfoRow(symbol: "wrench.and.screwdriver", label: "刷写后端",
                                 value: "内置 esptool \(esptoolVersion)，无需安装 Python")
                }
                StepCard(number: "", title: "数据来源") {
                    AboutInfoRow(symbol: "square.grid.2x2", label: "玩法社区", value: "公开目录，无需登录")
                    Divider()
                    AboutInfoRow(symbol: "sparkles", label: "官方精选", value: "FoloToy 推荐作品")
                    Divider()
                    AboutInfoRow(symbol: "checkmark.shield", label: "固件校验", value: "下载后核对文件大小与 SHA-256")
                    Divider()
                    AboutInfoRow(symbol: "arrow.counterclockwise", label: "出厂固件", value: "官方清单与四个默认分区")
                    Text("只有点击 \"安装\" 时才会下载固件（网站会统计一次下载）。本程序与 FoloToy 官方无关，数据接口可能随网站更新而变化。")
                        .font(.meta).foregroundStyle(.secondary)
                        .padding(.top, Space.xxs)
                }
                StepCard(number: "", title: "许可") {
                    AboutInfoRow(symbol: "terminal", label: "esptool", value: "GPL-2.0-or-later · Espressif")
                    Divider()
                    HStack(spacing: Space.s) {
                        Image(systemName: "gamecontroller")
                            .foregroundStyle(Brand.accent)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Link("FoloToy Passport Simulator", destination: URL(string: "https://github.com/VOID001/FoloToy-Passport-Simulator")!)
                                .font(.bodyText.weight(.semibold))
                            Text("MIT · VOID001 / ESP-EMU").font(.meta).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
            .frame(maxWidth: 1040, alignment: .leading)
            .frame(maxWidth: .infinity)
            .overlayScrollers()
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

private struct AboutInfoRow: View {
    let symbol: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: Space.s) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Brand.accent)
                .frame(width: 28, height: 28)
                .background(Brand.accentSoft, in: RoundedRectangle(cornerRadius: Radius.control))
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.bodyText.weight(.semibold))
                Text(value).font(.meta).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
        }
    }
}
