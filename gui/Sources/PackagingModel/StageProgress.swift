import Foundation

/// One stage of the plan the backend will really execute.
///
/// The list always arrives from the Python plan (revalidation, every recipe
/// command, audit, publication), so the window never guesses how many stages a
/// build has.
public struct BuildStage: Codable, Equatable, Sendable, Identifiable {
    public var key: String
    public var label: String
    public var id: String { key }
    public init(key: String, label: String) {
        self.key = key
        self.label = label
    }
}

public enum StagePhase: String, Sendable {
    case pending, running, done, failed, cancelled
}

/// Progress reported by structured stage events, never by guessing from text.
public struct StageProgress: Equatable, Sendable {
    public private(set) var stages: [BuildStage]
    /// Index of the stage being executed; also the number of finished stages.
    public private(set) var current = 0
    public private(set) var phase: StagePhase = .pending

    public init(stages: [BuildStage] = []) { self.stages = stages }

    public var total: Int { stages.count }
    public var isEmpty: Bool { stages.isEmpty }
    public var completed: Int {
        switch phase {
        case .done: return total
        case .pending: return 0
        case .running, .failed, .cancelled: return min(current, total)
        }
    }
    public var currentStage: BuildStage? { stages.indices.contains(current) ? stages[current] : nil }
    public var fraction: Double { total == 0 ? 0 : Double(completed) / Double(total) }
    public var headline: String { headline(in: .english) }
    public func headline(in language: InterfaceLanguage) -> String {
        guard phase != .pending, let stage = currentStage else { return "" }
        let known = GUIText.stage(stage.key)
        let label = known.key == stage.key ? stage.label : known.render(language)
        let text: GUIText = "Stage \(current + 1) / \(total): \(label)"
        return text.render(language)
    }
    public var statusText: String { statusText(in: .english) }
    public func statusText(in language: InterfaceLanguage) -> String {
        let names: [StagePhase: GUIText] = [.pending: "Pending", .running: "Running", .done: "Completed",
                                           .failed: "Failed", .cancelled: "Cancelled"]
        return names[phase]!.render(language)
    }
    public var isFinished: Bool { [.done, .failed, .cancelled].contains(phase) }

    /// Move to a stage key. An unknown key is appended instead of dropped, so a
    /// backend change can never make the shown total disagree with reality.
    public mutating func begin(_ key: String, label: String? = nil) {
        if let index = stages.firstIndex(where: { $0.key == key }) {
            current = index
        } else {
            stages.append(BuildStage(key: key, label: label ?? key))
            current = stages.count - 1
        }
        phase = .running
    }

    public mutating func finish(_ outcome: StagePhase) { phase = outcome }
}
