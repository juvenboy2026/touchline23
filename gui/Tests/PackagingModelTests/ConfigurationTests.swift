import XCTest
@testable import PackagingModel

final class ConfigurationTests: XCTestCase {
    func testModeSwitchDoesNotForwardInactiveBundledPaths() {
        var c = Configuration()
        c.mode = "directory"; c.aoc = "/game/aoc"; c.romfs = "/game/RomFS"
        XCTAssertTrue(c.arguments(action: "check").contains("--aoc"))
        c.mode = "nsp"
        XCTAssertFalse(c.arguments(action: "check").contains("--aoc"))
        XCTAssertFalse(c.arguments(action: "check").contains("--romfs"))
        c.mode = "directory"
        XCTAssertTrue(c.arguments(action: "check").contains("/game/aoc"))
    }
    func testDirectoryDisablesUpdateEditingButRetainsMatchingBuildInput() {
        var c = Configuration()
        c.update = "/game/update.nsp"
        XCTAssertTrue(c.updateSelectionEnabled)
        c.mode = "directory"
        XCTAssertFalse(c.updateSelectionEnabled)
        let bundled = c.arguments(action: "check", target: "macos")
        XCTAssertEqual(bundled[bundled.firstIndex(of: "--update")! + 1], c.update)
        c.mode = "nsp"
        XCTAssertTrue(c.updateSelectionEnabled)
        XCTAssertEqual(c.update, "/game/update.nsp")
        XCTAssertNotEqual(c.arguments(action: "check", target: "macos"), bundled)
    }
    func testArgumentsKeepPathsLiteral() {
        var c = Configuration()
        c.repository = "/tmp/repo"
        c.base = "/tmp/a ; $(touch injected).xci"
        c.keys = "/tmp/private.keys"
        c.output = "/tmp/output"
        let args = c.arguments(action: "plan")
        XCTAssertEqual(args[args.firstIndex(of: "--base")! + 1], c.base)
        // The run directory is the executor's business; the bridge arguments
        // carry no task path at all.
        XCTAssertFalse(args.contains("--task"))
        XCTAssertFalse(args.contains { $0.contains("gui-task-") })
        XCTAssertFalse(args.contains("-c"))
    }

    func testSecretsAreRedactedBeforeDisplay() {
        var c = Configuration()
        c.keys = "/private/secret.keys"
        let result = c.redacted("error \(c.keys) 00112233445566778899aabbccddeeff")
        XCTAssertFalse(result.contains(c.keys))
        XCTAssertFalse(result.contains("00112233445566778899aabbccddeeff"))
    }

