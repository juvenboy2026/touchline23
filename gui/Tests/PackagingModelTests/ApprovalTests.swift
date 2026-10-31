import XCTest
@testable import PackagingModel

final class ApprovalTests: XCTestCase {
    private let fingerprint = String(repeating: "ab", count: 32)

    private func review(fingerprint: String? = nil, task: String = "/game/gui-task-build-fixture",
                        realpath: String = "/fixture/base/bin/python3.13",
                        inputs: [String: String] = ["base": "FIFA.xci; bytes=1"],
                        title: String = "01001C8016B4E000",
                        allowed: Bool = true) -> BuildReview {
        BuildReview(execution_allowed: allowed, disabled_reason: allowed ? "" : "stale",
                    fingerprint: fingerprint ?? self.fingerprint, task_directory: task,
                    artifact_path: task + "/build/FIFA 23.app", git_sha: String(repeating: "c", count: 40),
                    interpreter: InterpreterIdentity(
                        executable: "/fixture/venv/bin/python3", realpath: realpath, version: "3.13.12",
                        implementation: "CPython",
                        dependencies: ["capstone": .init(available: true, version: "5.0.7", distribution: "5.0.9"),
                                       "lz4.block": .init(available: true, version: "4.4.5", distribution: "4.4.5"),
                                       "fontTools": .init(available: true, version: "4.67.0", distribution: "4.67.0")],
                        missing: []),
                    identified: IdentifiedGame(title_id: title, game: "FIFA 23 Legacy Edition"),
                    inputs: inputs, shader: ["chain": "a885c56c665a", "inputs": "18ce7e6ceb94", "shader_count": "386"],
                    program_version: "v0", shader_source_versions: ["v0"],
                    estimated_bytes: 8 << 30, free_bytes: 694 << 30, cleanup: "")
    }

    func testConfirmationShowsTheCompleteFingerprintAndItsTask() {
        let r = review()
        var c = Configuration()
        c.base = "/game/FIFA.xci"
        let text = ConfirmationSheet.text(review: r, configuration: c)
        XCTAssertTrue(text.contains(fingerprint), "the sheet must carry the full SHA-256")
        XCTAssertTrue(text.contains("Review fingerprint (SHA-256): " + fingerprint))
        XCTAssertTrue(text.contains(r.task_directory))
        XCTAssertTrue(text.contains("3.13.12"))
        XCTAssertTrue(text.contains("capstone 5.0.7"))
        XCTAssertTrue(text.contains("Game: FIFA 23 Legacy Edition (01001C8016B4E000)"))
        XCTAssertTrue(text.contains("Confirm this real build?"))
    }

    func testChangedIdentityInvalidatesEvenWithTheSameFingerprint() {
        let approval = Approval(review: review())
        XCTAssertFalse(approval.matches(review(title: "01001C8016B4E800")))
    }

    func testTheSheetIsTheOnlyPlaceThatShowsTheFingerprint() {
        // The general redaction rule must stay untouched: this is a dedicated
        // display field, not a weakened rule.
        var c = Configuration()
        c.keys = "/private/prod.keys"
        XCTAssertEqual(c.redacted(fingerprint), "<redacted-digest-or-key>")
        XCTAssertEqual(c.redacted("fingerprint=" + fingerprint).contains(fingerprint), false)
        XCTAssertTrue(ConfirmationSheet.fingerprintLine(review()).contains(fingerprint))
    }

    func testIdenticalReviewKeepsTheApprovalValid() {
        let r = review()
        XCTAssertTrue(Approval(review: r).matches(r))
    }

    func testAnyChangedFingerprintInvalidatesTheApproval() {
        let approval = Approval(review: review())
        XCTAssertFalse(approval.matches(review(fingerprint: String(repeating: "ef", count: 32))))
        XCTAssertFalse(Approval(review: review()).matches(review(fingerprint: "")))
    }

    func testChangedInterpreterInvalidatesEvenWithTheSameFingerprint() {
        let approval = Approval(review: review())
        XCTAssertFalse(approval.matches(review(realpath: "/other/base/bin/python3.13")))
    }

