import Foundation

/// One reviewed selection a human is about to approve.
///
/// The fingerprint already covers the task path, inputs, interpreter identity,
/// Shader cache inventory, recipe sources and Git revision, so re-deriving it
/// for any changed selection cannot reproduce this value. The individual fields
/// are kept beside it so a stale approval fails closed even if a fingerprint
/// were ever reused by mistake, and so the confirmation sheet can state exactly
/// what is being approved.
public struct Approval: Equatable, Sendable {
    public let fingerprint: String
    public let taskDirectory: String
    public let interpreterRealpath: String?
    public let selection: String

    public init(review: BuildReview) {
        fingerprint = review.fingerprint
        taskDirectory = review.task_directory
        interpreterRealpath = review.interpreter?.realpath
        selection = Approval.selection(of: review)
    }

    /// Deterministic description of the reviewed values a build depends on.
    /// Ordering is fixed so an unchanged review always yields the same string.
    public static func selection(of review: BuildReview) -> String {
        func pairs(_ values: [String: String]) -> [String] {
            values.keys.sorted().map { $0 + "=" + (values[$0] ?? "") }
        }
        let fixed = ["task=" + review.task_directory, "program=" + review.program_version,
                     "shader=" + review.shader_source_versions.joined(separator: ","),
                     "target=" + (review.target ?? ""), "mode=" + (review.mode ?? ""),
                     "title=" + (review.identified?.title_id ?? "")]
        return (fixed + pairs(review.inputs) + pairs(review.shader)).joined(separator: "\u{1F}")
    }

    /// True only while the shown review is still the approved one.
    public func matches(_ review: BuildReview) -> Bool {
        review.execution_allowed
            && !fingerprint.isEmpty
            && fingerprint == review.fingerprint
            && taskDirectory == review.task_directory
            && interpreterRealpath == review.interpreter?.realpath
            && selection == Approval.selection(of: review)
    }
}

/// One platform of a checked batch: the review that was made for it and the
/// approval the human gave for that exact review.
public struct PreparedBuild: Sendable {
    public let target: String
    public let review: BuildReview
    public let approval: Approval
    public init(target: String, review: BuildReview) {
        self.target = target
        self.review = review
        self.approval = Approval(review: review)
    }
    /// A prepared target may run only while its approval still matches.
    public var isApprovable: Bool { approval.matches(review) }
}

/// The confirmation sheet text.
///
/// This is the single dedicated place that shows the review fingerprint. It
/// deliberately does not run through `Configuration.redacted`, which masks
/// every long hexadecimal string on purpose; that rule is not relaxed for
/// anything else. The fingerprint is public build metadata, never key material.
public enum ConfirmationSheet {
    public static func fingerprintLine(_ review: BuildReview, language: InterfaceLanguage = .english) -> String {
        let text: GUIText = "Review fingerprint (SHA-256): \(review.fingerprint)"
        return text.render(language)
    }
    public static func targetName(_ target: String, mode: String, language: InterfaceLanguage = .english) -> String {
        (target == "ios" ? "iOS IPA" : "macOS App") + " · " + GUIText.mode(mode).render(language)
    }
    public static func text(review: BuildReview, configuration: Configuration, target: String,
                            language: InterfaceLanguage = .english) -> String {
        func l(_ text: GUIText) -> String { text.render(language) }
        let size = String(format: "%.2f GiB", Double(review.estimated_bytes) / 1073741824)
        let free = String(format: "%.2f GiB", Double(review.free_bytes) / 1073741824)
        let python = review.interpreter.map { identity in
            let path = identity.executable == identity.realpath ? identity.executable
                : identity.executable + " → " + identity.realpath
            return path + "\n  " + identity.summary(in: language)
        } ?? l("Not recorded (older review)")
        let game = review.identified.map { ($0.game ?? l("Identified")) + " (" + $0.title_id + ")" }
            ?? l("Not recorded (older review)")
        var lines = [l("Game: \(game)"), l("Base: \(configuration.base)"),
            l("Update: \(configuration.update.isEmpty ? l("None") : configuration.update)"),
            l("Platform and resources: \(targetName(target, mode: configuration.mode, language: language))"),
            l("Program: \(review.program_version); Shader sources: \(review.shader_source_versions.joined(separator: ", "))"),
            l("Python: \(python)"), l("Output: \(review.artifact_path)"), fingerprintLine(review, language: language),
            l("Internal task folder: \(review.task_directory)"), l("Estimated minimum \(size); available \(free)")]
        if configuration.mode == "directory" {
            lines.append(l("Resources: bundle \(configuration.romfs)"))
            if !configuration.aoc.isEmpty { lines.append(l("DLC: bundle \(configuration.aoc) (one per numbered folder)")) }
        } else {
            lines.append(l("Resources: game data stays external; import matching containers and keys on the device."))
        }
        lines.append(l("Reuse validated Shaders without full Metal compilation. Build and audit in an isolated task, publish only after validation, then remove this run’s work. Existing files are kept."))
        return lines.joined(separator: "\n")
    }
    public static func text(batch: [PreparedBuild], configuration: Configuration,
                            language: InterfaceLanguage = .english) -> String {
        func l(_ text: GUIText) -> String { text.render(language) }
        guard !batch.isEmpty else { return l("Run preflight first.") }
        let selected = configuration.orderedTargets.count
        var head = batch.count == 1 && selected <= 1 ? l("This build has 1 target.")
            : l("Build \(batch.count) target(s) in order: \(batch.map { targetName($0.target, mode: configuration.mode, language: language) }.joined(separator: " → "))")
        if batch.count < selected { head += "\n" + l("\(selected) selected; failed targets are excluded.") }
        head += "\n" + l("If a target fails or is cancelled, later targets will not start.")
        let parts = batch.map { item in
            "—— " + targetName(item.target, mode: configuration.mode, language: language) + " ——\n"
                + text(review: item.review, configuration: configuration, target: item.target, language: language)
        }
        return ([head] + parts + [l("Confirm this real build?")]).joined(separator: "\n\n")
    }
    public static func text(review: BuildReview, configuration: Configuration,
                            language: InterfaceLanguage = .english) -> String {
        let target = review.target ?? configuration.orderedTargets.first ?? "macos"
        return text(batch: [PreparedBuild(target: target, review: review)], configuration: configuration, language: language)
    }
}
