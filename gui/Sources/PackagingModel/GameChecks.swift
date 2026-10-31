import Foundation

/// What the selected game file actually is.
///
/// The Title ID comes from the container's own Program NCA, so a file name or
/// folder name cannot make the GUI believe it is packaging a different game.
/// `kind` distinguishes a base game from an update package (`base + 0x800`),
/// which must never be treated as another base game.
public struct GameIdentity: Codable, Equatable, Sendable {
    public var ok: Bool
    public var kind: String
    public var title_id: UInt64?
    public var title_hex: String?
    public var game: String?
    public var name: String?
    public var message: String
    public var program_version: String? = nil
    public var display_version: String? = nil

    public var isBase: Bool { ok && kind == "base" }
    public var headline: String {
        guard ok else { return message }
        return (name ?? "Identified") + " · " + (title_hex ?? "") + (display_version.map { " · " + $0 } ?? "")
    }
}

/// One line of the preflight list.
public struct CheckEntry: Codable, Sendable, Identifiable {
    public var name: String
    public var ok: Bool
    public var detail: String
    public var id: String { name }
}

public struct PlanSummary: Codable, Sendable {
    public var commands: Int
    public var stages: [BuildStage]
    public var artifact: String
    public var program_version: String
    public var shader_source_versions: [String]
}

/// One tile of the compact check grid: a name and one state, nothing else.
public struct CheckTile: Identifiable, Sendable {
    public var id: String
    public var label: String
    /// nil means "not checked yet".
    public var ok: Bool?
}

/// The whole `check` result: identification, preflight lines, recipe stages and
/// whether an approved build could run. Only aggregate values reach the window;
/// the full review JSON stays on disk for the confirmation sheet.
public struct CheckReport: Codable, Sendable {
    public var schema: Int
    public var identified: GameIdentity
    public var input_checks_passed: Bool
    public var checks: [CheckEntry]
    public var issues: [String]
    public var plan: PlanSummary?
    public var execution_allowed: Bool
    public var disabled_reason: String

    /// Families the compact grid groups real check results into. Details stay
    /// in the diagnostics list, never in the grid.
    private static let families: [(id: String, label: String, member: (String) -> Bool)] = [
        ("profile", "Registered profile", { $0 == "game-profile" }),
        ("game", "Game identity", { $0 == "container-identity" }),
        ("program", "Program version", { $0 == "program-identity" }),
        ("api", "Graphics API and targets", { $0 == "graphics-api" }),
        ("base", "Base game", { $0 == "base" }),
        ("keys", "Switch keys", { $0 == "console-keys" }),
        ("mode", "Build mode", { $0 == "options" }),
        ("update", "Update", { $0 == "update" }),
        ("shader", "Shader cache", { $0.hasPrefix("shader-") }),
        ("tools", "Build tools", { $0.hasPrefix("tool-") }),
        ("dependencies", "Dependencies", { $0.hasPrefix("python-") }),
        ("space", "Output space", { $0 == "output-space" }),
    ]

    /// Grid tiles derived from the checks that actually ran. A family with no
    /// result is omitted, and unknown checks are shown under their own name.
    public var tiles: [CheckTile] {
        var used = Set<String>()
        var result: [CheckTile] = []
        for family in CheckReport.families {
            let members = checks.filter { family.member($0.name) }
            guard !members.isEmpty else { continue }
            used.formUnion(members.map(\.name))
            result.append(CheckTile(id: family.id, label: family.label,
                                    ok: members.allSatisfy(\.ok)))
        }
        for entry in checks where !used.contains(entry.name) {
            result.append(CheckTile(id: entry.name, label: CheckLabel.text(entry.name), ok: entry.ok))
        }
        return result
    }
}

/// The neutral placeholder grid shown before any check has run. It is a list of
/// expected groups only; no state is invented for them.
public enum CheckPlaceholder {
    public static let tiles: [CheckTile] = [
        CheckTile(id: "game", label: "Game identity", ok: nil),
        CheckTile(id: "program", label: "Program version", ok: nil),
        CheckTile(id: "base", label: "Base game", ok: nil),
        CheckTile(id: "keys", label: "Switch keys", ok: nil),
        CheckTile(id: "mode", label: "Build mode", ok: nil),
        CheckTile(id: "shader", label: "Shader cache", ok: nil),
        CheckTile(id: "tools", label: "Build tools", ok: nil),
        CheckTile(id: "dependencies", label: "Dependencies", ok: nil),
        CheckTile(id: "space", label: "Output space", ok: nil),
    ]
}

/// Chinese labels for the preflight lines. Unknown names fall back to the raw
/// identifier so a new check is never silently hidden.
public enum CheckLabel {
    public static func localized(_ name: String, language: InterfaceLanguage) -> String {
        if name.hasPrefix("tool-") {
            let label: GUIText = "Tool: \(name.dropFirst(5))"
            return label.render(language)
        }
        return GUIText(key: text(name)).render(language)
    }
    public static func text(_ name: String) -> String {
        switch name {
        case "options": return "Build mode"
        case "base": return "Base game file"
        case "console-keys": return "Switch key file"
        case "update": return "Update"
        case "easf-key-file": return "EASF key file"
        case "easf-key": return "EASF key"
        case "output-space": return "Output location and space"
        case "game-profile": return "Registered profile"
        case "graphics-api": return "Graphics API and build targets"
        case "program-identity": return "Program version"
        case "romfs": return "RomFS"
        case "aoc": return "Add-on content"
        case "control-nacp": return "Control metadata"
        case "container-identity": return "Game and container identity"
        case "shader-cache": return "Shader cache"
        case "shader-generation": return "Shader generation"
        case "python-capstone": return "Python: capstone"
        case "python-lz4.block": return "Python: lz4.block"
        case "python-fontTools": return "Python: fontTools"
        default: return name.hasPrefix("tool-") ? "Tool: " + name.dropFirst(5) : name
        }
    }
}
