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
            List(selection: Binding(get: { app.tab }, set: { if let t = $0 { app.tab = t } })) {
                ForEach(SidebarTab.allCases) { tab in
                    Label(tab.title, systemImage: tab.symbol).tag(tab)
                }
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190)
            .safeAreaInset(edge: .bottom) { sidebarFooter }
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
        VStack(alignment: .leading, spacing: 4) {
            if let port = app.selectedPort {
                Label((port.path as NSString).lastPathComponent, systemImage: "cable.connector")
                    .font(.caption).foregroundStyle(.green)
            } else {
                Label("未连接设备", systemImage: "cable.connector.slash").font(.caption).foregroundStyle(.secondary)
            }
            if app.job.isRunning {
                ProgressView(value: app.progress).controlSize(.small)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
