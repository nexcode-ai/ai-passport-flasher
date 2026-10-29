import AppKit
import Darwin
import Foundation
import SwiftUI
import WebKit

struct SimulatorView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var store: CommunityStore
    @ObservedObject private var session = SimulatorSession.shared
    @ObservedObject private var host = SimulatorSession.shared.host
    @StateObject private var controller = SimulatorWebController()
    @AppStorage("simulator.libraryVisible") private var libraryVisible = true
    @AppStorage("simulator.noticeDismissed") private var noticeDismissed = false

    var body: some View {
        HStack(spacing: 0) {
            if libraryVisible {
                SimulatorLibraryPanel()
                    .frame(width: 272)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                Divider()
            }
            VStack(spacing: 0) {
                SimulatorNowPlayingBar(libraryVisible: $libraryVisible)
                Divider()
                stage
                Divider()
                SimulatorControlBar(controller: controller)
            }
        }
        .animation(.easeOut(duration: 0.2), value: libraryVisible)
        .background(PageBackground())
        .onAppear {
            store.start()
            host.start()
            session.adopt(playID: app.simulatorPlayID, store: store)
        }
        .onChange(of: app.simulatorPlayID) { _, id in session.adopt(playID: id, store: store) }
    }

    @ViewBuilder private var stage: some View {
        ZStack(alignment: .top) {
            switch host.state {
            case .idle, .starting:
                SimulatorLoadingView()
            case let .ready(baseURL):
                if ProcessInfo.processInfo.environment["APF_SNAPSHOT_DIR"] != nil {
                    SimulatorSnapshotPreview()
                } else {
                    SimulatorWebView(baseURL: baseURL, controller: controller) { message in
                        host.reportWebError(message)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                            .strokeBorder(Brand.hairline)
                    )
                    .padding(Space.s)
                }
            case let .failed(message):
                SimulatorFailureView(message: message) { host.restart() }
            }

            VStack(spacing: Space.xs) {
                if let error = session.lastError {
                    SimulatorErrorBanner(message: error) {
                        session.select(session.current)
                    } dismiss: {
                        session.lastError = nil
                    }
                }
                if !noticeDismissed, case .ready = host.state {
                    SimulatorNotice { noticeDismissed = true }
                }
            }
            .padding(Space.m)
            .frame(maxWidth: 640)

            if let toast = session.toast {
                VStack {
                    Spacer()
                    Label(toast, systemImage: "checkmark.circle.fill")
                        .font(.callout.weight(.medium))
                        .padding(.horizontal, Space.m)
                        .frame(height: 34)
                        .background(.regularMaterial, in: Capsule())
                        .overlay(Capsule().strokeBorder(Brand.hairline))
                        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
                        .padding(.bottom, Space.l)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Brand.surfaceSunken)
        .animation(.easeOut(duration: 0.2), value: session.toast)
    }
}

// MARK: - Library

struct SimulatorLibraryPanel: View {
    @EnvironmentObject private var store: CommunityStore
    @EnvironmentObject private var app: AppState
    @ObservedObject private var session = SimulatorSession.shared
    @State private var search = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Space.s) {
                Text("玩法库").font(.cardTitle)
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                    TextField("搜索玩法", text: $search).textFieldStyle(.plain).font(.callout)
                    if !search.isEmpty {
                        Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(RoundedRectangle(cornerRadius: Radius.field, style: .continuous).fill(Brand.surfaceSunken))
                .overlay(RoundedRectangle(cornerRadius: Radius.field, style: .continuous).strokeBorder(Brand.hairline))
            }
            .padding(Space.m)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2, pinnedViews: []) {
                    if !filteredRecents.isEmpty {
                        groupHeader("最近试用") {
                            Button { session.clearRecents() } label: {
                                Label("清除", systemImage: "xmark")
                            }
                                .buttonStyle(.app(.tertiary, size: .small))
                        }
                        ForEach(filteredRecents) { play in row(.play(play)) }
                    }
                    if !filteredFeatured.isEmpty {
                        groupHeader("官方精选")
                        ForEach(filteredFeatured) { play in row(.play(play)) }
                    } else if store.featured.isEmpty, store.featuredError == nil, search.isEmpty {
                        groupHeader("官方精选")
                        ForEach(0..<3, id: \.self) { _ in LibraryRowSkeleton() }
                    }
                    if !filteredBuiltins.isEmpty {
                        groupHeader("内置示例 · 无需联网")
                        ForEach(filteredBuiltins) { firmware in row(.builtin(firmware)) }
                    }
                    if !filteredCommunity.isEmpty {
                        groupHeader("社区玩法")
                        ForEach(filteredCommunity) { play in
                            row(.play(play))
                                .onAppear { if play.id == store.plays.last?.id, search.isEmpty { store.loadMore() } }
                        }
                    }
                    if store.error != nil || store.featuredError != nil {
                        Label("社区暂时无法连接，可先体验内置示例。", systemImage: "wifi.exclamationmark")
                            .font(.caption).foregroundStyle(.secondary)
                            .padding(Space.s)
                    }
                }
                .padding(.horizontal, Space.xs)
                .padding(.bottom, Space.m)
                .overlayScrollers()
            }
        }
        .background(.thinMaterial)
    }

    private var query: String { search.trimmingCharacters(in: .whitespaces).lowercased() }
    private func matches(_ text: String) -> Bool { query.isEmpty || text.lowercased().contains(query) }
    private func matches(_ play: Play) -> Bool { matches(play.title.display) || matches(play.author ?? "") }

    private var filteredRecents: [Play] { session.recents.filter(matches) }
    private var filteredFeatured: [Play] {
        let recent = Set(session.recents.map(\.id))
        return store.featured.filter { matches($0) && (!query.isEmpty || !recent.contains($0.id)) }
    }
    private var filteredBuiltins: [BuiltinFirmware] { BuiltinFirmware.all.filter { matches($0.name) } }
    private var filteredCommunity: [Play] {
        let shown = Set(store.featured.map(\.id) + session.recents.map(\.id))
        return store.plays.filter { matches($0) && !shown.contains($0.id) }
    }

    private func groupHeader<Trailing: View>(_ title: String, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) -> some View {
        HStack {
            Text(title).font(.eyebrow).foregroundStyle(.secondary)
            Spacer()
            trailing()
        }
        .padding(.horizontal, Space.xs)
        .padding(.top, Space.s)
        .padding(.bottom, Space.xxs)
    }

    private func row(_ item: SimulatorItem) -> some View {
        LibraryRow(item: item, selected: session.current.id == item.id, phase: session.status.phase) {
            session.select(item)
            if let play = item.play { app.simulatorPlayID = play.id }
        }
    }
}

