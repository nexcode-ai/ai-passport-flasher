import AppKit
import SwiftUI

@main
struct AIPassportFlasherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var app = Shared.app
    @StateObject private var community = Shared.community

    var body: some Scene {
        WindowGroup("AI Passport 刷机工具") {
            ContentView()
                .environmentObject(app)
                .environmentObject(community)
                .frame(minWidth: 1100, minHeight: 720)
                .tint(AppTheme.accent)
        }
        .defaultSize(width: 1240, height: 860)
        .windowToolbarStyle(.unified)
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}

@MainActor
enum Shared {
    static let app = AppState()
    static let community = CommunityStore()
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        let env = ProcessInfo.processInfo.environment
        return env["APF_SNAPSHOT_DIR"] == nil && env["APF_WINDOW_CAPTURE_DIR"] == nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            await SnapshotDriver.runIfRequested(app: Shared.app, community: Shared.community)
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                sidebarBrand
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.l) {
                        sidebarSection("开始") {
                            SidebarNavigationRow(tab: .community, title: "发现玩法")
                            SidebarNavigationRow(tab: .simulator, title: "玩法模拟器")
                        }
                        sidebarSection("我的设备") {
                            SidebarNavigationRow(tab: .flash, title: "安装到设备")
                            SidebarNavigationRow(tab: .restore, title: "恢复设备")
                        }
                        sidebarSection("支持") {
                            SidebarNavigationRow(tab: .about, title: "关于")
                        }
                    }
                    .padding(.horizontal, Space.s)
                    .padding(.vertical, Space.xs)
                    .overlayScrollers()
                }
                sidebarFooter
            }
            .background(
                ZStack {
                    Rectangle().fill(.ultraThinMaterial)
                    LinearGradient(
                        colors: [Brand.accent.opacity(0.08), .clear],
                        startPoint: .topLeading,
                        endPoint: .center
                    )
                }
            )
            .navigationSplitViewColumnWidth(min: 228, ideal: 240, max: 260)
        } detail: {
            Group {
                switch app.tab {
                case .community: CommunityView()
                case .simulator: SimulatorView()
                case .flash: FlashView()
                case .restore: RestoreView()
                case .about: AboutView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                DeviceStatusPill()
            }
        }
        .sheet(item: $app.detailPlay) { play in
            PlayDetailView(play: play) { app.detailPlay = nil }
                .environmentObject(app)
        }
    }

    private var sidebarBrand: some View {
        HStack(spacing: Space.s) {
            IconTile(symbol: "sparkles.rectangle.stack.fill", size: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text("AI Passport").font(.system(size: 15, weight: .bold))
                Text("探索 · 试用 · 安装")
                    .font(.meta)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, Space.m)
        .padding(.top, Space.l)
        .padding(.bottom, Space.m)
    }

    private func sidebarSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            Text(title.uppercased())
                .font(.eyebrow)
                .foregroundStyle(.secondary)
                .padding(.horizontal, Space.xs)
                .padding(.bottom, 2)
            content()
        }
    }

    private var sidebarFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let port = app.selectedPort {
                Label((port.path as NSString).lastPathComponent, systemImage: "cable.connector")
                    .font(.caption.weight(.medium)).foregroundStyle(.green)
            } else {
                Label("未连接设备", systemImage: "cable.connector.slash")
                    .font(.caption.weight(.medium)).foregroundStyle(.secondary)
            }
            if app.job.isRunning {
                ProgressView(value: app.progress).controlSize(.small)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.surface.opacity(0.72), in: RoundedRectangle(cornerRadius: Radius.inset, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.inset, style: .continuous).strokeBorder(Brand.hairline))
        .padding(12)
    }
}

private struct SidebarNavigationRow: View {
    @EnvironmentObject private var app: AppState
    let tab: SidebarTab
    let title: String
    @State private var hovering = false

