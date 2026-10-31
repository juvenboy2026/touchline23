import AppKit

/// Translate menu presentation without replacing commands, shortcuts or delegates.
/// AppKit may regenerate standard titles during validation, so callers reapply
/// this after native menu updates rather than only when the language changes.
@MainActor
public enum MenuPresentation {
    private static let selectors = [
        "orderFrontStandardAboutPanel:": "About Touchline 23 Packaging", "hide:": "Hide Touchline 23 Packaging",
        "hideOtherApplications:": "Hide Others", "unhideAllApplications:": "Show All", "terminate:": "Quit Touchline 23 Packaging",
        "performClose:": "Close Window", "undo:": "Undo", "redo:": "Redo", "cut:": "Cut", "copy:": "Copy",
        "paste:": "Paste", "pasteAsPlainText:": "Paste and Match Style", "selectAll:": "Select All",
        "toggleFullScreen:": "Enter Full Screen", "performMiniaturize:": "Minimize", "performZoom:": "Zoom",
        "arrangeInFront:": "Bring All to Front", "newWindowForTab:": "New Window", "showHelp:": "Touchline 23 Packaging Help"
    ]
    public static func localize(_ root: NSMenu, language: InterfaceLanguage) -> [NSMenu] {
        var menus: [NSMenu] = []
        let reverse = GUIText.catalog.keys.sorted().reduce(into: [String: String]()) { result, key in
            if let translated = GUIText.catalog[key], result[translated] == nil { result[translated] = key }
        }
        func walk(_ menu: NSMenu) {
            menus.append(menu)
            for item in menu.items {
                let key = item.action.flatMap { selectors[NSStringFromSelector($0)] }
                    ?? (GUIText.catalog[item.title] != nil ? item.title : reverse[item.title]) ?? item.title
                let title = GUIText(key: key).render(language)
                if item.title != title { item.title = title }
                if item.attributedTitle?.string != title {
                    let replacement = NSMutableAttributedString(attributedString: item.attributedTitle ?? NSAttributedString(string: item.title))
                    replacement.replaceCharacters(in: NSRange(location: 0, length: replacement.length), with: title)
                    item.attributedTitle = replacement
                }
                if let submenu = item.submenu {
                    // The native menu bar can derive its label from submenu.title.
                    if submenu.title != title { submenu.title = title }
                    if key != "Services" { walk(submenu) }
                }
            }
        }
        walk(root)
        // AppKit inserts its View menu ahead of custom scene menus. Keep the
        // familiar File / Edit / View / Window order without changing commands.
        let order = ["File", "Edit", "View", "Window", "Help"].map { GUIText(key: $0).render(language) }
        let ordered = root.items.filter { order.contains($0.title) }.sorted {
            order.firstIndex(of: $0.title)! < order.firstIndex(of: $1.title)!
        }
        let positions = root.items.indices.filter { order.contains(root.items[$0].title) }
        for (position, item) in zip(positions, ordered) where root.items[position] !== item {
            root.removeItem(item); root.insertItem(item, at: position)
        }
        return menus
    }
}
