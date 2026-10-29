import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct FlashView: View {
    @EnvironmentObject var app: AppState
    @State private var confirmFlash = false

    private var currentStep: Int {
        if app.selectedPort == nil { return 1 }
        if app.images.isEmpty || app.issues.contains(where: { $0.level == .error }) { return 2 }
        return 3
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeader(
                    eyebrow: app.job == .succeeded ? "安装完成" : "设备工作台",
                    title: app.job == .succeeded ? "玩法已安装" : "安装到 AI Passport",
                    subtitle: app.job == .succeeded
                        ? "设备已经自动重启，可以拔下数据线开始体验。"
                        : "跟随步骤连接设备、确认玩法并安全写入。",
                    symbol: app.job == .succeeded ? "checkmark.seal.fill" : "cable.connector"
                )
                if app.job == .succeeded {
                    InstallSuccessView()
                } else {
                    StepIndicator(current: currentStep, done: false)
                    if let play = app.selectedPlay {
                        InstallContextBar(play: play)
                    }
                    ConnectStep()
                    FirmwareStep()
                    WriteStep(confirmFlash: $confirmFlash)
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
            .frame(maxWidth: 1040, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(AppTheme.pageBackground)
        .confirmationDialog("确认写入固件？", isPresented: $confirmFlash, titleVisibility: .visible) {
            Button("开始写入（覆盖设备内容）", role: .destructive) { app.startFlash() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将向 \(app.selectedPort?.path ?? "") 写入 \(app.images.count) 个文件，覆盖设备 Flash 中对应区域的现有内容。写入过程中请勿拔线。")
        }
    }
}

struct InstallContextBar: View {
    let play: Play

    var body: some View {
        HStack(spacing: 14) {
            CoverImage(url: play.thumbnailURL)
                .frame(width: 54, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text("准备安装").font(.caption.weight(.semibold)).foregroundStyle(Brand.accent)
                Text(play.title.display).font(.headline).lineLimit(1)
            }
            Spacer()
            Label("固件已下载并通过校验", systemImage: "checkmark.shield.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(.green)
        }
        .padding(14)
        .card()
    }
}

struct InstallSuccessView: View {
    @EnvironmentObject var app: AppState
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 22) {
            ZStack {
                Circle().fill(Brand.accentSoft).frame(width: 112, height: 112)
                Circle().stroke(Brand.accent.opacity(0.18), lineWidth: 10).frame(width: 88, height: 88)
                Image(systemName: "checkmark")
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(Brand.accent)
            }
            .scaleEffect(appeared ? 1 : 0.7)
            .opacity(appeared ? 1 : 0)

            VStack(spacing: 7) {
                Text("安装成功").font(.system(size: 26, weight: .bold, design: .rounded))
                if let play = app.selectedPlay {
                    Text("“\(play.title.display)”已经写入 AI Passport")
                        .font(.body).foregroundStyle(.secondary)
                } else {
                    Text("固件已经写入 AI Passport").font(.body).foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 0) {
                SuccessHint(symbol: "power", title: "设备已重启", detail: "等待指示灯恢复")
                Divider().frame(height: 52).padding(.horizontal, 22)
                SuccessHint(symbol: "cable.connector.slash", title: "可以拔线", detail: "开始体验新玩法")
                Divider().frame(height: 52).padding(.horizontal, 22)
                SuccessHint(symbol: "arrow.counterclockwise", title: "随时可恢复", detail: "回到出厂系统")
            }
            .padding(20)
            .sunken(radius: 16)

            HStack(spacing: 12) {
                Button {
                    app.clearPlan()
                    app.tab = .community
                } label: {
                    Label("发现更多玩法", systemImage: "sparkles")
                }
                .buttonStyle(PrimaryButtonStyle(size: .large))

                Button {
                    app.clearPlan()
                    app.tab = .restore
                } label: {
                    Label("恢复出厂固件", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(SoftButtonStyle())
            }
        }
        .padding(.vertical, 44)
        .padding(.horizontal, 54)
        .frame(maxWidth: .infinity)
        .card(radius: 22, elevated: true)
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) { appeared = true }
        }
    }
}

struct SuccessHint: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: symbol).font(.title3).foregroundStyle(Brand.accent)
            Text(title).font(.callout.weight(.semibold))
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct StepIndicator: View {
    let current: Int
    let done: Bool
    private let titles = ["连接设备", "选择固件", "写入与重启"]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { i in
                let n = i + 1
                let complete = done || n < current
                VStack(spacing: 7) {
                    ZStack {
                        Circle()
                            .fill(complete ? Color.green : (n == current ? AppTheme.accent : Color.secondary.opacity(0.12)))
                        if complete {
                            Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white)
                        } else {
                            Image(systemName: ["cable.connector", "shippingbox", "bolt.fill"][i])
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(n == current ? .white : .secondary)
                        }
                    }
                    .frame(width: 34, height: 34)
                    .shadow(color: n == current ? AppTheme.accent.opacity(0.24) : .clear, radius: 7, y: 3)
                    Text(titles[i]).font(.caption.weight(n == current ? .semibold : .medium))
                        .foregroundStyle(n <= current || done ? .primary : .secondary)
                }
                .frame(width: 120)
                if i < 2 {
                    Rectangle()
                        .fill((complete ? Color.green : Color.secondary.opacity(0.18)))
                        .frame(height: 2)
                        .padding(.horizontal, 8)
                        .offset(y: -10)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .modernCard(padding: 16)
    }
}

// MARK: Step 1

struct ConnectStep: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        StepCard(number: "01", title: "连接设备",
                 subtitle: "串口每 1.5 秒自动刷新。AI Passport 在 macOS 上显示为 /dev/cu.usbmodem…（USB JTAG/serial debug unit）。") {
            if app.ports.isEmpty {
                HStack(spacing: 14) {
                    ZStack {
                        Circle().fill(AppTheme.accent.opacity(0.09))
                        Image(systemName: "cable.connector.slash")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(AppTheme.accent)
                    }
                    .frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 7) {
                            Text("正在等待设备").font(.callout.weight(.semibold))
                            ProgressView().controlSize(.mini)
                        }
                        Text("请确认设备已开机，并使用支持数据传输的 Type-C 线。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(14)
                .background(AppTheme.accent.opacity(0.045), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                VStack(spacing: 6) {
                    ForEach(app.ports) { port in
                        PortRow(port: port, selected: app.selectedPortPath == port.path) {
                            if !app.job.isRunning { app.selectedPortPath = port.path; app.deviceInfo = nil }
                        }
                    }
                }
            }
            HStack(spacing: 12) {
                Button { app.refreshPorts() } label: { Label("刷新", systemImage: "arrow.clockwise") }
                Toggle("显示全部串口", isOn: $app.showAllPorts)
                    .onChange(of: app.showAllPorts) { _, _ in app.refreshPorts() }
                Spacer()
                Button { app.readDeviceInfo() } label: { Label("读取芯片信息", systemImage: "cpu") }
                    .disabled(app.selectedPort == nil || app.job.isRunning)
                    .help("只读：读取芯片型号、MAC 与 Flash 容量，不会写入任何数据（设备会重启一次）")
            }
            if let info = app.deviceInfo {
                HStack(spacing: 18) {
                    InfoPair(label: "芯片", value: info.chip ?? "—")
                    InfoPair(label: "MAC / SN", value: info.mac ?? "—")
                    InfoPair(label: "Flash", value: info.flashSize ?? "—")
                }
            }
        }
    }
}

struct PortRow: View {
    let port: SerialPort
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(port.displayName).font(.body.monospaced())
                    if !port.detail.isEmpty { Text(port.detail).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
                if port.isEspressifJTAG { Tag(text: "ESP32-C3 USB JTAG", tint: .green) }
            }
            .padding(10)
            .contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(selected ? AppTheme.accent.opacity(0.09) : Color.secondary.opacity(0.035)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(selected ? AppTheme.accent.opacity(0.28) : Color.clear))
        }
        .buttonStyle(.plain)
    }
}

