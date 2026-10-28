import CryptoKit
import Foundation

enum PassportSite {
    static let base = URL(string: "https://ai-passport.folotoy.cn")!

    static func absolute(_ path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        if path.hasPrefix("http://") || path.hasPrefix("https://") { return URL(string: path) }
        return URL(string: path, relativeTo: base)?.absoluteURL
    }
}

struct LocalizedText: Codable, Hashable {
    var zh: String?
    var en: String?
    var display: String {
        let z = zh?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return z.isEmpty ? (en ?? "") : z
    }
}

struct PlayFirmware: Codable, Hashable {
    var available: Bool?
    var size: Int?
    var sha256: String?
    var url: String?
    var format: String?
}

struct Play: Codable, Identifiable, Hashable {
    var id: Int
    var slug: String
    var title: LocalizedText
    var description: LocalizedText?
    var author: String?
    var category: String?
    var image: String?
    var thumbnail: String?
    var updatedAt: String?
    var publishedAt: String?
    var isOfficial: Bool?
    var mustPlay: Bool?
    var categoryKey: String?
    var instructions: LocalizedText?
    var changelog: LocalizedText?
    var images: [String]?
    var hearts: Int?
    var commentCount: Int?
    var downloads: Int?
    var firmwareSize: Int?
    var firmwareSha256: String?
    var downloadUrl: String?
    var firmware: PlayFirmware?

    var expectedSize: Int? { firmware?.size ?? firmwareSize }
    var expectedSHA256: String? { (firmware?.sha256 ?? firmwareSha256)?.lowercased() }
    var downloadURL: URL? { PassportSite.absolute(firmware?.url ?? downloadUrl) }
    var thumbnailURL: URL? { PassportSite.absolute(thumbnail ?? image) }
    var pageURL: URL { PassportSite.base.appendingPathComponent("plays/\(id)") }
    var format: String { firmware?.format ?? "esp-merged-0x0" }

    /// Only merged images written at 0x0 with a published digest are installable.
    var isInstallable: Bool {
        (firmware?.available ?? true) && format == "esp-merged-0x0" && downloadURL != nil
            && (expectedSHA256?.count == 64) && (expectedSize ?? 0) > 0
    }

    var coverURL: URL? { PassportSite.absolute(image ?? thumbnail) }
    var galleryURLs: [URL] { (images ?? []).compactMap(PassportSite.absolute) }

    var categoryLabel: String {
        PlayCatalog.label(for: categoryKey) ?? PlayCatalog.label(for: category) ?? "玩法"
    }

    var updatedDate: Date? {
        guard let s = updatedAt ?? publishedAt else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }
}

/// Category / tag / sort vocabulary used by the community library on ai-passport.folotoy.cn.
enum PlayCatalog {
    static let categories: [(key: String, title: String)] = [
        ("all", "全部"), ("games", "游戏与互动"), ("productivity", "效率与工具"), ("information", "信息与展示"),
        ("learning", "学习与创作"), ("media", "音乐与影像"), ("social", "活动与社交"), ("developer", "开发者实验"),
    ]
    static let tags: [(key: String, title: String)] = [
        ("", "不限"), ("must-play", "必玩精选"), ("multiplayer", "多人玩法"), ("family", "亲子益智"),
    ]
    static let sorts: [(key: String, title: String)] = [
        ("newest", "最新发布"), ("downloads", "下载最多"), ("hearts", "最多喜欢"), ("comments", "讨论最多"),
    ]

    private static let subcategories: [String: String] = [
        "games-strategy": "策略战术", "games-seek": "寻宝互动", "games-collect": "抽卡收集", "games-divination": "抽签问答",
        "games-pet": "宠物养成", "games-relax": "解压互动", "games-narrative": "剧情冒险", "games-board": "桌游棋牌",
        "games-rhythm": "音乐节奏", "games-sports": "竞速体育", "games-simulation": "模拟经营", "games-rpg": "角色扮演",
        "games-puzzle": "益智解谜", "games-arcade": "动作街机", "games-collection": "游戏合集",
        "productivity-scoring": "计数记分", "productivity-decision": "日常决策", "productivity-focus": "计时专注",
        "productivity-tasks": "待办提醒", "productivity-voice": "语音记录", "productivity-control": "输入遥控",
        "productivity-health": "健康与生活", "productivity-ai": "AI 工作助手", "productivity-security": "安全与检测",
        "productivity-life": "日常记录", "productivity-toolbox": "综合工具",
        "information-dashboard": "综合看板", "information-finance": "行情财经", "information-monitor": "状态监控",
        "information-sports": "赛事资讯", "information-clock": "日期黄历", "information-weather": "天气环境",
        "information-reference": "图鉴速查", "information-identity": "身份展示", "information-reading": "资讯文字",
        "information-life": "生活看板",
        "learning-language": "语言单词", "learning-reading": "阅读经典", "learning-school": "学科练习",
        "learning-skills": "技能训练", "learning-knowledge": "知识探索", "learning-creative": "绘画设计",
        "learning-ai": "AI 问答", "learning-culture": "传统文化",
        "media-radio": "网络电台", "media-video": "视频播放", "media-sleep": "声景助眠", "media-music": "音乐播放",
        "media-sound": "音效互动", "media-visual": "影像展示", "media-projection": "拍照投屏", "media-instrument": "演奏节拍",
        "social-radio": "对讲通信", "social-nearby": "附近发现", "social-ai": "AI 陪伴", "social-identity": "名片交流",
        "social-expression": "社交表达", "social-party": "聚会互动", "social-community": "社区入口",
        "developer-installer": "安装管理", "developer-runtime": "脚本运行", "developer-wireless": "通信实验",
        "developer-benchmark": "设备调试", "developer-sensing": "交互实验", "developer-demo": "能力示例",
        "developer-accessory": "配件原型",
    ]

