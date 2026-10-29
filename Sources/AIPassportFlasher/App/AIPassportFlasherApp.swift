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
                    ForEach(SidebarTab.allCases) { tab in
                        HStack(spacing: 11) {
                            Image(systemName: tab.symbol)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(app.tab == tab ? AppTheme.accent : .secondary)
                                .frame(width: 24, height: 24)
                            Text(tab.title).font(.callout.weight(app.tab == tab ? .semibold : .medium))
                            Spacer()
                        }
                        .padding(.vertical, 5)
                        .tag(tab)
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
                case .flash: FlashView()
                case .restore: RestoreView()
                case .about: AboutView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(12)
    }
}
