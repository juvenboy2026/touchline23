import AppKit
import SwiftUI

/// A bounded, read-only native log viewport. SwiftUI selectable Text can spend
/// the main thread repeatedly laying out a live log when its disclosure reopens.
struct RawLogView: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.borderType = .bezelBorder
        let view = NSTextView(frame: .zero)
        view.isEditable = false
        view.isSelectable = true
        view.isRichText = false
        view.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        view.textContainerInset = NSSize(width: 5, height: 5)
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = true
        view.autoresizingMask = [.width]
        view.textContainer?.widthTracksTextView = false
        view.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        scroll.documentView = view
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? NSTextView, view.string != text else { return }
        let follow = view.string.isEmpty || scroll.documentVisibleRect.maxY >= view.bounds.maxY - 24
        let selection = view.selectedRange()
        view.string = text
        if follow { view.scrollToEndOfDocument(nil) }
        else if NSMaxRange(selection) <= (text as NSString).length { view.setSelectedRange(selection) }
    }
}
