import SwiftUI

struct CommunityView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var store: CommunityStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                if let err = app.downloadError {
                    Banner(kind: .error, text: err) { app.downloadError = nil }
                }
                featuredSection
                librarySection
            }
            .padding(24)
            .frame(maxWidth: 1240, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { store.start() }
        .sheet(item: $app.detailPlay) { play in
            PlayDetailView(play: play) { app.detailPlay = nil }
                .environmentObject(app)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("玩法社区").font(.largeTitle.bold())
                Text("挑一个喜欢的玩法，点击「安装」下载固件，再连接 AI Passport 写入。安装会覆盖设备当前的全部内容。")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button {
                app.clearPlan()
                app.tab = .flash
            } label: {
                Label("安装本地 .bin 固件", systemImage: "doc.badge.arrow.up")
            }
            .controlSize(.large)
            .help("已有 .bin 文件？从电脑选择并刷入")
        }
    }

    private var featuredSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("官方精选").font(.title2.bold())
                Text("由 FoloToy 官方从社区中挑选").foregroundStyle(.secondary).font(.callout)
                Spacer()
                if store.featuredError != nil {
                    Button("重新加载") { store.loadFeatured() }
                }
            }
            if let err = store.featuredError {
                Text(err).foregroundStyle(.red).font(.callout)
            } else if store.featured.isEmpty {
                HStack(spacing: 14) { ForEach(0..<5, id: \.self) { _ in FeaturedCardSkeleton() } }
            } else {
                ScrollView(.horizontal, showsIndicators: true) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(store.featured) { play in
                            FeaturedCard(play: play, onDetail: { app.detailPlay = play })
                        }
                    }
                    .padding(.bottom, 10)
                }
            }
        }
    }

    private var librarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("全部玩法").font(.title2.bold())
                if store.total > 0 {
                    Text("共 \(store.total) 个").foregroundStyle(.secondary)
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
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 400, maximum: 620), spacing: 14)], spacing: 14) {
                ForEach(store.plays) { play in
                    PlayCard(play: play, onDetail: { app.detailPlay = play })
                        .onAppear { if play.id == store.plays.last?.id { store.loadMore() } }
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
                } else if store.error == nil {
                    Text("没有找到符合条件的玩法").foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 8)
        }
    }

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("搜索玩法名称、作者或简介", text: $store.query.search)
                        .textFieldStyle(.plain)
                    if !store.query.search.isEmpty {
                        Button { store.query.search = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.25)))
                .frame(maxWidth: 380)

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

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            CoverImage(url: play.thumbnailURL)
                .frame(width: 126, height: 168)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .onTapGesture(perform: onDetail)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Tag(text: play.categoryLabel)
                    if play.mustPlay == true { Tag(text: "必玩", tint: .orange) }
                    Spacer()
                    if let d = play.updatedDate {
                        Text(d, format: .dateTime.year().month().day()).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text(play.title.display).font(.headline).lineLimit(2)
                Text("开发者 \(play.author ?? "—")").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Text(play.description?.display ?? "").font(.callout).foregroundStyle(.secondary).lineLimit(3)
                if let ins = play.instructions?.display, !ins.isEmpty {
                    Label { Text(ins).lineLimit(2) } icon: { Image(systemName: "hand.point.up.left") }
                        .font(.caption).foregroundStyle(.secondary)
                        .help(ins)
                }
                Spacer(minLength: 0)
                HStack(spacing: 10) {
                    Stats(play: play)
                    Spacer()
                    Button("详情", action: onDetail)
                    InstallButton(play: play)
                }
            }
        }
        .padding(12)
        .frame(minHeight: 192)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.secondary.opacity(0.18)))
    }
}

struct FeaturedCard: View {
    let play: Play
    let onDetail: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CoverImage(url: play.thumbnailURL)
                .frame(width: 186, height: 248)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(alignment: .topLeading) { Tag(text: play.categoryLabel, tint: .white, onDark: true).padding(8) }
                .onTapGesture(perform: onDetail)
            Text(play.title.display).font(.headline).lineLimit(1)
            Text("开发者 \(play.author ?? "—")").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Text(play.description?.display ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(2)
                .frame(height: 30, alignment: .top)
            HStack {
                Button("详情", action: onDetail).controlSize(.small)
                Spacer()
                InstallButton(play: play, compact: true).controlSize(.small)
            }
        }
        .frame(width: 186)
    }
}

struct FeaturedCardSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.12)).frame(width: 186, height: 248)
            RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.12)).frame(width: 120, height: 12)
            RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.10)).frame(width: 80, height: 10)
        }
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

struct Tag: View {
    let text: String
    var tint: Color = .accentColor
    var onDark = false
    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .foregroundStyle(onDark ? Color.white : tint)
            .background(Capsule().fill(onDark ? Color.black.opacity(0.55) : tint.opacity(0.14)))
    }
}

struct Chip: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.callout)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .background(Capsule().fill(selected ? Color.accentColor : Color.secondary.opacity(0.12)))
        }
        .buttonStyle(.plain)
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
                .padding(24)
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
            .padding(16)
        }
        .frame(width: 760, height: 620)
        .background(Color(nsColor: .windowBackgroundColor))
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

struct Banner: View {
    enum Kind { case error, warning, info }
    let kind: Kind
    let text: String
    var onClose: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: kind == .info ? "info.circle.fill" : "exclamationmark.triangle.fill")
            Text(text).fixedSize(horizontal: false, vertical: true)
            Spacer()
            if let onClose { Button { onClose() } label: { Image(systemName: "xmark") }.buttonStyle(.plain) }
        }
        .padding(12)
        .foregroundStyle(color)
        .background(RoundedRectangle(cornerRadius: 10).fill(color.opacity(0.1)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(color.opacity(0.35)))
    }

    private var color: Color {
        switch kind {
        case .error: return .red
        case .warning: return .orange
        case .info: return .blue
        }
    }
}
