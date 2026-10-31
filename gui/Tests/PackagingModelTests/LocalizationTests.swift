import XCTest
import Combine
@testable import PackagingModel

final class LocalizationTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    override func setUp() {
        suite = "org.nxnative.localization-test." + UUID().uuidString
        defaults = UserDefaults(suiteName: suite)!
    }
    override func tearDown() { defaults.removePersistentDomain(forName: suite) }

    @MainActor func testFirstLaunchFollowsSystemAndUnknownSavedChoiceReturnsToSystem() {
        XCTAssertEqual(LanguagePreferences(defaults: defaults).language, .system)
        defaults.set("unsupported", forKey: LanguagePreferences.key)
        XCTAssertEqual(LanguagePreferences(defaults: defaults).language, .system)
        XCTAssertEqual(InterfaceLanguage.system.resolve(preferred: ["zh-Hans-CN"]), .simplifiedChinese)
        XCTAssertEqual(InterfaceLanguage.system.resolve(preferred: ["en-US"]), .english)
        XCTAssertEqual(InterfaceLanguage.system.resolve(preferred: ["fr-FR", "zh-Hans"]), .english)
        XCTAssertEqual(InterfaceLanguage.system.resolve(preferred: ["zh-Hant-TW"]), .english)
        XCTAssertEqual(InterfaceLanguage.english.resolve(preferred: ["zh-CN"]), .english)
    }
    @MainActor func testSystemSelectionPersistsAndLauncherPreferenceIsIndependent() {
        let launcher = LanguagePreferences(defaults: defaults, key: "launcher.interface-language.v1")
        launcher.language = .simplifiedChinese
        let packaging = LanguagePreferences(defaults: defaults)
        packaging.language = .english
        XCTAssertEqual(LanguagePreferences(defaults: defaults, key: "launcher.interface-language.v1").language, .simplifiedChinese)
        packaging.language = .system
        XCTAssertEqual(LanguagePreferences(defaults: defaults).language, .system)
    }
    func testDLCDiscoveryDoesNotPresentStaleOrUnverifiedCounts() {
        func text(_ external: Bool, _ busy: Bool, _ verified: Bool, _ count: Int?) -> String {
            DLCDiscoveryText.summary(external: external, busy: busy, verified: verified, count: count).render(.english)
        }
        XCTAssertEqual(text(true, false, true, 0), "DLC verified before launch: 0")
        XCTAssertEqual(text(true, false, true, 5), "DLC verified before launch: 5")
        XCTAssertEqual(text(true, true, true, 5), "Scanning DLC…")
        XCTAssertEqual(text(true, false, false, 5), "DLC discovery is not verified. Check the resource diagnostics.")
        XCTAssertEqual(text(true, false, true, nil), text(true, false, false, nil))
        XCTAssertEqual(text(false, false, true, 5), "Bundled DLC cannot be verified here; availability is checked at runtime.")
        XCTAssertEqual(DLCDiscoveryText.summary(external: true, busy: false, verified: true, count: 5).render(.simplifiedChinese), "启动前已通过校验的 DLC：5")
    }
    @MainActor func testBothSwitchDirectionsPersistAcrossRestart() {
        let language = LanguagePreferences(defaults: defaults)
        language.language = .simplifiedChinese
        XCTAssertEqual(LanguagePreferences(defaults: defaults).language, .simplifiedChinese)
        language.language = .english
        XCTAssertEqual(LanguagePreferences(defaults: defaults).language, .english)
    }
    func testLauncherTemplatesPreserveTechnicalValuesAndTranslateChrome() {
        XCTAssertEqual(GUIText.launcher("Version 1.0.3", language: .simplifiedChinese), "版本 1.0.3")
        XCTAssertEqual(GUIText.launcher("/game/input.nsp", language: .simplifiedChinese), "/game/input.nsp")
        XCTAssertTrue(GUIText.filesHint("My Game").render(.simplifiedChinese).contains("My Game"))
        for key in ["Show virtual controller", "Show right stick in 3D mode", "Resource diagnostics", "Interface language"] {
            XCTAssertNotEqual(GUIText(key: key).render(.english), GUIText(key: key).render(.simplifiedChinese))
        }
    }
    func testMainLabelsAndDialogsRefreshInBothLanguages() {
        let labels: [(GUIText, String, String)] = [
            ("Touchline 23 Packaging", "Touchline 23 Packaging", "Touchline 23 打包工具"),
            ("Check configuration", "Check configuration", "检查配置"),
            ("Confirm a real build", "Confirm a real build", "确认一次真实构建"),
            ("Build now", "Build now", "确认执行"),
            ("Task history", "Task history", "任务历史"),
            ("Cancel task", "Cancel task", "取消任务")]
        for (key, english, chinese) in labels {
            XCTAssertEqual(key.render(.english), english)
            XCTAssertEqual(key.render(.simplifiedChinese), chinese)
            XCTAssertEqual(key.render(.english), english)
        }
    }
    func testInterpolationKeepsRawTechnicalValuesAndTranslatesNestedLabels() {
        let path = "/game/原始数据 %@.xci"
        let message: GUIText = "Base: \(path)"
        XCTAssertEqual(message.render(.english), "Base: " + path)
        XCTAssertEqual(message.render(.simplifiedChinese), "本体：" + path)
        let status: GUIText = "Running · \(GUIText.stage("rewrite-main"))"
        XCTAssertEqual(status.render(.english), "Running · Rewrite main program")
        XCTAssertEqual(status.render(.simplifiedChinese), "运行中 · 重写主程序")
        XCTAssertEqual(GUIText(key: "A future English fallback").render(.simplifiedChinese), "A future English fallback")
    }
    @MainActor func testSwitchDoesNotChangeSavedConfigurationOrBuildArguments() throws {
        var configuration = Configuration()
        configuration.base = "/game/base.xci"; configuration.keys = "/game/prod.keys"
        configuration.targets = ["macos", "ios"]; configuration.mode = "directory"
        configuration.romfs = "/game/RomFS"; configuration.cache = "/game/cache"
        let saved = try JSONEncoder().encode(configuration)
        defaults.set(saved, forKey: "packaging.paths.v1")
        let args = configuration.arguments(action: "execute", target: "ios")
        let language = LanguagePreferences(defaults: defaults)
        for selection in [InterfaceLanguage.simplifiedChinese, .english] {
            language.language = selection
            XCTAssertEqual(configuration.arguments(action: "execute", target: "ios"), args)
            XCTAssertEqual(defaults.data(forKey: "packaging.paths.v1"), saved)
            XCTAssertEqual(try JSONDecoder().decode(Configuration.self, from: saved), configuration)
        }
    }
    func testAboutSheetStringsTranslateAndNameThisProject() {
        let notes = [
            "Touchline 23 is an independent community project and is not affiliated with or endorsed by EA SPORTS, Nintendo, or their affiliates.",
            "The open-source license applies only to the project code explicitly covered by the license. It does not grant rights to game content, firmware, keys, or other third-party assets.",
            "Please use the official GitHub repository for project information. Beware of unauthorized paid IPA resales or unofficial repackaged builds.",
        ]
        for key in ["About Touchline 23", "Project home", "Report an issue"] + notes {
            XCTAssertEqual(GUIText(key: key).render(.english), key)
            XCTAssertNotEqual(GUIText(key: key).render(.simplifiedChinese), key, key)
            if key.hasPrefix("Touchline ") { XCTAssertTrue(GUIText(key: key).render(.simplifiedChinese).contains("Touchline 23"), key) }
        }
        XCTAssertEqual(GUIText(key: "About Touchline 23").render(.simplifiedChinese), "关于 Touchline 23")
        XCTAssertEqual(GUIText(key: "Project home").render(.simplifiedChinese), "项目主页")
        XCTAssertEqual(GUIText(key: "Report an issue").render(.simplifiedChinese), "问题反馈")
    }
    func testCatalogHasNoBlankTranslationsOrMismatchedArguments() {
        XCTAssertGreaterThan(GUIText.catalog.count, 150)
        for (english, chinese) in GUIText.catalog {
            XCTAssertFalse(english.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            XCTAssertFalse(chinese.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, english)
            XCTAssertEqual(english.components(separatedBy: "%@").count,
                           chinese.components(separatedBy: "%@").count, english)
        }
    }
    func testStageDisplayTranslatesWithoutMutatingSerializedPlan() throws {
        var progress = StageProgress(stages: [BuildStage(key: "rewrite-main", label: "重写主程序")])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let before = try encoder.encode(progress.stages)
        XCTAssertTrue(progress.headline.isEmpty, "a pending plan is not a running stage")
        progress.begin("rewrite-main")
        XCTAssertEqual(progress.headline(in: .english), "Stage 1 / 1: Rewrite main program")
        XCTAssertEqual(progress.headline(in: .simplifiedChinese), "第 1 / 1 阶段：重写主程序")
        XCTAssertEqual(try encoder.encode(progress.stages), before)
    }
    func testDynamicToolLabelsAndSimulationStageUseSelectedLanguage() {
        XCTAssertEqual(CheckLabel.localized("tool-xcrun", language: .english), "Tool: xcrun")
        XCTAssertEqual(CheckLabel.localized("tool-xcrun", language: .simplifiedChinese), "工具：xcrun")
        XCTAssertEqual(CheckLabel.localized("aoc", language: .simplifiedChinese), "附加内容")
        XCTAssertEqual(CheckLabel.localized("control-nacp", language: .english), "Control metadata")
        XCTAssertEqual(GUIText.stage("simulation-tree").render(.simplifiedChinese), "模拟任务")
    }
    @MainActor func testSwitchDuringRealExecutorRunKeepsProcessLogsAndAuditRecords() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("language-executor-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let executor = BuildExecutor(supervisorPython: "/usr/bin/python3", supervisorScript: repo.appendingPathComponent("scripts/packaging_supervisor.py").path)
        let language = LanguagePreferences(defaults: defaults)
        let command = BuildCommand(executable: "/usr/bin/python3",
            arguments: [repo.appendingPathComponent("gui/TestSupport/mock_task.py").path,"logs","--root",root.path],
            environment: ["PATH":"/usr/bin:/bin","PYTHONDONTWRITEBYTECODE":"1","PYTHONUNBUFFERED":"1"],
            directory: repo, stage: "simulation")
        let done = expectation(description: "executor survives switching")
        var toggled = false
        let watch = executor.$logText.sink { output in
            if output.contains("tick 0"), !toggled {
                toggled = true; language.language = .simplifiedChinese; language.language = .english
            }
        }
        Task {
            let result = await executor.execute(BuildJob(directory: root, commands: [command]))
            XCTAssertEqual(result?.state, .succeeded)
            XCTAssertEqual(result?.exitCode, 0)
            let log = try! Data(contentsOf: root.appendingPathComponent("task.log"))
            let record = try! Data(contentsOf: root.appendingPathComponent("result.json"))
            let audit = root.appendingPathComponent("audit.json")
            try! Data("{\"original\":true}".utf8).write(to: audit)
            language.language = .simplifiedChinese
            XCTAssertEqual(try! Data(contentsOf: root.appendingPathComponent("task.log")), log)
            XCTAssertEqual(try! Data(contentsOf: root.appendingPathComponent("result.json")), record)
            XCTAssertEqual(try! String(contentsOf: audit, encoding: .utf8), "{\"original\":true}")
            done.fulfill()
        }
        wait(for: [done], timeout: 10)
        XCTAssertTrue(toggled)
        withExtendedLifetime(watch) {}
    }
}
