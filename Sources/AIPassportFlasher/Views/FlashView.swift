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
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("连接与安装").font(.largeTitle.bold())
                    Text("用支持数据传输的 Type-C 线连接 AI Passport 并开机，选择串口和固件后写入。写入完成后设备会自动重启。")
                        .foregroundStyle(.secondary)
                }
                StepIndicator(current: currentStep, done: app.job == .succeeded)
                ConnectStep()
                FirmwareStep()
                WriteStep(confirmFlash: $confirmFlash)
            }
            .padding(24)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .confirmationDialog("确认写入固件？", isPresented: $confirmFlash, titleVisibility: .visible) {
            Button("开始写入（覆盖设备内容）", role: .destructive) { app.startFlash() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将向 \(app.selectedPort?.path ?? "") 写入 \(app.images.count) 个文件，覆盖设备 Flash 中对应区域的现有内容。写入过程中请勿拔线。")
        }
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
                HStack(spacing: 8) {
                    ZStack {
                        Circle().fill(complete ? Color.green : (n == current ? Color.accentColor : Color.secondary.opacity(0.2)))
                        if complete { Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white) }
                        else { Text(String(format: "%02d", n)).font(.caption.bold()).foregroundStyle(n == current ? .white : .secondary) }
                    }
                    .frame(width: 28, height: 28)
                    Text(titles[i]).fontWeight(n == current ? .semibold : .regular)
                        .foregroundStyle(n <= current || done ? .primary : .secondary)
                }
                if i < 2 {
                    Rectangle().fill(Color.secondary.opacity(0.25)).frame(height: 1).padding(.horizontal, 12)
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
    }
}

struct StepCard<Content: View>: View {
    let number: String
    let title: String
    var subtitle: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                if !number.isEmpty {
                    Text(number).font(.title3.monospacedDigit().bold()).foregroundStyle(Color.accentColor)
                }
                Text(title).font(.title3.bold())
            }
            if let subtitle { Text(subtitle).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.secondary.opacity(0.18)))
    }
}

// MARK: Step 1

struct ConnectStep: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        StepCard(number: "01", title: "连接设备",
                 subtitle: "串口每 1.5 秒自动刷新。AI Passport 在 macOS 上显示为 /dev/cu.usbmodem…（USB JTAG/serial debug unit）。") {
            if app.ports.isEmpty {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("等待设备…未检测到 usbmodem 串口。请确认设备已开机，并使用可传输数据的线缆。")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
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
            .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Color.accentColor.opacity(0.1) : Color.clear))
        }
        .buttonStyle(.plain)
    }
}

struct InfoPair: View {
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.callout.monospaced()).textSelection(.enabled)
        }
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
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5]))
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
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
        .disabled(app.job.isRunning)
    }
}

// MARK: Step 3

struct WriteStep: View {
    @EnvironmentObject var app: AppState
    @Binding var confirmFlash: Bool

    var body: some View {
        StepCard(number: "03", title: "写入与重启") {
            Banner(kind: .warning, text: "刷写会覆盖设备 Flash 中对应区域的现有内容（包括当前玩法和已保存的数据）。安装社区玩法后，若要再次使用小程序的通行证功能，需要先「恢复出厂固件」。写入过程中请勿拔线或退出本程序。")
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

            HStack(spacing: 12) {
                Button {
                    confirmFlash = true
                } label: {
                    Label(app.job.isRunning ? "正在写入…" : "开始写入", systemImage: "bolt.fill").frame(minWidth: 120)
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
            LogView()
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
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
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
