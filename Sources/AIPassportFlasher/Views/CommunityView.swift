import SwiftUI

struct CommunityView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var store: CommunityStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                header
                if let err = app.downloadError {
                    Banner(kind: .error, text: err) { app.downloadError = nil }
                }
                featuredSection
                librarySection
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
            .frame(maxWidth: 1320, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(AppTheme.pageBackground)
        .onAppear { store.start() }
        .sheet(item: $app.detailPlay) { play in
            PlayDetailView(play: play) { app.detailPlay = nil }
                .environmentObject(app)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 20) {
            PageHeader(
                eyebrow: "探索与发现",
                title: "玩法社区",
                subtitle: "发现社区创作的有趣玩法，一键下载并安装到你的 AI Passport。",
                symbol: "square.grid.2x2.fill"
            )
            Spacer()
            Button {
                app.clearPlan()
                app.tab = .flash
            } label: {
                Label("安装本地 .bin 固件", systemImage: "doc.badge.arrow.up")
                    .padding(.horizontal, 4)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .help("已有 .bin 文件？从电脑选择并刷入")
        }
    }

    private var featuredSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Label("官方精选", systemImage: "sparkles")
                    .font(.title2.bold())
                Text("FoloToy 官方推荐").foregroundStyle(.secondary).font(.callout)
                Spacer()
                if store.featuredError != nil {
                    Button("重新加载") { store.loadFeatured() }
                }
            }
            if let err = store.featuredError {
                Text(err).foregroundStyle(.red).font(.callout)
            } else if store.featured.isEmpty {
                HStack(spacing: 16) { ForEach(0..<5, id: \.self) { _ in FeaturedCardSkeleton() } }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 16) {
                        ForEach(store.featured) { play in
                            FeaturedCard(play: play, onDetail: { app.detailPlay = play })
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 2)
                }
            }
        }
    }

    private var librarySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Label("全部玩法", systemImage: "rectangle.grid.2x2")
                    .font(.title2.bold())
                if store.total > 0 {
                    Text("\(store.total) 个作品")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            filterBar
            if let err = store.error {
                HStack {
                    Text(err).foregroundStyle(.red)
                    Button("重试") { store.reload() }
                }
            }
            if store.loading && store.plays.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280, maximum: 380), spacing: 18)], spacing: 18) {
                    ForEach(0..<6, id: \.self) { _ in PlayCardSkeleton() }
                }
            } else if store.plays.isEmpty && store.error == nil {
                EmptyState(symbol: "sparkle.magnifyingglass", title: "没有找到相关玩法", message: "试试更换关键词或选择其他分类")
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280, maximum: 380), spacing: 18)], spacing: 18) {
                    ForEach(store.plays) { play in
                        PlayCard(play: play, onDetail: { app.detailPlay = play })
                            .onAppear { if play.id == store.plays.last?.id { store.loadMore() } }
                    }
                }
            }
            HStack {
                Spacer()
                if store.loading {
                    ProgressView().controlSize(.small)
                    Text("正在加载…").foregroundStyle(.secondary)
                } else if store.hasMore {
                    Button("加载更多") { store.loadMore() }
                } else if !store.plays.isEmpty {
                    Text("已显示全部 \(store.plays.count) 个玩法").foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 8)
        }
    }

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                    TextField("搜索玩法名称、作者或简介", text: $store.query.search)
                        .textFieldStyle(.plain)
                    if !store.query.search.isEmpty {
                        Button { store.query.search = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.secondary.opacity(0.18)))
                .frame(maxWidth: 440)

                Picker("标签", selection: $store.query.tag) {
                    ForEach(PlayCatalog.tags, id: \.key) { Text($0.title).tag($0.key) }
                }
                .frame(width: 170)

                Picker("排序", selection: $store.query.sort) {
                    ForEach(PlayCatalog.sorts, id: \.key) { Text($0.title).tag($0.key) }
                }
                .frame(width: 170)
                Spacer()
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(PlayCatalog.categories, id: \.key) { cat in
                        Chip(title: cat.title, selected: store.query.category == cat.key) {
                            store.query.category = cat.key
                        }
                    }
                }
            }
        }
        .modernCard(padding: 16)
    }
}
// MARK: - Cards

