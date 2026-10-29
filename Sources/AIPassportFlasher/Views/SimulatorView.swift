import AppKit
import Foundation
import SwiftUI
import WebKit

struct SimulatorView: View {
    @EnvironmentObject private var app: AppState
    @StateObject private var host = SimulatorHost()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                IconTile(symbol: "gamecontroller.fill", size: 46)
                VStack(alignment: .leading, spacing: 3) {
                    Text("玩法模拟器").font(.system(size: 24, weight: .bold, design: .rounded))
                    Text("先在 Mac 上体验玩法，再决定是否安装到设备。")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                SimulatorStatusPill(state: host.state)
                if app.simulatorPlayID != nil {
                    Button("返回内置玩法") { app.simulatorPlayID = nil }
                        .buttonStyle(SoftButtonStyle())
                }
                Button {
                    host.restart()
                } label: {
                    Label("重新启动", systemImage: "arrow.clockwise")
                }
                .buttonStyle(SoftButtonStyle())
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(.bar)

            Divider()

            Group {
                switch host.state {
                case .idle, .starting:
                    SimulatorLoadingView()
                case let .ready(baseURL):
                    if ProcessInfo.processInfo.environment["APF_SNAPSHOT_DIR"] != nil {
                        SimulatorSnapshotPreview()
                    } else {
                        SimulatorWebView(url: simulatorURL(from: baseURL)) { message in
                            host.reportWebError(message)
                        }
                    }
                case let .failed(message):
                    SimulatorFailureView(message: message) { host.restart() }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(PageBackground())
        .onAppear { host.start() }
        .onDisappear { host.stop() }
    }

    private func simulatorURL(from baseURL: URL) -> URL {
        guard let playID = app.simulatorPlayID else { return baseURL }
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "play", value: String(playID))]
        return components.url ?? baseURL
    }
}

struct SimulatorSnapshotPreview: View {
    private var deviceImage: NSImage? {
        Bundle.main.resourceURL
            .map { $0.appendingPathComponent("simulator/public/assets/ai-passport-shell-reference.png") }
            .flatMap(NSImage.init(contentsOf:))
    }

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                Color(red: 0.035, green: 0.055, blue: 0.065)
                if let deviceImage {
                    Image(nsImage: deviceImage)
                        .resizable()
                        .scaledToFit()
                        .padding(34)
                }
                VStack {
                    HStack {
                        Label("FoloToy 官方 Demo", systemImage: "play.circle.fill")
                        Spacer()
                        Text("60 FPS").monospacedDigit()
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.78))
                    .padding(18)
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("QEMU WASM", systemImage: "cpu")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Brand.accent)
                    Text("模拟器正在运行").font(.title2.bold())
                    Text("屏幕、按键、声音与虚拟网络已就绪")
                        .font(.callout).foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("内置玩法").font(.headline)
                    PreviewFirmwareRow(number: "01", title: "音乐钥匙扣")
                    PreviewFirmwareRow(number: "02", title: "答案之书")
                    PreviewFirmwareRow(number: "03", title: "FoloToy 官方 Demo", selected: true)
                    PreviewFirmwareRow(number: "04", title: "飞书日程助手")
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("键盘控制").font(.headline)
                    HStack(spacing: 8) {
                        ForEach(["↑  上", "↓  下", "↩  确认", "P  电源"], id: \.self) {
                            Text($0).font(.caption.monospaced().weight(.medium))
                                .padding(.horizontal, 9).padding(.vertical, 7)
                                .sunken(radius: 8)
                        }
                    }
                }

                Label("只在本机运行，不会写入 USB 设备", systemImage: "lock.shield.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.green)
                Spacer()
            }
            .padding(28)
            .frame(width: 430, alignment: .topLeading)
            .background(Brand.surface)
        }
    }
}

struct PreviewFirmwareRow: View {
    let number: String
    let title: String
    var selected = false

