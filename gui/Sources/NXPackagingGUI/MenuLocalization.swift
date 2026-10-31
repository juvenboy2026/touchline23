import AppKit
import PackagingModel

/// Native validation can recreate localized titles after a SwiftUI render.
/// Follow actual menu notifications; never replace the menu's command delegate.
@MainActor
final class MenuLocalization: NSObject {
    private static let shared = MenuLocalization()
    private var language: InterfaceLanguage = .english
    private var applying = false
    private var menus = Set<ObjectIdentifier>()

    private override init() {
        super.init()
        for name in [NSMenu.didAddItemNotification, NSMenu.didChangeItemNotification, NSMenu.didBeginTrackingNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(menuChanged(_:)), name: name, object: nil)
        }
    }
    static func apply(_ language: InterfaceLanguage) {
        shared.language = language
        shared.refresh()
    }
    static func refresh() { shared.refresh() }

    @objc private func menuChanged(_ notification: Notification) {
        guard !applying, let menu = notification.object as? NSMenu,
              menu === NSApp.mainMenu || menus.contains(ObjectIdentifier(menu)) else { return }
        refresh()
    }
    private func refresh() {
        guard !applying else { return }
        applying = true
        defer { applying = false }
        for window in NSApp.windows where window.title == "Touchline 23 Packaging" || window.title == "Touchline 23 打包工具" {
            window.title = GUIText(key: "Touchline 23 Packaging").render(language)
        }
        if let root = NSApp.mainMenu {
            menus = Set(MenuPresentation.localize(root, language: language).map(ObjectIdentifier.init))
        }
    }
}
