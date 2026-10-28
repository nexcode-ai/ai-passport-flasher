import Foundation

enum EsptoolEvent: Equatable {
    case phase(String)
    case chip(String)
    case mac(String)
    case flashSize(String)
    case progress(Double)
    case fileWritten
    case verified
    case resetting
}

/// Understands both esptool v4 and v5 console output.
enum EsptoolOutputParser {
    private static let percent = try! NSRegularExpression(pattern: "(\\d{1,3}(?:\\.\\d+)?)\\s*%")
    private static let macRe = try! NSRegularExpression(pattern: "^\\s*MAC:\\s*([0-9A-Fa-f]{2}(?::[0-9A-Fa-f]{2}){5})", options: [.anchorsMatchLines])
    private static let flashRe = try! NSRegularExpression(pattern: "Detected flash size:\\s*(\\S+)")
    private static let chipRe = try! NSRegularExpression(pattern: "^\\s*(?:Chip type:|Chip is)\\s*(.+?)\\s*$", options: [.anchorsMatchLines])

    static func events(in segment: String) -> [EsptoolEvent] {
        var out: [EsptoolEvent] = []
        let s = segment
        if let v = firstGroup(chipRe, s) { out.append(.chip(v)) }
        if let v = firstGroup(macRe, s) { out.append(.mac(v.lowercased())) }
        if let v = firstGroup(flashRe, s) { out.append(.flashSize(v)) }

        if s.contains("Writing at") || s.contains("Erasing") && s.contains("%") {
            let ns = s as NSString
            if let m = percent.matches(in: s, range: NSRange(location: 0, length: ns.length)).last,
               let v = Double(ns.substring(with: m.range(at: 1))) {
                out.append(.progress(min(100, max(0, v)) / 100))
            }
        }
        if s.hasPrefix("Wrote ") || s.contains("\nWrote ") { out.append(.fileWritten) }
        if s.contains("Hash of data verified") { out.append(.verified) }
        if s.contains("Hard resetting") { out.append(.resetting) }

        if s.contains("Connecting") { out.append(.phase("正在连接设备并进入下载模式…")) }
        else if s.contains("Uploading stub") || s.contains("Running stub") { out.append(.phase("正在加载刷写程序…")) }
        else if s.contains("Configuring flash size") || s.contains("Changing baud") { out.append(.phase("正在配置 Flash 参数…")) }
        else if s.contains("Compressed ") && s.contains(" bytes to ") { out.append(.phase("正在写入固件…")) }
        return out
    }

    static func mac(in transcript: String) -> String? { firstGroup(macRe, transcript)?.lowercased() }
    static func flashSize(in transcript: String) -> String? { firstGroup(flashRe, transcript) }
    static func chip(in transcript: String) -> String? { firstGroup(chipRe, transcript) }

    private static func firstGroup(_ re: NSRegularExpression, _ s: String) -> String? {
        let ns = s as NSString
        guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)), m.numberOfRanges > 1 else { return nil }
        return ns.substring(with: m.range(at: 1))
    }
}

enum EsptoolDiagnostics {
    static func summarize(_ output: String) -> String {
        let lines = output.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        let fatal = lines.last { $0.localizedCaseInsensitiveContains("error") } ?? lines.last ?? ""
        return [fatal, hint(for: output)].filter { !$0.isEmpty }.joined(separator: "\n")
    }

    static func hint(for output: String) -> String {
        let o = output.lowercased()
        if o.contains("busy or doesn't exist") {
            return "提示：串口不存在或被占用。请重新插拔设备、刷新串口列表，并关闭正在使用该串口的浏览器刷机页面或串口监视器。"
        }
        if o.contains("busy") || o.contains("resource busy") || o.contains("could not exclusively lock") {
            return "提示：串口被占用。请关闭正在使用该设备的浏览器刷机页面、串口监视器或其他程序后重试。"
        }
        if o.contains("no serial data received") || o.contains("failed to connect") || o.contains("wrong boot mode") {
            return "提示：未能进入下载模式。请确认设备已开机、使用的是数据线，然后拔插数据线重试。"
        }
        if o.contains("could not open") || o.contains("no such file") || o.contains("device not configured") {
            return "提示：串口已断开或不存在。请重新连接设备并刷新串口列表。"
        }
        if o.contains("this chip is") && o.contains("not") {
            return "提示：连接的芯片不是 ESP32-C3，请确认选择的是 AI Passport 的串口。"
        }
        if o.contains("doesn't fit") || o.contains("too big") {
            return "提示：固件超出 Flash 容量。"
        }
        return ""
    }
}
