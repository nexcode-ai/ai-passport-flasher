import AppKit
import SwiftUI

/// Developer-only screenshot mode (`APF_SNAPSHOT_DIR=<dir>`): renders each
/// screen into an off-screen window and writes PNGs, then quits. It never
/// talks to a serial port and never starts a write.
@MainActor
enum SnapshotDriver {
    static func runIfRequested(app: AppState, community: CommunityStore) async {
        let env = ProcessInfo.processInfo.environment
        if let dirPath = env["APF_WINDOW_CAPTURE_DIR"] {
            await captureRealWindow(app: app, community: community, dirPath: dirPath)
            return
        }
        guard let dirPath = env["APF_SNAPSHOT_DIR"] else { return }
        let dir = URL(fileURLWithPath: dirPath, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for w in NSApp.windows { w.orderOut(nil) }

        community.start()
        await waitUntil(timeout: 30) { !community.plays.isEmpty && !community.featured.isEmpty }
        log("community loaded: featured=\(community.featured.count) plays=\(community.plays.count)")
        await sleep(6)

        app.tab = .community
        await shoot(ContentView(), app: app, community: community, size: CGSize(width: 1280, height: 1380), to: dir, name: "01-community")

        if let play = community.featured.first(where: \.isInstallable) ?? community.plays.first {
            await shoot(PlayDetailView(play: play) {}, app: app, community: community, size: CGSize(width: 980, height: 720), to: dir, name: "02-play-detail")
        }

        app.clearPlan()
        app.tab = .flash
        await shoot(ContentView(), app: app, community: community, size: CGSize(width: 1280, height: 1560), to: dir, name: "03-step1-connect")

        let slug = env["APF_SAMPLE_PLAY_SLUG"] ?? ""
        if let play = (community.featured + community.plays).first(where: { $0.slug == slug }) {
            app.install(play)
            await waitUntil(timeout: 120) { app.downloadingPlayID == nil }
            app.tab = .flash
            await shoot(ContentView(), app: app, community: community, size: CGSize(width: 1280, height: 1560), to: dir, name: "04-step2-community-play")
        }

        let parts = (env["APF_SAMPLE_PARTS"] ?? "").split(separator: ":").map { URL(fileURLWithPath: String($0)) }
        if !parts.isEmpty {
            app.clearPlan()
            app.addPartitionFiles(parts)
            app.tab = .flash
            await shoot(ContentView(), app: app, community: community, size: CGSize(width: 1280, height: 1640), to: dir, name: "05-step2-local-partitions")
        }

        if let merged = env["APF_SAMPLE_MERGED"] {
            app.clearPlan()
            app.setMerged(URL(fileURLWithPath: merged))
            app.consent = true
            app.tab = .flash
            await shoot(ContentView(), app: app, community: community, size: CGSize(width: 1280, height: 1560), to: dir, name: "06-step3-write-ready")
        }

        app.clearPlan()
        app.tab = .restore
        await shoot(ContentView(), app: app, community: community, size: CGSize(width: 1280, height: 860), to: dir, name: "07-factory-restore")
        app.tab = .about
        await shoot(ContentView(), app: app, community: community, size: CGSize(width: 1280, height: 860), to: dir, name: "08-about", settle: 15)
        app.tab = .simulator
        await shoot(ContentView(), app: app, community: community, size: CGSize(width: 1280, height: 900), to: dir, name: "09-simulator", settle: 18)

        NSApp.terminate(nil)
    }

    /// Captures the actual on-screen app window without requiring the
    /// system-wide screen-recording permission.
    private static func captureRealWindow(app: AppState, community: CommunityStore, dirPath: String) async {
        let dir = URL(fileURLWithPath: dirPath, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        await waitUntil(timeout: 10) { NSApp.windows.contains { $0.contentView != nil } }
        guard let window = NSApp.windows.first(where: { $0.contentView != nil && $0.title == "AI Passport 刷机工具" })
                ?? NSApp.windows.first(where: { $0.contentView != nil }) else {
            log("no real window")
            NSApp.terminate(nil)
            return
        }

        window.setContentSize(CGSize(width: 1240, height: 860))
        window.center()
        window.makeKeyAndOrderFront(nil)
        community.start()
        await waitUntil(timeout: 30) { !community.plays.isEmpty || community.error != nil }
        await sleep(3)

        app.tab = .community
        await sleep(2)
        await capture(window: window, to: dir.appendingPathComponent("real-community.png"))

        let visiblePlays = community.featured + community.plays
        if let play = visiblePlays.first(where: { $0.title.display.contains("城市电台") })
            ?? visiblePlays.first {
            app.detailPlay = play
            await waitUntil(timeout: 5) {
                NSApp.windows.contains { $0 !== window && $0.isVisible && $0.contentView != nil }
            }
            await sleep(1)
            if let sheet = NSApp.windows.first(where: { $0 !== window && $0.isVisible && $0.contentView != nil }) {
                await capture(window: sheet, to: dir.appendingPathComponent("real-play-detail.png"))
            }
            app.detailPlay = nil
            await sleep(1)
            SimulatorSession.shared.tryPlay(play, app: app)
        } else {
            app.tab = .simulator
        }
        await sleep(16)
        if let controller = SimulatorWebController.active {
            await controller.setSnapshotNeutral(true)
            await captureSimulator(
                window: window,
                controller: controller,
                to: dir.appendingPathComponent("real-simulator.png")
            )
            await controller.captureDevice(to: dir.appendingPathComponent("real-simulator-buttons.png"))
            log("captured real-simulator-buttons.png")
            await controller.setSnapshotNeutral(false)
        } else {
            await capture(window: window, to: dir.appendingPathComponent("real-simulator.png"))
        }

        app.clearPlan()
        app.job = .idle
        app.tab = .flash
        await sleep(2)
        await capture(window: window, to: dir.appendingPathComponent("real-install.png"))

        app.job = .succeeded
        await sleep(1)
        await capture(window: window, to: dir.appendingPathComponent("real-install-success.png"))

        app.job = .idle
        app.tab = .restore
        await sleep(1)
        await capture(window: window, to: dir.appendingPathComponent("real-restore.png"))

        app.tab = .about
        await sleep(2)
        await capture(window: window, to: dir.appendingPathComponent("real-about.png"))
        NSApp.terminate(nil)
    }

    private static func capture(window: NSWindow, to url: URL) async {
        guard let root = window.contentView else { return }
        root.layoutSubtreeIfNeeded()
        guard let rep = root.bitmapImageRepForCachingDisplay(in: root.bounds) else {
            log("no bitmap for \(url.lastPathComponent)")
            return
        }
        root.cacheDisplay(in: root.bounds, to: rep)

        if let png = rep.representation(using: .png, properties: [:]) {
            do { try png.write(to: url); log("captured \(url.lastPathComponent)") }
            catch { log("write \(url.lastPathComponent) failed: \(error)") }
        }
    }

    private static func captureSimulator(
        window: NSWindow,
        controller: SimulatorWebController,
        to url: URL
    ) async {
        guard let root = window.contentView, let webView = controller.webView else { return }
        root.layoutSubtreeIfNeeded()
        guard let base = root.bitmapImageRepForCachingDisplay(in: root.bounds),
              let web = await controller.snapshotWebView() else { return }
        root.cacheDisplay(in: root.bounds, to: base)

        let converted = webView.convert(webView.bounds, to: root)
        let webFrame = root.isFlipped
            ? CGRect(
                x: converted.minX,
                y: root.bounds.height - converted.maxY,
                width: converted.width,
                height: converted.height
            )
            : converted
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: base)
        web.draw(in: webFrame, from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.current?.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        guard let png = base.representation(using: .png, properties: [:]) else { return }
        do { try png.write(to: url); log("captured \(url.lastPathComponent)") }
        catch { log("write \(url.lastPathComponent) failed: \(error)") }
    }

    private static func shoot<V: View>(_ view: V, app: AppState, community: CommunityStore, size: CGSize, to dir: URL, name: String, settle: Double = 3.5) async {
        let root = view.environmentObject(app).environmentObject(community).frame(width: size.width, height: size.height)
        let host = NSHostingView(rootView: root)
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: CGRect(x: -20000, y: -20000, width: size.width, height: size.height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.backgroundColor = .windowBackgroundColor
        window.contentView = host
        window.orderFrontRegardless()
        await sleep(settle)
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { log("no bitmap for \(name)"); return }
        host.cacheDisplay(in: host.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) {
            do { try png.write(to: dir.appendingPathComponent("\(name).png")) }
            catch { log("write \(name) failed: \(error)") }
        }
        log("captured \(name)")
        window.orderOut(nil)
    }

    private static func log(_ s: String) {
        FileHandle.standardError.write(Data("[snapshot] \(s)\n".utf8))
    }

    private static func waitUntil(timeout: Double, _ cond: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !cond() && Date() < deadline { await sleep(0.25) }
    }

    private static func sleep(_ s: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(s * 1_000_000_000))
    }
}
