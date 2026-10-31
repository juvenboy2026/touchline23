import AppKit
import Combine
import PackagingModel

@MainActor
final class Inspector: ObservableObject {
    @Published var configuration = Configuration()
    @Published var advanced = false
    @Published var confirmCacheClear = false
    @Published var cacheBytes: Int64 = 0
    @Published var tools: [String: Bool] = [:]
    private var measuredCache = ""
    var cacheSize: String { ByteCountFormatter.string(fromByteCount: cacheBytes, countStyle: .file) }

    private func settingReport(_ action: String, selected: Configuration, extra: [String] = []) async -> Data? {
        let directory = logTask("settings")
        let report = directory.appendingPathComponent("settings.json")
        let args = selected.arguments(action: action) + ["--report", report.path] + extra
        let side = BuildExecutor(supervisorPython: selected.python, supervisorScript: Inspector.supervisor(selected))
        let result = await side.execute(BuildJob(directory: directory,
            commands: [bridge(selected, args: args, stage: action)],
            context: TaskContext(kind: "settings"), redactions: selected.privatePaths))
        guard result?.state == .succeeded else {
            message = "Settings operation failed; see diagnostic logs."
            return nil
        }
        return try? Data(contentsOf: report)
    }

    func detectTools() {
        let selected = configuration
        Task {
            if let data = await settingReport("tools", selected: selected),
               let found = try? JSONDecoder().decode([String: Bool].self, from: data) { tools = found }
        }
    }

    func measureCache(confirm: Bool = false) {
        guard !running else { return }
        let selected = configuration
        Task {
            if let data = await settingReport("cache-status", selected: selected),
               let found = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let bytes = found["bytes"] as? Int64, selected.cache == configuration.cache, !running {
                cacheBytes = bytes; measuredCache = selected.cache
                if confirm { confirmCacheClear = true }
            }
        }
    }

    func clearCache() {
        guard !running, measuredCache == configuration.cache else { return }
        let selected = configuration
        busy = true
        Task {
            _ = await settingReport("cache-clear", selected: selected, extra: ["--expected-bytes", String(cacheBytes)])
            busy = false
            reports = [:]; preparedBuilds = []; reviewedConfiguration = nil
            measureCache()
        }
    }
    @Published var showConfirmation = false
    /// Whether the supported-games window is open. It lives here rather than in
    /// a view `@State` so the window keeps its catalog across re-renders of the
    /// content view.
    @Published var showGames = false
    @Published var history: [BuildRecord] = []
    @Published var message: GUIText = "Choose a base game and prod.keys to identify the game."
    @Published var simulationMode = "logs"
    /// The game the selected file really is, read from the container itself.
    @Published private(set) var identity: GameIdentity?
    /// The last completed check of each platform, keyed by target id.
    @Published private(set) var reports: [String: CheckReport] = [:]
    @Published private(set) var identifying = false
    @Published var executor: BuildExecutor
    /// Keep a failed run's temporary build products for diagnosis. Off by
    /// default: a failed run keeps only logs and the small failure report.
    @Published var keepWorkOnFailure = false
    /// Every platform that passed its review, in build order.
    @Published private(set) var preparedBuilds: [PreparedBuild] = []
    /// Results of the current or last batch, one record per platform that ran.
    @Published private(set) var batchResults: [BuildRecord] = []
    @Published private(set) var batchIndex = 0
    @Published private(set) var batchTotal = 0
    @Published private(set) var batchTarget = ""
    /// The registered-game list, read from the same registry the build engine
    /// uses. Loaded on demand, never during launch: reading the profiles needs an
    /// interpreter and must not delay the window.
    @Published private(set) var catalog: GameCatalog?
    @Published private(set) var catalogError: String = ""
    @Published private(set) var loadingCatalog = false
    /// The checkout the current catalog came from.
    private var catalogRepository = ""
    @Published private var busy = false
    private var reviewedConfiguration: Configuration?
    private var relay: AnyCancellable?
    private var watcher: AnyCancellable?
    private var identifyTask: Task<Void, Never>?
    private var identifyGeneration = 0

