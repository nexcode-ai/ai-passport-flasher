import Foundation

@MainActor
final class CommunityStore: ObservableObject {
    @Published var featured: [Play] = []
    @Published var featuredError: String?
    @Published var plays: [Play] = []
    @Published var total = 0
    @Published var hasMore = false
    @Published var loading = false
    @Published var error: String?
    @Published var query = PlayQuery() {
        didSet { if query != oldValue { scheduleReload(debounce: query.search != oldValue.search) } }
    }

    private var generation = 0
    private var reloadTask: Task<Void, Never>?
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        loadFeatured()
        reload()
    }

    func loadFeatured() {
        featuredError = nil
        Task {
            do { featured = try await CommunityAPI.loadFeatured(limit: 20) }
            catch { featuredError = "官方精选加载失败：\(error.localizedDescription)" }
        }
    }

    private func scheduleReload(debounce: Bool) {
        reloadTask?.cancel()
        reloadTask = Task {
            if debounce { try? await Task.sleep(nanoseconds: 400_000_000) }
            if Task.isCancelled { return }
            reload()
        }
    }

    func reload() {
        generation += 1
        plays = []
        total = 0
        hasMore = false
        fetch(offset: 0)
    }

    func loadMore() {
        guard hasMore, !loading else { return }
        fetch(offset: plays.count)
    }

    private func fetch(offset: Int) {
        let gen = generation
        let q = query
        loading = true
        error = nil
        Task {
            do {
                let page = try await CommunityAPI.loadPlays(q, offset: offset)
                guard gen == generation else { return }
                let known = Set(plays.map(\.id))
                plays += page.plays.filter { !known.contains($0.id) }
                total = page.total
                hasMore = page.hasMore
            } catch {
                guard gen == generation else { return }
                self.error = "玩法列表加载失败：\(error.localizedDescription)"
            }
            if gen == generation { loading = false }
        }
    }
}
