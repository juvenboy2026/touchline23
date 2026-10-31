import Foundation

/// One registered game profile, as the supported-games window shows it.
///
/// The payload comes from the generic registry (`tools/packaging_gui/registry.py`),
/// so the list and the build engine describe a profile the same way. A profile's
/// presence is never a verification claim: `capability` says what the engine can
/// build, and `evidence` says what was actually built and run, with the source
/// that recorded it.
public struct GameEntry: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var title_id: String
    public var name: String
    public var app_name: String
    public var error: String
    public var versions: [GameVersion]
    public var package: String
    public var shader_versions: [String]
    public var modules: [String]
    public var romfs_marker: String
    public var graphics_api: String
    public var archive_format: String
    public var capability: GameCapability
    public var evidence: GameEvidence
    /// Optional display metadata; never substitutes the profile/App name.
    public var chineseName: String? = nil

    public func displayName(in language: InterfaceLanguage) -> String {
        language.resolved == .simplifiedChinese ? chineseName ?? name : name
    }

    public var readable: Bool { error.isEmpty }

    /// Registered program versions in profile order, without duplicates.
    public var registeredVersions: [String] {
        var seen = Set<String>()
        return versions.map(\.display).filter { seen.insert($0).inserted }
    }

    /// The version column: what the profile registers, never what was built.
    public var versionText: String {
        registeredVersions.isEmpty ? "—" : registeredVersions.joined(separator: ", ")
    }

    public func supports(target: String) -> Bool {
        capability.targets.contains { $0.id == target && $0.supported }
    }

    /// "macOS + iOS", "macOS", or nothing buildable — from capability only.
    public var targetSummary: [String] {
        capability.targets.filter(\.supported).map(\.id)
    }
}

public struct GameVersion: Codable, Sendable, Identifiable, Equatable {
    public var version: String
    public var display: String
    public var modules: [String]
    public var build_ids: [String: String]
    public var id: String { version }
}

public struct GameCapability: Codable, Sendable, Equatable {
    public var targets: [GameCapabilityOption]
    public var modes: [GameCapabilityOption]
    public var graphics_api: String
    public var archive_format: String
    public var shader_reuse: Bool
    public var shader_generation: String
    public var plan_supported: Bool
    public var limitations: [String]

    public var supportedTargets: [GameCapabilityOption] { targets.filter(\.supported) }
    public var supportedModes: [GameCapabilityOption] { modes.filter(\.supported) }
}

public struct GameCapabilityOption: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var name: String
    public var supported: Bool
    public var reason: String
}

/// What was recorded for one game, and where. `none` is a recorded absence, not
/// an unsupported verdict, and it is never displayed as a success.
public struct GameEvidence: Codable, Sendable, Equatable {
    public var build: String
    public var runtime: String
    public var source: String
    public var note: String

    public var buildState: EvidenceState { EvidenceState(build: build) }
    public var runtimeState: EvidenceState { EvidenceState(runtime: runtime) }

    public var buildLabel: GUIText {
        switch build {
        case "fork-audited": return "Built and audited (this fork)"
        case "upstream-release": return "Built (upstream record)"
        default: return "No build record"
        }
    }

    public var runtimeLabel: GUIText {
        switch runtime {
        case "fork-report": return "Runtime reported (this fork)"
        case "upstream-iphone": return "Runtime (upstream record)"
        default: return "No runtime record"
        }
    }
}

/// Three separate answers per column: recorded here, recorded upstream, or none.
public enum EvidenceState: String, Sendable, Equatable {
    case fork, upstream, none

    public init(build: String) {
        switch build {
        case "fork-audited": self = .fork
        case "upstream-release": self = .upstream
        default: self = .none
        }
    }

    public init(runtime: String) {
        switch runtime {
        case "fork-report": self = .fork
        case "upstream-iphone": self = .upstream
        default: self = .none
        }
    }
}