struct LibraryRow: View {
    let item: SimulatorItem
    let selected: Bool
    let phase: SimulatorRuntimeStatus.Phase
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                thumbnail
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Brand.hairline))
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).font(.system(size: 13, weight: selected ? .semibold : .medium)).lineLimit(1)
                    Text(subtitle).font(.meta).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                if selected {
                    if phase == .loading {
                        ProgressView().controlSize(.small)
                    } else if phase == .running {
                        Image(systemName: "waveform").font(.system(size: 12, weight: .semibold)).foregroundStyle(Brand.accent)
                            .symbolEffect(.variableColor.iterative, options: .repeating)
                    }
                } else if hovering {
                    Image(systemName: "play.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(Brand.accent)
                }
            }
            .padding(.horizontal, Space.xs)
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(selected ? Brand.accentSoft : Color.primary.opacity(hovering ? 0.05 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(selected ? "正在模拟器中运行" : "在模拟器中试用")
    }

    @ViewBuilder private var thumbnail: some View {
        switch item {
        case let .play(play): CoverImage(url: play.thumbnailURL)
        case .builtin:
            ZStack {
                Brand.gradient
                Image(systemName: "cpu").font(.system(size: 15, weight: .semibold)).foregroundStyle(Color(rgb: 0x05261A))
            }
        }
    }

    private var subtitle: String {
        switch item {
        case let .play(play): return [play.author, play.categoryLabel].compactMap { $0 }.joined(separator: " · ")
        case let .builtin(firmware): return firmware.detail
        }
    }
}

struct LibraryRowSkeleton: View {
    var body: some View {
        HStack(spacing: 10) {
            SkeletonBlock().frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 5) {
                SkeletonBlock(radius: 4).frame(width: 120, height: 11)
                SkeletonBlock(radius: 4).frame(width: 80, height: 9)
            }
        }
        .padding(.horizontal, Space.xs)
        .frame(height: 50)
        .pulsing()
    }
}

// MARK: - Now playing

