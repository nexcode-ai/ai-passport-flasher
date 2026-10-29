import AppKit
import Foundation
import SwiftUI

enum SidebarTab: String, CaseIterable, Identifiable {
    case community, simulator, flash, restore, about
    var id: String { rawValue }
    var title: String {
        switch self {
        case .community: return "玩法社区"
        case .simulator: return "玩法模拟器"
        case .flash: return "连接与安装"
        case .restore: return "恢复出厂固件"
        case .about: return "关于"
        }
    }
    var symbol: String {
        switch self {
        case .community: return "square.grid.2x2"
        case .simulator: return "gamecontroller"
        case .flash: return "bolt.horizontal.circle"
        case .restore: return "arrow.counterclockwise.circle"
        case .about: return "info.circle"
        }
    }
}

struct LogLine: Identifiable, Equatable {
    enum Kind { case info, tool, success, error }
    let id = UUID()
    var text: String
    var kind: Kind
    var isProgress = false
}

enum JobState: Equatable {
    case idle
    case running(String)
    case succeeded
    case failed(String)
    case cancelled

    var isRunning: Bool { if case .running = self { return true }; return false }
}

struct DeviceInfo: Equatable {
    var chip: String?
    var mac: String?
    var flashSize: String?
    var snFromMAC: String? { mac?.replacingOccurrences(of: ":", with: "") }
}

@MainActor
final class AppState: ObservableObject {
    @Published var tab: SidebarTab =
        ProcessInfo.processInfo.environment["APF_START_TAB"] == "simulator"
        ? .simulator
        : .community
    @Published var simulatorPlayID: Int?
    @Published var downloadingPlayID: Int?
    @Published var downloadProgress: Double = 0
    @Published var downloadError: String?

    @Published var ports: [SerialPort] = []
    @Published var selectedPortPath: String?
    @Published var showAllPorts = false
    @Published var deviceInfo: DeviceInfo?

    @Published var mode: FirmwareMode = .merged
    @Published var mergedImage: FlashImage?
    @Published var partitionImages: [FlashImage] = []
    @Published var planSource: PlanSource = .local
    @Published var settings = FlashSettings()
    @Published var expectedMAC: String?
    @Published var baud = 460800

    @Published var consent = false
    @Published var job: JobState = .idle
    @Published var progress: Double = 0
    @Published var showCompletionActions = false
    @Published var log: [LogLine] = []

    let baudOptions = [115200, 230400, 460800, 921600]
    let esptoolURL = EsptoolRunner.executableURL()
    private var runner: EsptoolRunner?
    private var pollTimer: Timer?
    private var restoreTempDir: URL?

