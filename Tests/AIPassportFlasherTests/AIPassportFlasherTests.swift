import XCTest
@testable import AIPassportFlasher

final class CardidNVSTests: XCTestCase {
    /// Digests produced by the official web generator (cardid-nvs JS module) for the same inputs.
    func testMatchesWebGenerator() throws {
        let cases: [(String, String, String, String, String)] = [
            ("348518a1b2c3", "TestKey-ABCdef0123456789", "folotoy", "v1.0.0",
             "5512a73e0ed3cd0b64dd8002a014e018282db58773c3fbed76f5ab19801eace5"),
            ("00ff00ff00ff", String(repeating: "k", count: 64), String(repeating: "p", count: 16), "12345678",
             "af5904d76dcdc25ed022c129753b4e92063309d44427b392313fb57f259fb33e"),
            ("abcdefabcdef", "密钥测试🙂", "folotoy", "v1",
             "6e7d1fec32972e67ba66b20b73d49685400bddeb23caec1e7eb1f7641231f551"),
        ]
        for (sn, key, pk, hw, digest) in cases {
            let data = try CardidNVS.build(sn: sn, deviceSecret: key, productKey: pk, hardwareVersion: hw)
            XCTAssertEqual(data.count, 0x4000)
            XCTAssertEqual(CommunityAPI.sha256Hex(data), digest, "mismatch for \(sn)")
        }
    }

    func testRejectsBadInput() {
        XCTAssertThrowsError(try CardidNVS.build(sn: "348518A1B2C3", deviceSecret: "k", productKey: "p", hardwareVersion: "v"))
        XCTAssertThrowsError(try CardidNVS.build(sn: "348518a1b2c3", deviceSecret: String(repeating: "k", count: 65), productKey: "p", hardwareVersion: "v"))
        XCTAssertThrowsError(try CardidNVS.build(sn: "348518a1b2c3", deviceSecret: "k", productKey: "p", hardwareVersion: "123456789"))
    }
}

final class ParserTests: XCTestCase {
    func testV5Output() {
        let header = """
        Connected to ESP32-C3 on /dev/cu.usbmodem1101:
        Chip type:          ESP32-C3 (QFN32) (revision v0.4)
        MAC:                34:85:18:AA:BB:CC
        Detected flash size: 8MB
        """
        XCTAssertEqual(EsptoolOutputParser.mac(in: header), "34:85:18:aa:bb:cc")
        XCTAssertEqual(EsptoolOutputParser.flashSize(in: header), "8MB")
        XCTAssertEqual(EsptoolOutputParser.chip(in: header), "ESP32-C3 (QFN32) (revision v0.4)")
        XCTAssertEqual(EsptoolOutputParser.events(in: "Writing at 0x00010000 [=====>      ]  42.5% 212992/501234 bytes..."), [.progress(0.425)])
        XCTAssertTrue(EsptoolOutputParser.events(in: "Wrote 834624 bytes (501234 compressed) at 0x00000000 in 6.1 seconds.").contains(.fileWritten))
        XCTAssertTrue(EsptoolOutputParser.events(in: "Hard resetting via RTS pin...").contains(.resetting))
    }

    func testV4Output() {
        XCTAssertEqual(EsptoolOutputParser.chip(in: "Chip is ESP32-C3 (QFN32) (revision v0.4)"), "ESP32-C3 (QFN32) (revision v0.4)")
        XCTAssertEqual(EsptoolOutputParser.events(in: "Writing at 0x0001c000... (12 %)"), [.progress(0.12)])
    }

    func testANSIStrip() {
        XCTAssertEqual(ANSI.strip("\u{1B}[1;32mOK\u{1B}[0m done"), "OK done")
    }

    func testHints() {
        XCTAssertTrue(EsptoolDiagnostics.summarize("A fatal error occurred: Failed to connect to ESP32-C3: No serial data received.").contains("下载模式"))
        XCTAssertTrue(EsptoolDiagnostics.summarize("Could not exclusively lock port /dev/cu.usbmodem1: Resource temporarily unavailable").contains("占用"))
    }
}

@MainActor
final class ProgressTests: XCTestCase {
    func testOverallProgressAcrossFiles() {
        let t = WriteProgressTracker(sizes: [100, 300])
        XCTAssertEqual(t.update(fraction: 0.5).1, 0.125, accuracy: 1e-9)
        t.fileFinished()
        let (i, overall) = t.update(fraction: 0.5)
        XCTAssertEqual(i, 1)
        XCTAssertEqual(overall, 0.625, accuracy: 1e-9)
    }
}

@MainActor
final class AppStateTests: XCTestCase {
    func testSelectingAnotherFirmwareResetsCompletedInstall() throws {
        let firmware = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".bin")
        try Data([0xE9, 0, 0, 0]).write(to: firmware)
        defer { try? FileManager.default.removeItem(at: firmware) }

        let app = AppState()
        app.job = .succeeded
        app.progress = 1
        app.consent = true

        app.setMerged(firmware)

        XCTAssertEqual(app.job, .idle)
        XCTAssertEqual(app.progress, 0)
        XCTAssertFalse(app.consent)
        XCTAssertEqual(app.images.count, 1)
    }

    func testClearPlanDoesNotInterruptRunningInstall() {
        let app = AppState()
        app.job = .running("正在写入")
        app.progress = 0.42

        app.clearPlan()

        XCTAssertEqual(app.job, .running("正在写入"))
        XCTAssertEqual(app.progress, 0.42)
    }

    func testPrepareAnotherInstallClearsCompletionAndNavigates() {
        let app = AppState()
        app.job = .succeeded
        app.progress = 1
        app.downloadError = "旧错误"
        app.showCompletionActions = true
        app.tab = .flash

        app.prepareAnotherInstall(destination: .restore)

        XCTAssertEqual(app.job, .idle)
        XCTAssertEqual(app.progress, 0)
        XCTAssertNil(app.downloadError)
        XCTAssertFalse(app.showCompletionActions)
        XCTAssertEqual(app.tab, .restore)
    }
}