// MARK: Step 2

struct FirmwareStep: View {
    @EnvironmentObject var app: AppState
    @State private var dropTargeted = false

    var body: some View {
        StepCard(number: "02", title: "选择固件") {
            if let play = app.selectedPlay {
                SelectedPlayRow(play: play)
            } else if case let .factoryRestore(version, sn) = app.planSource {
                Banner(kind: .info, text: "恢复出厂固件 \(version)：将写入默认固件 4 个分区及本机生成的设备凭据分区（SN \(sn)）。写入前会核对设备 MAC。")
                ImageTable(editable: false)
                Button("清除") { app.clearPlan() }
            } else {
                localPicker
            }
            ForEach(app.issues) { issue in
                Label(issue.message, systemImage: issue.level == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(issue.level == .error ? .red : .orange)
                    .font(.callout)
            }
        }
    }

    private var localPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("推荐从「玩法社区」挑选并安装；已有 .bin 文件也可以在这里选择本地固件。文件只在本机读取。")
                    .foregroundStyle(.secondary)
                Spacer()
                Button { app.tab = .community } label: { Label("去玩法社区", systemImage: "square.grid.2x2") }
            }
            Picker("", selection: $app.mode) {
                ForEach(FirmwareMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 460)

            Group {
                if app.mode == .merged {
                    if app.mergedImage != nil {
                        ImageTable(editable: false)
                    }
                    HStack {
                        Button { pick(multiple: false) } label: { Label(app.mergedImage == nil ? "选择 full.bin…" : "重新选择…", systemImage: "doc") }
                        if app.mergedImage != nil { Button("清除") { app.clearPlan(keepMode: true) } }
                        Text("合并固件固定写入 0x0").font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    if !app.partitionImages.isEmpty { ImageTable(editable: true) }
                    HStack {
                        Button { pick(multiple: true) } label: { Label("添加 .bin 文件…", systemImage: "plus") }
                            .disabled(app.partitionImages.count >= DeviceSpec.maxPartitionFiles)
                        if !app.partitionImages.isEmpty { Button("全部清除") { app.clearPlan(keepMode: true) } }
                        Text("可重复添加，最多 8 个；默认地址依次为 0x0、0x8000、0x10000，可直接修改")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.accent.opacity(dropTargeted ? 0.08 : 0.025), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5]))
                .foregroundStyle(dropTargeted ? Color.accentColor : Color.secondary.opacity(0.35)))
            .onDrop(of: [.fileURL], isTargeted: $dropTargeted, perform: handleDrop)
            Text("也可以把 .bin 文件拖到上面的虚线框中。").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func pick(multiple: Bool) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = multiple
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [UTType(filenameExtension: "bin") ?? .data]
        panel.message = multiple ? "选择分区 .bin 文件（最多 8 个）" : "选择合并固件 full.bin"
        guard panel.runModal() == .OK else { return }
        if multiple { app.addPartitionFiles(panel.urls) } else if let u = panel.url { app.setMerged(u) }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let group = DispatchGroup()
        var urls: [URL] = []
        let lock = NSLock()
        for p in providers {
            group.enter()
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                if let url { lock.lock(); urls.append(url); lock.unlock() }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            let bins = urls.filter { $0.pathExtension.lowercased() == "bin" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
            guard !bins.isEmpty else { return }
            if app.mode == .merged, bins.count == 1 { app.setMerged(bins[0]) } else { app.addPartitionFiles(bins) }
        }
        return true
    }
}

struct SelectedPlayRow: View {
    @EnvironmentObject var app: AppState
    let play: Play

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            CoverImage(url: play.thumbnailURL).frame(width: 72, height: 96).clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 4) {
                HStack { Tag(text: play.categoryLabel); Tag(text: "已校验 SHA-256", tint: .green) }
                Text(play.title.display).font(.headline)
                Text("开发者 \(play.author ?? "—")").font(.caption).foregroundStyle(.secondary)
                Text("合并固件 · 写入 0x0 · \(ByteCountFormatter.string(fromByteCount: Int64(play.expectedSize ?? 0), countStyle: .file))")
                    .font(.caption).foregroundStyle(.secondary)
                if let ins = play.instructions?.display, !ins.isEmpty {
                    Text("操作说明：\(ins)").font(.caption).foregroundStyle(.secondary).lineLimit(3)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                Button { app.tab = .community } label: { Label("更换玩法", systemImage: "square.grid.2x2") }
                Button("改用本地固件") { app.clearPlan() }
            }
            .disabled(app.job.isRunning)
        }
    }
}