    func testChangedInputInvalidatesEvenWithTheSameFingerprint() {
        let approval = Approval(review: review())
        XCTAssertFalse(approval.matches(review(inputs: ["base": "FIFA.xci; bytes=2"])))
        XCTAssertFalse(approval.matches(review(inputs: [:])))
    }

    func testChangedTaskDirectoryInvalidatesEvenWithTheSameFingerprint() {
        let approval = Approval(review: review())
        XCTAssertFalse(approval.matches(review(task: "/game/gui-task-build-other")))
        XCTAssertEqual(approval.taskDirectory, "/game/gui-task-build-fixture")
    }

    func testReviewThatNoLongerAllowsExecutionInvalidatesTheApproval() {
        XCTAssertFalse(Approval(review: review()).matches(review(allowed: false)))
    }

    func testApprovalIsNotConfusedByShaderChanges() {
        var changed = review()
        changed.shader["chain"] = "b00000000000"
        XCTAssertFalse(Approval(review: review()).matches(changed))
    }

    func testPlatformChangeInvalidatesEvenWithTheSameFingerprint() {
        var mac = review()
        mac.target = "macos"
        var ios = review()
        ios.target = "ios"
        XCTAssertFalse(Approval(review: mac).matches(ios))
    }

    private func batch() -> [PreparedBuild] {
        var mac = review(); mac.target = "macos"
        var ios = review(fingerprint: String(repeating: "cd", count: 32), task: "/game/gui-task-build-ios")
        ios.target = "ios"
        ios.artifact_path = "/game/FIFA 23.ipa"
        return [PreparedBuild(target: "macos", review: mac), PreparedBuild(target: "ios", review: ios)]
    }

    func testBatchSheetStatesTheOrderEveryTargetAndEveryFingerprint() {
        var c = Configuration()
        c.targets = ["macos", "ios"]
        c.base = "/game/FIFA.xci"
        let items = batch()
        let text = ConfirmationSheet.text(batch: items, configuration: c)
        XCTAssertTrue(text.contains("Build 2 target(s) in order"))
        XCTAssertTrue(text.contains("macOS App · External XCI / NSP → iOS IPA · External XCI / NSP"))
        XCTAssertTrue(text.contains("If a target fails or is cancelled, later targets will not start"))
        for item in items {
            XCTAssertTrue(text.contains(item.review.fingerprint), "each fingerprint is shown in full")
            XCTAssertTrue(text.contains(item.review.task_directory))
        }
        XCTAssertTrue(text.contains("/game/FIFA 23.ipa"))
        XCTAssertEqual(text.components(separatedBy: "Confirm this real build?").count - 1, 1,
                       "the sheet asks once for the whole batch")
    }

    func testPartialBatchSaysHowManyOfTheSelectedTargetsWillBuild() {
        var c = Configuration()
        c.targets = ["macos", "ios"]
        c.base = "/game/FIFA.xci"
        var mac = review(); mac.target = "macos"
        let text = ConfirmationSheet.text(batch: [PreparedBuild(target: "macos", review: mac)],
                                          configuration: c)
        XCTAssertTrue(text.contains("Build 1 target(s) in order"))
        XCTAssertTrue(text.contains("2 selected; failed targets are excluded."))
        XCTAssertFalse(text.contains("Confirm this real build?\n\nConfirm this real build?"))
    }

    func testPreparedBuildRequiresItsReviewStillAllowingExecution() {
        var mac = review(); mac.target = "macos"
        XCTAssertTrue(PreparedBuild(target: "macos", review: mac).isApprovable)
        XCTAssertFalse(PreparedBuild(target: "macos", review: review(allowed: false)).isApprovable)
    }
    func testBothConfirmationLanguagesKeepApprovalAndReviewBytesUnchanged() throws {
        let r = review()
        let approval = Approval(review: r)
        var c = Configuration(); c.base = "/game/FIFA.xci"
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let before = try encoder.encode(r)
        let english = ConfirmationSheet.text(review: r, configuration: c)
        let chinese = ConfirmationSheet.text(review: r, configuration: c, language: .simplifiedChinese)
        XCTAssertTrue(english.contains("Confirm this real build?"))
        XCTAssertTrue(chinese.contains("是否确认执行这一次真实构建？"))
        XCTAssertTrue(chinese.contains("审核指纹（SHA-256）：" + fingerprint))
        XCTAssertEqual(ConfirmationSheet.text(review: r, configuration: c), english)
        XCTAssertTrue(approval.matches(r))
        XCTAssertEqual(try encoder.encode(r), before)
    }