public struct GameCatalog: Codable, Sendable, Equatable {
    public var schema: Int
    public var count: Int
    public var games: [GameEntry]
    /// Where the list came from: `dm/games` when it was scanned, or the path of
    /// a bundled catalog file. Shown so the list is never mistaken for a
    /// built-in constant.
    public var source: String?
    public var generated: String?

    public var registered: Int { games.count }
    public var buildable: Int { games.filter(\.capability.plan_supported).count }
    public var buildVerified: Int { games.filter { $0.evidence.buildState != .none }.count }
    public var runtimeVerified: Int { games.filter { $0.evidence.runtimeState != .none }.count }
    /// User-facing directory membership uses the existing per-target verdicts.
    /// plan_supported aggregates all targets and would wrongly hide a profile
    /// with one usable target. Evidence is deliberately irrelevant here.
    public var supportedGames: [GameEntry] {
        games.filter { !$0.capability.supportedTargets.isEmpty }
    }

    public func withLocalizedNames(_ names: LocalizedGameNames) -> GameCatalog {
        var copy = self
        copy.games = games.map { game in
            var value = game
            value.chineseName = names.chineseName(for: game.title_id)
            return value
        }
        return copy
    }
}

/// The four statements the list keeps apart. They are never folded into one
/// "supported" column: a registered profile is a description, a capability is
/// what the engine can do, and the two verification columns are records of what
/// was built and what was actually run.
public enum GameConcept: String, CaseIterable, Sendable {
    case profile, capability, build, runtime

    public var title: GUIText {
        switch self {
        case .profile: return "Registered profile"
        case .capability: return "Build capability"
        case .build: return "Build verified"
        case .runtime: return "Runtime verified"
        }
    }

    public var explanation: GUIText {
        switch self {
        case .profile:
            return "A folder in dm/games describes this game. The entry is a description, not a verification claim."
        case .capability:
            return "What this engine can plan and audit for the profile, derived from the profile and the engine's own dependencies."
        case .build:
            return "An App or IPA was built and passed the artifact audit. The game itself was not started."
        case .runtime:
            return "The packaged game was started and reported working, with the record that states it."
        }
    }
}

public enum GameSort: String, CaseIterable, Sendable {
    case name, titleID

    public var label: GUIText {
        switch self {
        case .name: return "Name (A–Z)"
        case .titleID: return "Title ID"
        }
    }
}

/// Search and ordering over a loaded catalog.
///
/// Pure value logic, so the window never has to ask Python again while the user
/// types: a name matches case- and diacritic-insensitively, and a Title ID
/// matches with or without spaces and in either case.
public struct GameQuery: Equatable, Sendable {
    public var search: String = ""
    public var sort: GameSort = .name

    public init(search: String = "", sort: GameSort = .name) {
        self.search = search; self.sort = sort
    }

    public func apply(to games: [GameEntry], language: InterfaceLanguage = .english) -> [GameEntry] {
        let needle = GameQuery.normalized(search)
        let filtered = needle.isEmpty ? games : games.filter { game in
            GameQuery.normalized(game.name).contains(needle)
                || GameQuery.normalized(game.chineseName ?? "").contains(needle)
                || GameQuery.normalized(game.title_id).contains(GameQuery.titleNeedle(search))
                || GameQuery.normalized(game.id).contains(GameQuery.titleNeedle(search))
                || game.versions.contains { version in
                    GameQuery.normalized(version.display).contains(needle)
                        || GameQuery.normalized(version.version).contains(needle)
                }
        }
        switch sort {
        case .name: return filtered.sorted {
            let comparison = $0.displayName(in: language).localizedStandardCompare($1.displayName(in: language))
            return comparison == .orderedSame ? $0.id < $1.id : comparison == .orderedAscending
        }
        case .titleID: return filtered.sorted { $0.title_id < $1.title_id }
        }
    }

    /// Fold case and diacritics and drop separators, so "01001c80" finds its game.
    public static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .replacingOccurrences(of: " ", with: "")
    }

    /// A Title ID is compared without spaces or dashes as well as written out.
    public static func titleNeedle(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
    }
}