struct CoverImage: View {
    let url: URL?
    var body: some View {
        AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
            switch phase {
            case let .success(img): img.resizable().aspectRatio(contentMode: .fill)
            case .failure: placeholder(icon: "photo")
            default: placeholder(icon: nil)
            }
        }
        .clipped()
    }

    private func placeholder(icon: String?) -> some View {
        ZStack {
            LinearGradient(colors: [Color.accentColor.opacity(0.18), Color.secondary.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)
            if let icon { Image(systemName: icon).font(.title).foregroundStyle(.secondary) }
            else { ProgressView().controlSize(.small) }
        }
    }
}
struct InstallButton: View {
    @EnvironmentObject var app: AppState
    let play: Play
    var compact = false

    var body: some View {
        let downloading = app.downloadingPlayID == play.id
        Button {
            app.install(play)
        } label: {
            HStack(spacing: 6) {
                if downloading {
                    ProgressView(value: app.downloadProgress).progressViewStyle(.circular).controlSize(.small)
                    Text("下载中 \(Int(app.downloadProgress * 100))%")
                } else {
                    Image(systemName: "arrow.down.circle.fill")
                    Text(play.isInstallable ? "安装" : "暂无固件")
                }
            }
            .frame(minWidth: compact ? 0 : 92)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!play.isInstallable || app.downloadingPlayID != nil || app.job.isRunning)
        .help(play.isInstallable ? "下载并校验固件（\(sizeText)），然后进入连接与安装步骤" : "该玩法暂未提供可安装的合并固件")
    }

    private var sizeText: String {
        ByteCountFormatter.string(fromByteCount: Int64(play.expectedSize ?? 0), countStyle: .file)
    }
}

struct PlayCard: View {
    let play: Play
    let onDetail: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CoverImage(url: play.thumbnailURL)
                .frame(maxWidth: .infinity)
                .frame(height: 178)
                .clipped()
                .overlay(alignment: .topLeading) {
                    HStack(spacing: 6) {
                        Tag(text: play.categoryLabel, tint: .white, onDark: true)
                        if play.mustPlay == true { Tag(text: "必玩", tint: .white, onDark: true) }
                    }
                    .padding(12)
                }
                .overlay {
                    LinearGradient(colors: [.clear, .black.opacity(0.13)], startPoint: .center, endPoint: .bottom)
                }
                .onTapGesture(perform: onDetail)
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(play.title.display)
                        .font(.system(size: 17, weight: .semibold))
                        .lineLimit(1)
                    Spacer()
                    if let d = play.updatedDate {
                        Text(d, format: .dateTime.month().day())
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                Text("开发者 \(play.author ?? "—")").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Text(play.description?.display ?? "")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(height: 38, alignment: .top)
                HStack(spacing: 12) {
                    Stats(play: play)
                    Spacer()
                    Button(action: onDetail) {
                        Image(systemName: "arrow.up.right")
                    }
                    .buttonStyle(.borderless)
                    .help("查看详情")
                    InstallButton(play: play)
                        .controlSize(.small)
                }
            }
            .padding(15)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(Color.secondary.opacity(hovering ? 0.28 : 0.13)))
        .shadow(color: .black.opacity(hovering ? 0.15 : 0.07), radius: hovering ? 18 : 9, y: hovering ? 9 : 4)
        .scaleEffect(hovering ? 1.012 : 1)
        .animation(.easeOut(duration: 0.18), value: hovering)
        .onHover { hovering = $0 }
    }
}

