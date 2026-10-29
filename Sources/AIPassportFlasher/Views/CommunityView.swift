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
                eyebrow: "从这里开始",
                title: "发现新玩法",
                subtitle: "浏览官方精选与社区创作，先了解玩法，再跟随引导安装到你的 AI Passport。",
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
                HStack(spacing: 14) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.title2)
                        .foregroundStyle(Brand.warning)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("官方精选暂时没有加载出来").font(.headline)
                        Text(err).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer()
                    Button("重新加载") { store.loadFeatured() }
                        .buttonStyle(SoftButtonStyle())
                }
                .padding(18)
                .card()
            } else if store.featured.isEmpty {
                HeroFeaturedSkeleton()
            } else {
                if let hero = store.featured.first {
                    HeroFeaturedCard(play: hero, onDetail: { app.detailPlay = hero })
                }
                if store.featured.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: 16) {
                            ForEach(Array(store.featured.dropFirst().prefix(8))) { play in
                                FeaturedCard(play: play, onDetail: { app.detailPlay = play })
                            }
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 2)
                    }
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
                VStack(spacing: 12) {
                    Image(systemName: "network.slash")
                        .font(.system(size: 28))
                        .foregroundStyle(Brand.warning)
                    Text("玩法社区连接失败").font(.headline)
                    Text("请检查网络连接后重试。已经下载的固件不会受到影响。")
                        .font(.callout).foregroundStyle(.secondary)
                    Text(err).font(.caption).foregroundStyle(.tertiary).lineLimit(2)
                    Button("重新连接") { store.reload() }
                        .buttonStyle(PrimaryButtonStyle())
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 34)
                .card()
            }
            if store.loading && store.plays.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280, maximum: 380), spacing: 18)], spacing: 18) {
                    ForEach(0..<6, id: \.self) { _ in PlayCardSkeleton() }
                }
            } else if store.plays.isEmpty && store.error == nil {
                EmptyStateView(
                    symbol: "sparkle.magnifyingglass",
                    title: "没有找到相关玩法",
                    message: "换一个关键词，或清除筛选条件后再看看。",
                    actionTitle: "清除搜索",
                    action: { store.query.search = ""; store.query.category = "all"; store.query.tag = "" }
                )
                .card()
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
    var action: (() -> Void)?

    var body: some View {
        let downloading = app.downloadingPlayID == play.id
        Button {
            if let action { action() } else { app.detailPlay = play }
        } label: {
            HStack(spacing: 6) {
                if downloading {
                    ProgressView(value: app.downloadProgress).progressViewStyle(.circular).controlSize(.small)
                    Text("下载中 \(Int(app.downloadProgress * 100))%")
                } else {
                    Image(systemName: "arrow.down.circle.fill")
                    Text(play.isInstallable ? (compact ? "安装" : "查看并安装") : "暂无固件")
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

struct HeroFeaturedCard: View {
    @EnvironmentObject var app: AppState
    let play: Play
    let onDetail: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 0) {
            CoverImage(url: play.coverURL)
                .frame(maxWidth: .infinity)
                .frame(height: 330)
                .clipped()
                .overlay {
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.38)],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                }
                .overlay(alignment: .topLeading) {
                    Label("本周官方精选", systemImage: "sparkles")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(.black.opacity(0.48), in: Capsule())
                        .padding(18)
                }
                .frame(minWidth: 430)
                .onTapGesture(perform: onDetail)

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 7) {
                    Tag(text: play.categoryLabel)
                    if play.mustPlay == true { Tag(text: "必玩", tint: .orange) }
                }
                Text(play.title.display)
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .lineLimit(2)
                Text("开发者 \(play.author ?? "—")")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(play.description?.display ?? "")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .lineSpacing(3)
                Stats(play: play)
                Spacer(minLength: 4)
                HStack(spacing: 10) {
                    Button {
                        app.simulatorPlayID = play.id
                        app.tab = .simulator
                    } label: {
                        Label("先试用", systemImage: "gamecontroller")
                    }
                    .buttonStyle(SoftButtonStyle())
                    Button("查看详情", action: onDetail)
                        .buttonStyle(SoftButtonStyle())
                    InstallButton(play: play)
                        .buttonStyle(PrimaryButtonStyle())
                }
            }
            .padding(26)
            .frame(width: 360, height: 330, alignment: .topLeading)
            .background(Brand.surface)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Brand.hairline))
        .shadow(color: .black.opacity(hovering ? 0.16 : 0.09), radius: hovering ? 24 : 14, y: hovering ? 12 : 7)
        .scaleEffect(hovering ? 1.004 : 1)
        .animation(.easeOut(duration: 0.18), value: hovering)
        .onHover { hovering = $0 }
    }
}

