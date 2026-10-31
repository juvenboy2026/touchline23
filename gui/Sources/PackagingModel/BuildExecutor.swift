import Foundation
import Combine
import Darwin

public enum BuildState: String, Codable, Sendable {
    case idle, starting, running, cancelling, succeeded, failed, cancelled, interrupted
    public var isActive: Bool { [.starting, .running, .cancelling].contains(self) }
}

public struct BuildCommand: Sendable {
    public var executable: String
    public var arguments: [String]
    public var environment: [String: String]
    public var directory: URL
    public var stage: String
    public init(executable: String, arguments: [String], environment: [String: String], directory: URL, stage: String) {
        self.executable = executable; self.arguments = arguments
        self.environment = environment; self.directory = directory; self.stage = stage
    }
}

public struct TaskContext: Codable, Sendable {
    public var kind: String
    public var gitSHA: String
    public var game: String
    public var titleID: String
    public var platform: String
    public var resourceMode: String
    public var inputs: [String: String]
    public var shader: [String: String]
    /// Runs started by one confirmation share this id, so the history and the
    /// result list can show that two artifacts came from one batch.
    public var batch: String? = nil
    public init(kind: String = "simulation", gitSHA: String = "unknown", game: String = "",
                titleID: String = "", platform: String = "simulation", resourceMode: String = "none",
                inputs: [String: String] = [:], shader: [String: String] = [:], batch: String? = nil) {
        self.kind = kind; self.gitSHA = gitSHA; self.game = game; self.titleID = titleID
        self.platform = platform; self.resourceMode = resourceMode; self.inputs = inputs; self.shader = shader
        self.batch = batch
    }
}

public struct ArtifactSummary: Codable, Sendable {
    public var path: String
    public var bytes: Int64
    public var sha256: String
    public var audit: [String: Bool]
    public var game_run_verified: Bool
}

public struct BuildRecord: Codable, Identifiable, Sendable {
    public var schema = 1
    public var id: String
    public var started: Date
    public var finished: Date?
    public var duration: TimeInterval
    public var state: BuildState
    public var stage: String
    public var exitCode: Int32?
    public var termination: String?
    public var error: String?
    public var context: TaskContext
    public var taskDirectory: String
    public var logPath: String
    public var commands: [[String]]
    public var artifact: ArtifactSummary?
    public var processGroupCleanupAttempted: Bool?
    /// Whether this run's temporary work folder was removed after a cancel or
    /// a signal exit. Absent for records written before cleanup existed.
    public var workDiscarded: Bool?
    /// Whether the run directory itself was archived into the log folder and
    /// then removed, leaving only the published App.
    public var archived: Bool?
    public var gameRunVerified = false
    public var deviceRunVerified = false
}

public struct BuildJob: Sendable {
    public var directory: URL
    public var commands: [BuildCommand]
    public var context: TaskContext
    public var redactions: [String]
    public var requiresAudit: Bool
    /// The stage plan the backend reported for this build, in execution order.
    public var stages: [BuildStage]
    /// Keeps this run's temporary work folder after a failure for diagnosis.
    public var keepWorkOnFailure: Bool
    /// Where the small permanent records (result, audit, log copies) are
    /// archived before the run directory is removed. nil keeps the directory.
    public var archiveRoot: URL?
    /// Folder name the Python side creates inside the run directory for the
    /// build itself. Only this folder is ever removed here.
    public static let workFolder = "work"
    public init(directory: URL, commands: [BuildCommand], context: TaskContext = TaskContext(),
                redactions: [String] = [], requiresAudit: Bool = false,
                stages: [BuildStage] = [], keepWorkOnFailure: Bool = false,
                archiveRoot: URL? = nil) {
        self.directory = directory; self.commands = commands; self.context = context
        self.redactions = redactions; self.requiresAudit = requiresAudit
        self.stages = stages; self.keepWorkOnFailure = keepWorkOnFailure
        self.archiveRoot = archiveRoot
    }
}

public struct LogRedactor: Sendable {
    public let paths: [String]
    public init(paths: [String]) { self.paths = paths.filter { !$0.isEmpty }.sorted { $0.count > $1.count } }
    public func apply(_ text: String) -> String {
        var result = text
        for path in paths { result = result.replacingOccurrences(of: path, with: "<private-path>") }
        result = result.replacingOccurrences(of: #"(?i)(?<![0-9a-f])[0-9a-f]{32,128}(?![0-9a-f])"#,
                                             with: "<redacted-key-or-digest>", options: .regularExpression)
        result = result.replacingOccurrences(of: #"(?i)(authorization|password|token|secret|aes[_-]?key)\s*[:=]\s*\S+"#,
                                             with: "$1=<redacted>", options: .regularExpression)
        return result
    }
}

