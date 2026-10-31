import AppKit
import XCTest
@testable import PackagingModel

final class MenuPresentationTests: XCTestCase {
    @MainActor func testNativeValidationTitlesAndAttributedTitlesRefreshBothWays() {
        let root = NSMenu(title: "Main")
        let file = NSMenuItem(title: "文件", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "文件")
        file.submenu = submenu; root.addItem(file)
        let close = NSMenuItem(title: "关闭窗口", action: NSSelectorFromString("performClose:"), keyEquivalent: "w")
        close.attributedTitle = NSAttributedString(string: "关闭窗口", attributes: [.foregroundColor: NSColor.red])
        submenu.addItem(close)
        for language in [InterfaceLanguage.english, .simplifiedChinese, .english] {
            _ = MenuPresentation.localize(root, language: language)
            XCTAssertEqual(file.title, GUIText(key: "File").render(language))
            XCTAssertEqual(submenu.title, file.title)
            XCTAssertEqual(close.title, GUIText(key: "Close Window").render(language))
            XCTAssertEqual(close.attributedTitle?.string, close.title)
            XCTAssertEqual(close.attributedTitle?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, .red)
            XCTAssertEqual(close.action, NSSelectorFromString("performClose:"))
            XCTAssertEqual(close.keyEquivalent, "w")
        }
        close.title = "关闭窗口" // AppKit regenerates standard commands on opening.
        _ = MenuPresentation.localize(root, language: .english)
        XCTAssertEqual(close.title, "Close Window")
    }
    @MainActor func testServicesProvidersAndMenuDelegateArePreserved() {
        class Delegate: NSObject, NSMenuDelegate {}
        let delegate = Delegate()
        let root = NSMenu(title: "Main"); root.delegate = delegate
        let services = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        services.submenu = NSMenu(title: "Services")
        let provider = NSMenuItem(title: "在文本编辑中打开选定文件", action: nil, keyEquivalent: "")
        services.submenu!.addItem(provider); root.addItem(services)
        _ = MenuPresentation.localize(root, language: .simplifiedChinese)
        _ = MenuPresentation.localize(root, language: .english)
        XCTAssertTrue(root.delegate === delegate)
        XCTAssertEqual(provider.title, "在文本编辑中打开选定文件")
    }
    @MainActor func testAppKitViewMenuKeepsStandardOrderAndSameCommands() {
        let root = NSMenu(title: "Main")
        let app = NSMenuItem(title: "Touchline 23 Packaging", action: nil, keyEquivalent: "")
        root.addItem(app)
        for key in ["View", "File", "Edit", "Window"] {
            let item = NSMenuItem(title: key, action: nil, keyEquivalent: "")
            item.submenu = NSMenu(title: key); root.addItem(item)
        }
        let original = Set(root.items.map(ObjectIdentifier.init))
        for language in [InterfaceLanguage.english, .simplifiedChinese, .english] {
            _ = MenuPresentation.localize(root, language: language)
            XCTAssertEqual(Array(root.items.dropFirst()).map(\.title), ["File", "Edit", "View", "Window"].map { GUIText(key: $0).render(language) })
            XCTAssertEqual(Set(root.items.map(ObjectIdentifier.init)), original)
        }
    }

}
