import AppKit
import Foundation
import SwiftUI

/// A firmware bundled with the simulator itself (no network needed).
struct BuiltinFirmware: Identifiable, Hashable {
    let id: String
    let urlID: Int
    let name: String
    let detail: String

    static let all: [BuiltinFirmware] = [
        .init(id: "official-demo", urlID: 3, name: "FoloToy 官方 Demo", detail: "默认演示 · 1.5 MB"),
        .init(id: "music-keychain", urlID: 1, name: "音乐钥匙扣", detail: "语音互动 · 8 MB"),
        .init(id: "answer-book", urlID: 2, name: "答案之书", detail: "随机回答 · 2.8 MB"),
        .init(id: "feishu-calendar-assistant", urlID: 4, name: "飞书日程助手", detail: "日程与待办 · 2.2 MB"),
    ]
}

enum SimulatorItem: Hashable, Identifiable {
    case builtin(BuiltinFirmware)
    case play(Play)

    var id: String {
        switch self {
        case let .builtin(firmware): return "builtin-\(firmware.id)"
        case let .play(play): return "play-\(play.id)"
        }
    }

    var title: String {
        switch self {
        case let .builtin(firmware): return firmware.name
        case let .play(play): return play.title.display
        }
    }

    var play: Play? { if case let .play(play) = self { return play }; return nil }
}

/// What the embedded simulator page reports about itself.
struct SimulatorRuntimeStatus: Equatable {
    enum Phase: Equatable { case waiting, loading, running, failed }
    var phase: Phase = .waiting
    var stage = ""
    var detail = ""
    var percent = 0
    var audioEnabled = false
    var microphoneEnabled = false
    var recording = false
    var recordingAvailable = false
}

/// View-level state shared between 发现玩法 and 玩法模拟器: the app currently loaded into
/// the simulator, the recently tried list (persisted), and the local runtime host.
@MainActor
final class SimulatorSession: ObservableObject {
    static let shared = SimulatorSession()

    @Published private(set) var current: SimulatorItem = .builtin(BuiltinFirmware.all[0])
    @Published private(set) var recents: [Play] = []
    @Published var status = SimulatorRuntimeStatus()
    @Published var lastError: String?
    @Published var toast: String?
    /// Incremented for every explicit selection so the web view reloads even when re-selecting.
    @Published private(set) var requestID = 0

    let host = SimulatorHost()
    private let recentsKey = "simulator.recentPlays.v1"
    private var toastTask: Task<Void, Never>?

    private init() {
        if let data = UserDefaults.standard.data(forKey: recentsKey),
           let plays = try? JSONDecoder().decode([Play].self, from: data) {
            recents = plays
        }
    }

    /// 先试用: loads a community or official app into the simulator and opens the page.
    func tryPlay(_ play: Play, app: AppState) {
        select(.play(play))
        app.simulatorPlayID = play.id
        app.tab = .simulator
    }

    func select(_ item: SimulatorItem) {
        current = item
        lastError = nil
        status = SimulatorRuntimeStatus(phase: .loading, stage: "正在准备", detail: item.title)
        requestID += 1
        if case let .play(play) = item { remember(play) }
    }

    func hasTried(_ play: Play) -> Bool { recents.contains { $0.id == play.id } }

    func clearRecents() {
        recents = []
        UserDefaults.standard.removeObject(forKey: recentsKey)
    }

    func showToast(_ text: String) {
        toast = text
        toastTask?.cancel()
        toastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            if !Task.isCancelled { toast = nil }
        }
    }

    /// The community card that can be installed for the current simulator item, if any.
    func installablePlay(in store: CommunityStore) -> Play? {
        switch current {
        case let .play(play): return play
        case let .builtin(firmware):
            return (store.featured + store.plays + recents).first { $0.title.display == firmware.name }
        }
    }

    /// Resolves a play ID set elsewhere (e.g. a deep link) into a card from the catalog.
    func adopt(playID: Int?, store: CommunityStore) {
        guard let playID, current.play?.id != playID else { return }
        if let play = (store.featured + store.plays + recents).first(where: { $0.id == playID }) {
            select(.play(play))
        }
    }

    private func remember(_ play: Play) {
        recents.removeAll { $0.id == play.id }
        recents.insert(play, at: 0)
        if recents.count > 8 { recents = Array(recents.prefix(8)) }
        if let data = try? JSONEncoder().encode(recents) {
            UserDefaults.standard.set(data, forKey: recentsKey)
        }
    }
}
