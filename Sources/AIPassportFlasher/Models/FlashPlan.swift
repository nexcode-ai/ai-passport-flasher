import Foundation

enum DeviceSpec {
    static let flashBytes = 8 * 1024 * 1024
    static let sectorSize = 0x1000
    static let maxPartitionFiles = 8
    static let espressifVID = 0x303A
    static let usbSerialJtagPID = 0x1001
}

struct FlashImage: Identifiable, Equatable {
    let id = UUID()
    var name: String
    var fileURL: URL
    var size: Int
    var offsetText: String
    var firstByte: UInt8?

    init(fileURL: URL, offsetText: String, displayName: String? = nil) throws {
        let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        self.fileURL = fileURL
        self.name = displayName ?? fileURL.lastPathComponent
        self.size = (attrs[.size] as? NSNumber)?.intValue ?? 0
        self.offsetText = offsetText
        if let handle = try? FileHandle(forReadingFrom: fileURL) {
            firstByte = try? handle.read(upToCount: 1)?.first
            try? handle.close()
        }
    }

    var offset: Int? { FlashImage.parseOffset(offsetText) }

    static func parseOffset(_ text: String) -> Int? {
        let t = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard !t.isEmpty else { return nil }
        if t.hasPrefix("0x") { return Int(t.dropFirst(2), radix: 16) }
        return Int(t, radix: 10)
    }

    static func formatOffset(_ value: Int) -> String { "0x" + String(value, radix: 16) }

    /// Same defaults the web flasher assigns to the 1st/2nd/3rd selected file.
    static func defaultOffset(forIndex index: Int) -> String {
        switch index {
        case 0: return "0x0"
        case 1: return "0x8000"
        case 2: return "0x10000"
        default: return "0x0"
        }
    }
}

enum FirmwareMode: String, CaseIterable, Identifiable {
    case merged, partitions
    var id: String { rawValue }
    var title: String { self == .merged ? "合并固件（full.bin @ 0x0）" : "分区文件（最多 8 个）" }
}

enum PlanSource: Equatable {
    case local
    case featured(title: String, sha256: String)
    case factoryRestore(version: String, sn: String)

    var label: String {
        switch self {
        case .local: return "本地文件"
        case let .featured(title, _): return "社区玩法：\(title)"
        case let .factoryRestore(version, sn): return "恢复出厂固件 \(version)（设备 \(sn)）"
        }
    }
}

struct FlashSettings: Equatable {
    var flashMode = "keep"
    var flashFreq = "keep"
    var flashSize = "keep"
}

struct PlanIssue: Identifiable, Equatable {
    enum Level { case error, warning }
    let id = UUID()
    let level: Level
    let message: String
}

enum PlanValidator {
    static func issues(for images: [FlashImage]) -> [PlanIssue] {
        var out: [PlanIssue] = []
        if images.isEmpty { return out }
        if images.count > DeviceSpec.maxPartitionFiles {
            out.append(.init(level: .error, message: "最多只能写入 \(DeviceSpec.maxPartitionFiles) 个文件"))
        }
        var ranges: [(Range<Int>, String)] = []
        for img in images {
            guard let off = img.offset else {
                out.append(.init(level: .error, message: "\(img.name)：地址 “\(img.offsetText)” 无效，请使用 0x 开头的十六进制"))
                continue
            }
            if img.size == 0 {
                out.append(.init(level: .error, message: "\(img.name)：文件为空"))
            }
            if off % DeviceSpec.sectorSize != 0 {
                out.append(.init(level: .error, message: "\(img.name)：地址 \(FlashImage.formatOffset(off)) 必须按 4 KB（0x1000）对齐"))
            }
            if off + img.size > DeviceSpec.flashBytes {
                out.append(.init(level: .error, message: "\(img.name)：超出 8 MB Flash 范围"))
            }
            if off == 0, img.firstByte != 0xE9 {
                out.append(.init(level: .warning, message: "\(img.name)：写入 0x0 的文件不是有效的 ESP 镜像（首字节应为 0xE9），设备可能无法启动"))
            }
            let end = off + ((img.size + DeviceSpec.sectorSize - 1) / DeviceSpec.sectorSize) * DeviceSpec.sectorSize
            for (r, other) in ranges where r.overlaps(off..<end) {
                out.append(.init(level: .error, message: "\(img.name) 与 \(other) 的写入区域重叠"))
            }
            ranges.append((off..<max(end, off + 1), img.name))
        }
        return out
    }
}
