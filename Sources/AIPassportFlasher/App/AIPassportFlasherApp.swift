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
                .frame(minWidth: 1020, minHeight: 700)
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
        ProcessInfo.processInfo.environment["APF_SNAPSHOT_DIR"] == nil
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
                HStack(spacing: 11) {
                    Image(systemName: "sparkles.rectangle.stack.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(AppTheme.accent.gradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .shadow(color: AppTheme.accent.opacity(0.22), radius: 8, y: 3)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("AI Passport").font(.headline)
                        Text("刷机工具").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 14)

                List(selection: Binding(get: { app.tab }, set: { if let t = $0 { app.tab = t } })) {
                    Section("开始") {
                        sidebarRow(.community, title: "发现玩法")
                        sidebarRow(.simulator, title: "玩法模拟器")
                    }
                    Section("我的设备") {
                        sidebarRow(.flash, title: "安装到设备")
                        sidebarRow(.restore, title: "恢复设备")
                    }
                    Section {
                        sidebarRow(.about, title: "关于")
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                sidebarFooter
            }
            .background(.ultraThinMaterial)
            .navigationSplitViewColumnWidth(min: 210, ideal: 220)
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
    }

    private func sidebarRow(_ tab: SidebarTab, title: String) -> some View {
        HStack(spacing: 11) {
            Image(systemName: tab.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(app.tab == tab ? AppTheme.accent : .secondary)
                .frame(width: 24, height: 24)
            Text(title).font(.callout.weight(app.tab == tab ? .semibold : .medium))
            Spacer()
        }
        .padding(.vertical, 5)
        .tag(tab)
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
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(12)
    }
}

struct DeviceStatusPill: View {
    @EnvironmentObject var app: AppState
    @State private var hovering = false

    var body: some View {
        Button {
            app.tab = .flash
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
        .help("查看设备与安装状态")
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