struct ImageTable: View {
    @EnvironmentObject var app: AppState
    let editable: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("写入地址").frame(width: 130, alignment: .leading)
                Text("文件").frame(maxWidth: .infinity, alignment: .leading)
                Text("大小").frame(width: 110, alignment: .trailing)
                if editable { Spacer().frame(width: 28) }
            }
            .font(.caption.bold()).foregroundStyle(.secondary)
            .padding(.horizontal, 8).padding(.vertical, 6)
            Divider()
            ForEach(app.images) { img in
                HStack {
                    if editable, let idx = app.partitionImages.firstIndex(where: { $0.id == img.id }) {
                        TextField("0x0", text: $app.partitionImages[idx].offsetText)
                            .font(.body.monospaced())
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                            .frame(width: 130, alignment: .leading)
                    } else {
                        Text(img.offsetText).font(.body.monospaced()).frame(width: 130, alignment: .leading)
                    }
                    Text(img.name).lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading)
                        .help(img.fileURL.path)
                    Text(ByteCountFormatter.string(fromByteCount: Int64(img.size), countStyle: .file))
                        .font(.callout.monospacedDigit()).foregroundStyle(.secondary).frame(width: 110, alignment: .trailing)
                    if editable {
                        Button { app.removePartition(img.id) } label: { Image(systemName: "minus.circle.fill") }
                            .buttonStyle(.plain).foregroundStyle(.secondary).frame(width: 28)
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 5)
            }
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.55), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.secondary.opacity(0.12)))
        .disabled(app.job.isRunning)
    }
}