struct FeaturedCard: View {
    let play: Play
    let onDetail: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            CoverImage(url: play.thumbnailURL)
                .frame(width: 214, height: 268)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay(alignment: .topLeading) { Tag(text: play.categoryLabel, tint: .white, onDark: true).padding(10) }
                .onTapGesture(perform: onDetail)
            Text(play.title.display).font(.headline.weight(.semibold)).lineLimit(1)
            Text("开发者 \(play.author ?? "—")").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Text(play.description?.display ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(2)
                .frame(height: 30, alignment: .top)
            HStack {
                Button("详情", action: onDetail).controlSize(.small)
                Spacer()
                InstallButton(play: play, compact: true).controlSize(.small)
            }
        }
        .frame(width: 214)
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(Color.secondary.opacity(hovering ? 0.27 : 0.12)))
        .shadow(color: .black.opacity(hovering ? 0.13 : 0.06), radius: hovering ? 17 : 8, y: hovering ? 8 : 4)
        .offset(y: hovering ? -3 : 0)
        .animation(.easeOut(duration: 0.18), value: hovering)
        .onHover { hovering = $0 }
    }
}

struct FeaturedCardSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.12)).frame(width: 214, height: 268)
            RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.12)).frame(width: 120, height: 12)
            RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.10)).frame(width: 80, height: 10)
        }
        .padding(10)
        .modernCard(padding: 0)
    }
}

struct PlayCardSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.11)).frame(height: 178)
            RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.13)).frame(width: 150, height: 14)
            RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.09)).frame(height: 11)
            RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.09)).frame(width: 190, height: 11)
        }
        .padding(12)
        .modernCard(padding: 0)
    }
}

struct Stats: View {
    let play: Play
    var body: some View {
        HStack(spacing: 10) {
            if let d = play.downloads { Label("\(d)", systemImage: "arrow.down.circle") }
            if let h = play.hearts { Label("\(h)", systemImage: "heart") }
            if let s = play.expectedSize {
                Text(ByteCountFormatter.string(fromByteCount: Int64(s), countStyle: .file))
            }
        }
        .font(.caption).foregroundStyle(.secondary).labelStyle(.titleAndIcon)
    }
}

// MARK: - Detail

struct PlayDetailView: View {
    @EnvironmentObject var app: AppState
    let play: Play
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                HStack(alignment: .top, spacing: 20) {
                    CoverImage(url: play.coverURL)
                        .frame(width: 240, height: 320)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 10) {
                        HStack { Tag(text: play.categoryLabel); if play.mustPlay == true { Tag(text: "必玩", tint: .orange) } }
                        Text(play.title.display).font(.title.bold())
                        Text("开发者 \(play.author ?? "—")").foregroundStyle(.secondary)
                        Stats(play: play)
                        section("玩法介绍", play.description?.display)
                        section("操作说明", play.instructions?.display)
                        section("更新记录", play.changelog?.display)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("固件信息").font(.headline)
                            Text("格式：\(play.format == "esp-merged-0x0" ? "合并固件，写入地址 0x0" : play.format)")
                            if let s = play.expectedSize { Text("大小：\(s) 字节") }
                            if let h = play.expectedSHA256 { Text("SHA-256：\(h)").textSelection(.enabled) }
                        }
                        .font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                }
                .padding(28)
                if !play.galleryURLs.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: 10) {
                            ForEach(play.galleryURLs, id: \.self) { url in
                                CoverImage(url: url).frame(width: 150, height: 200).clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                        .padding(.horizontal, 24)
                    }
                    .padding(.bottom, 16)
                }
            }
            Divider()
            HStack {
                Link("在网页中查看", destination: play.pageURL)
                Spacer()
                Text("安装会覆盖设备当前的全部内容").font(.caption).foregroundStyle(.orange)
                Button("关闭", action: close).keyboardShortcut(.cancelAction)
                InstallButton(play: play)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
            .background(.thinMaterial)
        }
        .frame(width: 760, height: 620)
        .background(AppTheme.pageBackground)
        .onChange(of: app.tab) { _, tab in if tab == .flash { close() } }
    }

    @ViewBuilder
    private func section(_ title: String, _ text: String?) -> some View {
        if let t = text?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(t).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
        }
    }
}