    func testCompactSummaryShowsSixFieldsWithoutDiagnosticsOrDuplicateTargets() {
        let items = batch()
        var c = Configuration(); c.targets = ["macos", "ios"]
        c.base = "/game/FIFA.xci"; c.keys = "/private/prod.keys"; c.output = "/game/output"
        let value = ConfirmationPresentation(batch: items, configuration: c, identity: nil,
                                             catalog: nil, language: .english)
        XCTAssertEqual(value.summary.map(\.id), ["game", "version", "targets", "mode", "shader", "output"])
        XCTAssertEqual(value.summary.first { $0.id == "targets" }?.value, "macOS App · iOS IPA")
        let text = value.summary.map(\.value).joined(separator: "\n")
        for technical in [c.base, c.keys, fingerprint, "Python", "01001C8016B4E000", items[0].review.task_directory] {
            XCTAssertFalse(text.contains(technical), technical)
        }
        XCTAssertEqual(value.details.filter { $0.id == "base" }.count, 1)
        for item in items { XCTAssertTrue(value.details.contains { $0.value.contains(item.review.fingerprint) }) }
    }

    func testSummaryUsesOnlyApprovedTargetsAndDoesNotGuessDisplayVersions() {
        var c = Configuration(); c.targets = ["macos", "ios"]
        let value = ConfirmationPresentation(batch: [batch()[0]], configuration: c, identity: nil,
                                             catalog: nil, language: .english)
        XCTAssertEqual(value.summary.first { $0.id == "targets" }?.value, "macOS App")
        XCTAssertEqual(value.summary.first { $0.id == "version" }?.value, "v0")
        XCTAssertFalse(value.summary.contains { $0.value == "1.0.0" })
    }

    func testSummaryUsesMatchingIdentityAndRealShaderPlanInBothLanguages() throws {
        var r = review(); r.prepared_shader = ["action": "generate", "cache": "/cache/new"]
        let identity = GameIdentity(ok: true, kind: "base", title_hex: "01001C8016B4E000",
                                    name: "FIFA 23", message: "", program_version: "v0", display_version: "1.0.0")
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let before = try encoder.encode(r)
        for language in [InterfaceLanguage.english, .simplifiedChinese] {
            let value = ConfirmationPresentation(batch: [PreparedBuild(target: "macos", review: r)],
                configuration: Configuration(), identity: identity, catalog: nil, language: language)
            XCTAssertEqual(value.summary.first { $0.id == "version" }?.value, "1.0.0")
            XCTAssertEqual(value.summary.first { $0.id == "shader" }?.value,
                           GUIText(key: "Generation required").render(language))
            XCTAssertTrue(Approval(review: r).matches(r))
        }
        XCTAssertEqual(try encoder.encode(r), before)
    }

    func testMixedShaderTargetsAndStaleIdentityAreDisplayedAccurately() {
        var mac = review(); mac.prepared_shader = ["action":"reuse"]
        var ios = review(); ios.prepared_shader = ["action":"generate"]
        let stale = GameIdentity(ok: true, kind: "base", title_hex: "different", message: "",
                                 program_version: "v0", display_version: "9.9.9")
        let value = ConfirmationPresentation(batch: [PreparedBuild(target:"macos",review:mac), PreparedBuild(target:"ios",review:ios)],
            configuration: Configuration(), identity: stale, catalog: nil, language: .english)
        XCTAssertEqual(value.summary.first { $0.id == "version" }?.value, "v0")
        XCTAssertEqual(value.summary.first { $0.id == "shader" }?.value, "macOS App: Reuse cache · iOS IPA: Generation required")
    }

}
