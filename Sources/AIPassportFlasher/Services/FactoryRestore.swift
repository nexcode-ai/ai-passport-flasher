import Foundation

/// Mirrors the official "恢复默认固件" flow for AI Passport: public default
/// image set + a per-device `cardid` NVS partition built from the SN / KEY in
/// the device's private QR link.
enum FactoryRestore {
    static let firmwareBase = PassportSite.base.appendingPathComponent("assets/firmwares/ai-passport-default")
    static let productLookupBase = URL(string: "https://webapp.folotoy.cn/v1/toys/sn")!
    static let cardidOffset = 0x356000

    static let expectedFiles: [String: Int] = [
        "bootloader.bin": 0x0,
        "partition-table.bin": 0x8000,
        "trae_card.bin": 0x10000,
        "imgava.bin": 0x3FA000,
    ]
    static let flashOrder = ["bootloader.bin", "partition-table.bin", "trae_card.bin", "imgava.bin"]

    struct Credentials: Equatable {
        var sn: String
        var key: String
    }

    struct Manifest: Codable {
        struct File: Codable {
            var name: String
            var address: Int
            var size: Int
            var sha256: String
        }
        var version: String
        var firmwareCommit: String
        var productKey: String
        var hardwareVersion: String
        var files: [File]
    }

    struct Prepared {
        var manifest: Manifest
        var directory: URL
        var images: [FlashImage]
    }

    enum RestoreError: LocalizedError {
        case badLink
        case badSN
        case badKey
        case partition(String)

        var errorDescription: String? {
            switch self {
            case .badLink: return "无法从链接中读取 SN 和 KEY。请粘贴设备专属页面的完整链接（包含 ?s=…&k=…）。"
            case .badSN: return "SN 格式无效：应为 12 位十六进制字符（即设备 MAC 地址）。"
            case .badKey: return "KEY 无效：长度应为 1–64 字节。"
            case let .partition(msg): return "默认固件分区表与 AI Passport 不匹配：\(msg)"
            }
        }
    }

    /// Accepts the full private device link, a bare query string, or `SN KEY`.
    static func parseCredentials(link: String) throws -> Credentials {
        let text = link.trimmingCharacters(in: .whitespacesAndNewlines)
        var query = text
        if let comps = URLComponents(string: text), let q = comps.percentEncodedQuery { query = q }
        else if let i = text.firstIndex(of: "?") { query = String(text[text.index(after: i)...]) }
        if let i = query.firstIndex(of: "#") { query = String(query[..<i]) }
        var comps = URLComponents()
        comps.percentEncodedQuery = query
        let items = comps.queryItems ?? []
        let sn = items.first { $0.name == "s" }?.value
        let key = items.first { $0.name == "k" }?.value
        guard let sn, let key else { throw RestoreError.badLink }
        return try validate(sn: sn, key: key)
    }

    static func validate(sn: String, key: String) throws -> Credentials {
        let s = String(sn.trimmingCharacters(in: .whitespaces).prefix(80)).lowercased()
        let k = String(key.trimmingCharacters(in: .whitespaces).prefix(256))
        guard s.range(of: "^[0-9a-f]{12}$", options: .regularExpression) != nil else { throw RestoreError.badSN }
        guard !k.isEmpty, k.utf8.count <= 64, !k.contains("\0") else { throw RestoreError.badKey }
        return Credentials(sn: s, key: k)
    }

    enum ProductCheck: Equatable {
        case aiPassport
        case other(String)
        case unknown(String)
    }

    /// Same lookup the official device page uses to choose the restore flavour.
    static func lookupProduct(sn: String) async -> ProductCheck {
        let url = productLookupBase.appendingPathComponent(sn).appendingPathComponent("product")
        do {
            let (data, resp) = try await CommunityAPI.session().data(from: url)
            guard let http = resp as? HTTPURLResponse else { return .unknown("无响应") }
            guard http.statusCode == 200 else { return .unknown("HTTP \(http.statusCode)") }
            let obj = try JSONSerialization.jsonObject(with: data)
            return classify(obj)
        } catch {
            return .unknown(error.localizedDescription)
        }
    }

    static func classify(_ json: Any) -> ProductCheck {
        func norm(_ v: Any?) -> String? {
            guard let s = v as? String else { return nil }
            let t = s.trimmingCharacters(in: .whitespaces).lowercased()
                .replacingOccurrences(of: "_", with: "-").replacingOccurrences(of: " ", with: "-")
            if t.isEmpty { return nil }
            if t == "jd-passport" || t == "watcha-passport" { return t }
            if t == "trae" || t == "traecard" || t.hasPrefix("trae-") || t.contains("trae-card") { return "trae" }
            return "ai-passport"
        }
        guard let root = json as? [String: Any] else { return .unknown("响应格式未知") }
        let data = root["data"] as? [String: Any]
        let product = (data?["device"] ?? data?["product"] ?? root["device"] ?? root["product"]) as? [String: Any] ?? data ?? root
        let keys = ["product_key", "productKey", "product_type", "productType", "type", "product_code", "productCode"]
        if keys.contains(where: { norm(product[$0]) == "watcha-passport" }) { return .other("watcha-passport") }
        var kind: String?
        if let k = norm(product["product_key"] ?? product["productKey"]) { kind = k }
        else if let t = (product["is_trae"] ?? product["isTrae"]) as? Bool { kind = t ? "trae" : "ai-passport" }
        else { kind = keys.lazy.compactMap { norm(product[$0]) }.first }
        guard let kind else { return .unknown("未返回产品型号") }
        return kind == "ai-passport" ? .aiPassport : .other(kind)
    }