// MARK: Step 3

struct WriteStep: View {
    @EnvironmentObject var app: AppState
    @Binding var confirmFlash: Bool
    @State private var showLog = false

    var body: some View {
        StepCard(number: "03", title: "写入与重启") {
            Banner(kind: .warning, text: "写入会替换设备中的现有玩法和相关数据。之后可随时通过「恢复出厂固件」回到默认状态；写入期间请保持连接。")
            HStack(spacing: 18) {
                Picker("波特率", selection: $app.baud) {
                    ForEach(app.baudOptions, id: \.self) { Text("\($0)").tag($0) }
                }
                .frame(width: 200)
                .disabled(app.job.isRunning)
                Text("Flash 参数：\(app.settings.flashMode) / \(app.settings.flashFreq) / \(app.settings.flashSize)")
                    .font(.caption.monospaced()).foregroundStyle(.secondary)
                    .help("keep 表示保留固件镜像头中的原有设置，与网页刷机工具一致")
            }
            Toggle(isOn: $app.consent) {
                Text("我已了解：写入会覆盖这台设备上的现有内容").fontWeight(.medium)
            }
            .toggleStyle(.checkbox)
            .disabled(app.job.isRunning)
            .padding(.vertical, 2)

            HStack(spacing: 12) {
                Button {
                    confirmFlash = true
                } label: {
                    Label(app.job.isRunning ? "正在写入…" : "开始写入", systemImage: "bolt.fill")
                        .font(.headline)
                        .frame(minWidth: 190)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!app.blockers.isEmpty || app.job.isRunning)
                if app.job.isRunning {
                    Button("取消", role: .cancel) { app.cancelJob() }
                }
                if !app.blockers.isEmpty && !app.job.isRunning {
                    Text(app.blockers.joined(separator: " · ")).font(.callout).foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(statusText).font(.callout.weight(.medium)).foregroundStyle(statusColor)
                    Spacer()
                    Text("\(Int(app.progress * 100))%").font(.callout.monospacedDigit())
                }
                ProgressView(value: app.progress).tint(statusColor == .red ? .red : (app.job == .succeeded ? .green : .accentColor))
            }
            .padding(14)
            .background(Color.secondary.opacity(0.055), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            if let failureText {
                Banner(kind: .error, text: "安装没有完成：\(failureText)\n请重新插拔数据线、关闭其他串口工具，然后再次尝试。")
            }
            DisclosureGroup("高级：设备日志与故障排查", isExpanded: $showLog) {
                LogView().padding(.top, 10)
            }
            .font(.callout)
        }
        .onChange(of: app.job) { _, job in
            if case .failed = job { showLog = true }
        }
    }

    private var statusText: String {
        switch app.job {
        case .idle: return app.images.isEmpty ? "等待选择固件" : "\(app.images.count) 个文件 · \(ByteCountFormatter.string(fromByteCount: Int64(app.totalBytes), countStyle: .file))"
        case let .running(s): return s
        case .succeeded: return "安装完成，设备已自动重启"
        case let .failed(msg): return "失败：\(msg.split(separator: "\n").first ?? "")"
        case .cancelled: return "已取消"
        }
    }

    private var statusColor: Color {
        switch app.job {
        case .failed, .cancelled: return .red
        case .succeeded: return .green
        default: return .primary
        }
    }

    private var failureText: String? {
        if case let .failed(message) = app.job {
            return String(message.split(separator: "\n").first ?? "")
        }
        return nil
    }
}

struct LogView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("设备日志").font(.headline)
                Spacer()
                Button("复制") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(app.logText, forType: .string)
                }
                Button("保存…") { save() }
                Button("清空") { app.clearLog() }.disabled(app.job.isRunning)
            }
            .controlSize(.small)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(app.log) { line in
                            Text(line.text)
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundStyle(color(line.kind))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .id(line.id)
                        }
                    }
                    .padding(10)
                }
                .frame(height: 220)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.62), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(Color.secondary.opacity(0.12)))
                .onChange(of: app.log.last?.text) { _, _ in
                    if let id = app.log.last?.id { proxy.scrollTo(id, anchor: .bottom) }
                }
            }
        }
    }

    private func color(_ k: LogLine.Kind) -> Color {
        switch k {
        case .info: return .primary
        case .tool: return .secondary
        case .success: return .green
        case .error: return .red
        }
    }

    private func save() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "ai-passport-flash-log.txt"
        if panel.runModal() == .OK, let url = panel.url {
            try? app.logText.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
