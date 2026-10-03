//
//  ConsoleTranscriptView.swift
//  64Edit
//
//  Read-only console transcript (NSTextView) with ⌘-click → VIEW, matching
//  the 64Forth console Hyper path via ForthConnectionManager.viewWord.
//

import SwiftUI
import AppKit

struct ConsoleTranscriptView: NSViewRepresentable {
    var lines: [String]
    var fontSize: CGFloat = 12
    var onCommandClickWord: ((String) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.findBarPosition = .aboveContent

        let tv = ConsoleNSTextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.isRichText = false
        tv.allowsUndo = false
        tv.usesFindBar = true
        tv.isIncrementalSearchingEnabled = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        tv.backgroundColor = .clear
        tv.drawsBackground = false
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = true
        tv.autoresizingMask = [.width]
        tv.textContainer?.containerSize = NSSize(
            width: scroll.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        tv.textContainer?.widthTracksTextView = true
        tv.string = Self.joined(lines)

        scroll.documentView = tv
        context.coordinator.textView = tv
        context.coordinator.installCommandClick(on: tv)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let tv = scroll.documentView as? ConsoleNSTextView else { return }
        context.coordinator.installCommandClick(on: tv)
        tv.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)

        let next = Self.joined(lines)
        guard tv.string != next else { return }

        let wasNearBottom = Self.isNearBottom(scroll)
        tv.string = next
        if wasNearBottom || lines.isEmpty {
            DispatchQueue.main.async {
                Self.scrollToEnd(tv)
            }
        }
    }

    private static func joined(_ lines: [String]) -> String {
        lines.joined(separator: "\n")
    }

    private static func isNearBottom(_ scroll: NSScrollView) -> Bool {
        let clip = scroll.contentView.bounds
        let docHeight = scroll.documentView?.bounds.height ?? 0
        let visibleBottom = clip.origin.y + clip.height
        return docHeight - visibleBottom < 40
    }

    private static func scrollToEnd(_ tv: NSTextView) {
        let len = (tv.string as NSString).length
        guard len > 0 else { return }
        tv.scrollRangeToVisible(NSRange(location: len, length: 0))
    }

    final class Coordinator {
        var parent: ConsoleTranscriptView
        weak var textView: ConsoleNSTextView?

        init(_ parent: ConsoleTranscriptView) { self.parent = parent }

        func installCommandClick(on tv: ConsoleNSTextView) {
            tv.onCommandClickWord = { [weak self] word in
                self?.parent.onCommandClickWord?(word)
            }
        }
    }
}

/// Console transcript NSTextView — ⌘-click VIEW; distinct from `EditorNSTextView`
/// so DEBUG key routing still defers only when the source editor is focused.
final class ConsoleNSTextView: NSTextView {
    var onCommandClickWord: ((String) -> Void)?

    override func mouseDown(with event: NSEvent) {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if mods.contains(.command) {
            let pt = convert(event.locationInWindow, from: nil)
            let idx = characterIndexForInsertion(at: pt)
            let ns = string as NSString
            if let word = EditorNSTextView.forthToken(at: idx, in: ns),
               word.rangeOfCharacter(from: .whitespacesAndNewlines) == nil {
                let caret = min(max(0, idx), ns.length)
                setSelectedRange(NSRange(location: caret, length: 0))
                window?.makeFirstResponder(self)
                onCommandClickWord?(word)
                return
            }
        }
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if handleHomeEndKeys(event) { return }
        super.keyDown(with: event)
    }
}