    func testSettingsStoreOnlyConfiguration() throws {
        var c = Configuration()
        c.shaderAction = "reuse"
        let data = try JSONEncoder().encode(c)
        XCTAssertEqual(try JSONDecoder().decode(Configuration.self, from: data), c)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("log"))
    }

    func testDefaultPythonIsNeverSilentlyTheSystemInterpreter() {
        let c = Configuration()
        XCTAssertTrue(c.python.isEmpty)
        XCTAssertNotEqual(c.python, "/usr/bin/python3")
        XCTAssertNotNil(c.launchIssue)
    }

    func testPythonIsDiscoveredOnlyInsideTheSelectedRepository() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("python-lookup-" + UUID().uuidString)
        let bin = root.appendingPathComponent(".venv/bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let python = bin.appendingPathComponent("python3")
        XCTAssertTrue(FileManager.default.createFile(atPath: python.path, contents: Data("#!/bin/sh\n".utf8)))
        XCTAssertNil(Configuration.discoveredPython(in: root.path), "a non-executable file is not an interpreter")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: python.path)
        XCTAssertEqual(Configuration.discoveredPython(in: root.path), python.path)
        XCTAssertNil(Configuration.discoveredPython(in: "an unrelated directory"))
        XCTAssertNil(Configuration.discoveredPython(in: ""))
    }

    func testSelectedPythonMustBeExecutable() {
        var c = Configuration()
        c.repository = "/tmp/repo"
        c.python = "/nonexistent/interpreter"
        XCTAssertEqual(c.launchIssue, "Choose an executable Python interpreter.")
        c.python = ""
        XCTAssertEqual(c.launchIssue, "Choose a project Python with capstone, lz4.block and fontTools.")
    }

    func testConfirmationCarriesInterpreterAndDependencyVersions() throws {
        let json = """
        {"execution_allowed": true, "disabled_reason": "", "fingerprint": "f", "task_directory": "/t",
         "artifact_path": "/t/build/FIFA 23.app", "git_sha": "s", "inputs": {}, "shader": {},
         "program_version": "v0", "shader_source_versions": ["v0"], "estimated_bytes": 1,
         "free_bytes": 2, "cleanup": "",
         "interpreter": {"executable": "/fixture/venv/bin/python3",
                         "realpath": "/fixture/base/bin/python3.13", "version": "3.13.12",
                         "implementation": "CPython", "cache_tag": "cpython-313", "prefix": "/fixture/venv",
                         "dependencies": {
                            "capstone": {"available": true, "version": "5.0.7", "distribution": "5.0.9"},
                            "lz4.block": {"available": true, "version": "4.4.5", "distribution": "4.4.5"},
                            "fontTools": {"available": true, "version": "4.67.0", "distribution": "4.67.0"}},
                         "missing": []}}
        """
        let review = try JSONDecoder().decode(BuildReview.self, from: Data(json.utf8))
        let interpreter = try XCTUnwrap(review.interpreter)
        XCTAssertEqual(interpreter.realpath, "/fixture/base/bin/python3.13")
        XCTAssertTrue(interpreter.summary.contains("3.13.12"))
        XCTAssertTrue(interpreter.summary.contains("capstone 5.0.7"))
        XCTAssertTrue(interpreter.summary.contains("CPython"))
        XCTAssertTrue(interpreter.missing.isEmpty)
    }

    func testReviewWithoutInterpreterStillDecodes() throws {
        let json = """
        {"execution_allowed": false, "disabled_reason": "stale", "fingerprint": "f", "task_directory": "/t",
         "artifact_path": "/t/a", "git_sha": "s", "inputs": {}, "shader": {}, "program_version": "v0",
         "shader_source_versions": ["v0"], "estimated_bytes": 1, "free_bytes": 2, "cleanup": ""}
        """
        let review = try JSONDecoder().decode(BuildReview.self, from: Data(json.utf8))
        XCTAssertNil(review.interpreter)
    }

    func testMissingDependencyIsNamedInTheSummary() {
        let interpreter = InterpreterIdentity(
            executable: "/fixture/bin/python3", realpath: "/fixture/bin/python3.13", version: "3.13.0",
            implementation: "CPython",
            dependencies: ["capstone": .init(available: true, version: "5.0.7", distribution: "5.0.9"),
                           "lz4.block": .init(available: false, version: nil, distribution: nil)],
            missing: ["lz4.block"])
        XCTAssertTrue(interpreter.summary.contains("lz4.block missing"))
        XCTAssertTrue(interpreter.summary.contains("capstone 5.0.7"))
    }

    func testNoUserFacingEASFKeyInputRemains() {
        // The EASF key is discovered by the build itself; no action may ask the
        // user for one, and no such flag may reach the bridge again.
        var command = Configuration()
        command.base = "/tmp/a.xci"
        command.keys = "/tmp/prod.keys"
        command.output = "/tmp/output"
        for action in ["identify", "inspect", "plan", "check", "review", "execute"] {
            let args = command.arguments(action: action)
            XCTAssertFalse(args.contains("--easf-key-file"), action)
            XCTAssertFalse(args.contains { $0.lowercased().contains("easf") }, action)
        }
    }

    func testOutputSuggestionIsTheFolderContainingTheGameFile() {
        XCTAssertEqual(Configuration.suggestedOutput(forBase: "/Game/fifa23/gameresource/x.xci"),
                       "/Game/fifa23/gameresource")
        XCTAssertEqual(Configuration.suggestedOutput(forBase: ""), "")
        XCTAssertEqual(Configuration.suggestedOutput(forBase: "/x.xci"), "")
    }

    func testUnsupportedOptionsStayVisibleButDisabled() {
        XCTAssertEqual(Configuration.targetOptions.map(\.id), ["macos", "ios"])
        XCTAssertEqual(Configuration.modeOptions.map(\.id), ["nsp", "directory"])
        XCTAssertTrue(Configuration.targetOptions.allSatisfy { !$0.title.isEmpty && !$0.note.isEmpty })
        XCTAssertTrue(Configuration.targetOptions.allSatisfy(\.supported))
        XCTAssertTrue(Configuration.modeOptions.allSatisfy(\.supported))
        var c = Configuration(); c.targets = ["macos"]; c.mode = "nsp"
        XCTAssertNil(c.capabilityIssue)
        c.targets = ["ios"]
        XCTAssertNil(c.capabilityIssue)
        c.targets = []
        XCTAssertEqual(c.capabilityIssue, "Select at least one target platform.")
    }

    func testPlatformsAreABatchInCanonicalOrder() throws {
        XCTAssertEqual(Configuration.normalized(["ios", "macos"]), ["macos", "ios"])
        XCTAssertEqual(Configuration.normalized(["ios"]), ["ios"])
        XCTAssertEqual(Configuration.normalized(["ios", "ios"]), ["ios"])
        XCTAssertEqual(Configuration.normalized([]), [])
        XCTAssertEqual(Configuration.normalized(["android"]), [], "an unknown platform is never offered")
        var c = Configuration()
        c.targets = ["ios", "macos"]
        XCTAssertEqual(c.orderedTargets, ["macos", "ios"])
    }

    func testLegacySingleTargetSettingsBecomeAOneEntryBatch() throws {
        let legacy = #"{"repository":"/tmp/repo","python":"/tmp/py","target":"ios","mode":"nsp"}"#
        let decoded = try JSONDecoder().decode(Configuration.self, from: Data(legacy.utf8))
        XCTAssertEqual(decoded.targets, ["ios"])
        XCTAssertEqual(decoded.orderedTargets, ["ios"])
        let current = try JSONDecoder().decode(Configuration.self, from: JSONEncoder().encode(decoded))
        XCTAssertEqual(current, decoded)
    }

    func testEachPlatformGetsItsOwnTargetArgumentAndTheAddOnFolder() {
        var c = Configuration()
        c.repository = "/tmp/repo"
        c.targets = ["macos", "ios"]
        c.mode = "directory"
        c.romfs = "/game/RomFS"
        c.aoc = "/game/aoc"
        let mac = c.arguments(action: "check", target: "macos")
        let ios = c.arguments(action: "check", target: "ios")
        XCTAssertEqual(mac[mac.firstIndex(of: "--target")! + 1], "macos")
        XCTAssertEqual(ios[ios.firstIndex(of: "--target")! + 1], "ios")
        XCTAssertEqual(ios[ios.firstIndex(of: "--mode")! + 1], "directory")
        XCTAssertEqual(ios[ios.firstIndex(of: "--aoc")! + 1], "/game/aoc")
        XCTAssertEqual(ios[ios.firstIndex(of: "--romfs")! + 1], "/game/RomFS")
        // Without an explicit platform the first of the batch is used.
        XCTAssertEqual(c.arguments(action: "identify")[1], "identify")
        XCTAssertEqual(c.arguments(action: "identify")[3], "macos")
    }

    func testDirectoryModeNeedsARomFSAndAddOnContentOnlyFitsAnIOSDirectoryBatch() {
        var c = Configuration()
        c.repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().path
        c.python = "/bin/sh"
        c.targets = ["macos"]
        c.mode = "directory"
        XCTAssertEqual(c.launchIssue, "Directory mode requires an extracted RomFS folder.")
        c.romfs = "/game/RomFS"
        XCTAssertNil(c.launchIssue)
        c.aoc = "/game/aoc"
        XCTAssertEqual(c.launchIssue, "DLC folders require iOS Directory mode; clear this input for other combinations.")
        c.targets = ["ios"]
        XCTAssertNil(c.launchIssue)
    }

    func testAddOnFolderIsRedactedAndPrivate() {
        var c = Configuration()
        c.aoc = "/game/dlc-aoc"
        XCTAssertTrue(c.privatePaths.contains("/game/dlc-aoc"))
        XCTAssertFalse(c.redacted("error at /game/dlc-aoc").contains("/game/dlc-aoc"))
    }
}