struct SimulatorNowPlayingBar: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var store: CommunityStore
    @ObservedObject private var session = SimulatorSession.shared
    @Binding var libraryVisible: Bool

    var body: some View {
        HStack(spacing: Space.s) {
            IconButton(symbol: "sidebar.left", help: libraryVisible ? "隐藏玩法库" : "显示玩法库", active: libraryVisible) {
                libraryVisible.toggle()
            }
            artwork
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.field, style: .continuous).strokeBorder(Brand.hairline))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("正在试用").font(.eyebrow).foregroundStyle(Brand.accent)
                    if let play = session.current.play { Tag(text: play.categoryLabel) }
                    if case .builtin = session.current { Tag(text: "内置示例", tint: .secondary) }
                }
                Text(session.current.title).font(.cardTitle).lineLimit(1)
                statusLine
            }
            Spacer(minLength: Space.s)
            JourneyStrip(step: .tryOut)
                .padding(.trailing, Space.xs)
            if let play = session.current.play {
                Button {
                    app.detailPlay = play
                } label: {
                    Label("详情", systemImage: "info.circle")
                }
                .buttonStyle(.app(.secondary))
            }
            installButton
        }
        .padding(.horizontal, Space.m)
        .frame(height: 76)
        .background(.bar)
    }

    @ViewBuilder private var installButton: some View {
        let play = session.installablePlay(in: store)
        Button {
            if let play { app.detailPlay = play }
        } label: {
            Label("安装到我的设备", systemImage: "arrow.down.circle.fill")
        }
        .buttonStyle(.app(.primary))
        .disabled(play?.isInstallable != true || app.job.isRunning)
        .help(play == nil ? "内置示例没有对应的社区作品，可在左侧选择社区玩法后安装" : "打开安装引导，连接设备后写入这个玩法")
    }

    @ViewBuilder private var artwork: some View {
        switch session.current {
        case let .play(play): CoverImage(url: play.thumbnailURL)
        case .builtin:
            ZStack {
                Brand.gradient
                Image(systemName: "cpu").font(.system(size: 20, weight: .semibold)).foregroundStyle(Color(rgb: 0x05261A))
            }
        }
    }

    @ViewBuilder private var statusLine: some View {
        let status = session.status
        HStack(spacing: 6) {
            switch status.phase {
            case .running:
                Circle().fill(Color.green).frame(width: 6, height: 6)
                Text(subtitle(prefix: "运行中")).foregroundStyle(.secondary)
            case .loading:
                ProgressView(value: Double(status.percent), total: 100).frame(width: 64).controlSize(.mini)
                Text("\(status.stage.isEmpty ? "正在装载" : status.stage) \(status.percent)%").foregroundStyle(.secondary)
            case .failed:
                Circle().fill(Brand.danger).frame(width: 6, height: 6)
                Text("装载失败").foregroundStyle(Brand.danger)
            case .waiting:
                Circle().fill(Color.secondary).frame(width: 6, height: 6)
                Text("等待启动").foregroundStyle(.secondary)
            }
        }
        .font(.meta)
        .lineLimit(1)
    }

    private func subtitle(prefix: String) -> String {
        switch session.current {
        case let .play(play): return [prefix, play.author.map { "开发者 \($0)" }].compactMap { $0 }.joined(separator: " · ")
        case let .builtin(firmware): return "\(prefix) · \(firmware.detail)"
        }
    }
}

// MARK: - Controls

struct SimulatorControlBar: View {
    @ObservedObject var controller: SimulatorWebController
    @ObservedObject private var session = SimulatorSession.shared

    var body: some View {
        HStack(spacing: Space.xs) {
            HStack(spacing: 6) {
                KeyHint(keys: "↑ ↓", title: "切换")
                KeyHint(keys: "↩", title: "确认")
                KeyHint(keys: "P", title: "电源")
            }
            Spacer()
            let running = session.status.phase == .running
            IconButton(symbol: session.status.audioEnabled ? "speaker.wave.2.fill" : "speaker.slash",
                       help: session.status.audioEnabled ? "扬声器已开启" : "开启扬声器",
                       active: session.status.audioEnabled) { controller.click("audio-enable") }
            IconButton(symbol: session.status.microphoneEnabled ? "mic.fill" : "mic.slash",
                       help: session.status.microphoneEnabled ? "关闭麦克风" : "允许麦克风输入",
                       active: session.status.microphoneEnabled) { controller.click("microphone-toggle") }
            Divider().frame(height: 18).padding(.horizontal, 4)
            IconButton(symbol: "camera", help: "截取屏幕并复制到剪贴板") { controller.copyScreenshot() }
                .disabled(!running)
            IconButton(symbol: session.status.recording ? "stop.circle.fill" : "record.circle",
                       help: session.status.recording ? "停止录屏并保存到“下载”" : "录制屏幕",
                       active: session.status.recording) { controller.click("recording-toggle") }
                .disabled(!session.status.recordingAvailable && !session.status.recording)
            IconButton(symbol: "arrow.up.left.and.arrow.down.right", help: "全屏显示设备") { controller.click("fullscreen-toggle") }
                .disabled(!running)
            Divider().frame(height: 18).padding(.horizontal, 4)
            Button {
                controller.click("restart-runtime")
            } label: {
                Label("重启设备", systemImage: "power")
            }
            .buttonStyle(.app(.secondary, size: .small))
        }
        .padding(.horizontal, Space.m)
        .frame(height: 48)
        .background(.bar)
    }
}

struct KeyHint: View {
    let keys: String
    let title: String
    var body: some View {
        HStack(spacing: 5) {
            Text(keys)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .padding(.horizontal, 6)
                .frame(minWidth: 22, minHeight: 20)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.primary.opacity(0.07)))
                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Brand.hairline))
            Text(title).font(.meta).foregroundStyle(.secondary)
        }
    }
}

