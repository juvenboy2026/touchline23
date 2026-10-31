import AppKit
import SwiftUI
import PackagingModel


struct ContentView: View {
    @StateObject private var model = Inspector()
    @EnvironmentObject private var language: LanguagePreferences
    private func l(_ text: GUIText) -> String { text.render(language.language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(l("Touchline 23 Packaging")).font(.title2.bold())
                Spacer()
                Picker(l("Interface language"), selection: $language.language) {
                    ForEach(InterfaceLanguage.allCases, id: \.self) { item in
                        Text(item == .system ? GUIText(key: "System language").render(language.language) : item.displayName).tag(item)
                    }
                }.pickerStyle(.menu).fixedSize().accessibilityIdentifier("interface-language")
                Text(model.status(language.language)).font(.callout).foregroundStyle(.secondary).lineLimit(1)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Group {
                        choiceSection
                        gameSection
                        inputSection
                    }.disabled(model.running)
                    checkSection
                    if model.running || model.executor.record != nil || !model.batchResults.isEmpty { progressSection }
                    advancedSection
                }.padding(.bottom, 4)
            }
            footer
        }
        .padding(18)
        .frame(minWidth: 780, minHeight: 640)
        .sheet(isPresented: $model.showConfirmation) {
            PackagingConfirmationView(model: model,
                cancel: { model.showConfirmation = false },
                confirm: { model.showConfirmation = false; model.startApprovedBuild() })
                .environmentObject(language)
        }
        .alert(l("Clear managed cache?"), isPresented: $model.confirmCacheClear) {
            Button(l("Cancel"), role: .cancel) {}
            Button(l("Clear cache"), role: .destructive) { model.clearCache() }
        } message: {
            Text(l("Remove %@ of managed cache. Other files and previous cache locations are kept.").replacingOccurrences(of: "%@", with: model.cacheSize))
        }
    }

    // MARK: - Platform and resource mode

    private var choiceSection: some View {
        GroupBox(l("Packaging")) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Text(l("Target platforms")).frame(width: 92, alignment: .leading)
                    targetButtons
                }
                HStack(spacing: 8) {
                    Text(l("Resource mode")).frame(width: 92, alignment: .leading)
                    segments(Configuration.modeOptions, selection: $model.configuration.mode)
                }
            }.padding(6)
        }
    }

    /// Platforms are a multi-select: each ticked one is built and audited on its
    /// own, one after the other, in the canonical order shown here.
    private var targetButtons: some View {
        HStack(spacing: 8) {
            ForEach(Configuration.targetOptions) { option in
                let on = model.configuration.targets.contains(option.id)
                Button { model.toggle(target: option.id) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: on ? "checkmark.square.fill" : "square")
                        VStack(alignment: .leading, spacing: 1) {
                            Text(l(GUIText(key: option.title)))
                            Text(option.supported ? l(GUIText(key: option.note)) : l("Unavailable · \(GUIText(key: option.note))"))
                                .font(.caption2).opacity(0.72)
                        }
                    }
                    .padding(.vertical, 4).padding(.horizontal, 10)
                    .background(on ? Color.accentColor.opacity(0.20) : Color.clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!option.supported)
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.gray.opacity(0.3)))
            }
            Text(l("Select one or both; each builds and audits in order")).font(.caption2).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }

    /// A segmented control whose unsupported options are visibly disabled.
    /// SwiftUI pickers cannot disable a single segment, so the segments are
    /// plain buttons; the selection only ever reaches the review, which
    /// independently rejects unsupported values.
    private func segments(_ options: [Configuration.Option], selection: Binding<String>) -> some View {
        HStack(spacing: 0) {
            ForEach(options) { option in
                Button {
                    selection.wrappedValue = option.id
                } label: {
                    VStack(spacing: 1) {
                        Text(l(GUIText(key: option.title)))
                        Text(option.supported ? l(GUIText(key: option.note)) : l("Unavailable · \(GUIText(key: option.note))"))
                            .font(.caption2).opacity(0.75)
                    }
                    .padding(.vertical, 5).padding(.horizontal, 16)
                    .frame(maxWidth: .infinity)
                    .background(selection.wrappedValue == option.id
                                ? Color.accentColor.opacity(0.22) : Color.clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!option.supported)
                if option.id != options.last?.id { Divider().frame(height: 30) }
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.gray.opacity(0.3)))
    }

    // MARK: - Game

    private var gameSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Text(l("FIFA 23 Legacy Edition")).font(.headline)
                Text(l("Nintendo Switch · Base 1.0.0 · Optional update 1.0.3"))
                    .font(.caption).foregroundStyle(.secondary)
                pathRow("Base game", Binding(get: { model.configuration.base }, set: { model.configuration.selectBase($0) }), directory: model.configuration.automatic, prompt: "Choose a resource folder or enter an .xci / .nsp path")
                HStack(spacing: 8) {
                    Text(l("Game identity")).frame(width: 92, alignment: .leading)
                    if let identity = model.identity {
                        Label(identity.ok ? identity.headline : l("Game could not be identified"), systemImage: identity.ok ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(identity.ok ? Color.green : Color.red)
                            .lineLimit(2)
                    } else {
                        Text(l(model.identifying ? "Reading Title ID from game resources…" : "Choose a base game and prod.keys to identify it"))
                            .foregroundStyle(.secondary)
                    }
                    if model.identifying { ProgressView().controlSize(.small) }
                    Spacer()
                }
            }.padding(6)
        }
    }

    // MARK: - Inputs

    private var inputSection: some View {
        GroupBox(l("Inputs")) {
            VStack(alignment: .leading, spacing: 8) {
                pathRow("Switch keys", $model.configuration.keys, prompt: "Choose prod.keys")
                pathRow("Update (optional)", $model.configuration.update, prompt: "Choose an .nsp update, or leave empty")
                    .disabled(!model.configuration.updateSelectionEnabled)
                if !model.configuration.updateSelectionEnabled {
                    Text(l("Bundled resources must match the selected base and update. To change the update, switch to External mode first.")).font(.caption).foregroundStyle(.secondary)
                }
                pathRow("Output folder", Binding(get: { model.configuration.output }, set: { model.configuration.selectOutput($0) }), directory: true,
                        prompt: "Defaults to the base game folder")
                Button(l("Restore default output")) { model.configuration.restoreOutput() }
            }.padding(6)
        }
    }

    // MARK: - Check results

    private var checkSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(l("Preflight checks")).font(.headline)
                    if model.identifying || (model.running && model.batchTotal > 0 && model.batchTarget != "" && model.executor.record?.context.kind == "check") {
                        ProgressView().controlSize(.small)
                    }
                    Spacer()
                    if !model.preparedBuilds.isEmpty {
                        Text(l(model.preparedBuilds.count == model.configuration.orderedTargets.count ? "Passed" : "Partially passed"))
                            .foregroundStyle(.green).font(.callout)
                    }
                }
                // One line per selected platform: the state of its own check.
                ForEach(model.configuration.orderedTargets, id: \.self) { target in
                    HStack(spacing: 6) {
                        Image(systemName: symbol(for: model.reports[target]))
                            .foregroundStyle(colour(for: model.reports[target]))
                        Text(target == "ios" ? "iOS IPA" : "macOS App").font(.callout)
                        Text(state(of: model.reports[target])).font(.callout).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.tail)
                        Spacer(minLength: 0)
                    }
                }
                if model.reports.isEmpty {
                    Text(l(model.message)).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                }
                let failures = checkFailures
                if !failures.isEmpty {
                    DisclosureGroup(l("Technical details (\(failures.count))")) {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(failures, id: \.self) { line in
                                Text(line).font(.caption).foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }.padding(.top, 3)
                    }.font(.callout)
                }
            }.padding(6)
        }
    }

    private var checkFailures: [String] {
        var failures = model.configuration.orderedTargets.flatMap { target -> [String] in
                    guard let report = model.reports[target] else { return [] }
                    return report.checks.filter { !$0.ok }.map {
                        (target == "ios" ? "iOS · " : "macOS · ") + CheckLabel.localized($0.name, language: language.language) + "：" + $0.detail
                    }
                }
                for target in model.configuration.orderedTargets {
                    if let report = model.reports[target], !report.execution_allowed {
                        failures.append(report.identified.ok ? report.disabled_reason : report.identified.message)
                    }
                }
        return failures.filter { !$0.isEmpty }
    }

    private func symbol(for report: CheckReport?) -> String {
        guard let report else { return "circle.dashed" }
        if !report.identified.ok { return "xmark.octagon.fill" }
        return report.execution_allowed ? "checkmark.circle.fill" : "xmark.octagon.fill"
    }
    private func colour(for report: CheckReport?) -> Color {
        guard let report else { return .gray }
        return report.execution_allowed ? .green : .red
    }
    private func state(of report: CheckReport?) -> String {
        guard let report else { return l("Not checked") }
        if !report.identified.ok { return l("Game could not be identified") }
        if report.execution_allowed { return l("Passed") }
                return l("Preflight failed · See technical details")
    }

    // MARK: - Build progress

    private var progressSection: some View {
        let p = model.executor.progress
        return GroupBox(l("Build progress")) {
            VStack(alignment: .leading, spacing: 6) {
                if model.batchTotal > 1 {
                    HStack(spacing: 8) {
                        Text(l("Batch: target \(min(model.batchIndex + 1, model.batchTotal))/\(model.batchTotal)"))
                            .font(.callout)
                        Text(model.batchTarget == "ios" ? "iOS IPA" : "macOS App")
                            .font(.callout).foregroundStyle(.secondary)
                        Spacer()
                    }
                }
                if p.isEmpty {
                    Text(l(model.running ? "Preparing task…" : "Task finished; see the result below."))
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 8) {
                        Text(p.headline(in: language.language).isEmpty ? l("Build in progress") : p.headline(in: language.language)).font(.callout)
                        if model.running { ProgressView().controlSize(.small) }
                        Spacer()
                        Text(p.statusText(in: language.language)).font(.callout).foregroundStyle(.secondary)
                    }
                    // Overall progress follows the finished-stage count only;
                    // the current stage shows an indeterminate animation rather
                    // than an invented percentage.
                    ProgressView(value: p.fraction)
                }
                if let record = model.executor.record, !model.running {
                    HStack(spacing: 6) {
                        Image(systemName: record.state == .succeeded ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(record.state == .succeeded ? Color.green : Color.red)
                        Text(summary(of: record)).font(.callout)
                        Spacer(minLength: 0)
                    }
                }
                // Results of every platform that ran in this batch.
                if !model.batchResults.isEmpty {
                    Divider()
                    ForEach(Array(model.batchResults.enumerated()), id: \.offset) { _, record in
                        HStack(spacing: 6) {
                            Image(systemName: record.state == .succeeded ? "checkmark.circle.fill" : "xmark.octagon.fill")
                                .foregroundStyle(record.state == .succeeded ? Color.green : Color.red)
                            Text(record.context.platform == "ios" ? "iOS IPA" : "macOS App").font(.callout)
                            Text(summary(of: record)).font(.callout).foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                            if let artifact = record.artifact {
                                Button(l("Show artifact")) {
                                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: artifact.path)])
                                }.font(.caption)
                            }
                        }
                    }
                }
            }.padding(6)
        }
    }

    private func summary(of record: BuildRecord) -> String {
        let seconds = Int(record.duration)
        switch record.state {
        case .succeeded:
            let outcome: GUIText = record.context.kind == "build" && record.artifact != nil
                ? "Artifact audit passed" : record.context.kind == "check" ? "Preflight passed" : "Task complete"
            var text = l("Elapsed \(seconds) s · \(outcome)")
            if let artifact = record.artifact {
                text += " · " + URL(fileURLWithPath: artifact.path).lastPathComponent
            }
            return text
        case .cancelled, .interrupted:
            return l("Elapsed \(seconds) s · Stopped") + (record.workDiscarded == true ? l(" · Temporary work removed") : "")
        default:
            return l("Elapsed \(seconds) s · Exit \(record.exitCode.map(String.init) ?? "—") · See task log")
        }
    }

    // MARK: - Advanced settings

    private var advancedSection: some View {
        DisclosureGroup(l("Settings and diagnostics"), isExpanded: $model.advanced) {
            VStack(alignment: .leading, spacing: 8) {
                pathRow("Cache folder", $model.configuration.cache, directory: true)
                    .disabled(model.running)
                HStack {
                    Text(model.cacheSize).font(.caption).foregroundStyle(.secondary)
                    Button(l("Measure cache")) { model.measureCache() }.disabled(model.running)
                    Button(l("Clear cache…")) { model.measureCache(confirm: true) }.disabled(model.running)
                }
                Text(l("Changing the cache folder keeps the previous cache in place."))
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Text(l("Build tools")).font(.headline)
                    Button(l("Detect again")) { model.detectTools() }
                }
                ForEach(model.tools.keys.sorted(), id: \.self) { name in
                    HStack {
                        Text(name)
                        Text(l(model.tools[name] == true ? "Detected" : "Not detected"))
                            .foregroundStyle(model.tools[name] == true ? Color.secondary : Color.orange)
                    }.font(.caption)
                }
                Text(l("Tool detection is informational. Missing tools are reported by the actual build."))
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button(l("Save settings")) { model.savePaths() }
                    Button(l("Open diagnostic logs")) { NSWorkspace.shared.open(Inspector.logRoot) }
                }
                if !model.output.isEmpty {
                    Text(l("Raw tool output / technical details")).font(.caption)
                    RawLogView(text: model.output).frame(height: 140)
                }
                Text(l("Task history")).font(.headline)
                if model.history.isEmpty { Text(l("No tasks yet")).foregroundStyle(.secondary) }
                ForEach(model.history.prefix(8)) { record in
                    HStack {
                        Text(l("\(GUIText.kind(record.context.kind)) · \(GUIText.state(record.state.rawValue)) · \(GUIText.platform(record.context.platform)) / \(GUIText.mode(record.context.resourceMode))"))
                        Spacer()
                        Button(l("View log")) { NSWorkspace.shared.open(URL(fileURLWithPath: record.logPath)) }
                    }.font(.caption)
                }
            }.padding(6)
        }.onAppear { model.detectTools(); model.measureCache() }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            Button(l("Check configuration")) { model.runCheck() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(!model.canCheck)
            Button(l(model.configuration.orderedTargets.count > 1
                   ? "Build \(model.configuration.orderedTargets.count) targets…" : "Build…")) {
                model.showConfirmation = true
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!model.canConfirmBuild)
            if model.running {
                Button(l("Cancel task")) { model.cancel() }.keyboardShortcut(.cancelAction)
                ProgressView().controlSize(.small)
            }
            if model.executor.record != nil, !model.running {
                Button(l("View task log")) { model.openLog() }
            }
            Spacer()
        }
    }

    // MARK: - Path controls

    private func pathRow(_ title: GUIText, _ value: Binding<String>, directory: Bool = false,
                         prompt: GUIText = "Choose a path") -> some View {
        HStack(spacing: 8) {
            Text(l(title)).frame(width: 92, alignment: .leading)
            TextField(l(prompt), text: value).textFieldStyle(.roundedBorder)
            Button(l("Choose…")) { choose(value, directory: directory) }
            if !value.wrappedValue.isEmpty {
                Button(l("Clear")) { value.wrappedValue = "" }
            }
        }
    }

    private func choose(_ value: Binding<String>, directory: Bool) {
        let panel = NSOpenPanel()
        panel.title = l(directory ? "Folder" : "File")
        panel.prompt = l("Open")
        panel.canChooseDirectories = directory
        panel.canChooseFiles = !directory
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = directory
        // A project interpreter is normally a symlink such as .venv/bin/python.
        // Resolving it would store the base interpreter, whose site-packages
        // lack the build dependencies, so the link the user picked is kept.
        panel.resolvesAliases = false
        if panel.runModal() == .OK, let url = panel.url { value.wrappedValue = url.path }
    }
}