struct HeroFeaturedSkeleton: View {
    var body: some View {
        HStack(spacing: 0) {
            SkeletonBlock(radius: 0).frame(height: 330)
            VStack(alignment: .leading, spacing: 14) {
                SkeletonBlock().frame(width: 92, height: 24)
                SkeletonBlock().frame(height: 28)
                SkeletonBlock().frame(width: 160, height: 13)
                SkeletonBlock().frame(height: 13)
                SkeletonBlock().frame(width: 240, height: 13)
                Spacer()
            }
            .padding(26)
            .frame(width: 360, height: 330)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .card(radius: 22)
        .pulsing()
    }
}

struct PlayCard: View {
    @EnvironmentObject var app: AppState
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
                    Button {
                        app.simulatorPlayID = play.id
                        app.tab = .simulator
                    } label: {
                        Image(systemName: "gamecontroller")
                    }
                    .buttonStyle(.borderless)
                    .help("先在模拟器中体验")
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
    @State private var showTechnicalDetails = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                IconTile(symbol: "arrow.down.to.line.compact", size: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text("安装引导").font(.headline)
                    Text("先确认玩法信息，再连接设备完成安装").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("关闭", action: close)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .background(.bar)
            Divider()

            HStack(spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    CoverImage(url: play.coverURL)
                        .frame(width: 330)
                        .frame(maxHeight: .infinity)
                        .clipped()
                    LinearGradient(colors: [.clear, .black.opacity(0.72)], startPoint: .center, endPoint: .bottom)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Tag(text: play.categoryLabel, tint: .white, onDark: true)
                            if play.mustPlay == true { Tag(text: "官方必玩", tint: .white, onDark: true) }
                        }
                        Text(play.title.display)
                            .font(.system(size: 25, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text("开发者 \(play.author ?? "—")").foregroundStyle(.secondary)
                            .colorScheme(.dark)
                        Stats(play: play).colorScheme(.dark)
                    }
                    .padding(22)
                }
                .frame(width: 330)

                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            HStack(spacing: 0) {
                                GuideStepBadge(number: 1, title: "选择玩法", complete: true, active: false)
                                GuideConnector(complete: true)
                                GuideStepBadge(number: 2, title: "连接设备", complete: app.selectedPort != nil, active: app.selectedPort == nil)
                                GuideConnector(complete: false)
                                GuideStepBadge(number: 3, title: "确认安装", complete: false, active: app.selectedPort != nil)
                            }

                            Text(play.description?.display ?? "这个玩法暂时没有介绍。")
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .lineSpacing(3)

                            if let instructions = play.instructions?.display, !instructions.isEmpty {
                                GuideInfoBlock(
                                    symbol: "hand.tap",
                                    title: "怎么玩",
                                    text: instructions
                                )
                            }

                            GuideInfoBlock(
                                symbol: app.selectedPort == nil ? "cable.connector.slash" : "checkmark.circle.fill",
                                title: app.selectedPort == nil ? "下一步：连接 AI Passport" : "设备已经连接",
                                text: app.selectedPort == nil
                                    ? "下载并校验固件后，会进入设备连接页面。请准备一根支持数据传输的 Type-C 线。"
                                    : "已检测到 \((app.selectedPort!.path as NSString).lastPathComponent)，下载完成后可直接确认写入。"
                            )

                            DisclosureGroup("固件与更新信息", isExpanded: $showTechnicalDetails) {
                                VStack(alignment: .leading, spacing: 7) {
                                    if let changelog = play.changelog?.display, !changelog.isEmpty {
                                        Text(changelog).font(.callout).foregroundStyle(.secondary)
                                    }
                                    Divider()
                                    Text("格式：\(play.format == "esp-merged-0x0" ? "合并固件，写入地址 0x0" : play.format)")
                                    if let size = play.expectedSize {
                                        Text("大小：\(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))")
                                    }
                                    if let hash = play.expectedSHA256 {
                                        Text("SHA-256：\(hash)").textSelection(.enabled)
                                    }
                                }
                                .font(.caption.monospaced())
                                .padding(.top, 9)
                            }

                            if let error = app.downloadError {
                                Banner(kind: .error, text: error) { app.downloadError = nil }
                            }
                        }
                        .padding(24)
                    }

                    Divider()
                    HStack(spacing: 12) {
                        Link("在网页中查看", destination: play.pageURL)
                        Button {
                            close()
                            app.simulatorPlayID = play.id
                            app.tab = .simulator
                        } label: {
                            Label("先在模拟器中体验", systemImage: "gamecontroller")
                        }
                        .buttonStyle(SoftButtonStyle())
                        Spacer()
                        if app.downloadingPlayID == play.id {
                            VStack(alignment: .trailing, spacing: 4) {
                                Text("正在下载并校验 \(Int(app.downloadProgress * 100))%")
                                    .font(.caption).foregroundStyle(.secondary)
                                ProgressView(value: app.downloadProgress).frame(width: 150)
                            }
                        } else {
                            Button {
                                app.install(play)
                            } label: {
                                Label("下载并继续", systemImage: "arrow.down.circle.fill")
                            }
                            .buttonStyle(PrimaryButtonStyle(size: .large))
                            .keyboardShortcut(.defaultAction)
                            .disabled(!play.isInstallable || app.downloadingPlayID != nil || app.job.isRunning)
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 16)
                    .background(.bar)
                }
            }
        }
        .frame(width: 900, height: 680)
        .background(Brand.surface)
        .onChange(of: app.tab) { _, tab in if tab == .flash { close() } }
    }
}

struct GuideStepBadge: View {
    let number: Int
    let title: String
    let complete: Bool
    let active: Bool

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                Circle().fill(complete ? Brand.accent : (active ? Brand.accentSoft : Color.primary.opacity(0.06)))
                if complete {
                    Image(systemName: "checkmark").foregroundStyle(Brand.onAccent)
                } else {
                    Text("\(number)").foregroundStyle(active ? Brand.accent : .secondary)
                }
            }
            .font(.caption.bold())
            .frame(width: 28, height: 28)
            Text(title)
                .font(.system(size: 10, weight: active ? .semibold : .regular))
                .foregroundStyle(active || complete ? .primary : .secondary)
        }
        .frame(width: 82)
    }
}

struct GuideConnector: View {
    let complete: Bool
    var body: some View {
        Rectangle()
            .fill(complete ? Brand.accent : Color.primary.opacity(0.10))
            .frame(height: 2)
            .offset(y: -9)
    }
}

struct GuideInfoBlock: View {
    let symbol: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Brand.accent)
                .frame(width: 32, height: 32)
                .background(Brand.accentSoft, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.callout.weight(.semibold))
                Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sunken()
    }
}
