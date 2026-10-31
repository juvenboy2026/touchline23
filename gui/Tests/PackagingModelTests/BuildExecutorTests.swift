import XCTest
import Combine
import Darwin
@testable import PackagingModel

final class BuildExecutorTests: XCTestCase {
    private var root: URL!
    private var sawLiveLog = false
    private var repo: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("executor-fixture-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    }
    override func tearDownWithError() throws {
        // This suite exclusively owns this newly created synthetic fixture root.
        if let root { try FileManager.default.removeItem(at: root) }
    }
    @MainActor private func run(_ mode: String, executable: String = "/usr/bin/python3", cancel: Bool = false,
                                audit: Bool = false, secret: String = "") -> (BuildExecutor, BuildRecord, [BuildState]) {
        let executor = BuildExecutor(supervisorPython: "/usr/bin/python3", supervisorScript: repo.appendingPathComponent("scripts/packaging_supervisor.py").path)
        let task = root.appendingPathComponent("gui-task-" + UUID().uuidString)
        var env = ["PATH": "/usr/bin:/bin", "PYTHONDONTWRITEBYTECODE": "1", "PYTHONUNBUFFERED": "1"]
        env["TMPDIR"] = root.path
        let command = BuildCommand(executable: executable,
            arguments: [repo.appendingPathComponent("gui/TestSupport/mock_task.py").path, mode,
                        "--root", task.path, "--secret", secret], environment: env, directory: root, stage: mode)
        let job = BuildJob(directory: task, commands: [command], redactions: [secret], requiresAudit: audit)
        let finished = expectation(description: "task finalized")
        var result: BuildRecord?, states: [BuildState] = []
        let subscription = executor.$state.sink { states.append($0) }
        let logs = executor.$logText.sink { if $0.contains("tick 0") && executor.state.isActive { self.sawLiveLog = true } }
        Task { result = await executor.execute(job); finished.fulfill() }
        if cancel {
            // Wait until the child has created its marker, then cancel the group.
            func attempt(_ remaining: Int) {
                let marker = mode == "ignore" ? "child-ready" : "parent.pid"
                if FileManager.default.fileExists(atPath: task.appendingPathComponent(marker).path) || remaining == 0 { executor.cancel() }
                else { DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { attempt(remaining - 1) } }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { attempt(50) }
        }
        wait(for: [finished], timeout: 12)
        withExtendedLifetime((subscription, logs)) {}
        return (executor, result!, states)
    }
    @MainActor func testNormalExitAndHistoryRecovery() throws {
        let (_, result, states) = run("success")
        XCTAssertEqual(result.state, .succeeded); XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(states.contains(.running)); XCTAssertTrue(states.contains(.succeeded))
        let history = try BuildHistory.load(from: root)
        XCTAssertEqual(history.count, 1); XCTAssertEqual(history[0].id, result.id)
        XCTAssertFalse(history[0].gameRunVerified)
    }
    @MainActor func testContinuousLogsArriveBeforeExit() {
        let (executor, result, _) = run("logs")
        XCTAssertEqual(result.state, .succeeded)
        XCTAssertTrue(executor.logText.contains("tick 0")); XCTAssertTrue(executor.logText.contains("tick 4"))
        XCTAssertTrue(sawLiveLog, "Output must arrive while the task is still running")
    }
    @MainActor func testStderrIsCaptured() {
        let (executor, result, _) = run("stderr")
        XCTAssertEqual(result.state, .succeeded); XCTAssertTrue(executor.logText.contains("[stderr] synthetic warning"))
    }
    @MainActor func testNonzeroExitAndState() {
        let (_, result, states) = run("fail")
        XCTAssertEqual(result.state, .failed); XCTAssertEqual(result.exitCode, 23)
        XCTAssertTrue(states.contains(.failed))
    }
    @MainActor func testMissingExecutable() {
        let (_, result, _) = run("success", executable: root.appendingPathComponent("missing").path)
        XCTAssertEqual(result.state, .failed); XCTAssertNotNil(result.error)
    }
    @MainActor func testAbnormalSignalExit() {
        let (_, result, _) = run("signal")
        XCTAssertEqual(result.state, .failed); XCTAssertEqual(result.termination, "signal")
        XCTAssertEqual(result.exitCode, -SIGTERM)
    }
    @MainActor func testLongTaskCancellationAndState() {
        let (_, result, states) = run("long", cancel: true)
        XCTAssertEqual(result.state, .cancelled); XCTAssertTrue(states.contains(.cancelling))
        XCTAssertLessThan(result.duration, 5)
    }
    private func assertNotRunning(_ file: URL, fileName: StaticString = #filePath, line: UInt = #line) throws {
        let pid = try String(contentsOf: file, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        let heartbeat = file.deletingLastPathComponent().appendingPathComponent(pid + ".heartbeat")
        let before = try? Data(contentsOf: heartbeat)
        Thread.sleep(forTimeInterval: 0.3)
        XCTAssertEqual(try? Data(contentsOf: heartbeat), before, "Descendant continues working: \(pid)", file: fileName, line: line)
        // macOS can retain an orphan zombie until launchd reaps it. kill(0)
        // cannot distinguish that state, and sandboxed ps is unavailable.
        if Darwin.kill(Int32(pid)!, 0) == -1 { XCTAssertEqual(errno, ESRCH, file: fileName, line: line) }
    }
    @MainActor func testCancellationStopsParentAndIgnoringChild() throws {
        let (_, result, _) = run("tree", cancel: true)
        XCTAssertEqual(result.state, .cancelled)
        let directory = URL(fileURLWithPath: result.taskDirectory)
        try assertNotRunning(directory.appendingPathComponent("parent.pid"))
        try assertNotRunning(directory.appendingPathComponent("child.pid"))
    }
    @MainActor func testNormalLeaderExitCleansOrphanChild() throws {
        let (_, result, _) = run("orphan")
        XCTAssertEqual(result.state, .succeeded)
        try assertNotRunning(URL(fileURLWithPath: result.taskDirectory).appendingPathComponent("child.pid"))
    }
    @MainActor func testSplitSecretsAreNeverDisplayedOrPersisted() throws {
        let secret = "/synthetic/private key file.keys"
        let (executor, result, _) = run("secret", secret: secret)
        let log = try String(contentsOfFile: result.logPath, encoding: .utf8)
        XCTAssertFalse(log.contains(secret)); XCTAssertFalse(executor.logText.contains(secret))
        XCTAssertFalse(log.contains("00112233445566778899aabbccddeeff"))
        XCTAssertFalse(try String(contentsOfFile: result.taskDirectory + "/result.json", encoding: .utf8).contains(secret))
    }
    @MainActor func testAuditedArtifactIsRecordedSeparatelyFromRuntime() {
        let (_, result, _) = run("artifact", audit: true)
        XCTAssertEqual(result.state, .succeeded); XCTAssertEqual(result.artifact?.sha256.count, 64)
        XCTAssertFalse(result.gameRunVerified); XCTAssertFalse(result.artifact!.game_run_verified)
    }
    @MainActor func testMissingAuditDoesNotBecomeBuildSuccess() {
        let (_, result, _) = run("success", audit: true)
        XCTAssertEqual(result.state, .failed)
    }
    @MainActor func testIncompleteHistoryRestoresAsInterruptedWithoutRewriting() throws {
        let (_, record, _) = run("success")
        var unfinished = record; unfinished.state = .running; unfinished.finished = nil
        let url = URL(fileURLWithPath: record.taskDirectory).appendingPathComponent("result.json")
        let data = try JSONEncoder().encode(unfinished); try data.write(to: url)
        XCTAssertEqual(try BuildHistory.load(from: root)[0].state, .interrupted)
        XCTAssertEqual(try Data(contentsOf: url), data)
    }
    @MainActor func testExistingTaskDirectoryIsNotOverwritten() throws {
        let marker = root.appendingPathComponent("keep.txt"); try Data("keep".utf8).write(to: marker)
        let executor = BuildExecutor(supervisorPython: "/usr/bin/python3", supervisorScript: repo.appendingPathComponent("scripts/packaging_supervisor.py").path)
        let finished = expectation(description: "refused existing directory")
        var result: BuildRecord?
        Task { result = await executor.execute(BuildJob(directory: root, commands: [])); finished.fulfill() }
        wait(for: [finished], timeout: 4)
        XCTAssertEqual(result?.state, .failed)
        XCTAssertEqual(try String(contentsOf: marker, encoding: .utf8), "keep")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("result.json").path))
    }
    @MainActor func testFoundationLaunchFailureFinalizesHistory() throws {
        let executor = BuildExecutor(supervisorPython: root.appendingPathComponent("missing-python").path, supervisorScript: "unused")
        let directory = root.appendingPathComponent("gui-task-launch-error")
        let command = BuildCommand(executable: "/usr/bin/true", arguments: [], environment: [:], directory: root, stage: "launch")
        let finished = expectation(description: "foundation failure")
        var result: BuildRecord?
        Task { result = await executor.execute(BuildJob(directory: directory, commands: [command])); finished.fulfill() }
        wait(for: [finished], timeout: 4)
        XCTAssertEqual(result?.state, .failed); XCTAssertNotNil(result?.error)
        XCTAssertEqual(try BuildHistory.load(from: root).first?.state, .failed)
    }
    @MainActor func testBurstOutputKeepsFullDiskLogAndBoundedDisplay() throws {
        let (executor, record, _) = run("burst")
        XCTAssertEqual(record.state, .succeeded)
        let log = try String(contentsOfFile: record.logPath, encoding: .utf8)
        XCTAssertTrue(log.contains("burst-0 ")); XCTAssertTrue(log.contains("burst-9999 "))
        XCTAssertTrue(executor.logText.contains("burst-9999 "))
        XCTAssertLessThanOrEqual(executor.logText.utf8.count, 262144)
    }
    @MainActor func testIgnoringLeaderRequiresKillEscalation() {
        let (_, record, _) = run("ignore", cancel: true)
        XCTAssertEqual(record.state, .cancelled)
        XCTAssertEqual(record.exitCode, -SIGKILL)
    }
    @MainActor func testScratchLocationsAndRevisionMetadata() throws {
        let (_, record, _) = run("environment")
        XCTAssertEqual(record.state, .succeeded); XCTAssertEqual(record.context.gitSHA, String(repeating: "a", count: 40))
        let data = try Data(contentsOf: URL(fileURLWithPath: record.taskDirectory).appendingPathComponent("environment.json"))
        let env = try JSONDecoder().decode([String: String].self, from: data)
        for value in env.values { XCTAssertTrue(value.hasPrefix(record.taskDirectory + "/tmp")) }
    }
}