    /// Inspection, recipe preview and check logs are GUI diagnostics, not build
    /// products, so they never enter the game output folder. Only a build the
    /// human confirmed creates a directory under the selected output parent.
    static let logRoot: URL = {
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return library.appendingPathComponent("Logs/Touchline23Packaging", isDirectory: true)
    }()
    var logRootPath: String { Inspector.logRoot.path }

    init() {
        var initial = Configuration()
        if let data = UserDefaults.standard.data(forKey: "packaging.paths.v2"),
           let saved = try? JSONDecoder().decode(Configuration.self, from: data) { initial = saved }
        if let resources = Bundle.main.resourceURL,
           FileManager.default.fileExists(atPath: resources.appendingPathComponent("Packaging/release.json").path) {
            initial.useBundle(resources)
        }
        configuration = initial
        executor = BuildExecutor(supervisorPython: initial.python, supervisorScript: Inspector.supervisor(initial))
        bindExecutor()
        // Any change to the inputs the identification depends on restarts it;
        // the game shown must always belong to the file currently selected.
        watcher = $configuration
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                // Published emits before storing the new value. Read inputs on
                // the next main-queue turn, after all edited fields are current.
                DispatchQueue.main.async { [weak self] in self?.inputsChanged() }
            }
        // Restored settings already name a game file: identify it on launch so
        // the window never shows an unidentified game next to a filled-in path.
        Task { [weak self] in self?.scheduleIdentify() }
        Task { [weak self] in self?.loadHistory() }
    }

    private static func supervisor(_ selected: Configuration) -> String {
        URL(fileURLWithPath: selected.repository).appendingPathComponent("scripts/packaging_supervisor.py").path
    }
    private func bindExecutor() {
        relay = executor.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }
    var running: Bool { busy || executor.state.isActive }
    var output: String { executor.logText }

    /// The target prefix while a batch runs, so the stage headline
    /// cannot be mistaken for the other platform's progress.
    func status(_ language: InterfaceLanguage) -> String {
        func l(_ text: GUIText) -> String { text.render(language) }
        let prefix = batchTotal > 1 && !batchTarget.isEmpty
            ? l("Target \(min(batchIndex + 1, batchTotal))/\(batchTotal) (\(batchTarget == "ios" ? "iOS IPA" : "macOS App")) · ") : ""
        if identifying { return l("Identifying game…") }
        switch executor.state {
        case .idle: return l("Ready to check")
        case .starting: return prefix + l("Preparing task…")
        case .running:
            return prefix + (executor.progress.isEmpty
                ? l("Running · \(GUIText.stage(executor.stage))")
                : executor.progress.headline(in: language) + " · " + executor.progress.statusText(in: language))
        case .cancelling: return l("Stopping the task process group…")
        case .succeeded:
            return executor.record?.context.kind == "build"
                ? prefix + l("Build complete · Artifact audit passed · Game runtime unverified")
                : executor.record?.context.kind == "check" ? l("Preflight complete · Passed") : l("Task complete")
        case .failed:
            return l("Failed · See task log")
        case .cancelled:
            return l("Cancelled") + " · " + l(executor.record?.workDiscarded == true ? "Temporary work removed" : "Files kept")
        case .interrupted: return l("Interrupted · Files kept")
        }
    }
    /// Everything a check needs is chosen; the button never guesses a default.
    var canCheck: Bool {
        !running && !identifying && !configuration.base.isEmpty && !configuration.keys.isEmpty
            && !configuration.output.isEmpty && !configuration.library.isEmpty && !configuration.python.isEmpty
            && !configuration.orderedTargets.isEmpty
    }
    var canConfirmBuild: Bool {
        guard !running, configuration == reviewedConfiguration,
              !preparedBuilds.isEmpty else { return false }
        // Each platform that passed carries its own still-valid approval. A target
        // that failed its check is simply not part of the batch, and the
        // confirmation sheet names how many of the selected ones will build.
        return preparedBuilds.allSatisfy(\.isApprovable)
    }
    func confirmationText(_ language: InterfaceLanguage) -> String {
        ConfirmationSheet.text(batch: preparedBuilds, configuration: configuration, language: language)
    }

    func savePaths() {
        if let data = try? JSONEncoder().encode(configuration) {
            UserDefaults.standard.set(data, forKey: "packaging.paths.v2")
            message = "Paths saved; inputs will be revalidated before use."
        }
    }

    // MARK: - Platform selection

    /// Toggle one platform of the batch. The stored list always keeps the
    /// canonical order (macOS before iOS) so the sheet and the build agree.
    func toggle(target: String) {
        var selected = configuration.targets
        if let index = selected.firstIndex(of: target) { selected.remove(at: index) }
        else { selected.append(target) }
        configuration.targets = Configuration.normalized(selected)
    }

    // MARK: - Identification

    private func inputsChanged() {
        reports = [:]; preparedBuilds = []; reviewedConfiguration = nil
        // The list belongs to the checkout it was read from: another repository
        // may describe other profiles, so it is dropped instead of going stale.
        if catalog != nil, configuration.repository != catalogRepository {
            catalog = nil; catalogError = ""
        }
        if configuration.output.isEmpty, !configuration.base.isEmpty {
            let suggested = Configuration.suggestedOutput(forBase: configuration.base)
            // Assigned on the next tick: mutating the same published value from
            // inside its own sink would re-enter this method.
            if !suggested.isEmpty {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.configuration.output.isEmpty else { return }
                    self.configuration.output = suggested
                }
            }
        }
        scheduleIdentify()
    }
    /// Debounced so typing a path does not start one mount per keystroke.
    func scheduleIdentify() {
        identifyGeneration += 1
        let generation = identifyGeneration
        identifyTask?.cancel()
        identifying = false
        let selected = configuration
        guard !running, !identifying, !selected.base.isEmpty, !selected.keys.isEmpty,
              !selected.library.isEmpty, !selected.python.isEmpty else {
            if identity != nil { identity = nil }
            return
        }
        identifyTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            await self?.identify(selected, generation: generation)
        }
    }
    private func identify(_ selected: Configuration, generation: Int) async {
        guard generation == identifyGeneration, !running else { return }
        identifying = true
        defer { if generation == identifyGeneration { identifying = false } }
        let directory = logTask("identify")
        let path = directory.appendingPathComponent("identify.json")
        var args = selected.arguments(action: "identify")
        args += ["--report", path.path]
        // A throwaway executor: identifying must not replace the log or the
        // record of the check or build the window is showing.
        let side = BuildExecutor(supervisorPython: selected.python, supervisorScript: Inspector.supervisor(selected))
        _ = await side.execute(BuildJob(
            directory: directory, commands: [bridge(selected, args: args, stage: "identify")],
            context: TaskContext(kind: "identify", platform: selected.orderedTargets.first ?? "macos",
                                 resourceMode: selected.mode),
            redactions: selected.privatePaths))
        guard generation == identifyGeneration else { return }
        if let data = try? Data(contentsOf: path), let found = try? JSONDecoder().decode(GameIdentity.self, from: data) {
            identity = found
            if found.ok, reports.isEmpty {
                message = "Identified \(found.name ?? "game"); choose Check configuration to run preflight."
            }
        } else {
            identity = nil
            message = "Cannot identify the game; check the selected file and prod.keys."
        }
    }

    // MARK: - Supported games

    /// Why the list cannot be read yet, or nil when it can. Reading the registry
    /// needs an interpreter and the bridge, nothing else: no base game, no keys,
    /// no output folder.
    var catalogIssue: GUIText? {
        let selected = configuration
        if selected.python.isEmpty { return "Choose a project Python to read the game list." }
        if !FileManager.default.isExecutableFile(atPath: selected.python) { return "Choose an executable Python interpreter." }
        let root = URL(fileURLWithPath: selected.repository)
        if !FileManager.default.isReadableFile(atPath: root.appendingPathComponent("scripts/packaging_gui.py").path) {
            return "Choose the GUI repository containing scripts/packaging_gui.py."
        }
        // A checkout that predates the profile registry can identify a game but
        // cannot describe the list, so it is named instead of failing silently.
        if !FileManager.default.isReadableFile(atPath: root.appendingPathComponent("tools/packaging_gui/registry.py").path) {
            return "This checkout has no game registry; choose the packaging checkout."
        }
        return nil
    }

    /// Read the registered games on demand. `force` re-reads after the profiles
    /// were edited; the first call after launch is enough otherwise.
    func loadCatalog(force: Bool = false) {
        guard !loadingCatalog else { return }
        if !force, catalog != nil { return }
        guard catalogIssue == nil else { catalog = nil; catalogError = ""; return }
        let selected = configuration
        loadingCatalog = true
        Task { [weak self] in
            guard let self else { return }
            // The catalog is a report like `identify`: it lives in a GUI
            // diagnostic directory and never inside a game output folder.
            let directory = self.logTask("games")
            let path = directory.appendingPathComponent("games.json")
            var args = selected.catalogArguments()
            args += ["--report", path.path]
            let side = BuildExecutor(supervisorPython: selected.python,
                                     supervisorScript: Inspector.supervisor(selected))
            _ = await side.execute(BuildJob(
                directory: directory, commands: [self.bridge(selected, args: args, stage: "games")],
                context: TaskContext(kind: "games", platform: "simulation", resourceMode: "none"),
                redactions: selected.privatePaths))
            if let data = try? Data(contentsOf: path),
               let found = try? JSONDecoder().decode(GameCatalog.self, from: data) {
                let namesURL = URL(fileURLWithPath: selected.repository)
                    .appendingPathComponent("tools/packaging_gui/data/game_names.zh-Hans.json")
                // Missing/corrupt display metadata must never prevent listing,
                // identification or packaging. The original English names stay.
                if let names = try? LocalizedGameNames.load(from: namesURL) {
                    self.catalog = found.withLocalizedNames(names)
                } else {
                    self.catalog = found
                }
                self.catalogError = ""
                self.catalogRepository = selected.repository
            } else {
                self.catalogError = "Cannot read the registered games; see the task log."
            }
            self.loadingCatalog = false
        }
    }

    // MARK: - Check and build

    private func parent(for selected: Configuration) -> URL {
        let url = URL(fileURLWithPath: selected.output)
        if !selected.output.isEmpty, FileManager.default.isWritableFile(atPath: url.path) { return url }
        return FileManager.default.temporaryDirectory
    }
    /// The run directory must never sit inside the player-visible output
    /// folder: only the published artifact lives there. The parent of the output
    /// folder keeps the run on the same roomy volume as the game; the temp
    /// directory is the fallback.
    private func runParent(for selected: Configuration) -> URL {
        let root = URL(fileURLWithPath: selected.cache).appendingPathComponent("Touchline23Packaging-v1/tasks")
        return root
    }
    private func newTask(_ parent: URL, kind: String) -> URL {
        parent.appendingPathComponent("gui-task-" + kind + "-" + UUID().uuidString)
    }
    /// New, never reused diagnostic directory outside the game output folder.
    private func logTask(_ kind: String) -> URL {
        try? FileManager.default.createDirectory(at: Inspector.logRoot, withIntermediateDirectories: true)
        return Inspector.logRoot.appendingPathComponent(kind + "-" + UUID().uuidString, isDirectory: true)
    }
    private func bridge(_ selected: Configuration, args: [String], stage: String) -> BuildCommand {
        BuildCommand(executable: selected.python, arguments: args, environment: selected.processEnvironment,
                     directory: URL(fileURLWithPath: selected.repository), stage: stage)
    }

    /// One action for the whole preflight: every selected platform is identified,
    /// inspected, planned and reviewed in the same interpreter, one after the
    /// other. Each keeps its own task directory and fingerprint, so approving the
    /// batch approves exactly the reviews shown.
    func runCheck() {
        guard !running, !identifying else { return }
        let selected = configuration
        if let issue = selected.launchIssue { message = GUIText(key: issue); return }
        let targets = selected.orderedTargets
        guard !targets.isEmpty else { message = "Select at least one target platform."; return }
        reports = [:]; preparedBuilds = []; reviewedConfiguration = nil; batchResults = []
        batchTotal = targets.count; batchIndex = 0; batchTarget = targets[0]
        busy = true
        let executor = BuildExecutor(supervisorPython: selected.python, supervisorScript: Inspector.supervisor(selected))
        self.executor = executor
        bindExecutor()
        Task {
            var prepared: [PreparedBuild] = []
            for (index, target) in targets.enumerated() {
                batchIndex = index; batchTarget = target
                let directory = logTask("check-" + target)
                let future = newTask(runParent(for: selected), kind: "build")
                var args = selected.arguments(action: "check", target: target)
                args += ["--task", future.path,
                         "--report", directory.appendingPathComponent("review.json").path,
                         "--revision-report", directory.appendingPathComponent("revision.txt").path]
                _ = await executor.execute(BuildJob(
                    directory: directory, commands: [bridge(selected, args: args, stage: "check")],
                    context: TaskContext(kind: "check", platform: target, resourceMode: selected.mode),
                    redactions: selected.privatePaths))
                if let found = read(CheckReport.self, from: directory.appendingPathComponent("check.json")) {
                    reports[target] = found
                }
                if let reviewed: BuildReview = read(BuildReview.self, from: directory.appendingPathComponent("review.json")),
                   reviewed.execution_allowed, reviewed.target == nil || reviewed.target == target {
                    prepared.append(PreparedBuild(target: target, review: reviewed))
                }
            }
            busy = false
            preparedBuilds = prepared
            reviewedConfiguration = prepared.isEmpty ? nil : selected
            if prepared.count == targets.count {
                message = "Preflight passed: \(prepared.count) target(s) ready to build."
            } else if prepared.isEmpty {
                message = "Preflight failed; see results below."
            } else {
                let missing = targets.filter { target in !prepared.contains { $0.target == target } }
                message = "Partially passed: \(missing.map { $0 == "ios" ? "iOS IPA" : "macOS App" }.joined(separator: ", ")) failed; only \(prepared.count) target(s) will build."
            }
            refreshHistory()
        }
    }

    private func read<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func start(_ job: BuildJob, selected: Configuration, completion: ((BuildRecord?) -> Void)? = nil) {
        guard !running else { return }
        busy = true
        executor = BuildExecutor(supervisorPython: selected.python, supervisorScript: Inspector.supervisor(selected))
        bindExecutor()
        Task {
            let result = await executor.execute(job)
            busy = false
            completion?(result)
            refreshHistory()
        }
    }

    /// Build the approved platforms one after another. Each starts only after the
    /// previous one finished, keeps its own task directory, audit and result, and
    /// publishes its own artifact. A failure or a cancellation stops the batch:
    /// the remaining platforms are reported as not started instead of being run
    /// against an environment that just failed.
    func startApprovedBuild() {
        guard canConfirmBuild, let reviewed = reviewedConfiguration else { return }
        let plan = preparedBuilds
        let selected = reviewed
        preparedBuilds = []; reviewedConfiguration = nil
        batchResults = []; batchTotal = plan.count; batchIndex = 0
        let batchID = UUID().uuidString
        busy = true
        let executor = BuildExecutor(supervisorPython: selected.python, supervisorScript: Inspector.supervisor(selected))
        self.executor = executor
        bindExecutor()
        Task {
            for (index, item) in plan.enumerated() {
                batchIndex = index; batchTarget = item.target
                // The approved values are used verbatim; the Python side re-derives
                // the fingerprint from the same task and refuses any mismatch.
                var args = selected.arguments(action: "execute", target: item.target)
                args += ["--task", item.approval.taskDirectory, "--approval", item.approval.fingerprint]
                if selected.automatic, let shader = item.review.prepared_shader,
                   let cache = shader["cache"], let action = shader["action"] {
                    args += ["--prepared-cache", cache, "--prepared-shader-action", action]
                }
                let inputs = item.review.inputs.merging(
                    ["program_version": item.review.program_version,
                     "shader_source_versions": item.review.shader_source_versions.joined(separator: ",")]) { _, new in new }
                // The game recorded with the run is the one the engine resolved
                // from the resource itself, so the history never inherits a name
                // from whichever game happened to be built last.
                let context = TaskContext(kind: "build", gitSHA: item.review.git_sha,
                                          game: item.review.game_name ?? item.review.identified?.name ?? "",
                                          titleID: item.review.identified?.title_id ?? item.review.game ?? "",
                                          platform: item.target, resourceMode: selected.mode,
                                          inputs: inputs, shader: item.review.shader, batch: batchID)
                let job = BuildJob(directory: URL(fileURLWithPath: item.approval.taskDirectory),
                                   commands: [bridge(selected, args: args, stage: "revalidate")],
                                   context: context, redactions: selected.privatePaths + [item.approval.fingerprint],
                                   requiresAudit: true, stages: item.review.stages ?? [],
                                   keepWorkOnFailure: keepWorkOnFailure, archiveRoot: Inspector.logRoot)
                let record = await executor.execute(job)
                if let record { batchResults = batchResults + [record] }
                // Only a fully audited, published artifact lets the next platform
                // start; anything else ends the batch here.
                guard record?.state == .succeeded else { break }
            }
            busy = false
            refreshHistory()
        }
    }
    func simulate() {
        guard !running else { return }
        let selected = configuration
        if let issue = selected.launchIssue { message = GUIText(key: issue); return }
        batchTotal = 0; batchIndex = 0; batchTarget = ""
        let directory = logTask("simulation")
        let fixture = URL(fileURLWithPath: selected.repository).appendingPathComponent("gui/TestSupport/mock_task.py").path
        let command = BuildCommand(executable: selected.python,
            arguments: [fixture, simulationMode, "--root", directory.path, "--repository", selected.repository], environment: selected.processEnvironment,
            directory: URL(fileURLWithPath: selected.repository), stage: "simulation-" + simulationMode)
        start(BuildJob(directory: directory, commands: [command], context: TaskContext(kind: "simulation")), selected: selected)
    }
    func cancel() { executor.cancel() }
    func loadHistory() { refreshHistory() }
    /// History lives in two places: archives of finished runs in the log
    /// folder, and run directories on the game volume that still exist (kept
    /// failure scenes, or a run whose owner vanished). Both are read.
    private func refreshHistory() {
        let archiveRoot = Inspector.logRoot
        let runRoot = runParent(for: configuration)
        Task {
            do {
                let archived = try await Task.detached { try BuildHistory.load(from: archiveRoot) }.value
                let local = try? await Task.detached { try BuildHistory.load(from: runRoot) }.value
                var seen = Set<String>()
                history = (archived + (local ?? [])).filter { seen.insert($0.taskDirectory + $0.started.description).inserted }
            } catch { message = "Cannot read history · See technical details" }
        }
    }
    func openLog() {
        let record = batchResults.last ?? executor.record
        if let record { NSWorkspace.shared.open(URL(fileURLWithPath: record.logPath)) }
    }
}