    init() {
        refreshPorts()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshPorts() }
        }
        appendLog(esptoolURL == nil ? "未找到内置 esptool，无法刷写。" : "内置 esptool 已就绪：\(esptoolURL!.path)",
                  esptoolURL == nil ? .error : .info)
    }

    // MARK: Ports

    var selectedPort: SerialPort? { ports.first { $0.path == selectedPortPath } }

    func refreshPorts() {
        let found = SerialPortScanner.scan(onlyUSBModem: !showAllPorts)
        if found != ports { ports = found }
        if let sel = selectedPortPath, !found.contains(where: { $0.path == sel }) {
            if !job.isRunning { selectedPortPath = nil; deviceInfo = nil }
        }
        if selectedPortPath == nil, let first = found.first(where: { $0.isEspressifJTAG || $0.isUSBModem }) {
            selectedPortPath = first.path
        }
    }

    // MARK: Plan

    var images: [FlashImage] {
        mode == .merged ? (mergedImage.map { [$0] } ?? []) : partitionImages
    }

    var issues: [PlanIssue] { PlanValidator.issues(for: images) }
    var totalBytes: Int { images.reduce(0) { $0 + $1.size } }
    var planIsLocked: Bool { if case .local = planSource { return false }; return true }

    var blockers: [String] {
        var b: [String] = []
        if esptoolURL == nil { b.append("内置 esptool 缺失") }
        if selectedPort == nil { b.append("尚未选择设备串口") }
        if images.isEmpty { b.append("尚未选择固件") }
        if issues.contains(where: { $0.level == .error }) { b.append("固件设置有错误") }
        if !consent { b.append("请先勾选确认覆盖设备内容") }
        return b
    }

    func setMerged(_ url: URL) {
        clearPlan(keepMode: true)
        do {
            mergedImage = try FlashImage(fileURL: url, offsetText: "0x0")
            mode = .merged
        } catch { appendLog("无法读取文件：\(error.localizedDescription)", .error) }
    }

    func addPartitionFiles(_ urls: [URL]) {
        if planIsLocked { clearPlan(keepMode: true) }
        mode = .partitions
        for url in urls {
            guard partitionImages.count < DeviceSpec.maxPartitionFiles else {
                appendLog("最多支持 \(DeviceSpec.maxPartitionFiles) 个分区文件，多余文件已忽略。", .error)
                break
            }
            do {
                let img = try FlashImage(fileURL: url, offsetText: FlashImage.defaultOffset(forIndex: partitionImages.count))
                partitionImages.append(img)
            } catch { appendLog("无法读取文件：\(error.localizedDescription)", .error) }
        }
    }

    func removePartition(_ id: UUID) { partitionImages.removeAll { $0.id == id } }

    func clearPlan(keepMode: Bool = false) {
        if !job.isRunning {
            job = .idle
            progress = 0
            showCompletionActions = false
        }
        mergedImage = nil
        partitionImages = []
        planSource = .local
        settings = FlashSettings()
        expectedMAC = nil
        selectedPlay = nil
        consent = false
        if let dir = restoreTempDir {
            try? FileManager.default.removeItem(at: dir)
            restoreTempDir = nil
        }
        if !keepMode { mode = .merged }
    }

    func prepareAnotherInstall(destination: SidebarTab = .community) {
        guard !job.isRunning else { return }
        clearPlan()
        downloadError = nil
        tab = destination
    }

    /// Downloads (only on explicit click) and verifies a community play, then
    /// opens the connect + flash screen with it loaded. Never starts writing.
    func install(_ play: Play) {
        guard downloadingPlayID == nil, !job.isRunning else { return }
        guard play.isInstallable else {
            downloadError = "\"\(play.title.display)\" 暂未提供可安装的固件。"
            return
        }
        downloadingPlayID = play.id
        downloadProgress = 0
        downloadError = nil
        appendLog("正在获取 \"\(play.title.display)\" 固件…")
        Task {
            do {
                let file = try await CommunityAPI.downloadFirmware(for: play) { p in
                    Task { @MainActor in self.downloadProgress = p }
                }
                usePlay(play, file: file)
            } catch {
                downloadError = "下载 \"\(play.title.display)\" 失败：\(error.localizedDescription)"
                appendLog(downloadError!, .error)
            }
            downloadingPlayID = nil
        }
    }

    func usePlay(_ play: Play, file: URL) {
        clearPlan()
        do {
            mergedImage = try FlashImage(fileURL: file, offsetText: "0x0", displayName: "\(play.slug).bin")
            mode = .merged
            planSource = .featured(title: play.title.display, sha256: play.expectedSHA256 ?? "")
            selectedPlay = play
            tab = .flash
            appendLog("已载入 \"\(play.title.display)\"，大小与 SHA-256 校验通过。请连接设备并确认后开始安装。", .success)
        } catch { appendLog("无法读取下载的固件：\(error.localizedDescription)", .error) }
    }

    @Published var selectedPlay: Play?
    @Published var detailPlay: Play?

    func useFactoryRestore(_ prepared: FactoryRestore.Prepared, credentials: FactoryRestore.Credentials) {
        clearPlan()
        restoreTempDir = prepared.directory
        partitionImages = prepared.images
        mode = .partitions
        planSource = .factoryRestore(version: prepared.manifest.version, sn: credentials.sn)
        settings = FlashSettings(flashMode: "dio", flashFreq: "80m", flashSize: "8MB")
        expectedMAC = credentials.sn
        tab = .flash
        appendLog("已准备恢复出厂固件 \(prepared.manifest.version)（\(prepared.images.count) 个分区，所有文件 SHA-256 校验通过）。", .success)
    }

    // MARK: Log

    func appendLog(_ text: String, _ kind: LogLine.Kind = .info, progress: Bool = false) {
        if progress, let last = log.last, last.isProgress {
            log[log.count - 1].text = text
            return
        }
        if !progress, let last = log.last, last.isProgress, kind == .tool, isSameProgressLine(last.text, text) {
            log[log.count - 1] = LogLine(text: text, kind: kind)
            return
        }
        log.append(LogLine(text: text, kind: kind, isProgress: progress))
        if log.count > 4000 { log.removeFirst(log.count - 4000) }
    }

    private func isSameProgressLine(_ a: String, _ b: String) -> Bool {
        a.contains("%") && b.contains("%") && a.prefix(10) == b.prefix(10)
    }

    func clearLog() { log.removeAll() }

    var logText: String { log.map(\.text).joined(separator: "\n") }

    // MARK: Device info (read-only)

    func readDeviceInfo() {
        guard let port = selectedPort, !job.isRunning else { return }
        job = .running("正在读取芯片信息…")
        appendLog("读取芯片信息（只读，不写入 Flash）：\(port.path)")
        let r = EsptoolRunner()
        runner = r
        Task {
            do {
                let out = try await r.run(baseArgs(port: port.path, after: "hard-reset") + ["flash-id"]) { seg, ow in
                    Task { @MainActor in self.appendLog(seg, .tool, progress: ow) }
                }
                deviceInfo = DeviceInfo(chip: EsptoolOutputParser.chip(in: out), mac: EsptoolOutputParser.mac(in: out),
                                        flashSize: EsptoolOutputParser.flashSize(in: out))
                job = .idle
                appendLog("读取完成，设备已重启。", .success)
            } catch {
                job = .idle
                appendLog("读取失败：\(error.localizedDescription)", .error)
            }
            runner = nil
        }
    }

    // MARK: Flash

    private func baseArgs(port: String, after: String) -> [String] {
        ["--chip", "esp32c3", "--port", port, "--baud", String(baud), "--before", "default-reset", "--after", after]
    }

    func startFlash() {
        guard blockers.isEmpty, let port = selectedPort, !job.isRunning else { return }
        let images = self.images
        let sizes = images.map(\.size)
        let total = sizes.reduce(0, +)
        progress = 0
        job = .running("准备中…")
        appendLog("———— 开始写入 \(images.count) 个文件（\(ByteCountFormatter.string(fromByteCount: Int64(total), countStyle: .file))）到 \(port.path) ————")
        for img in images { appendLog("  \(img.offsetText)  \(img.name)  \(img.size) 字节") }

        let r = EsptoolRunner()
        runner = r
        let expected = expectedMAC
        let s = settings
        Task {
            do {
                if let expected {
                    job = .running("正在核对设备…")
                    let out = try await r.run(baseArgs(port: port.path, after: "no-reset") + ["flash-id"]) { seg, ow in
                        Task { @MainActor in self.appendLog(seg, .tool, progress: ow) }
                    }
                    let mac = EsptoolOutputParser.mac(in: out)?.replacingOccurrences(of: ":", with: "")
                    guard let mac else { throw FlashCheckError.noMAC }
                    guard mac == expected else { throw FlashCheckError.macMismatch(expected: expected, actual: mac) }
                    if let fs = EsptoolOutputParser.flashSize(in: out), let mb = Int(fs.replacingOccurrences(of: "MB", with: "")), mb < 8 {
                        throw FlashCheckError.flashTooSmall(fs)
                    }
                    appendLog("设备核对通过：MAC 与二维码 SN 一致（\(mac)）。", .success)
                }
                progress = 0.02
                job = .running("正在连接设备…")

                var args = baseArgs(port: port.path, after: "hard-reset") + ["write-flash",
                    "--flash-mode", s.flashMode, "--flash-freq", s.flashFreq, "--flash-size", s.flashSize]
                for img in images { args += [FlashImage.formatOffset(img.offset ?? 0), img.fileURL.path] }

                let tracker = WriteProgressTracker(sizes: sizes)
                _ = try await r.run(args) { seg, ow in
                    let events = EsptoolOutputParser.events(in: seg)
                    Task { @MainActor in
                        self.appendLog(seg, .tool, progress: ow)
                        for e in events {
                            switch e {
                            case let .phase(p): self.job = .running(p)
                            case let .progress(f):
                                let (i, overall) = tracker.update(fraction: f)
                                self.progress = max(self.progress, 0.02 + 0.96 * overall)
                                self.job = .running("正在写入 \(images[i].name)（\(i + 1)/\(images.count)）")
                            case .fileWritten:
                                tracker.fileFinished()
                            case .verified: self.job = .running("数据校验通过")
                            case .resetting: self.job = .running("正在重启设备…")
                            case let .mac(m): self.deviceInfo = DeviceInfo(chip: self.deviceInfo?.chip, mac: m, flashSize: self.deviceInfo?.flashSize)
                            case let .chip(c): self.deviceInfo = DeviceInfo(chip: c, mac: self.deviceInfo?.mac, flashSize: self.deviceInfo?.flashSize)
                            default: break
                            }
                        }
                    }
                }
                progress = 1
                job = .succeeded
                consent = false
                appendLog("写入完成，已发送硬件复位，设备正在重启。", .success)
            } catch EsptoolError.cancelled {
                job = .cancelled
                appendLog("已取消。若写入中途被打断，设备可能无法启动，重新刷写即可恢复（芯片 ROM 下载模式不会被破坏）。", .error)
            } catch {
                job = .failed(error.localizedDescription)
                appendLog("写入失败：\(error.localizedDescription)", .error)
            }
            runner = nil
        }
    }

    func cancelJob() { runner?.cancel() }
}

