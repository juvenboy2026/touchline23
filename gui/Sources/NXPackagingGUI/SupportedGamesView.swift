import AppKit
import Combine
import SwiftUI
import PackagingModel

@MainActor
final class GamesWindowState: ObservableObject {
    @Published var query = GameQuery()
    @Published var selected: String?
    @Published var showTechnical = false
}

/// User directory over the existing per-target capability verdicts. Historical
/// evidence remains in the catalog payload but never participates in this view.
struct SupportedGamesView: View {
    @ObservedObject var model: Inspector
    @EnvironmentObject private var language: LanguagePreferences
    let close: () -> Void
    @StateObject private var state = GamesWindowState()

    private func l(_ text: GUIText) -> String { text.render(language.language) }
    private var supported: [GameEntry] { model.catalog?.supportedGames ?? [] }
    private var games: [GameEntry] { state.query.apply(to: supported, language: language.language) }
    private var current: GameEntry? { games.first { $0.id == state.selected } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(l("Supported Games")).font(.title2.bold())
                if model.loadingCatalog { ProgressView().controlSize(.small) }
                Spacer()
                Button(l("Refresh")) { model.loadCatalog(force: true) }
                    .disabled(model.loadingCatalog || model.catalogIssue != nil)
                Button(l("Done"), action: close).keyboardShortcut(.defaultAction)
            }
            HStack(spacing: 8) {
                TextField(l("Search by name, Title ID or version"), text: $state.query.search)
                    .textFieldStyle(.roundedBorder).frame(maxWidth: 350)
                    .accessibilityIdentifier("games-search")
                if !state.query.search.isEmpty {
                    Button(l("Clear")) { state.query.search = "" }
                }
                Picker(l("Sort"), selection: $state.query.sort) {
                    ForEach(GameSort.allCases, id: \.self) { item in Text(l(item.label)).tag(item) }
                }.pickerStyle(.menu).fixedSize()
                Spacer()
                if model.catalog != nil {
                    Text(l("Supported games: \(supported.count)"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Divider()
            HStack(alignment: .top, spacing: 0) {
                List(selection: $state.selected) {
                    ForEach(games) { game in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(game.displayName(in: language.language)).font(.body.weight(.medium)).lineLimit(2)
                            Text(game.title_id).font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Text(game.versionText).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }.padding(.vertical, 3).tag(game.id)
                    }
                }
                .listStyle(.inset).frame(width: 320)
                .overlay { if games.isEmpty { emptyList } }
                Divider()
                detail.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            if let issue = model.catalogIssue {
                Text(l(issue)).font(.caption).foregroundStyle(.orange)
            } else if !model.catalogError.isEmpty {
                Text(model.catalogError).font(.caption).foregroundStyle(.orange)
            }
            Text(l("Localized names do not indicate in-game language support."))
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 900, height: 570)
        .task { model.loadCatalog() }
        .onExitCommand(perform: close)
        .onChange(of: state.selected) { _ in state.showTechnical = false }
    }

    private var emptyList: some View {
        VStack(spacing: 6) {
            if model.loadingCatalog {
                ProgressView().controlSize(.small)
                Text(l("Loading games…"))
            } else {
                Text(l(model.catalog == nil ? "The game list is not loaded yet" : "No game matches this search"))
            }
        }.foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private var detail: some View {
        if let game = current {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(game.displayName(in: language.language)).font(.title3.bold()).textSelection(.enabled)
                    if game.displayName(in: language.language) != game.name {
                        Text(game.name).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    VStack(alignment: .leading, spacing: 7) {
                        field("Title ID", game.title_id)
                        field("App name", game.app_name)
                        field("Registered versions", game.versionText)
                        field("Resource modes", game.capability.supportedModes.map {
                            GUIText(key: $0.name).render(language.language)
                        }.joined(separator: " · "))
                    }
                    if game.capability.supportedModes.contains(where: { $0.id == "nsp" }) {
                        Text(l("External mode keeps game images and keys outside the artifact."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if game.capability.supportedModes.contains(where: { $0.id == "directory" }) {
                        Text(l("Directory mode bundles prepared resources and needs more disk space."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    DisclosureGroup(l("Technical Details"), isExpanded: $state.showTechnical) {
                        VStack(alignment: .leading, spacing: 8) {
                            field("Code modules", game.modules.joined(separator: ", "))
                            field("Package", game.package)
                            field("Shader versions", game.shader_versions.joined(separator: ", "))
                            field("Graphics API", game.graphics_api)
                            field("Shader archive", game.archive_format)
                            field("RomFS marker", game.romfs_marker)
                            ForEach(game.versions) { version in
                                field("Build IDs", version.version + " · " + version.display + "\n" + version.build_ids.keys.sorted().map {
                                    $0 + "=" + (version.build_ids[$0] ?? "")
                                }.joined(separator: "\n"))
                            }
                            ForEach(game.capability.limitations.filter {
                                !$0.hasPrefix("macOS App:") && !$0.hasPrefix("iOS IPA:")
                            }, id: \.self) { line in
                                Text(GUIText(key: line).render(language.language)).font(.caption).foregroundStyle(.secondary)
                            }
                        }.padding(.top, 8)
                    }
                }.padding(.leading, 16).padding(.trailing, 8)
            }
        } else {
            Text(l("Select a game to view details"))
                .foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func field(_ title: GUIText, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(l(title)).font(.caption).foregroundStyle(.secondary).frame(width: 115, alignment: .leading)
            Text(value.isEmpty ? "—" : value).font(.callout).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