@main
struct PackagingApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var language = LanguagePreferences()
    var body: some Scene {
        WindowGroup(GUIText(key: "Touchline 23 Packaging").render(language.language)) {
            ContentView().environmentObject(language)
                .environment(\.locale, Locale(identifier: language.language.resolved.rawValue))
                .onReceive(language.$language) { selection in
                    DispatchQueue.main.async { MenuLocalization.apply(selection) }
                }
                .onAppear { DispatchQueue.main.async { MenuLocalization.apply(language.language) } }
        }
        .commandsRemoved()
        .commands {
            CommandMenu(GUIText(key: "File").render(language.language)) {
                Button(GUIText(key: "Close Window").render(language.language)) {
                    NSApp.keyWindow?.performClose(nil)
                }.keyboardShortcut("w")
            }
            CommandMenu(GUIText(key: "Edit").render(language.language)) {
                ForEach(["Undo", "Redo", "Cut", "Copy", "Paste", "Select All"], id: \.self) { key in
                    Button(GUIText(key: key).render(language.language)) {
                        let actions = ["Undo": "undo:", "Redo": "redo:", "Cut": "cut:", "Copy": "copy:", "Paste": "paste:", "Select All": "selectAll:"]
                        NSApp.sendAction(NSSelectorFromString(actions[key]!), to: nil, from: nil)
                    }.keyboardShortcut(KeyEquivalent(["Undo": "z", "Redo": "Z", "Cut": "x", "Copy": "c", "Paste": "v", "Select All": "a"][key]!.first!))
                }
            }
            CommandMenu(GUIText(key: "Window").render(language.language)) {
                Button(GUIText(key: "Minimize").render(language.language)) { NSApp.keyWindow?.miniaturize(nil) }.keyboardShortcut("m")
                Button(GUIText(key: "Zoom").render(language.language)) { NSApp.keyWindow?.zoom(nil) }
                Button(GUIText(key: "Bring All to Front").render(language.language)) { NSApp.arrangeInFront(nil) }
            }
            CommandGroup(replacing: .appInfo) {
                Button(GUIText(key: "About Touchline 23 Packaging").render(language.language)) {
                    NSApp.orderFrontStandardAboutPanel(nil)
                }
            }
            CommandGroup(replacing: .appVisibility) {
                Button(GUIText(key: "Hide Touchline 23 Packaging").render(language.language)) { NSApp.hide(nil) }
                    .keyboardShortcut("h")
                Button(GUIText(key: "Hide Others").render(language.language)) { NSApp.hideOtherApplications(nil) }
                    .keyboardShortcut("h", modifiers: [.command, .option])
                Button(GUIText(key: "Show All").render(language.language)) { NSApp.unhideAllApplications(nil) }
            }
            CommandGroup(replacing: .appTermination) {
                Button(GUIText(key: "Quit Touchline 23 Packaging").render(language.language)) { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
