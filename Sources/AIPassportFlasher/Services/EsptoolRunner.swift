import Darwin
import Foundation

enum EsptoolError: LocalizedError {
    case binaryMissing
    case launchFailed(String)
    case failed(code: Int32, summary: String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .binaryMissing: return "找不到内置的 esptool，可执行文件可能已损坏，请重新构建应用。"
        case let .launchFailed(msg): return "无法启动 esptool：\(msg)"
        case let .failed(code, summary): return summary.isEmpty ? "esptool 退出码 \(code)" : summary
        case .cancelled: return "已取消"
        }
    }
}

/// Runs the bundled esptool executable with stdout/stderr on a pipe. With a
/// non-TTY stdout esptool (esp-pylib) prints one full line per progress
/// update, which is what the parser consumes.
final class EsptoolRunner: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    static func executableURL() -> URL? {
        let fm = FileManager.default
        var candidates: [URL] = []
        if let res = Bundle.main.resourceURL {
            candidates.append(res.appendingPathComponent("esptool/esptool"))
        }
        if let env = ProcessInfo.processInfo.environment["APF_ESPTOOL"] {
            candidates.append(URL(fileURLWithPath: env))
        }
        let exeDir = Bundle.main.executableURL?.deletingLastPathComponent()
        if let dir = exeDir {
            // `swift run` / `swift build` layout: <repo>/.build/<config>/AIPassportFlasher
            var probe = dir
            for _ in 0..<4 {
                candidates.append(probe.appendingPathComponent("Vendor/esptool/esptool"))
                probe.deleteLastPathComponent()
            }
        }
        candidates.append(URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent("Vendor/esptool/esptool"))
        return candidates.first { fm.isExecutableFile(atPath: $0.path) }
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let p = process
        lock.unlock()
        guard let p, p.isRunning else { return }
        p.terminate()
        let pid = p.processIdentifier
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
            if p.isRunning { kill(pid, SIGKILL) }
        }
    }

    /// - Parameter onSegment: called (on a background queue) for every output
    ///   segment. `isOverwrite` is true when the segment was terminated by a
    ///   bare carriage return, i.e. a progress-bar refresh.
    func run(_ arguments: [String], onSegment: @escaping (_ text: String, _ isOverwrite: Bool) -> Void) async throws -> String {
        guard let exe = EsptoolRunner.executableURL() else { throw EsptoolError.binaryMissing }

        var fds: [Int32] = [0, 0]
        guard pipe(&fds) == 0 else { throw EsptoolError.launchFailed("无法创建输出管道") }
        let readFD = fds[0]
        let writeFD = fds[1]

        let p = Process()
        p.executableURL = exe
        p.arguments = arguments
        var env = ProcessInfo.processInfo.environment
        env["PYTHONUNBUFFERED"] = "1"
        env["PYTHONIOENCODING"] = "utf-8"
        env["NO_COLOR"] = "1"
        env["TERM"] = "dumb"
        env["COLUMNS"] = "200"
        p.environment = env
        let writeHandle = FileHandle(fileDescriptor: writeFD, closeOnDealloc: false)
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = writeHandle
        p.standardError = writeHandle

        let alreadyCancelled = lock.withLock { () -> Bool in
            if cancelled { return true }
            process = p
            return false
        }
        if alreadyCancelled { close(writeFD); close(readFD); throw EsptoolError.cancelled }

        let reader = SegmentReader(onSegment: onSegment)
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            let ioQueue = DispatchQueue(label: "esptool.output")
            let flags = fcntl(readFD, F_GETFL)
            _ = fcntl(readFD, F_SETFL, flags | O_NONBLOCK)
            func drain() -> Bool {
                var buf = [UInt8](repeating: 0, count: 16384)
                while true {
                    let n = read(readFD, &buf, buf.count)
                    if n > 0 { reader.feed(Data(buf[0..<n])); continue }
                    return n == 0
                }
            }
            let source = DispatchSource.makeReadSource(fileDescriptor: readFD, queue: ioQueue)
            source.setEventHandler { if drain() { source.cancel() } }
            source.resume()
            p.terminationHandler = { proc in
                ioQueue.async {
                    _ = drain()
                    source.cancel()
                    self.finish(proc, readFD: readFD, reader: reader, cont: cont)
                }
            }
            do {
                try p.run()
            } catch {
                source.cancel()
                close(writeFD); close(readFD)
                cont.resume(throwing: EsptoolError.launchFailed(error.localizedDescription))
                return
            }
            close(writeFD)
        }
    }

    private func finish(_ p: Process, readFD: Int32, reader: SegmentReader, cont: CheckedContinuation<String, Error>) {
        reader.flush()
        close(readFD)
        let wasCancelled = lock.withLock { () -> Bool in
            process = nil
            return cancelled
        }
        let output = reader.transcript
        if wasCancelled {
            cont.resume(throwing: EsptoolError.cancelled)
        } else if p.terminationStatus != 0 {
            cont.resume(throwing: EsptoolError.failed(code: p.terminationStatus, summary: EsptoolDiagnostics.summarize(output)))
        } else {
            cont.resume(returning: output)
        }
    }
}

/// Splits PTY output into `\n`-terminated lines and `\r`-terminated progress refreshes.
private final class SegmentReader: @unchecked Sendable {
    private var buffer = Data()
    private(set) var transcript = ""
    private let onSegment: (String, Bool) -> Void
    private let lock = NSLock()

    init(onSegment: @escaping (String, Bool) -> Void) { self.onSegment = onSegment }

    func feed(_ data: Data) {
        lock.lock(); defer { lock.unlock() }
        buffer.append(data)
        while let idx = buffer.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) {
            let terminator = buffer[idx]
            let chunk = buffer[buffer.startIndex..<idx]
            var next = buffer.index(after: idx)
            var overwrite = terminator == 0x0D
            if terminator == 0x0D, next < buffer.endIndex, buffer[next] == 0x0A {
                overwrite = false
                next = buffer.index(after: next)
            } else if terminator == 0x0D, next == buffer.endIndex {
                // Wait for the following byte to decide between CRLF and a bare CR.
                break
            }
            emit(Data(chunk), overwrite: overwrite)
            buffer = Data(buffer[next...])
        }
    }

    func flush() {
        lock.lock(); defer { lock.unlock() }
        var rest = buffer
        if rest.last == 0x0D { rest.removeLast() }
        if !rest.isEmpty { emit(rest, overwrite: false) }
        buffer.removeAll()
    }

    private func emit(_ data: Data, overwrite: Bool) {
        let text = ANSI.strip(String(decoding: data, as: UTF8.self))
        if text.trimmingCharacters(in: .whitespaces).isEmpty { return }
        if !overwrite { transcript += text + "\n" }
        onSegment(text, overwrite)
    }
}

enum ANSI {
    private static let pattern = try! NSRegularExpression(pattern: "\u{1B}\\[[0-9;?]*[ -/]*[@-~]|\u{1B}\\][^\u{07}\u{1B}]*(\u{07}|\u{1B}\\\\)|\u{1B}[()][A-Za-z0-9]")

    static func strip(_ s: String) -> String {
        let range = NSRange(s.startIndex..., in: s)
        return pattern.stringByReplacingMatches(in: s, range: range, withTemplate: "")
    }
}