/// Runs the real bundled esptool without any device attached.
final class EsptoolRunnerTests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipIf(EsptoolRunner.executableURL() == nil, "Vendor/esptool missing; run scripts/fetch-esptool.sh")
    }

    func testVersion() async throws {
        let out = try await EsptoolRunner().run(["version"]) { _, _ in }
        XCTAssertTrue(out.contains("5.6.0"), out)
    }

    func testMissingPortFailsCleanly() async throws {
        let port = "/dev/cu.usbmodem-apf-does-not-exist"
        do {
            _ = try await EsptoolRunner().run(["--chip", "esp32c3", "--port", port, "--before", "no-reset", "--after", "no-reset", "flash-id"]) { _, _ in }
            XCTFail("expected failure")
        } catch let EsptoolError.failed(code, summary) {
            XCTAssertNotEqual(code, 0)
            XCTAssertFalse(summary.isEmpty)
            print("esptool summary:", summary)
        }
    }
}

final class PlanTests: XCTestCase {
    private func tempFile(_ bytes: [UInt8]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".bin")
        try Data(bytes).write(to: url)
        return url
    }

    func testOffsets() {
        XCTAssertEqual(FlashImage.parseOffset("0x10000"), 0x10000)
        XCTAssertEqual(FlashImage.parseOffset(" 0X8000 "), 0x8000)
        XCTAssertEqual(FlashImage.parseOffset("4096"), 4096)
        XCTAssertNil(FlashImage.parseOffset("0xZZ"))
        XCTAssertEqual(FlashImage.defaultOffset(forIndex: 2), "0x10000")
    }

    func testValidation() throws {
        let img = try FlashImage(fileURL: tempFile([0xE9] + [UInt8](repeating: 0, count: 5000)), offsetText: "0x0")
        XCTAssertTrue(PlanValidator.issues(for: [img]).isEmpty)

        let overlap = try FlashImage(fileURL: tempFile([UInt8](repeating: 1, count: 10)), offsetText: "0x1000")
        XCTAssertTrue(PlanValidator.issues(for: [img, overlap]).contains { $0.message.contains("重叠") })

        let misaligned = try FlashImage(fileURL: tempFile([1]), offsetText: "0x8001")
        XCTAssertTrue(PlanValidator.issues(for: [misaligned]).contains { $0.level == .error })

        let notESP = try FlashImage(fileURL: tempFile([0x00, 1, 2]), offsetText: "0x0")
        XCTAssertEqual(PlanValidator.issues(for: [notESP]).first?.level, .warning)

        let tooBig = try FlashImage(fileURL: tempFile([1, 2]), offsetText: "0x7FFFFF")
        XCTAssertFalse(PlanValidator.issues(for: [tooBig]).isEmpty)
    }
}

final class RestoreTests: XCTestCase {
    func testParseLink() throws {
        let c = try FactoryRestore.parseCredentials(link: "https://ai-passport.folotoy.cn/?s=348518A1B2C3&k=abc%2Bdef#x")
        XCTAssertEqual(c, .init(sn: "348518a1b2c3", key: "abc+def"))
        XCTAssertThrowsError(try FactoryRestore.parseCredentials(link: "https://ai-passport.folotoy.cn/?s=123"))
        XCTAssertThrowsError(try FactoryRestore.parseCredentials(link: "s=zz&k=1"))
    }

    func testProductClassification() {
        XCTAssertEqual(FactoryRestore.classify(["data": ["product_key": "folotoy"]]), .aiPassport)
        XCTAssertEqual(FactoryRestore.classify(["data": ["device": ["is_trae": true]]]), .other("trae"))
        XCTAssertEqual(FactoryRestore.classify(["data": ["product_key": "jd_passport"]]), .other("jd-passport"))
    }

    /// Opt-in: downloads the real public default image set and checks it end to end.
    func testRealManifest() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["APF_NETWORK_TESTS"] == "1", "set APF_NETWORK_TESTS=1")
        let creds = try FactoryRestore.validate(sn: "000000000000", key: "fixture-key")
        let prepared = try await FactoryRestore.prepare(credentials: creds) { _, _ in }
        defer { try? FileManager.default.removeItem(at: prepared.directory) }
        XCTAssertEqual(prepared.images.map(\.offsetText), ["0x0", "0x8000", "0x10000", "0x3fa000", "0x356000"])
        XCTAssertTrue(PlanValidator.issues(for: prepared.images).isEmpty)
    }

    func testCommunityListing() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["APF_NETWORK_TESTS"] == "1", "set APF_NETWORK_TESTS=1")
        let page = try await CommunityAPI.loadPlays(PlayQuery(category: "games", sort: "downloads"), offset: 0, limit: 5)
        XCTAssertEqual(page.plays.count, 5)
        XCTAssertTrue(page.total > 5)
        XCTAssertTrue(page.plays.allSatisfy { $0.categoryLabel != "玩法" })
        let featured = try await CommunityAPI.loadFeatured()
        XCTAssertFalse(featured.isEmpty)
    }
}
