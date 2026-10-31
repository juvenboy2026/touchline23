import XCTest
@testable import PackagingModel

final class StandaloneTests: XCTestCase {
    func testBundleOverridesEveryPersistedDeveloperPath() {
        var c = Configuration()
        c.repository = "/old/repository"; c.python = "/old/venv/python"
        c.library = "/old/reader"; c.exefs = "/old/ExeFS"; c.romfs = "/old/RomFS"
        c.useBundle(URL(fileURLWithPath: "/Moved Folder/NXPackagingGUI.app/Contents/Resources"))
        XCTAssertTrue(c.automatic)
        XCTAssertEqual(c.repository, "/Moved Folder/NXPackagingGUI.app/Contents/Resources/Packaging")
        XCTAssertEqual(c.python, "/Moved Folder/NXPackagingGUI.app/Contents/Resources/Python/bin/python3")
        XCTAssertTrue(c.library.hasPrefix("/Moved Folder/"))
        XCTAssertTrue(c.gamesIndex.hasPrefix("/Moved Folder/"))
        XCTAssertTrue(c.exefs.isEmpty); XCTAssertTrue(c.romfs.isEmpty)
        XCTAssertEqual(c.cache, Configuration.defaultCache)
    }

    func testCustomCacheSurvivesRelocationAndNoInternalInputMustBeChosen() {
        var c = Configuration(); c.cache = "/mnt/SSD/cache"
        c.useBundle(URL(fileURLWithPath: "/Applications/NXPackagingGUI.app/Contents/Resources"))
        let args = c.arguments(action: "check")
        XCTAssertEqual(args[args.firstIndex(of: "--cache-root")! + 1], c.cache)
        XCTAssertTrue(args.contains("--automatic"))
        for flag in ["--cache", "--exefs", "--romfs", "--shader-action"] {
            XCTAssertFalse(args.contains(flag), flag)
        }
    }

    func testAutomaticOutputTracksTheGameUntilManuallyChanged() {
        var c = Configuration()
        c.selectBase("/mnt/Game A/base.xci")
        XCTAssertEqual(c.output, "/mnt/Game A")
        c.selectBase("/mnt/Game B/base.nsp")
        XCTAssertEqual(c.output, "/mnt/Game B")
        c.selectOutput("/mnt/Results")
        c.selectBase("/mnt/Game C/base.xci")
        XCTAssertEqual(c.output, "/mnt/Results")
        c.restoreOutput()
        XCTAssertTrue(c.outputAutomatic)
        XCTAssertEqual(c.output, "/mnt/Game C")
    }

    func testAutomaticOutputPreferencePersists() throws {
        var c = Configuration(); c.selectOutput("/my/output")
        let decoded = try JSONDecoder().decode(Configuration.self, from: JSONEncoder().encode(c))
        XCTAssertFalse(decoded.outputAutomatic)
        let legacy = try JSONDecoder().decode(Configuration.self, from: Data(#"{"output":"/previous/output"}"#.utf8))
        XCTAssertFalse(legacy.outputAutomatic)
    }

    func testAdvisoryToolDetectionIsAbsentFromLaunchAndCapabilityState() {
        var c = Configuration(); c.automatic = true; c.targets = ["macos", "ios"]
        XCTAssertNil(c.capabilityIssue)
        XCTAssertFalse(c.arguments(action: "check").contains("--tools-detected"))
    }
}