    static func label(for key: String?) -> String? {
        guard let key, !key.isEmpty else { return nil }
        if let sub = subcategories[key] { return sub }
        return categories.first { $0.key == key }?.title
    }
}

struct PlayQuery: Equatable {
    var search = ""
    var category = "all"
    var tag = ""
    var sort = "newest"
}

struct PlayPage {
    var plays: [Play]
    var total: Int
    var hasMore: Bool
}

private struct RecommendationsResponse: Codable {
    var ok: Bool?
    var plays: [Play]
}

private struct PlayListResponse: Codable {
    struct Pagination: Codable { var total: Int; var hasMore: Bool }
    var ok: Bool?
    var plays: [Play]
    var pagination: Pagination?
    var allTotal: Int?
}

private struct APIErrorBody: Codable { var detail: String? }

enum DownloadError: LocalizedError {
    case http(Int)
    case sizeMismatch(expected: Int, actual: Int)
    case digestMismatch
    case notESPImage(String)
    case invalidManifest(String)

    var errorDescription: String? {
        switch self {
        case let .http(code): return "下载失败（HTTP \(code)）"
        case let .sizeMismatch(e, a): return "文件大小校验失败：应为 \(e) 字节，实际 \(a) 字节"
        case .digestMismatch: return "SHA-256 校验失败，文件可能已损坏，已丢弃"
        case let .notESPImage(name): return "\(name) 不是有效的 ESP 固件镜像"
        case let .invalidManifest(msg): return "固件清单异常：\(msg)"
        }
    }
}

enum CommunityAPI {
    static let recommendationsURL = PassportSite.base.appendingPathComponent("api/plays/recommendations")

    static func session() -> URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.httpAdditionalHeaders = ["Accept": "application/json", "User-Agent": "AIPassportFlasher-macOS/1.0"]
        cfg.timeoutIntervalForRequest = 30
        return URLSession(configuration: cfg)
    }

    static func loadFeatured(limit: Int = 20) async throws -> [Play] {
        var comps = URLComponents(url: recommendationsURL, resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "limit", value: String(limit))]
        let (data, resp) = try await session().data(from: comps.url!)
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 { throw DownloadError.http(http.statusCode) }
        return try JSONDecoder().decode(RecommendationsResponse.self, from: data).plays
    }

    static let listURL = PassportSite.base.appendingPathComponent("api/plays")

    /// Public, anonymous community library listing (same request the 玩法社区 page sends).
    static func loadPlays(_ query: PlayQuery, offset: Int, limit: Int = 24) async throws -> PlayPage {
        var comps = URLComponents(url: listURL, resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "tag", value: query.tag),
            URLQueryItem(name: "bootstrap", value: "false"),
            URLQueryItem(name: "q", value: query.search.trimmingCharacters(in: .whitespacesAndNewlines)),
            URLQueryItem(name: "category", value: query.category),
            URLQueryItem(name: "sort", value: query.sort),
            URLQueryItem(name: "period", value: "all"),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset)),
        ]
        let (data, resp) = try await session().data(from: comps.url!)
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
            if let body = try? JSONDecoder().decode(APIErrorBody.self, from: data), let d = body.detail {
                throw DownloadError.invalidManifest("服务器返回：\(d)")
            }
            throw DownloadError.http(http.statusCode)
        }
        let r = try JSONDecoder().decode(PlayListResponse.self, from: data)
        return PlayPage(plays: r.plays, total: r.pagination?.total ?? r.plays.count, hasMore: r.pagination?.hasMore ?? false)
    }

    static var cacheDirectory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("AIPassportFlasher/firmware", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Downloads the merged image (only on explicit user request) and verifies size + SHA-256.
    static func downloadFirmware(for play: Play, progress: @escaping (Double) -> Void) async throws -> URL {
        guard play.isInstallable, let url = play.downloadURL, let sha = play.expectedSHA256, let size = play.expectedSize else {
            throw DownloadError.invalidManifest("该玩法暂未提供可安装的合并固件")
        }
        let dest = cacheDirectory.appendingPathComponent("\(play.slug)-\(sha.prefix(12)).bin")
        if let cached = try? Data(contentsOf: dest), cached.count == size, sha256Hex(cached) == sha {
            progress(1)
            return dest
        }
        let data = try await fetch(url, expectedSize: size, progress: progress)
        guard data.count == size else { throw DownloadError.sizeMismatch(expected: size, actual: data.count) }
        guard sha256Hex(data) == sha else { throw DownloadError.digestMismatch }
        guard data.first == 0xE9 else { throw DownloadError.notESPImage(play.title.display) }
        try data.write(to: dest, options: .atomic)
        return dest
    }

    static func fetch(_ url: URL, expectedSize: Int?, progress: @escaping (Double) -> Void) async throws -> Data {
        let (bytes, resp) = try await session().bytes(from: url)
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 { throw DownloadError.http(http.statusCode) }
        let total = expectedSize ?? Int(resp.expectedContentLength)
        var data = Data()
        if total > 0 { data.reserveCapacity(total) }
        var lastReport = 0
        var chunk = [UInt8]()
        chunk.reserveCapacity(65536)
        for try await b in bytes {
            chunk.append(b)
            if chunk.count == 65536 {
                data.append(contentsOf: chunk)
                chunk.removeAll(keepingCapacity: true)
                if total > 0, data.count - lastReport > total / 100 {
                    lastReport = data.count
                    progress(min(1, Double(data.count) / Double(total)))
                }
            }
        }
        data.append(contentsOf: chunk)
        progress(1)
        return data
    }
}