private final class ProcessControl: @unchecked Sendable {
    private let lock = NSLock()
    private var group: Int32?
    private var process: Process?
    private var stopped = false
    private var done = false
    private var stageEnded = false
    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
    func attach(_ process: Process) { lock.lock(); self.process = process; group = nil; stageEnded = false; lock.unlock() }
    func ready(_ group: Int32) {
        lock.lock(); self.group = group; let cancel = stopped, ended = stageEnded; lock.unlock()
        if ended { signal(SIGKILL) } else if cancel { signal(SIGINT) }
    }
    func signal(_ value: Int32) {
        lock.lock(); defer { lock.unlock() }
        guard !done else { return }
        if let group, group > 1, group != getpgrp() { _ = Darwin.kill(-group, value) }
        else if let process, process.isRunning { process.terminate() }
    }
    func cancel() {
        lock.lock()
        if stopped || done { lock.unlock(); return }
        stopped = true; lock.unlock()
        signal(SIGINT)
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.6) { self.signal(SIGTERM) }
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.2) { self.signal(SIGKILL) }
    }
    func finish() {
        // A crashed supervisor must not leave its already identified group alive.
        signal(SIGKILL)
        lock.lock(); done = true; process = nil; lock.unlock()
    }
    func endStage() { lock.lock(); stageEnded = true; lock.unlock(); signal(SIGKILL) }
    func clearStage() { lock.lock(); group = nil; process = nil; lock.unlock() }
}

// Separate pipe readers feed a locked, line-oriented sink. Private strings split
// across read boundaries never reach display or disk before redaction.
private final class OutputSink: @unchecked Sendable {
    private let lock = NSLock()
    private var buffers: [String: Data] = [:]
    private var dropping: Set<String> = []
    private let token: String
    private let redactor: LogRedactor
    private let control: ProcessControl
    private let file: FileHandle
    private let emit: @Sendable (String, String?) -> Void
    var targetCode: Int32?
    var launchError: String?
    var cleanupError: String?
    var lastStage: String?
    var cleanupAttempted = false
    private(set) var writeError: String?
    init(token: String, redactor: LogRedactor, control: ProcessControl, file: FileHandle,
         emit: @escaping @Sendable (String, String?) -> Void) {
        self.token = token; self.redactor = redactor; self.control = control; self.file = file; self.emit = emit
    }
    func feed(_ data: Data, stream: String, end: Bool = false) {
        lock.lock(); defer { lock.unlock() }
        for byte in data {
            if byte == 10 {
                if dropping.remove(stream) != nil { line("<overlong log line omitted>", stream: stream) }
                else { line(String(decoding: buffers[stream] ?? Data(), as: UTF8.self), stream: stream) }
                buffers[stream] = Data()
            } else if !dropping.contains(stream) {
                buffers[stream, default: Data()].append(byte)
                if buffers[stream]!.count > 65536 { buffers[stream] = Data(); dropping.insert(stream) }
            }
        }
        if end {
            if dropping.remove(stream) != nil { line("<overlong log line omitted>", stream: stream) }
            else if let data = buffers[stream], !data.isEmpty { line(String(decoding: data, as: UTF8.self), stream: stream) }
            buffers[stream] = nil
        }
    }
    private func line(_ raw: String, stream: String) {
        let prefix = "@@NX_EXEC:\(token)@@"
        if stream == "stderr", raw.hasPrefix(prefix),
           let data = String(raw.dropFirst(prefix.count)).data(using: .utf8),
           let event = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            switch event["event"] as? String {
            case "ready": if let group = event["pgid"] as? Int32 { control.ready(group) }
            case "exit":
                targetCode = event["code"] as? Int32
                cleanupAttempted = event["descendant_cleanup_attempted"] as? Bool ?? false
            case "launch-error":
                launchError = redactor.apply(event["message"] as? String ?? "Launch failed")
                line("Launch failed: " + launchError!, stream: stream)
            case "cleanup-error":
                cleanupError = redactor.apply(event["message"] as? String ?? "Group cleanup failed")
                line(cleanupError!, stream: stream)
            default: break
            }
            return
        }
        let stage = raw.hasPrefix("@@NX_STAGE@@") ? String(raw.dropFirst(12)) : nil
        if let stage { lastStage = redactor.apply(stage) }
        let safe = redactor.apply(raw)
        let line = "[\(stream)] \(safe)\n"
        do { try file.write(contentsOf: Data(line.utf8)) }
        catch { writeError = "Cannot persist task log" }
        emit(line, stage.map { redactor.apply($0) })
    }
}