struct SimulatorNotice: View {
    let dismiss: () -> Void
    var body: some View {
        HStack(alignment: .top, spacing: Space.s) {
            Image(systemName: "info.circle.fill").foregroundStyle(Brand.accent).font(.system(size: 15, weight: .semibold))
            VStack(alignment: .leading, spacing: 3) {
                Text("模拟器用于快速体验，不是完整的硬件模拟").font(.callout.weight(.semibold))
                Text("屏幕、声音与按键可用；Wi-Fi 为虚拟网络；BLE、NFC 与电池不支持。安装前请以真机表现为准。")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button(action: dismiss) {
                Label("知道了", systemImage: "checkmark")
            }
            .buttonStyle(.app(.secondary, size: .small))
        }
        .padding(Space.s)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.inset, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.inset, style: .continuous).strokeBorder(Brand.hairline))
        .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
    }
}

struct SimulatorErrorBanner: View {
    let message: String
    let retry: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: Space.s) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Brand.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text("这个玩法没能在模拟器中运行").font(.callout.weight(.semibold))
                Text(message).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 0)
            Button(action: retry) { Label("重试", systemImage: "arrow.clockwise") }
                .buttonStyle(.app(.secondary, size: .small))
            IconButton(symbol: "xmark", help: "关闭", size: .small, action: dismiss)
        }
        .padding(Space.s)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.inset, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.inset, style: .continuous).strokeBorder(Brand.warning.opacity(0.3)))
        .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
    }
}

struct SimulatorLoadingView: View {
    var body: some View {
        VStack(spacing: Space.s) {
            ProgressView().controlSize(.large)
            Text("正在启动本地模拟器").font(.cardTitle)
            Text("首次加载 WebAssembly 与固件需要几秒钟，全程只在这台 Mac 上运行。")
                .font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SimulatorFailureView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: Space.s) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 30))
                .foregroundStyle(Brand.warning)
            Text("模拟器没有启动").font(.sectionTitle)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
            Button(action: retry) { Label("重新启动模拟器", systemImage: "arrow.clockwise") }
                .buttonStyle(.app(.primary))
                .padding(.top, Space.xxs)
        }
        .padding(Space.xxl)
        .card(elevated: true)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Static stand-in for the off-screen screenshot mode, where WebKit content cannot be captured.
struct SimulatorSnapshotPreview: View {
    private var deviceImage: NSImage? {
        Bundle.main.resourceURL
            .map { $0.appendingPathComponent("simulator/public/assets/ai-passport-shell-reference.png") }
            .flatMap(NSImage.init(contentsOf:))
    }

