import Foundation

/// Display-only projection of existing approved reviews. No checks, filesystem
/// reads or approval mutations occur while opening or expanding the sheet.
public struct ConfirmationPresentation {
    public struct Field: Identifiable {
        public let id: String
        public let label: GUIText
        public let value: String
        public let copyable: Bool
    }
    public let summary: [Field]
    public let details: [Field]

    public init(batch: [PreparedBuild], configuration: Configuration,
                identity: GameIdentity?, catalog: GameCatalog?, language: InterfaceLanguage) {
        func l(_ text: GUIText) -> String { text.render(language) }
        func unique(_ values: [String]) -> [String] {
            var seen = Set<String>()
            return values.filter { !$0.isEmpty && seen.insert($0).inserted }
        }
        func shared(_ values: [String]) -> String {
            let values = unique(values)
            return values.count == 1 ? values[0] : l("Unknown")
        }
        let reviews = batch.map(\.review)
        let game = shared(reviews.map { $0.game_name ?? $0.identified?.name ?? "" })
        let version = shared(reviews.map { review in
            if let identity, identity.ok,
               identity.title_hex == review.identified?.title_id,
               identity.program_version == review.program_version,
               let display = identity.display_version, !display.isEmpty { return display }
            // A recorded version identifier is still reliable when its human
            // display version is absent; never infer a display from v0/vNNN.
            return review.program_version
        })
        let modes = reviews.map { GUIText.mode($0.mode ?? configuration.mode).render(language) }
        let states = reviews.map { review -> String in
            switch review.prepared_shader?["action"] {
            case "reuse": return l("Reuse cache")
            case "generate": return l("Generation required")
            default: return review.shader.isEmpty ? l("Unknown") : l("Validated cache")
            }
        }
        let shader = unique(states).count == 1 ? states.first! : zip(batch, states).map {
            GUIText.platform($0.0.target).render(language) + ": " + $0.1
        }.joined(separator: " · ")
        summary = [
            Field(id: "game", label: "Game", value: game, copyable: false),
            Field(id: "version", label: "Game version", value: version, copyable: false),
            Field(id: "targets", label: "Build targets", value: batch.map { GUIText.platform($0.target).render(language) }.joined(separator: " · "), copyable: false),
            Field(id: "mode", label: "Resource mode", value: shared(modes), copyable: false),
            Field(id: "shader", label: "Shader status", value: shader.isEmpty ? l("Unknown") : shader, copyable: false),
            Field(id: "output", label: "Output location", value: configuration.output, copyable: true)
        ]
        var fields: [Field] = []
        func add(_ id: String, _ label: GUIText, _ value: String, copy: Bool = true) {
            if !value.isEmpty { fields.append(Field(id: id, label: label, value: value, copyable: copy)) }
        }
        add("title", "Title ID", unique(reviews.compactMap { $0.identified?.title_id }).joined(separator: ", "))
        add("program", "Program version", unique(reviews.map(\.program_version)).joined(separator: ", "))
        if let catalog {
            let ids = unique(reviews.compactMap { $0.game ?? $0.identified?.title_id })
            for game in catalog.games where ids.contains(game.id) {
                for version in game.versions where reviews.contains(where: { $0.program_version == version.version }) {
                    add("build-" + game.id + version.id, "Build IDs", version.build_ids.keys.sorted().map {
                        $0 + "=" + (version.build_ids[$0] ?? "")
                    }.joined(separator: "\n"))
                }
            }
        }
        add("base", "Base game", configuration.base)
        add("update", "Update", configuration.update)
        add("keys", "Switch keys", configuration.keys)
        add("cache", "Shader cache", unique(reviews.compactMap { $0.prepared_shader?["cache"] }).joined(separator: "\n"))
        add("sources", "Shader versions", unique(reviews.flatMap(\.shader_source_versions)).joined(separator: ", "))
        for key in ["chain", "inputs", "shader_count"] {
            add("shader-" + key, GUIText(key: key == "chain" ? "Shader chain" : key == "inputs" ? "Shader input digest" : "Shader count"),
                unique(reviews.compactMap { $0.shader[key] }).joined(separator: ", "))
        }
        add("python", "Python", unique(reviews.compactMap { $0.interpreter?.summary(in: language) }).joined(separator: "\n"), copy: false)
        for item in batch {
            add("fingerprint-" + item.target, "Review fingerprint (SHA-256)",
                GUIText.platform(item.target).render(language) + ": " + item.review.fingerprint)
        }
        details = fields
    }
}