public enum BuildHistory {
    /// Run directories are named after the kind of task that owns them. Earlier
    /// builds used a different prefix, so both are read instead of hiding them.
    public static let prefixes = ["build-", "gui-task-"]

    public static func load(from parent: URL) throws -> [BuildRecord] {
        let manager = FileManager.default
        let children = try manager.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil)
        return children.filter { url in prefixes.contains { url.lastPathComponent.hasPrefix($0) } }.compactMap { url in
            guard let data = try? Data(contentsOf: url.appendingPathComponent("result.json")),
                  var record = try? JSONDecoder().decode(BuildRecord.self, from: data), record.schema == 1 else { return nil }
            if record.state.isActive { record.state = .interrupted; record.error = "Previous owner exited before task finalization" }
            // An archived run points at its removed directory; the copy of the
            // log inside the archive is the one that still exists.
            if !manager.fileExists(atPath: record.logPath) {
                let local = url.appendingPathComponent("task.log").path
                if manager.fileExists(atPath: local) { record.logPath = local }
            }
            return record
        }.sorted { $0.started > $1.started }
    }
}

private final class LiveOutput: @unchecked Sendable {
    private let lock = NSLock()
    private var text = ""
    private var stage: String?
    func append(_ value: String, stage: String?) {
        lock.lock(); defer { lock.unlock() }
        text += value
        if text.utf8.count > 262144 { text = String(text.suffix(100000)) }
        if let stage { self.stage = stage }
    }
    func take() -> (String, String?) {
        lock.lock(); defer { lock.unlock() }
        let value = (text, stage); text = ""; stage = nil; return value
    }
}

@MainActor
public final class BuildExecutor: ObservableObject {
    @Published public private(set) var state: BuildState = .idle
    @Published public private(set) var stage = ""
    @Published public private(set) var logText = ""
    @Published public private(set) var record: BuildRecord?
    /// Structured stage progress: indices and total come from the backend plan.
    @Published public private(set) var progress = StageProgress()
    private var control: ProcessControl?
    public let supervisorPython: String
    public let supervisorScript: String
    public init(supervisorPython: String, supervisorScript: String) {
        self.supervisorPython = supervisorPython; self.supervisorScript = supervisorScript
    }
    public func cancel() {
        guard state.isActive else { return }
        state = .cancelling
        progress.finish(.cancelled)
        control?.cancel()
    }