    static func prepare(credentials: Credentials, progress: @escaping (String, Double) -> Void) async throws -> Prepared {
        progress("正在下载默认固件清单…", 0)
        let manifestURL = firmwareBase.appendingPathComponent("manifest.json")
        let manifestData = try await CommunityAPI.fetch(manifestURL, expectedSize: nil) { _ in }
        let manifest = try JSONDecoder().decode(Manifest.self, from: manifestData)
        guard !manifest.version.isEmpty, !manifest.firmwareCommit.isEmpty, !manifest.productKey.isEmpty, !manifest.hardwareVersion.isEmpty else {
            throw DownloadError.invalidManifest("缺少版本或产品信息")
        }
        guard manifest.files.count == expectedFiles.count, Set(manifest.files.map(\.name)) == Set(expectedFiles.keys) else {
            throw DownloadError.invalidManifest("文件列表与预期不一致")
        }

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("apf-restore-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])

        var blobs: [String: Data] = [:]
        let totalBytes = Double(manifest.files.reduce(0) { $0 + $1.size })
        var doneBytes = 0.0
        for file in manifest.files {
            guard expectedFiles[file.name] == file.address else { throw DownloadError.invalidManifest("\(file.name) 的写入地址异常") }
            guard file.sha256.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else {
                throw DownloadError.invalidManifest("\(file.name) 的 SHA-256 格式无效")
            }
            var comps = URLComponents(url: firmwareBase.appendingPathComponent(file.name), resolvingAgainstBaseURL: false)!
            comps.queryItems = [URLQueryItem(name: "v", value: manifest.version), URLQueryItem(name: "sha", value: String(file.sha256.prefix(12)))]
            let base = doneBytes
            let data = try await CommunityAPI.fetch(comps.url!, expectedSize: file.size) { p in
                progress("正在下载 \(file.name)…", (base + p * Double(file.size)) / totalBytes)
            }
            guard data.count == file.size else { throw DownloadError.sizeMismatch(expected: file.size, actual: data.count) }
            guard CommunityAPI.sha256Hex(data) == file.sha256 else { throw DownloadError.digestMismatch }
            blobs[file.name] = data
            doneBytes += Double(file.size)
        }

        progress("正在校验分区表…", 1)
        try checkImages(blobs)

        let cardid = try CardidNVS.build(sn: credentials.sn, deviceSecret: credentials.key,
                                         productKey: manifest.productKey, hardwareVersion: manifest.hardwareVersion)

        var images: [FlashImage] = []
        for name in flashOrder {
            let url = dir.appendingPathComponent(name)
            try blobs[name]!.write(to: url)
            images.append(try FlashImage(fileURL: url, offsetText: FlashImage.formatOffset(expectedFiles[name]!)))
        }
        let cardURL = dir.appendingPathComponent("cardid.bin")
        try cardid.write(to: cardURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: cardURL.path)
        images.append(try FlashImage(fileURL: cardURL, offsetText: FlashImage.formatOffset(cardidOffset), displayName: "cardid.bin（设备凭据，本机生成）"))
        return Prepared(manifest: manifest, directory: dir, images: images)
    }

    static func checkImages(_ blobs: [String: Data]) throws {
        guard let boot = blobs["bootloader.bin"], let table = blobs["partition-table.bin"],
              let app = blobs["trae_card.bin"], let ava = blobs["imgava.bin"] else {
            throw DownloadError.invalidManifest("缺少文件")
        }
        guard boot.first == 0xE9, app.first == 0xE9 else { throw DownloadError.notESPImage("bootloader.bin / trae_card.bin") }
        guard table.count == 3072 else { throw RestoreError.partition("分区表大小应为 3072 字节") }
        let parts = PartitionTable.parse(table)
        func expect(_ name: String, _ offset: Int, _ size: Int) throws {
            guard let p = parts[name], p.offset == offset, p.size == size else {
                throw RestoreError.partition("\(name) 分区位置不符")
            }
        }
        try expect("factory", 0x10000, 0x300000)
        try expect("cardid", cardidOffset, 0x4000)
        try expect("imgava", 0x3FA000, 0x100000)
        try expect("imguser", 0x35A000, 0x20000)
        if parts["recovery"] != nil { throw RestoreError.partition("包含不兼容的 recovery 分区") }
        guard ava.count == 0x100000, ava.prefix(4) == Data("AVA1".utf8) else { throw RestoreError.partition("默认头像资源无效") }
    }
}

enum PartitionTable {
    struct Entry: Equatable {
        var type: UInt8
        var subtype: UInt8
        var offset: Int
        var size: Int
        var name: String
    }

    static func parse(_ data: Data) -> [String: Entry] {
        let b = [UInt8](data)
        var out: [String: Entry] = [:]
        var i = 0
        func u32(_ o: Int) -> Int { Int(b[o]) | Int(b[o + 1]) << 8 | Int(b[o + 2]) << 16 | Int(b[o + 3]) << 24 }
        while i + 32 <= b.count, b[i] == 0xAA, b[i + 1] == 0x50 {
            let raw = b[(i + 12)..<(i + 28)]
            let nameBytes = raw.prefix { $0 != 0 }
            let name = String(decoding: nameBytes, as: UTF8.self)
            out[name] = Entry(type: b[i + 2], subtype: b[i + 3], offset: u32(i + 4), size: u32(i + 8), name: name)
            i += 32
        }
        return out
    }
}