/// Maps esptool's per-file percentage onto a single overall fraction.
@MainActor
final class WriteProgressTracker {
    private let sizes: [Int]
    private let prefix: [Int]
    private let total: Double
    private(set) var index = 0
    private var last = 0.0

    init(sizes: [Int]) {
        self.sizes = sizes
        prefix = sizes.indices.map { sizes[..<$0].reduce(0, +) }
        total = Double(max(1, sizes.reduce(0, +)))
    }

    func update(fraction f: Double) -> (Int, Double) {
        if f + 0.05 < last, index < sizes.count - 1 { index += 1 }
        last = f
        let i = min(index, sizes.count - 1)
        return (i, (Double(prefix[i]) + f * Double(sizes[i])) / total)
    }

    func fileFinished() {
        index = min(index + 1, sizes.count - 1)
        last = 0
    }
}

enum FlashCheckError: LocalizedError {
    case noMAC
    case macMismatch(expected: String, actual: String)
    case flashTooSmall(String)

    var errorDescription: String? {
        switch self {
        case .noMAC: return "无法读取设备 MAC，已停止，未写入任何数据。"
        case let .macMismatch(e, a): return "设备不匹配：二维码 SN 为 \(e)，当前连接的设备为 \(a)。已停止，未写入任何数据。"
        case let .flashTooSmall(s): return "Flash 容量不足：检测到 \(s)，默认固件需要 8MB。已停止，未写入任何数据。"
        }
    }
}