    /// Remove the temporary work folder of this run, and only that folder: a
    /// real directory named `work` directly below the executor-owned task that
    /// still holds `result.json`. Never a glob, never another path.
    nonisolated public static func discardWork(in directory: URL) -> Bool {
        let manager = FileManager.default
        let work = directory.appendingPathComponent(BuildJob.workFolder, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: work.path, isDirectory: &isDirectory), isDirectory.boolValue,
              (try? work.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink != true,
              manager.fileExists(atPath: directory.appendingPathComponent("result.json").path) else { return false }
        do { try manager.removeItem(at: work); return true } catch { return false }
    }

    /// The small records worth keeping: results, audits, summaries and the log.
    nonisolated private static let archivedFiles = ["result.json", "task.log", "audit.json", "summary.json",
                                        "artifact-files.json", "failure.json", "revision.txt"]

    /// Copy the run's small records into the log folder, then remove the run
    /// directory itself. Every guard must hold before anything is deleted:
    /// the directory is one this executor created (name and result.json), no
    /// work products remain inside, and either the build succeeded with a
    /// published, fully audited App on disk, or the failure kept nothing to
    /// diagnose. Any doubt keeps the directory untouched.
    nonisolated public static func archive(_ directory: URL, record: BuildRecord, into logRoot: URL) -> Bool {
        let manager = FileManager.default
        let name = directory.lastPathComponent
        guard name.hasPrefix("gui-task-") || name.hasPrefix("build-"),
              manager.fileExists(atPath: directory.appendingPathComponent("result.json").path),
              (try? directory.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink != true,
              record.workDiscarded == true || record.state == .succeeded else { return false }
        if record.state == .succeeded {
            guard let artifact = record.artifact, !artifact.audit.isEmpty,
                  artifact.audit.values.allSatisfy({ $0 }),
                  manager.fileExists(atPath: artifact.path) else { return false }
        }
        do {
            try manager.createDirectory(at: logRoot, withIntermediateDirectories: true)
            let destination = logRoot.appendingPathComponent(name, isDirectory: true)
            guard !manager.fileExists(atPath: destination.path) else { return false }
            try manager.createDirectory(at: destination, withIntermediateDirectories: false)
            for file in archivedFiles {
                let source = directory.appendingPathComponent(file)
                if manager.fileExists(atPath: source.path) {
                    try manager.copyItem(at: source, to: destination.appendingPathComponent(file))
                }
            }
            try manager.removeItem(at: directory)
            return true
        } catch { return false }
    }

    public func execute(_ job: BuildJob) async -> BuildRecord? {
        guard !state.isActive else { return nil }
        let control = ProcessControl(); self.control = control
        state = .starting; stage = "preparing"; logText = ""
        progress = StageProgress(stages: job.stages)
        let redactor = LogRedactor(paths: job.redactions)
        var initial = BuildRecord(id: UUID().uuidString, started: Date(), duration: 0, state: .starting,
                                  stage: "preparing", context: job.context, taskDirectory: job.directory.path,
                                  logPath: job.directory.appendingPathComponent("task.log").path,
                                  commands: job.commands.map { [$0.executable] + $0.arguments }.map { $0.map(redactor.apply) })
        // Only explicitly typed, non-key metadata is persisted; protect paths in
        // caller-provided descriptions as well as command/log strings.
        initial.context.inputs = initial.context.inputs.mapValues(redactor.apply)
        record = initial
        let startedRecord = initial
        let python = supervisorPython, supervisor = supervisorScript
        let live = LiveOutput()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        let plannedLabel = { (key: String) -> String? in job.stages.first { $0.key == key }?.label }
        let updateDisplay = {
            let (text, stage) = live.take()
            if !text.isEmpty {
                self.logText += text
                if self.logText.utf8.count > 262144 { self.logText = String(self.logText.suffix(100000)) }
            }
            if let stage {
                self.stage = stage
                // Structured stage events, not string guessing: the backend
                // prints @@NX_STAGE@@ exactly once per real stage transition.
                self.progress.begin(stage, label: plannedLabel(stage))
            }
        }
        timer.setEventHandler(handler: updateDisplay)
        timer.schedule(deadline: .now(), repeating: 0.1); timer.resume()
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var result = startedRecord
                let clock = ProcessInfo.processInfo.systemUptime
                var ownsDirectory = false
                let publish: @Sendable (String, String?) -> Void = { line, stage in
                    live.append(line, stage: stage)
                }
                func save() throws {
                    let data = try JSONEncoder().encode(result)
                    try data.write(to: job.directory.appendingPathComponent("result.json"), options: .atomic)
                }
                do {
                    // Exclusive mkdir, not createDirectory's succeeds-if-existing behavior.
                    guard Darwin.mkdir(job.directory.path, 0o700) == 0 else {
                        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSLocalizedDescriptionKey: "Choose a new task directory; existing data was retained"])
                    }
                    ownsDirectory = true
                    try FileManager.default.createDirectory(at: job.directory.appendingPathComponent("tmp"), withIntermediateDirectories: false)
                    try save()
                    let fd = Darwin.open(result.logPath, O_WRONLY | O_CREAT | O_EXCL, 0o600)
                    guard fd >= 0 else { throw CocoaError(.fileWriteUnknown) }
                    let log = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
                    defer { try? log.close() }
                    if job.commands.isEmpty { throw CocoaError(.executableNotLoadable) }
                    for command in job.commands {
                        if control.cancelled { break }
                        result.stage = command.stage; result.state = .running; try save()
                        DispatchQueue.main.async {
                            self.stage = command.stage
                            if self.state != .cancelling { self.state = .running }
                            self.progress.begin(command.stage, label: plannedLabel(command.stage))
                        }
                        let stageLine = "[stage] \(redactor.apply(command.stage))\n"
                        try log.write(contentsOf: Data(stageLine.utf8)); publish(stageLine, command.stage)
                        let process = Process(), stdout = Pipe(), stderr = Pipe(), token = UUID().uuidString
                        process.executableURL = URL(fileURLWithPath: python)
                        process.arguments = [supervisor, "--token", token, "--", command.executable] + command.arguments
                        var environment = command.environment
                        let scratch = job.directory.appendingPathComponent("tmp")
                        environment["TMPDIR"] = scratch.path
                        environment["DOTNET_CLI_HOME"] = scratch.appendingPathComponent("dotnet").path
                        environment["DOTNET_SKIP_FIRST_TIME_EXPERIENCE"] = "1"
                        environment["DOTNET_CLI_TELEMETRY_OPTOUT"] = "1"
                        environment["CLANG_MODULE_CACHE_PATH"] = scratch.appendingPathComponent("clang").path
                        environment["SWIFTPM_MODULECACHE_OVERRIDE"] = scratch.appendingPathComponent("swift").path
                        process.environment = environment
                        process.currentDirectoryURL = command.directory
                        process.standardInput = FileHandle.nullDevice
                        process.standardOutput = stdout; process.standardError = stderr
                        control.attach(process)
                        let sink = OutputSink(token: token, redactor: redactor, control: control, file: log, emit: publish)
                        try process.run()
                        try stdout.fileHandleForWriting.close(); try stderr.fileHandleForWriting.close()
                        let readers = DispatchGroup()
                        for (stream, handle) in [("stdout", stdout.fileHandleForReading), ("stderr", stderr.fileHandleForReading)] {
                            readers.enter()
                            DispatchQueue.global().async {
                                while true {
                                    let data = handle.availableData
                                    if data.isEmpty { break }
                                    sink.feed(data, stream: stream)
                                }
                                sink.feed(Data(), stream: stream, end: true)
                                try? handle.close(); readers.leave()
                            }
                        }
                        process.waitUntilExit()
                        control.endStage()
                        readers.wait()
                        result.stage = sink.lastStage ?? result.stage
                        result.processGroupCleanupAttempted = (result.processGroupCleanupAttempted ?? false) || sink.cleanupAttempted
                        result.exitCode = sink.targetCode ?? process.terminationStatus
                        result.termination = (sink.targetCode ?? 0) < 0 || process.terminationReason == .uncaughtSignal ? "signal" : "exit"
                        control.clearStage()
                        if let error = sink.launchError ?? sink.cleanupError ?? sink.writeError { throw NSError(domain: "BuildExecutor", code: 1, userInfo: [NSLocalizedDescriptionKey: error]) }
                        if result.exitCode != 0 { break }
                    }
                    result.state = control.cancelled ? .cancelled : result.exitCode == 0 ? .succeeded : .failed
                    if job.requiresAudit && result.state == .succeeded {
                        result.artifact = try JSONDecoder().decode(ArtifactSummary.self, from: Data(contentsOf: job.directory.appendingPathComponent("audit.json")))
                        guard result.artifact!.bytes > 0, result.artifact!.sha256.count == 64,
                              !result.artifact!.audit.isEmpty, result.artifact!.audit.values.allSatisfy({ $0 }),
                              !result.artifact!.game_run_verified else { throw CocoaError(.fileReadCorruptFile) }
                    }
                    if result.state == .failed { result.error = "Command failed; inspect the retained task log" }
                } catch {
                    result.state = control.cancelled ? .cancelled : .failed
                    result.error = redactor.apply(error.localizedDescription)
                    publish("[error] \(result.error!)\n", nil)
                }
                control.finish()
                if result.context.gitSHA == "unknown",
                   let revision = try? String(contentsOf: job.directory.appendingPathComponent("revision.txt"), encoding: .utf8)
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                   revision.range(of: #"^[a-f0-9]{40}$"#, options: .regularExpression) != nil {
                    result.context.gitSHA = revision
                }
                result.finished = Date(); result.duration = ProcessInfo.processInfo.systemUptime - clock
                // Temporary build products never outlive a failed or stopped
                // run unless diagnosis was explicitly requested. Only this
                // run's `work` folder is removed; logs and result.json stay.
                if result.state == .failed || result.state == .cancelled {
                    result.workDiscarded = job.keepWorkOnFailure ? false : Self.discardWork(in: job.directory)
                }
                if ownsDirectory {
                    do { try save() }
                    catch { result.state = .failed; result.error = "Cannot save task history; task files retained" }
                }
                // With the result safely on disk, a finished run leaves only
                // the published App: the small records are archived into the
                // log folder and the run directory itself is removed.
                if let archiveRoot = job.archiveRoot, ownsDirectory,
                   result.state == .succeeded || result.workDiscarded == true {
                    result.archived = Self.archive(job.directory, record: result, into: archiveRoot)
                    // The run directory is gone; this session's log button
                    // must open the archived copy of task.log.
                    if result.archived == true {
                        result.logPath = archiveRoot
                            .appendingPathComponent(job.directory.lastPathComponent + "/task.log").path
                    }
                }
                let completed = result
                DispatchQueue.main.async {
                    timer.cancel(); updateDisplay()
                    self.record = completed; self.state = completed.state; self.stage = completed.stage
                    switch completed.state {
                    case .succeeded: self.progress.finish(.done)
                    case .cancelled, .interrupted: self.progress.finish(.cancelled)
                    default: self.progress.finish(.failed)
                    }
                    self.control = nil; continuation.resume(returning: completed)
                }
            }
        }
    }
}