    var body: some View {
        ZStack {
            if let deviceImage {
                Image(nsImage: deviceImage)
                    .resizable()
                    .scaledToFit()
                    .padding(Space.xl)
                    .shadow(color: .black.opacity(0.25), radius: 20, y: 14)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Runtime host

@MainActor
final class SimulatorHost: ObservableObject {
    enum State: Equatable {
        case idle
        case starting
        case ready(URL)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    private var process: Process?
    private var retiring: Process?
    private var launchTask: Task<Void, Never>?
    private var terminationObserver: NSObjectProtocol?

    init() {
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.process?.terminate() }
        }
    }

    func start() {
        switch state {
        case .starting, .ready: return
        case .idle, .failed: break
        }
        state = .starting
        launchTask = Task { await launch() }
    }

    func stop() {
        launchTask?.cancel()
        if let process {
            process.terminate()
            retiring = process
        }
        process = nil
        state = .idle
    }

    func restart() {
        stop()
        start()
    }

    func reportWebError(_ message: String) {
        state = .failed(message)
    }

    private func launch() async {
        if let retiring {
            for _ in 0..<40 where retiring.isRunning {
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            if retiring.isRunning { kill(retiring.processIdentifier, SIGKILL) }
            self.retiring = nil
        }
        guard !Task.isCancelled else { return }

        guard let runtime = Bundle.main.resourceURL?.appendingPathComponent("simulator"),
              FileManager.default.fileExists(atPath: runtime.appendingPathComponent("server.mjs").path) else {
            state = .failed("应用包中的模拟器资源不完整，请重新安装应用。")
            return
        }
        guard let nodeURL = Self.nodeExecutable() else {
            state = .failed("应用包中的模拟器运行时不完整，请重新安装应用。")
            return
        }
        guard let port = Self.freeLoopbackPort() else {
            state = .failed("没有可用的本机端口，请关闭其他占用网络端口的程序后重试。")
            return
        }

        let task = Process()
        task.executableURL = nodeURL
        task.arguments = [runtime.appendingPathComponent("server.mjs").path, "--allow-local-firmware-upload"]
        task.currentDirectoryURL = runtime
        var environment = ProcessInfo.processInfo.environment
        environment["HOST"] = "127.0.0.1"
        environment["PORT"] = String(port)
        environment["EMULATOR_ALLOW_LOCAL_FIRMWARE_UPLOAD"] = "1"
        environment["EMULATOR_TRAFFIC_ANALYTICS"] = "0"
        task.environment = environment

        let output = Pipe()
        task.standardOutput = output
        task.standardError = output
        output.fileHandleForReading.readabilityHandler = { handle in _ = handle.availableData }
        task.terminationHandler = { [weak self] finished in
            output.fileHandleForReading.readabilityHandler = nil
            Task { @MainActor in
                guard let self, self.process === finished else { return }
                self.process = nil
                self.state = .failed("本地运行时意外退出（代码 \(finished.terminationStatus)），请重新启动模拟器。")
            }
        }

        do {
            try task.run()
            process = task
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            state = .failed("启动本地运行时失败：\(error.localizedDescription)")
            return
        }

        let health = URL(string: "http://127.0.0.1:\(port)/healthz")!
        for _ in 0..<80 {
            guard !Task.isCancelled, let process, process === task, task.isRunning else { return }
            if let (_, response) = try? await URLSession.shared.data(from: health),
               (response as? HTTPURLResponse)?.statusCode == 200 {
                state = .ready(URL(string: "http://127.0.0.1:\(port)/")!)
                return
            }
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
        state = .failed("本地运行时启动超时，请重新启动模拟器。")
    }

    private static func nodeExecutable() -> URL? {
        guard let bundled = Bundle.main.resourceURL?.appendingPathComponent("node/node"),
              FileManager.default.isExecutableFile(atPath: bundled.path) else { return nil }
        return bundled
    }

    /// Asks the kernel for an unused loopback port so a second copy of the simulator
    /// (or anything else on a fixed port) can never answer our health check.
    private static func freeLoopbackPort() -> Int? {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else { return nil }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
        }
        guard named == 0 else { return nil }
        return Int(UInt16(bigEndian: address.sin_port))
    }
}

// MARK: - Web view bridge

@MainActor
final class SimulatorWebController: ObservableObject {
    weak var webView: WKWebView?
    var pageReady = false
    var loadedRequestID = -1

    func click(_ elementID: String) {
        webView?.evaluateJavaScript("window.__apf && window.__apf.click('\(elementID)')")
    }

    func load(_ item: SimulatorItem) {
        switch item {
        case let .play(play):
            webView?.evaluateJavaScript("window.__apf && window.__apf.loadCommunity(\(play.id))")
        case let .builtin(firmware):
            webView?.evaluateJavaScript("window.__apf && window.__apf.loadPreset('\(firmware.id)')")
        }
    }

    func copyScreenshot() {
        guard let webView else { return }
        webView.evaluateJavaScript("window.__apf && window.__apf.screenRect()") { result, _ in
            guard let values = result as? [Double], values.count == 4 else { return }
            let configuration = WKSnapshotConfiguration()
            configuration.rect = CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
            webView.takeSnapshot(with: configuration) { image, _ in
                guard let image else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([image])
                SimulatorSession.shared.showToast("屏幕截图已复制到剪贴板")
            }
        }
    }

    static func entryURL(base: URL, item: SimulatorItem) -> URL {
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        components.scheme = SimulatorSchemeHandler.scheme
        components.host = "runtime"
        components.port = nil
        switch item {
        case let .play(play): components.queryItems = [URLQueryItem(name: "play", value: String(play.id))]
        case let .builtin(firmware): components.queryItems = [URLQueryItem(name: "id", value: String(firmware.urlID))]
        }
        return components.url!
    }
}

struct SimulatorWebView: NSViewRepresentable {
    let baseURL: URL
    @ObservedObject var controller: SimulatorWebController
    @ObservedObject private var session = SimulatorSession.shared
    let onError: (String) -> Void

    init(baseURL: URL, controller: SimulatorWebController, onError: @escaping (String) -> Void) {
        self.baseURL = baseURL
        self.controller = controller
        self.onError = onError
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(port: baseURL.port ?? 0, controller: controller, onError: onError)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.preferences.isElementFullscreenEnabled = true
        configuration.setURLSchemeHandler(context.coordinator.schemeHandler, forURLScheme: SimulatorSchemeHandler.scheme)
        let content = configuration.userContentController
        content.add(context.coordinator, name: "apf")
        content.addUserScript(WKUserScript(source: SimulatorBridgeScript.source, injectionTime: .atDocumentStart, forMainFrameOnly: true))

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsMagnification = false
        controller.webView = webView
        controller.pageReady = false
        controller.loadedRequestID = session.requestID
        webView.load(URLRequest(url: SimulatorWebController.entryURL(base: baseURL, item: session.current)))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard controller.loadedRequestID != session.requestID else { return }
        controller.loadedRequestID = session.requestID
        if controller.pageReady {
            controller.load(session.current)
        } else {
            webView.load(URLRequest(url: SimulatorWebController.entryURL(base: baseURL, item: session.current)))
        }
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "apf")
        webView.stopLoading()
        webView.loadHTMLString("", baseURL: nil)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler, WKDownloadDelegate {
        let schemeHandler: SimulatorSchemeHandler
        let controller: SimulatorWebController
        let onError: (String) -> Void
        private var wasRecording = false
        private var downloadDestination: URL?

        init(port: Int, controller: SimulatorWebController, onError: @escaping (String) -> Void) {
            schemeHandler = SimulatorSchemeHandler(port: port)
            self.controller = controller
            self.onError = onError
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
            MainActor.assumeIsolated {
                let session = SimulatorSession.shared
                switch type {
                case "ready":
                    controller.pageReady = true
                    if ProcessInfo.processInfo.environment["APF_SIMULATOR_DIAGNOSTICS_DIR"] != nil {
                        SimulatorDiagnostics.capture(controller: controller)
                    }
                case "state":
                    var status = SimulatorRuntimeStatus()
                    let state = body["state"] as? String ?? "waiting"
                    let failed = body["failed"] as? Bool ?? false
                    status.phase = failed ? .failed : (state == "running" ? .running : (state == "loading" ? .loading : .waiting))
                    if status.phase == .waiting, session.status.phase == .loading { status.phase = .loading }
                    status.stage = body["stage"] as? String ?? ""
                    status.detail = body["detail"] as? String ?? ""
                    status.percent = (body["percent"] as? NSNumber)?.intValue ?? 0
                    status.audioEnabled = body["audio"] as? Bool ?? false
                    status.microphoneEnabled = body["mic"] as? Bool ?? false
                    status.recording = body["recording"] as? Bool ?? false
                    status.recordingAvailable = body["recordingAvailable"] as? Bool ?? false
                    if failed, session.lastError == nil {
                        session.lastError = (body["loadingDetail"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "固件装载失败"
                    }
                    if status.phase == .running { session.lastError = nil }
                    if wasRecording, !status.recording {
                        controller.webView?.evaluateJavaScript("window.__apf && window.__apf.downloadRecording()")
                    }
                    wasRecording = status.recording
                    if session.status != status { session.status = status }
                case "error":
                    let text = (body["message"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    session.lastError = text.isEmpty ? "固件导入失败，请检查网络后重试。" : text
                    session.status.phase = .failed
                default:
                    break
                }
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.shouldPerformDownload {
                decisionHandler(.download)
                return
            }
            guard let destination = navigationAction.request.url else { return decisionHandler(.cancel) }
            if destination.scheme == "https", navigationAction.targetFrame == nil || navigationAction.navigationType == .linkActivated {
                NSWorkspace.shared.open(destination)
                return decisionHandler(.cancel)
            }
            let allowed = ["about", "blob", SimulatorSchemeHandler.scheme].contains(destination.scheme ?? "")
            decisionHandler(allowed ? .allow : .cancel)
        }

        func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
            download.delegate = self
        }

        func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
            download.delegate = self
        }

        func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                      suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
            let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            let name = suggestedFilename.isEmpty ? "AI-Passport-录屏.webm" : suggestedFilename
            var target = folder.appendingPathComponent(name)
            var index = 2
            while FileManager.default.fileExists(atPath: target.path) {
                let base = (name as NSString).deletingPathExtension
                let ext = (name as NSString).pathExtension
                target = folder.appendingPathComponent("\(base) \(index)").appendingPathExtension(ext)
                index += 1
            }
            downloadDestination = target
            completionHandler(target)
        }

        func downloadDidFinish(_ download: WKDownload) {
            let name = downloadDestination?.lastPathComponent ?? "录屏"
            Task { @MainActor in SimulatorSession.shared.showToast("录屏已保存到“下载”：\(name)") }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            if (error as NSError).code == NSURLErrorCancelled { return }
            onError("模拟器页面加载失败：\(error.localizedDescription)")
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url, url.scheme == "https" { NSWorkspace.shared.open(url) }
            return nil
        }

        func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                     initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                     decisionHandler: @escaping (WKPermissionDecision) -> Void) {
            decisionHandler(type == .microphone ? .grant : .deny)
        }
    }
}

/// Serves the simulator page from a private same-origin scheme by proxying the local
/// runtime, and adds the app's theme stylesheet (inline styles are blocked by the page CSP).
final class SimulatorSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "apf-simulator"
    static let themePath = "/apf-theme.css"

    private let port: Int
    private let lock = NSLock()
    private var tasks: [ObjectIdentifier: URLSessionDataTask] = [:]

    init(port: Int) { self.port = port }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let sourceURL = urlSchemeTask.request.url,
              var components = URLComponents(url: sourceURL, resolvingAgainstBaseURL: false) else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }

        if components.path == Self.themePath {
            let data = Data(SimulatorTheme.css.utf8)
            let response = HTTPURLResponse(url: sourceURL, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [
                "Content-Type": "text/css; charset=utf-8",
                "Cross-Origin-Resource-Policy": "same-origin",
                "Cache-Control": "no-store",
            ])!
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
            return
        }

        components.scheme = "http"
        components.host = "127.0.0.1"
        components.port = port
        guard let targetURL = components.url else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }

        var request = URLRequest(url: targetURL)
        request.httpMethod = urlSchemeTask.request.httpMethod
        request.httpBody = urlSchemeTask.request.httpBody ?? Self.drain(urlSchemeTask.request.httpBodyStream)
        request.allHTTPHeaderFields = urlSchemeTask.request.allHTTPHeaderFields
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 120

        let identifier = ObjectIdentifier(urlSchemeTask as AnyObject)
        let port = self.port
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self, self.removeTask(identifier) else { return }
            if let error {
                urlSchemeTask.didFailWithError(error)
                return
            }
            guard let backend = response as? HTTPURLResponse else {
                urlSchemeTask.didFailWithError(URLError(.badServerResponse))
                return
            }
            var headers: [String: String] = [:]
            for (key, value) in backend.allHeaderFields {
                let name = String(describing: key)
                if ["content-length", "content-encoding", "transfer-encoding"].contains(name.lowercased()) { continue }
                headers[name] = String(describing: value)
            }
            var body = data ?? Data()
            let contentType = backend.value(forHTTPHeaderField: "Content-Type") ?? ""
            if contentType.hasPrefix("text/html"), var html = String(data: body, encoding: .utf8) {
                html = html.replacingOccurrences(
                    of: "</head>",
                    with: "  <link rel=\"stylesheet\" href=\"\(Self.themePath)\">\n  </head>"
                )
                body = Data(html.utf8)
            } else if targetURL.path.hasSuffix("/qemu-worker.js"), let script = String(data: body, encoding: .utf8) {
                body = Data(script.replacingOccurrences(of: "__APF_BRIDGE_PORT__", with: String(port)).utf8)
            }
            guard let proxied = HTTPURLResponse(url: sourceURL, statusCode: backend.statusCode,
                                                httpVersion: "HTTP/1.1", headerFields: headers) else {
                urlSchemeTask.didFailWithError(URLError(.badServerResponse))
                return
            }
            urlSchemeTask.didReceive(proxied)
            urlSchemeTask.didReceive(body)
            urlSchemeTask.didFinish()
        }
        lock.lock()
        tasks[identifier] = task
        lock.unlock()
        task.resume()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        let identifier = ObjectIdentifier(urlSchemeTask as AnyObject)
        lock.lock()
        let task = tasks.removeValue(forKey: identifier)
        lock.unlock()
        task?.cancel()
    }

