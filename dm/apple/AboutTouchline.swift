// SPDX-License-Identifier: MIT
import SwiftUI

/// "About Touchline 23": the project home, the issue tracker and the open-source disclaimer.
/// The iPhone launcher shows it as a sheet over the settings screen, the Mac launcher as a sheet
/// over its window; one view, so the wording and the two links cannot drift apart. Both links open
/// the system browser. There is no telemetry, no version check and no other network access.
struct AboutTouchlineView: View {
    @EnvironmentObject private var language: LanguagePreferences
    @Environment(\.dismiss) private var dismiss
    private func l(_ text: String) -> String { GUIText(key: text).render(language.language) }
    private let home = URL(string: "https://github.com/ohxiaoguang/touchline23")!
    private let issues = URL(string: "https://github.com/ohxiaoguang/touchline23/issues")!
    private let notes = [
        "Touchline 23 is an independent community project and is not affiliated with or endorsed by EA SPORTS, Nintendo, or their affiliates.",
        "The open-source license applies only to the project code explicitly covered by the license. It does not grant rights to game content, firmware, keys, or other third-party assets.",
        "Please use the official GitHub repository for project information. Beware of unauthorized paid IPA resales or unofficial repackaged builds.",
    ]

    var body: some View {
        #if os(macOS)
        VStack(spacing: 0) {
            content.formStyle(.grouped)
            Divider()
            HStack {
                Spacer()
                Button(l("Done")) { dismiss() }.keyboardShortcut(.defaultAction)
            }.padding(12)
        }
        .frame(width: 520, height: 430)
        #else
        NavigationStack {
            content
                .navigationTitle(l("About Touchline 23"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(l("Done")) { dismiss() } } }
        }
        .preferredColorScheme(.dark)
        #endif
    }

    // The same rows on both platforms: two links, then the disclaimer, in the reader's language.
    private var content: some View {
        Form {
            Section {
                Link(destination: home) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(l("Project home"))
                            Text("github.com/ohxiaoguang/touchline23").font(.caption).foregroundStyle(.secondary)
                        }
                    } icon: { Image(systemName: "house") }
                }
                Link(destination: issues) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(l("Report an issue"))
                            Text("github.com/ohxiaoguang/touchline23/issues").font(.caption).foregroundStyle(.secondary)
                        }
                    } icon: { Image(systemName: "exclamationmark.bubble") }
                }
            }
            Section {
                ForEach(notes, id: \.self) { Text(l($0)).font(.callout) }
            }
        }
    }
}