    var body: some View {
        let selected = app.tab == tab
        Button {
            app.tab = tab
        } label: {
            HStack(spacing: Space.s) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(selected ? Brand.accent : Color.secondary)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                            .fill(selected ? Brand.surfaceRaised : Color.primary.opacity(hovering ? 0.07 : 0.04))
                    )
                Text(title)
                    .font(.system(size: 13.5, weight: selected ? .semibold : .medium))
                    .foregroundStyle(.primary)
                Spacer()
                if selected {
                    Circle().fill(Brand.accent).frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, Space.xs)
            .frame(height: 42)
            .background(
                RoundedRectangle(cornerRadius: Radius.inset, style: .continuous)
                    .fill(selected ? Brand.accentSoft : Color.primary.opacity(hovering ? 0.045 : 0))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.inset, style: .continuous)
                    .strokeBorder(selected ? Brand.accent.opacity(0.20) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.14), value: hovering)
        .animation(.easeOut(duration: 0.14), value: selected)
    }
}

struct DeviceStatusPill: View {
    @EnvironmentObject var app: AppState
    @State private var hovering = false

    var body: some View {
        Button {
            if app.job == .succeeded {
                app.showCompletionActions.toggle()
            } else {
                app.tab = .flash
            }
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    Circle().fill(statusColor.opacity(0.14))
                    Image(systemName: statusSymbol)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(statusColor)
                }
                .frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 0) {
                    Text(statusTitle).font(.caption.weight(.semibold))
                    Text(statusDetail).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
                if app.job.isRunning {
                    ProgressView(value: app.progress)
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.leading, 7)
            .padding(.trailing, 10)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(hovering ? 0.09 : 0.055), in: Capsule())
            .overlay(Capsule().stroke(Color.primary.opacity(0.07)))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(app.job == .succeeded ? "查看安装完成后的下一步" : "查看设备与安装状态")
        .popover(isPresented: $app.showCompletionActions, arrowEdge: .bottom) {
            completionPopover
        }
        .onChange(of: app.job) { _, job in
            if job != .succeeded { app.showCompletionActions = false }
        }
    }

    private var completionPopover: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(spacing: Space.s) {
                ZStack {
                    Circle().fill(Color.green.opacity(0.14))
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.green)
                }
                .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text("安装已完成").font(.headline)
                    Text(app.selectedPlay?.title.display ?? "固件已写入设备")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Text("设备已自动重启。你可以继续安装其他玩法，或前往完成页查看使用提示。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: Space.xs) {
                Button {
                    app.prepareAnotherInstall()
                } label: {
                    Label("安装其他玩法", systemImage: "square.grid.2x2")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.app(.primary))

                HStack(spacing: Space.xs) {
                    Button {
                        app.tab = .flash
                        app.showCompletionActions = false
                    } label: {
                        Label("查看完成页", systemImage: "checkmark.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.app(.secondary, size: .small))

                    Button {
                        app.prepareAnotherInstall(destination: .restore)
                    } label: {
                        Label("恢复设备", systemImage: "arrow.counterclockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.app(.secondary, size: .small))
                }
            }
        }
        .padding(Space.l)
        .frame(width: 330)
    }

    private var statusTitle: String {
        if app.job.isRunning { return "正在安装" }
        if app.job == .succeeded { return "安装完成" }
        return app.selectedPort == nil ? "设备未连接" : "设备已连接"
    }

    private var statusDetail: String {
        if app.job.isRunning { return "\(Int(app.progress * 100))%" }
        if app.job == .succeeded { return "查看下一步" }
        if let port = app.selectedPort { return (port.path as NSString).lastPathComponent }
        return "连接后即可安装"
    }

    private var statusSymbol: String {
        if app.job.isRunning { return "bolt.fill" }
        if app.job == .succeeded { return "checkmark" }
        return app.selectedPort == nil ? "cable.connector.slash" : "cable.connector"
    }

    private var statusColor: Color {
        if app.job.isRunning { return Brand.accent }
        if app.job == .succeeded { return .green }
        return app.selectedPort == nil ? .secondary : .green
    }
}