    private func removeTask(_ identifier: ObjectIdentifier) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return tasks.removeValue(forKey: identifier) != nil
    }

    private static func drain(_ stream: InputStream?) -> Data? {
        guard let stream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

enum SimulatorBridgeScript {
    static let source = """
    (() => {
      const post = (message) => { try { window.webkit.messageHandlers.apf.postMessage(message); } catch (_) {} };
      HTMLDialogElement.prototype.showModal = function () {
        if (this.id === 'firmware-guidance') {
          const error = document.getElementById('firmware-upload-error');
          post({ type: 'error', message: error ? error.textContent : '' });
        }
      };
      const byId = (id) => document.getElementById(id);
      const text = (id) => ((byId(id) || {}).textContent || '').trim();
      const snapshot = () => {
        const recording = byId('recording-toggle');
        post({
          type: 'state',
          state: (byId('runtime-light') || { dataset: {} }).dataset.state || 'waiting',
          detail: text('runtime-state'),
          stage: text('loading-stage'),
          loadingDetail: text('loading-detail'),
          percent: parseInt(text('loading-percent'), 10) || 0,
          failed: !!(byId('screen-overlay') && byId('screen-overlay').classList.contains('is-error')),
          audio: !!byId('audio-enable') && byId('audio-enable').getAttribute('aria-pressed') === 'true',
          mic: !!byId('microphone-toggle') && byId('microphone-toggle').getAttribute('aria-pressed') === 'true',
          recording: !!recording && recording.getAttribute('aria-pressed') === 'true',
          recordingAvailable: !!recording && !recording.disabled,
        });
      };
      let timer = null;
      const schedule = () => { if (timer) return; timer = setTimeout(() => { timer = null; snapshot(); }, 90); };
      window.__apf = {
        click(id) { const element = byId(id); if (element) element.click(); },
        loadPreset(id) {
          const button = document.querySelector('.firmware-preset[data-firmware-id="' + id + '"]');
          if (button) button.click();
        },
        loadCommunity(id) {
          const input = byId('community-play-url');
          if (!input) return;
          input.value = 'https://ai-passport.folotoy.cn/plays/' + id + '/';
          input.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true }));
        },
        downloadRecording() {
          const link = byId('recording-download');
          if (link && !link.hidden && link.href) link.click();
        },
        screenRect() {
          const rect = byId('qemu-display').getBoundingClientRect();
          return [rect.x, rect.y, rect.width, rect.height];
        },
        probe() {
          const root = document.querySelector('.emulator');
          return {
            styles: document.styleSheets.length,
            theme: [...document.styleSheets].some((sheet) => (sheet.href || '').endsWith('/apf-theme.css')),
            root: !!root,
            toolbarHidden: getComputedStyle(document.querySelector('.toolbar')).display === 'none',
            libraryHidden: getComputedStyle(document.querySelector('.try-panel')).display === 'none',
            state: (byId('runtime-light') || { dataset: {} }).dataset.state,
          };
        },
      };
      document.addEventListener('DOMContentLoaded', () => {
        const shell = document.querySelector('.passport-shell');
        if (shell && !shell.querySelector('.apf-shell-content')) {
          const content = document.createElement('div');
          content.className = 'apf-shell-content';
          while (shell.firstChild) content.appendChild(shell.firstChild);
          shell.appendChild(content);
        }
        const watched = ['runtime-light', 'runtime-state', 'loading-stage', 'loading-percent', 'loading-detail',
          'screen-overlay', 'audio-enable', 'microphone-toggle', 'recording-toggle', 'recording-download'];
        const observer = new MutationObserver(schedule);
        for (const id of watched) {
          const element = byId(id);
          if (element) observer.observe(element, { attributes: true, childList: true, characterData: true, subtree: true });
        }
        snapshot();
        post({ type: 'ready' });
      });
    })();
    """
}

enum SimulatorTheme {
    static let css = """
    :root {
      color-scheme: light dark;
      --apf-accent: #0E9F57;
      --apf-stage: #F4F5F4;
      --apf-line: rgba(0, 0, 0, .10);
      --mint: #20E47C;
    }
    @media (prefers-color-scheme: dark) {
      :root {
        --apf-accent: #20E47C;
        --apf-stage: #1C1E20;
        --apf-line: rgba(255, 255, 255, .11);
      }
    }
    html, body {
      background: transparent !important;
      overflow: hidden !important;
      font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "PingFang SC", sans-serif !important;
    }
    .toolbar, .try-panel, .site-footer, .debug-panel, .simulator-actions, .capture-feedbacks, dialog {
      display: none !important;
    }
    .emulator { display: block !important; min-height: 0 !important; height: 100vh; margin: 0 !important; }
    .workspace { display: block !important; height: 100vh; }
    .stage { height: 100vh; padding: 18px !important; background: var(--apf-stage) !important; }
    .stage:fullscreen { background: #0B0D0F !important; }
    .passport-shell {
      width: min(calc(100vw - 36px), calc((100vh - 36px) * 566 / 882)) !important;
      aspect-ratio: 566 / 882 !important;
      overflow: hidden !important;
      border: 1px solid var(--apf-line) !important;
      border-radius: 20px !important;
      background: var(--apf-stage) !important;
      box-shadow: 0 14px 28px rgba(0, 0, 0, .16) !important;
      filter: none !important;
    }
    .apf-shell-content {
      position: absolute;
      left: -40.46%;
      top: -4.31%;
      width: 180.92%;
      height: 109.64%;
    }
    @media (prefers-color-scheme: dark) {
      .passport-shell { box-shadow: 0 18px 34px rgba(0, 0, 0, .42) !important; }
    }
    .screen-overlay strong, .loading-progress-meta, .loading-progress small, .hardware-key span {
      font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "PingFang SC", sans-serif !important;
      letter-spacing: 0 !important;
    }
    .loading-progress-track span { background: #20E47C !important; box-shadow: none !important; }
    .hardware-key:hover { border-color: #20E47C !important; }
    .hardware-key:focus-visible { outline: 2px solid #20E47C; outline-offset: 2px; }
    """
}

/// Developer-only verification (`APF_SIMULATOR_DIAGNOSTICS_DIR`): records the DOM probe once the page is ready.
@MainActor
enum SimulatorDiagnostics {
    static func capture(controller: SimulatorWebController) {
        guard let directory = ProcessInfo.processInfo.environment["APF_SIMULATOR_DIAGNOSTICS_DIR"] else { return }
        let output = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard let webView = controller.webView,
                  let probe = try? await webView.evaluateJavaScript("window.__apf.probe()") as? [String: Any] else { return }
            var report = probe
            report["url"] = webView.url?.absoluteString ?? ""
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: output.appendingPathComponent("simulator-dom.json"))
            }
        }
    }
}
