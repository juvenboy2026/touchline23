import AppKit
import SwiftUI
import PackagingModel

/// A bounded native sheet; only diagnostic content scrolls when expanded.
struct PackagingConfirmationView: View {
    @ObservedObject var model: Inspector
    @EnvironmentObject private var language: LanguagePreferences
    let cancel: () -> Void
    let confirm: () -> Void
    @State private var showDetails = false

    private func l(_ text: GUIText) -> String { text.render(language.language) }
    private var presentation: ConfirmationPresentation {
        ConfirmationPresentation(batch: model.preparedBuilds, configuration: model.configuration,
                                 identity: model.identity, catalog: model.catalog, language: language.language)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(l("Confirm Packaging")).font(.title2.bold())
            VStack(alignment: .leading, spacing: 10) {
                ForEach(presentation.summary) { field in fieldRow(field) }
            }
            Divider()
            DisclosureGroup(l("Technical Details"), isExpanded: $showDetails) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(presentation.details) { field in fieldRow(field) }
                    }.padding(.top, 8).padding(.trailing, 8)
                }.frame(height: 210)
            }.accessibilityIdentifier("confirmation-details")
            HStack {
                Spacer()
                Button(l("Cancel"), action: cancel).keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("cancel-packaging")
                Button(l("Start Packaging"), action: confirm).keyboardShortcut(.defaultAction)
                    .disabled(!model.canConfirmBuild).accessibilityIdentifier("confirm-packaging")
            }
        }
        .padding(20)
        .frame(width: 600)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("packaging-confirmation")
        .onAppear { showDetails = false }
    }

    private func fieldRow(_ field: ConfirmationPresentation.Field) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(l(field.label)).foregroundStyle(.secondary)
                .frame(width: 125, alignment: .leading)
            Text(field.value.isEmpty ? l("Unknown") : field.value)
                .lineLimit(2).truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled).help(field.value)
            if field.copyable && !field.value.isEmpty {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(field.value, forType: .string)
                } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(.borderless).help(l("Copy full value"))
                    .accessibilityLabel(l("Copy full value"))
            }
        }.font(.callout)
    }
}