    var body: some View {
        HStack {
            Text(number).font(.caption.monospaced().bold()).foregroundStyle(Brand.accent)
            Text(title).font(.callout.weight(.medium))
            Spacer()
            if selected {
                Label("运行中", systemImage: "waveform")
                    .font(.caption.weight(.semibold)).foregroundStyle(.green)
            } else {
                Image(systemName: "play.fill").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(11)
        .background(selected ? Brand.accentSoft : Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct SimulatorStatusPill: View {
    let state: SimulatorHost.State

    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(title).font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(color.opacity(0.10), in: Capsule())
        .foregroundStyle(color)
    }

    private var title: String {
        switch state {
        case .idle: return "未启动"
        case .starting: return "正在启动"
        case .ready: return "本地运行"
        case .failed: return "需要处理"
        }
    }

    private var color: Color {
        switch state {
        case .ready: return .green
        case .failed: return Brand.danger
        default: return Brand.accent
        }
    }
}

struct SimulatorLoadingView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView().controlSize(.large)
            Text("正在启动本地模拟器").font(.headline)
            Text("首次加载 WebAssembly 与固件可能需要几秒钟。")
                .font(.callout).foregroundStyle(.secondary)
            Label("模拟器只在 Mac 内存中运行，不会访问 USB 设备", systemImage: "lock.shield")
                .font(.caption.weight(.medium))
                .foregroundStyle(Brand.accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Brand.accentSoft, in: Capsule())
        }
    }
}

struct SimulatorFailureView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 15) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 34))
                .foregroundStyle(Brand.warning)
            Text("模拟器没有启动").font(.title2.bold())
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 560)
            HStack(spacing: 10) {
                Button("重试", action: retry)
                    .buttonStyle(PrimaryButtonStyle())
                Link("安装 Node.js 20 或更高版本", destination: URL(string: "https://nodejs.org/zh-cn/download")!)
            }
            Text("模拟器运行时来自 VOID001/FoloToy-Passport-Simulator（MIT），仅监听本机 localhost。")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .padding(32)
        .card(elevated: true)
    }
}

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
    private let port = 4190

    func start() {
        guard process == nil, state != .starting else { return }
        state = .starting

        guard let runtime = Bundle.main.resourceURL?.appendingPathComponent("simulator"),
              FileManager.default.fileExists(atPath: runtime.appendingPathComponent("server.mjs").path) else {
            state = .failed("应用包中的模拟器资源不完整，请重新安装应用。")
            return
        }
        guard let nodeURL = nodeExecutable() else {
            state = .failed("这台 Mac 尚未安装 Node.js 20 或更高版本。安装后点击“重试”即可。")
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
        output.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData
        }
        task.terminationHandler = { [weak self] process in
            Task { @MainActor in
                guard let self, self.process === process else { return }
                self.process = nil
                if process.terminationStatus != 0, case .starting = self.state {
                    self.state = .failed("本地运行时启动失败（代码 \(process.terminationStatus)）。")
                }
            }
        }

        do {
            try task.run()
            process = task
            Task { await waitUntilReady() }
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            state = .failed("启动本地运行时失败：\(error.localizedDescription)")
        }
    }

    func stop() {
        process?.terminate()
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

    private func waitUntilReady() async {
        let url = URL(string: "http://localhost:\(port)/healthz")!
        for _ in 0..<60 {
            guard process != nil else { return }
            do {
                let (_, response) = try await URLSession.shared.data(from: url)
                if (response as? HTTPURLResponse)?.statusCode == 200 {
                    state = .ready(URL(string: "http://localhost:\(port)/")!)
                    return
                }
            } catch {}
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        state = .failed("本地运行时启动超时，请点击“重新启动”再试。")
    }

    private func nodeExecutable() -> URL? {
        let candidates = [
            "/usr/local/bin/node",
            "/opt/homebrew/bin/node",
            "/usr/bin/node",
        ]
        return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
            .map { URL(fileURLWithPath: $0) }
    }
}

struct SimulatorWebView: NSViewRepresentable {
    let url: URL
    let onError: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onError: onError)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.preferences.isElementFullscreenEnabled = true
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        context.coordinator.load(url, in: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.lastURL != url else { return }
        context.coordinator.load(url, in: webView)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var lastURL: URL?
        let onError: (String) -> Void

        init(onError: @escaping (String) -> Void) {
            self.onError = onError
        }

        func load(_ url: URL, in webView: WKWebView) {
            lastURL = url
            Task {
                do {
                    let (data, response) = try await URLSession.shared.data(from: url)
                    guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                        throw URLError(.badServerResponse)
                    }
                    let html = String(decoding: data, as: UTF8.self)
                    await MainActor.run {
                        guard self.lastURL == url else { return }
                        webView.loadHTMLString(html, baseURL: url)
                    }
                } catch {
                    await MainActor.run {
                        self.onError("模拟器页面加载失败：\(error.localizedDescription)")
                    }
                }
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let destination = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }
            let allowed = destination.scheme == "about"
                || destination.scheme == "https"
                || (destination.scheme == "http" && destination.host == "localhost")
            decisionHandler(allowed ? .allow : .cancel)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            onError("页面加载失败：\(error.localizedDescription)")
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            onError("页面加载失败：\(error.localizedDescription)")
        }

        @available(macOS 12.0, *)
        func webView(
            _ webView: WKWebView,
            requestMediaCapturePermissionFor origin: WKSecurityOrigin,
            initiatedByFrame frame: WKFrameInfo,
            type: WKMediaCaptureType,
            decisionHandler: @escaping (WKPermissionDecision) -> Void
        ) {
            decisionHandler(type == .microphone ? .grant : .deny)
        }
    }
}
